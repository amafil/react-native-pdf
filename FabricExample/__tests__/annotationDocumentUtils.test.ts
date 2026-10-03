import {
  normalizeAnnotationPayload,
  joinAnnotationMessagePayload,
  parseAnnotationMessagePayload,
  stringifyAnnotationDocument,
} from 'react-native-pdf/annotationDocumentUtils';

const ink = {id: 'stroke|1', page: 1, type: 'ink', points: [{x: 0.1, y: 0.2}], style: {color: '#111111', thickness: 3}};

describe('Ink annotation documents', () => {
  it('round trips Ink without changing points, style or IDs containing pipes', () => {
    const document = {editable: true, idMode: 'auto', annotations: [ink]};
    const json = stringifyAnnotationDocument(document);
    expect(json).toBe(JSON.stringify(document));
    const parts = ['annotationSaveComplete', ...json.split('|')];
    expect(joinAnnotationMessagePayload(parts)).toBe(json);
    expect(parseAnnotationMessagePayload(parts)).toEqual(document);
  });

  it('filters unsupported and malformed entries on load and save', () => {
    const annotations = [null, [], 1, {}, ...['text', 'highlight', 'underline', 'strikeout'].map(type => ({type})), ink];
    expect(normalizeAnnotationPayload(annotations)).toEqual([ink]);
    const document = {editable: false, idMode: 'manual', annotations};
    const expected = {...document, annotations: [ink]};
    expect(JSON.parse(stringifyAnnotationDocument(document))).toEqual(expected);
    expect(parseAnnotationMessagePayload(['annotationSaveComplete', JSON.stringify(document)])).toEqual(expected);
    expect(annotations).toHaveLength(9);
  });

  it('reports circular documents and preserves error messages', () => {
    const document: Record<string, unknown> = {editable: true};
    document.self = document;
    const onError = jest.fn();
    expect(stringifyAnnotationDocument(document, onError)).toBeNull();
    expect(onError).toHaveBeenCalledTimes(1);
    expect(parseAnnotationMessagePayload(['annotationSaveError', 'Unavailable'])).toBe('Unavailable');
    expect(parseAnnotationMessagePayload([])).toBeNull();
  });
});
