import Pdf from 'react-native-pdf';
import { Image } from 'react-native';
import BlobUtil from 'react-native-blob-util';

jest.mock('react-native-blob-util', () => ({
  fs: {
    dirs: { CacheDir: '/cache' },
    unlink: jest.fn().mockResolvedValue(undefined),
    cp: jest.fn().mockResolvedValue(undefined),
    writeFile: jest.fn().mockResolvedValue(undefined),
    readFileWithTransform: jest.fn().mockResolvedValue('pdf'),
    stat: jest.fn().mockResolvedValue({ lastModified: Date.now() }),
  },
}));
jest.mock('react-native-pdf/fabric/RNPDFPdfNativeComponent', () => ({
  __esModule: true,
  default: 'RNPDFPdfView',
  Commands: {},
}));
const createPdf = (source: object, transformFile = false) => {
  const pdf = new (Pdf as any)({ source, transformFile });
  pdf._mounted = true;
  pdf.setState = (state: object) => Object.assign(pdf.state, state);
  return pdf;
};
const flush = async () => {
  for (let i = 0; i < 10; i++) {
    await Promise.resolve();
  }
};
beforeEach(() => jest.clearAllMocks());

it.each([true, false, undefined])(
  'preserves local PDFs with cache=%s on reopen',
  async cache => {
    const source = { uri: 'file:///documents/song%20431.pdf', cache };
    for (let i = 0; i < 2; i++) {
      const pdf = createPdf(source);
      await pdf._prepareFile(source);
      expect(pdf.state.path).toBe('/documents/song 431.pdf');
      pdf.componentWillUnmount();
    }
    expect(BlobUtil.fs.unlink).not.toHaveBeenCalled();
  },
);
it('preserves borrowed files even in CacheDir', async () => {
  const source = { uri: '/cache/song.pdf', cacheFileName: 'song.pdf' };
  const pdf = createPdf(source);
  await pdf._prepareFile(source);
  pdf.componentWillUnmount();
  expect(BlobUtil.fs.unlink).not.toHaveBeenCalled();
});
it('cleans transformed view but preserves local input', async () => {
  const source = { uri: 'file:///documents/song.pdf' };
  const pdf = createPdf(source, true);
  await pdf._prepareFile(source);
  jest.clearAllMocks();
  pdf.componentWillUnmount();
  expect(BlobUtil.fs.unlink).toHaveBeenCalledTimes(1);
  expect(BlobUtil.fs.unlink).toHaveBeenCalledWith('/documents/song.pdf.view');
});
it.each([
  'https://example.com/song.pdf',
  'bundle-assets://song.pdf',
  'data:application/pdf;base64,cGRm',
])('respects source.cache for generated files: %s', async uri => {
  for (const cache of [true, false]) {
    const source = { uri, cache, cacheFileName: 'song.pdf' };
    const pdf = createPdf(source);
    pdf._downloadFile = jest.fn().mockResolvedValue(undefined);
    await pdf._prepareFile(source);
    await flush();
    jest.clearAllMocks();
    pdf.componentWillUnmount();
    expect(BlobUtil.fs.unlink).toHaveBeenCalledTimes(cache ? 0 : 1);
    if (!cache) {
      expect(BlobUtil.fs.unlink).toHaveBeenCalledWith('/cache/song.pdf');
    }
  }
});
it.each([false, true])(
  'preserves cache hits, transform=%s',
  async transform => {
    const resolve = jest
      .spyOn(Image, 'resolveAssetSource')
      .mockImplementation(source => source as any);
    const source = {
      uri: 'https://example.com/song.pdf',
      cache: true,
      cacheFileName: 'song.pdf',
    };
    const pdf = createPdf(source, transform);
    pdf._loadFromSource(source);
    await flush();
    expect(pdf.state.isDownloaded).toBe(true);
    jest.clearAllMocks();
    pdf.componentWillUnmount();
    expect(BlobUtil.fs.unlink).not.toHaveBeenCalledWith('/cache/song.pdf');
    if (transform) {
      expect(BlobUtil.fs.unlink).toHaveBeenCalledWith('/cache/song.pdf.view');
    }
    resolve.mockRestore();
  },
);
