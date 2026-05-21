/**
 * Copyright (c) 2017-present, Wonday (@wonday.org)
 * All rights reserved.
 *
 * This source code is licensed under the MIT-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

import * as React from 'react';
import * as ReactNative from 'react-native';

export type TableContent = {
    children: TableContent[],
    mNativePtr: number,
    pageIdx: number,
    title: string,
};

export type Source = {
    uri?: string;
    headers?: {
        [key: string]: string;
    };
    cache?: boolean;
    cacheFileName?: string;
    expiration?: number;
    method?: string;
};

export type AnnotationRotation = 0 | 90 | 180 | 270;
export type AnnotationIdMode = 'auto' | 'manual';
export type AnnotationTool = 'select' | 'ink' | 'text';
export type AnnotationTextAlign = 'left' | 'center' | 'right';

export type AnnotationPoint = {
    x: number,
    y: number,
    pressure?: number,
};

export type AnnotationBounds = {
    x: number,
    y: number,
    width: number,
    height: number,
};

export type AnnotationStyle = {
    color?: string,
    thickness?: number,
    fontFamily?: string,
    fontSize?: number,
    textAlign?: AnnotationTextAlign,
    rotation?: AnnotationRotation,
};

export type AnnotationBase = {
    id: string,
    page: number,
    locked?: boolean,
    createdAt?: number,
    updatedAt?: number,
};

export type InkAnnotation = AnnotationBase & {
    type: 'ink',
    points: AnnotationPoint[],
    style?: AnnotationStyle,
};

export type TextAnnotation = AnnotationBase & {
    type: 'text',
    bounds: AnnotationBounds,
    text: string,
    style?: AnnotationStyle,
};

export type MarkupAnnotation = AnnotationBase & {
    type: 'highlight',
    bounds: AnnotationBounds,
    style?: AnnotationStyle,
};

export type Annotation = InkAnnotation | TextAnnotation | MarkupAnnotation;

export type AnnotationDocument = {
    editable?: boolean,
    idMode?: AnnotationIdMode,
    annotations: Annotation[],
};

export type TextSelectionChangeEvent = {
  nativeEvent:
    | {
        type: 'selectionCleared';
      }
    | {
        type: 'selectionChanged';
        text: string;
      };
};

export interface PdfProps {
    style?: ReactNative.StyleProp<ReactNative.ViewStyle>,
    progressContainerStyle?: ReactNative.StyleProp<ReactNative.ViewStyle>,
    source: Source | number,
    page?: number,
    scale?: number,
    minScale?: number,
    maxScale?: number,
    horizontal?: boolean,
    showsHorizontalScrollIndicator?: boolean,
    showsVerticalScrollIndicator?: boolean,
    scrollEnabled?: boolean,
    spacing?: number,
    password?: string,
    renderActivityIndicator?: (progress: number) => React.ReactElement,
    enableAntialiasing?: boolean,
    enablePaging?: boolean,
    enableRTL?: boolean,
    enableAnnotationRendering?: boolean,
    enableDoubleTapZoom?: boolean;
    /**
     * Initial annotation document to render in the overlay.
     */
    annotations?: AnnotationDocument,
    /**
     * Enable annotation editing mode.
     */
    annotationMode?: boolean,
    /**
     * Active tool used while annotation editing is enabled.
     */
    annotationTool?: AnnotationTool,
    /**
     * Allow in-place annotation edits.
     */
    annotationEditable?: boolean,
    /**
     * Controls how annotation IDs are generated and preserved.
     */
    annotationIdMode?: AnnotationIdMode,
    /**
     * Default color applied to newly created ink annotations.
     */
    annotationInkColor?: string,
    /**
     * Default thickness applied to newly created ink annotations.
     */
    annotationInkThickness?: number,
    /**
     * Only works on iOS. Defaults to `true`.
     */
    enableTextSelection?: boolean;
    /**
     * Fit policy.  This will adjust the initial zoom of the PDF based on the initial size of the view and the scale factor.
     * 0 = fit width
     * 1 = fit height
     * 2 = fit both
     */
    fitPolicy?: 0 | 1 | 2,
    trustAllCerts?: boolean,
    singlePage?: boolean,
    onLoadProgress?: (percent: number,) => void,
    onLoadComplete?: (numberOfPages: number, path: string, size: {height: number, width: number}, tableContents?: TableContent[]) => void,
    onPageChanged?: (page: number, numberOfPages: number) => void,
    onError?: (error: object) => void,
    onPageSingleTap?: (page: number, x: number, y: number) => void,
    onScaleChanged?: (scale: number) => void,
    onPressLink?: (url: string) => void,
    onAutoScrollEnd?: () => void,
    onAnnotationStrokeEnd?: () => void,
    onTextSelectionChange?: (event: TextSelectionChangeEvent) => void,
}

export interface PdfRef {
    setPage(pageNumber: number): void
    /**
     * Resolves with the current annotation document serialized by native code.
     */
    saveAnnotations(): Promise<AnnotationDocument>
    /**
     * Deletes the currently selected custom annotation.
     */
    deleteSelectedAnnotation(): void
    /**
     * Deletes all custom annotations in the current overlay draft.
     */
    deleteAllAnnotations(): void
    /**
     * Start smooth automatic vertical scrolling using the display refresh rate.
     * @param dpPerSecond - Scroll speed in density-independent pixels (dp) per second (default: 15). Produces consistent physical speed across screen densities.
     * @param resumeDelay - Milliseconds to wait before resuming after user touch (default: 3000)
     */
    startAutoScroll(dpPerSecond?: number, resumeDelay?: number): void
    /** Stop automatic scrolling. */
    stopAutoScroll(): void
}

declare const Pdf: React.ForwardRefExoticComponent<PdfProps & React.RefAttributes<PdfRef>>

export default Pdf;
