'use strict';

const LEGACY_MARKUP_TYPES = new Set(['underline', 'strikeout']);

export function normalizeAnnotation(annotation) {
    if (!annotation || typeof annotation !== 'object' || Array.isArray(annotation)) {
        return annotation;
    }

    if (!LEGACY_MARKUP_TYPES.has(annotation.type)) {
        return annotation;
    }

    return {
        ...annotation,
        type: 'highlight',
    };
}

export function normalizeAnnotationPayload(payload) {
    if (!payload || typeof payload !== 'object') {
        return payload;
    }

    if (Array.isArray(payload)) {
        return payload.map(normalizeAnnotation);
    }

    if (!Array.isArray(payload.annotations)) {
        return payload;
    }

    return {
        ...payload,
        annotations: payload.annotations.map(normalizeAnnotation),
    };
}

export function joinAnnotationMessagePayload(messageParts, startIndex = 1) {
    if (!Array.isArray(messageParts) || messageParts.length <= startIndex) {
        return '';
    }

    return messageParts.slice(startIndex).join('|');
}

export function parseAnnotationMessagePayload(messageParts, startIndex = 1) {
    const payload = joinAnnotationMessagePayload(messageParts, startIndex);

    if (!payload) {
        return null;
    }

    try {
        return normalizeAnnotationPayload(JSON.parse(payload));
    } catch (error) {
        return payload;
    }
}

export function stringifyAnnotationDocument(document, onError) {
    if (!document) {
        return null;
    }

    try {
        return JSON.stringify(normalizeAnnotationPayload(document));
    } catch (error) {
        if (onError) {
            onError(error);
        }
        return null;
    }
}
