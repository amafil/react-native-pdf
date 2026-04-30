import {
  joinAnnotationMessagePayload,
  parseAnnotationMessagePayload,
  stringifyAnnotationDocument,
} from 'react-native-pdf/annotationDocumentUtils';

describe('annotationDocumentUtils', () => {
  it('stringifies an annotation document', () => {
    const document = {
      editable: true,
      idMode: 'auto',
      annotations: [
        {
          id: 'note-1',
          page: 1,
          type: 'text' as const,
          bounds: {x: 0.15, y: 0.24, width: 0.28, height: 0.12},
          text: 'Reminder for page one',
        },
      ],
    };

    expect(stringifyAnnotationDocument(document)).toBe(JSON.stringify(document));
  });

  it('returns null and reports circular documents', () => {
    const document: Record<string, unknown> = {editable: true};
    (document as Record<string, unknown>).self = document;
    const onError = jest.fn();

    expect(stringifyAnnotationDocument(document, onError)).toBeNull();
    expect(onError).toHaveBeenCalledTimes(1);
  });

  it('rebuilds pipe-delimited save payloads and falls back to raw text', () => {
    const messageParts = [
      'annotationSaveComplete',
      '{"editable":true,"idMode":"manual","annotations":[{"id":"note-1","page":1,"type":"text","bounds":{"x":0.1,"y":0.2,"width":0.3,"height":0.4},"text":"Hello',
      'world"}]}',
    ];

    expect(joinAnnotationMessagePayload(messageParts)).toBe(
      '{"editable":true,"idMode":"manual","annotations":[{"id":"note-1","page":1,"type":"text","bounds":{"x":0.1,"y":0.2,"width":0.3,"height":0.4},"text":"Hello|world"}]}',
    );
    expect(parseAnnotationMessagePayload(messageParts)).toEqual({
      editable: true,
      idMode: 'manual',
      annotations: [
        {
          id: 'note-1',
          page: 1,
          type: 'text',
          bounds: {x: 0.1, y: 0.2, width: 0.3, height: 0.4},
          text: 'Hello|world',
        },
      ],
    });

    expect(parseAnnotationMessagePayload(['annotationSaveError', 'Annotation overlay unavailable'])).toBe(
      'Annotation overlay unavailable',
    );
  });

  it('normalizes legacy underline and strikeout annotations to highlight', () => {
    const legacyDocument = {
      editable: true,
      idMode: 'auto',
      annotations: [
        {
          id: 'legacy-underline',
          page: 1,
          type: 'underline',
          bounds: {x: 0.1, y: 0.2, width: 0.25, height: 0.05},
        },
        {
          id: 'legacy-strikeout',
          page: 2,
          type: 'strikeout',
          bounds: {x: 0.15, y: 0.32, width: 0.2, height: 0.04},
        },
      ],
    };

    const normalizedDocument = {
      ...legacyDocument,
      annotations: legacyDocument.annotations.map(annotation => ({
        ...annotation,
        type: 'highlight',
      })),
    };

    expect(stringifyAnnotationDocument(legacyDocument)).toBe(JSON.stringify(normalizedDocument));
    expect(parseAnnotationMessagePayload(['annotationSaveComplete', JSON.stringify(legacyDocument)])).toEqual(
      normalizedDocument,
    );
  });
});
