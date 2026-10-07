import Pdf from 'react-native-pdf';
import {UIManager, findNodeHandle} from 'react-native';
import {Commands} from 'react-native-pdf/fabric/RNPDFPdfNativeComponent';

jest.mock('react-native-blob-util', () => ({fs: {dirs: {CacheDir: '/tmp'}}}));
jest.mock('react-native-pdf/fabric/RNPDFPdfNativeComponent', () => ({
  __esModule: true,
  default: 'RNPDFPdfView',
  Commands: {undoLastInkStroke: jest.fn()},
}));

const createPdf = (props = {}) => new (Pdf as any)({source: {uri: 'file:///test.pdf'}, ...props});

describe('Ink undo native bridge', () => {
  afterEach(() => {
    delete (global as any).nativeFabricUIManager;
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });

  it('dispatches undo to Fabric', () => {
    (global as any).nativeFabricUIManager = {};
    const pdf = createPdf();
    pdf._root = {};
    pdf.undoLastInkStroke();
    expect(Commands.undoLastInkStroke).toHaveBeenCalledWith(pdf._root);
  });

  it('dispatches undo to Paper', () => {
    const dispatch = jest.spyOn(UIManager, 'dispatchViewManagerCommand');
    const pdf = createPdf();
    pdf._root = {_nativeTag: 42};
    pdf.undoLastInkStroke();
    expect(dispatch).toHaveBeenCalledWith(findNodeHandle(pdf._root), 'undoLastInkStroke', []);
  });

  it('ignores commands before the native view mounts', () => {
    (global as any).nativeFabricUIManager = {};
    createPdf().undoLastInkStroke();
    expect(Commands.undoLastInkStroke).not.toHaveBeenCalled();
  });

  it('reports native undo availability separately from stroke completion', () => {
    const onAnnotationUndoStateChanged = jest.fn();
    const onAnnotationStrokeEnd = jest.fn();
    const pdf = createPdf({onAnnotationUndoStateChanged, onAnnotationStrokeEnd});
    for (const value of ['true', 'false']) {
      pdf._onChange({nativeEvent: {message: `annotationUndoStateChanged|${value}`}});
    }
    expect(onAnnotationUndoStateChanged.mock.calls).toEqual([[{canUndo: true}], [{canUndo: false}]]);
    expect(onAnnotationStrokeEnd).not.toHaveBeenCalled();
    pdf._onChange({nativeEvent: {message: 'strokeEnd'}});
    expect(onAnnotationStrokeEnd).toHaveBeenCalledTimes(1);
  });
});
