'use strict';

const isInkAnnotation = annotation => (
    annotation != null && typeof annotation === 'object' && !Array.isArray(annotation) && annotation.type === 'ink'
);

export function normalizeAnnotationPayload(payload) {
    if (!payload || typeof payload !== 'object') {
        return payload;
    }

    if (Array.isArray(payload)) {
        return payload.filter(isInkAnnotation);
    }

    if (!Array.isArray(payload.annotations)) {
        return payload;
    }

    return {
        ...payload,
        annotations: payload.annotations.filter(isInkAnnotation),
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
