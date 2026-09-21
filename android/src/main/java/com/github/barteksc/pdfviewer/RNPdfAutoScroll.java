package com.github.barteksc.pdfviewer;

/**
 * Access to AndroidPdfViewer 4.0.1's package-private document geometry.
 * Keep this adapter in the renderer package so we use its actual layout,
 * including pixel spacing and automatic page spacing, without reflection.
 */
public final class RNPdfAutoScroll {
    private RNPdfAutoScroll() {}

    /** Scroll to a vertical pixel offset and return whether scrolling is finished. */
    public static boolean scrollTo(PDFView view, float offset) {
        if (view.pdfFile == null || !view.isSwipeVertical()) {
            return true;
        }

        float range = view.pdfFile.getDocLen(view.getZoom()) - view.getHeight();
        if (range <= 0f) {
            return true;
        }

        // This preserves X and updates the current page and its callbacks,
        // including when the final frame reaches the bottom of the document.
        view.setPositionOffset(Math.max(0f, Math.min(1f, offset / range)));
        return offset >= range;
    }
}
