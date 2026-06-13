/**
 * Copyright (c) 2017-present, Wonday (@wonday.org)
 * All rights reserved.
 *
 * This source code is licensed under the MIT-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

package org.wonday.pdf;

import java.io.File;
import java.io.IOException;

import android.content.ContentResolver;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.util.SizeF;
import android.util.SparseArray;
import android.view.Choreographer;
import android.view.View;
import android.view.ViewGroup;
import android.util.Log;
import android.net.Uri;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.ViewConfiguration;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PointF;
import android.graphics.RectF;
import android.graphics.pdf.PdfRenderer;
import android.widget.EditText;
import android.text.Editable;
import android.text.TextWatcher;
import android.text.TextUtils;
import android.view.Gravity;
import android.widget.FrameLayout;

import io.legere.pdfiumandroid.util.Config;
import io.legere.pdfiumandroid.util.ConfigKt;
import io.legere.pdfiumandroid.util.AlreadyClosedBehavior;
import io.legere.pdfiumandroid.DefaultLogger;

import com.facebook.react.uimanager.ThemedReactContext;
import com.facebook.react.uimanager.UIManagerHelper;
import com.github.barteksc.pdfviewer.PDFView;
import com.github.barteksc.pdfviewer.listener.OnPageChangeListener;
import com.github.barteksc.pdfviewer.listener.OnLoadCompleteListener;
import com.github.barteksc.pdfviewer.listener.OnErrorListener;
import com.github.barteksc.pdfviewer.listener.OnTapListener;
import com.github.barteksc.pdfviewer.listener.OnDrawListener;
import com.github.barteksc.pdfviewer.listener.OnPageScrollListener;
import com.github.barteksc.pdfviewer.util.FitPolicy;
import com.github.barteksc.pdfviewer.util.Constants;
import com.github.barteksc.pdfviewer.link.LinkHandler;
import com.github.barteksc.pdfviewer.model.LinkTapEvent;

import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.uimanager.UIManagerModule;
import com.facebook.react.uimanager.events.EventDispatcher;
import com.facebook.react.uimanager.events.Event;
import com.facebook.react.uimanager.events.RCTEventEmitter;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import static java.lang.String.format;

import java.io.FileNotFoundException;
import java.io.InputStream;

import com.google.gson.Gson;

import org.wonday.pdf.events.TopChangeEvent;

public class PdfView extends PDFView implements OnPageChangeListener,OnLoadCompleteListener,OnErrorListener,OnTapListener,OnDrawListener,OnPageScrollListener, LinkHandler {
    private int page = 1;               // start from 1
    private boolean horizontal = false;
    private float scale = 1;
    private float minScale = 1;
    private float maxScale = 3;
    private String path;
    private int spacing = 10;
    private String password = "";
    private boolean enableAntialiasing = true;
    private boolean enableAnnotationRendering = true;
    private boolean enableDoubleTapZoom = true;
    private String annotations;
    private boolean annotationMode = false;
    private String annotationTool = "select";
    private boolean annotationEditable = true;
    private String annotationIdMode = "auto";
    private String annotationInkColor = "#111111";
    private float annotationInkThickness = 2f;
    private AnnotationOverlayView annotationOverlayView;

    private boolean enablePaging = false;
    private boolean autoSpacing = false;
    private boolean pageFling = false;
    private boolean pageSnap = false;
    private FitPolicy fitPolicy = FitPolicy.WIDTH;
    private boolean singlePage = false;
    private boolean scrollEnabled = true;
    private boolean enableRTL = false;
    private View.OnTouchListener dragPinchTouchListener;

    private float originalWidth = 0;
    private float lastPageWidth = 0;
    private float lastPageHeight = 0;
    private final SparseArray<PageRenderInfo> pageRenderInfoByIndex = new SparseArray<>();
    private final Matrix pageRenderMatrix = new Matrix();
    private final float[] pageRenderMatrixValues = new float[9];

    // used to store the parameters for `super.onSizeChanged`
    private int oldW = 0;
    private int oldH = 0;

    // Autoscroll
    private Choreographer.FrameCallback autoScrollFrameCallback;
    private Runnable autoScrollResumeRunnable;
    private Handler autoScrollResumeHandler;
    private boolean isAutoScrolling = false;
    private boolean isUserTouching = false;
    private float autoScrollPixels = 15f;   // pixels per second
    private long autoScrollResumeDelay = 3000L;
    private long lastFrameTimeNanos = 0;
    private float accumulatedScrollOffset = 0f; // float accumulator – avoids re-reading the rendering-quantised offset

    private static final class PageRenderInfo {
        final float left;
        final float top;
        final float width;
        final float height;

        PageRenderInfo(float left, float top, float width, float height) {
            this.left = left;
            this.top = top;
            this.width = width;
            this.height = height;
        }
    }

    @Override
    public void setOnTouchListener(View.OnTouchListener l) {
        dragPinchTouchListener = l;
        super.setOnTouchListener(l);
    }

    public boolean dispatchToParentTouchListener(MotionEvent event) {
        return dragPinchTouchListener != null && dragPinchTouchListener.onTouch(this, event);
    }

    public PdfView(Context context, AttributeSet set){
        super(context, set);
        ConfigKt.setPdfiumConfig(new Config(new DefaultLogger(), AlreadyClosedBehavior.IGNORE));
        autoScrollResumeHandler = new Handler(Looper.getMainLooper());
        annotationOverlayView = new AnnotationOverlayView(context);
        addView(annotationOverlayView, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        bringChildToFront(annotationOverlayView);
        updateAnnotationOverlayConfig();
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_DOWN) {
            isUserTouching = true;
            if (isAutoScrolling && autoScrollFrameCallback != null) {
                Choreographer.getInstance().removeFrameCallback(autoScrollFrameCallback);
                autoScrollResumeHandler.removeCallbacks(autoScrollResumeRunnable);
                lastFrameTimeNanos = 0;
            }
        } else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            isUserTouching = false;
            if (isAutoScrolling) {
                scheduleAutoScrollResume();
            }
        }
        return super.dispatchTouchEvent(event);
    }

    @Override
    public void onPageChanged(int page, int numberOfPages) {
        // pdf lib page start from 0, convert it to our page (start from 1)
        page = page+1;
        this.page = page;
        showLog(format("%s %s / %s", path, page, numberOfPages));

        WritableMap event = Arguments.createMap();
        event.putString("message", "pageChanged|"+page+"|"+numberOfPages);

        ThemedReactContext context = (ThemedReactContext) getContext();
        EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
        int surfaceId = UIManagerHelper.getSurfaceId(this);

        TopChangeEvent tce = new TopChangeEvent(surfaceId, getId(), event);

        if (dispatcher != null) {
            new Handler(Looper.getMainLooper()).postDelayed(() -> dispatcher.dispatchEvent(tce), 10);
        }

        if (annotationOverlayView != null) {
            annotationOverlayView.invalidate();
        }

//        ReactContext reactContext = (ReactContext)this.getContext();
//        reactContext.getJSModule(RCTEventEmitter.class).receiveEvent(
//            this.getId(),
//            "topChange",
//            event
//         );
    }

    // In some cases Yoga (I think) will measure the view only along one axis first, resulting in
    // onSizeChanged being called with either w or h set to zero. This in turn starts the rendering
    // of the pdf under the hood with one dimension being set to zero and the follow-up call to
    // onSizeChanged with the correct dimensions doesn't have any effect on the already started process.
    // The offending class is DecodingAsyncTask, which tries to get width and height of the pdfView
    // in the constructor, and is created as soon as the measurement is complete, which in some cases
    // may be incomplete as described above.
    // By delaying calling super.onSizeChanged until the size in both dimensions is correct we are able
    // to prevent this from happening.
    //
    // I'm not sure whether the second condition is necessary, but without it, it would be impossible
    // to set the dimensions to zero after first measurement.
    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        if ((w > 0 && h > 0) || this.oldW > 0 || this.oldH > 0) {
            super.onSizeChanged(w, h, this.oldW, this.oldH);
            this.oldW = w;
            this.oldH = h;
        }
    }

    @Override
    public void loadComplete(int numberOfPages) {
        SizeF pageSize = getPageSize(0);
        float width = pageSize.getWidth();
        float height = pageSize.getHeight();

        this.zoomTo(this.scale);
        WritableMap event = Arguments.createMap();

        //create a new json Object for the TableOfContents
        Gson gson = new Gson();
        event.putString("message", "loadComplete|"+numberOfPages+"|"+width+"|"+height+"|"+gson.toJson(this.getTableOfContents()));

        ThemedReactContext context = (ThemedReactContext) getContext();
        EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
        int surfaceId = UIManagerHelper.getSurfaceId(this);

        TopChangeEvent tce = new TopChangeEvent(surfaceId, getId(), event);

        if (dispatcher != null) {
            dispatcher.dispatchEvent(tce);
        }
        //        ReactContext reactContext = (ReactContext)this.getContext();
//        reactContext.getJSModule(RCTEventEmitter.class).receiveEvent(
//            this.getId(),
//            "topChange",
//            event
//         );

        //Log.e("ReactNative", gson.toJson(this.getTableOfContents()));

    }

    @Override
    public void onError(Throwable t){
        WritableMap event = Arguments.createMap();
        if (t.getMessage().contains("Password required or incorrect password")) {
            event.putString("message", "error|Password required or incorrect password.");
        } else {
            event.putString("message", "error|"+t.getMessage());
        }

        ThemedReactContext context = (ThemedReactContext) getContext();
        EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
        int surfaceId = UIManagerHelper.getSurfaceId(this);

        TopChangeEvent tce = new TopChangeEvent(surfaceId, getId(), event);

        if (dispatcher != null) {
            dispatcher.dispatchEvent(tce);
        }

//        ReactContext reactContext = (ReactContext)this.getContext();
//        reactContext.getJSModule(RCTEventEmitter.class).receiveEvent(
//            this.getId(),
//            "topChange",
//            event
//         );
    }

    private void notifyOnChangeWithMessage(String message) {
        WritableMap event = Arguments.createMap();
        event.putString("message", message);

        ThemedReactContext context = (ThemedReactContext) getContext();
        EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
        int surfaceId = UIManagerHelper.getSurfaceId(this);

        TopChangeEvent tce = new TopChangeEvent(surfaceId, getId(), event);

        if (dispatcher != null) {
            dispatcher.dispatchEvent(tce);
        }
    }

    @Override
    public void onPageScrolled(int page, float positionOffset){

        // maybe change by other instance, restore zoom setting
        Constants.Pinch.MINIMUM_ZOOM = this.minScale;
        Constants.Pinch.MAXIMUM_ZOOM = this.maxScale;

        if (annotationOverlayView != null) {
            annotationOverlayView.invalidate();
        }

    }

    @Override
    public boolean onTap(MotionEvent e){

        // maybe change by other instance, restore zoom setting
        //Constants.Pinch.MINIMUM_ZOOM = this.minScale;
        //Constants.Pinch.MAXIMUM_ZOOM = this.maxScale;

        WritableMap event = Arguments.createMap();
        event.putString("message", "pageSingleTap|"+page+"|"+e.getX()+"|"+e.getY());

        ThemedReactContext context = (ThemedReactContext) getContext();
        EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
        int surfaceId = UIManagerHelper.getSurfaceId(this);

        TopChangeEvent tce = new TopChangeEvent(surfaceId, getId(), event);

        if (dispatcher != null) {
            dispatcher.dispatchEvent(tce);
        }
//        ReactContext reactContext = (ReactContext)this.getContext();
//        reactContext.getJSModule(RCTEventEmitter.class).receiveEvent(
//            this.getId(),
//            "topChange",
//            event
//         );

        // process as tap
         return true;

    }

    @Override
    public void onLayerDrawn(Canvas canvas, float pageWidth, float pageHeight, int displayedPage){
        if (originalWidth == 0) {
            originalWidth = pageWidth;
        }

        canvas.getMatrix(pageRenderMatrix);
        pageRenderMatrix.getValues(pageRenderMatrixValues);
        pageRenderInfoByIndex.put(displayedPage, new PageRenderInfo(
            pageRenderMatrixValues[Matrix.MTRANS_X] - getCurrentXOffset(),
            pageRenderMatrixValues[Matrix.MTRANS_Y] - getCurrentYOffset(),
            pageWidth,
            pageHeight
        ));

        if (lastPageWidth>0 && lastPageHeight>0 && (pageWidth!=lastPageWidth || pageHeight!=lastPageHeight)) {
            // maybe change by other instance, restore zoom setting
            Constants.Pinch.MINIMUM_ZOOM = this.minScale;
            Constants.Pinch.MAXIMUM_ZOOM = this.maxScale;

            WritableMap event = Arguments.createMap();
            event.putString("message", "scaleChanged|"+(pageWidth/originalWidth));
            ThemedReactContext context = (ThemedReactContext) getContext();
            EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
            int surfaceId = UIManagerHelper.getSurfaceId(this);

            TopChangeEvent tce = new TopChangeEvent(surfaceId, getId(), event);

            if (dispatcher != null) {
                dispatcher.dispatchEvent(tce);
            }
//            ReactContext reactContext = (ReactContext)this.getContext();
//            reactContext.getJSModule(RCTEventEmitter.class).receiveEvent(
//                this.getId(),
//                "topChange",
//                event
//             );
        }

        lastPageWidth = pageWidth;
        lastPageHeight = pageHeight;

        if (annotationOverlayView != null) {
            annotationOverlayView.invalidate();
        }
    }

    private void clearPageRenderInfo() {
        pageRenderInfoByIndex.clear();
        originalWidth = 0;
        lastPageWidth = 0;
        lastPageHeight = 0;
    }

    private PageRenderInfo getPageRenderInfo(int pageIndex) {
        PageRenderInfo pageRenderInfo = pageRenderInfoByIndex.get(pageIndex);
        if (pageRenderInfo != null) {
            return new PageRenderInfo(
                pageRenderInfo.left + getCurrentXOffset(),
                pageRenderInfo.top + getCurrentYOffset(),
                pageRenderInfo.width,
                pageRenderInfo.height
            );
        }

        SizeF pageSize = getPageSize(pageIndex);
        if (pageSize == null) {
            return null;
        }

        float zoom = getZoom();
        float scaledPageWidth = pageSize.getWidth() * zoom;
        float scaledPageHeight = pageSize.getHeight() * zoom;
        float horizontalMargin = Math.max(0f, (getWidth() - scaledPageWidth) / 2f);
        float pageTop = getFallbackPageTop(pageIndex, zoom) + getCurrentYOffset();
        return new PageRenderInfo(horizontalMargin, pageTop, scaledPageWidth, scaledPageHeight);
    }

    private float getFallbackPageTop(int pageIndex, float zoom) {
        float pageTop = 0f;
        for (int i = 0; i < pageIndex; i++) {
            SizeF previousPageSize = getPageSize(i);
            if (previousPageSize == null) {
                continue;
            }

            pageTop += previousPageSize.getHeight() * zoom;
            pageTop += spacing * zoom;
        }

        return pageTop;
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        if (this.isRecycled())
            this.drawPdf();
    }

    private int getPdfPageCount(File pdfFile) throws IOException {
        ParcelFileDescriptor fileDescriptor =
                ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY);
        PdfRenderer renderer = new PdfRenderer(fileDescriptor);
        int pageCount = renderer.getPageCount();
        renderer.close();
        fileDescriptor.close();
        return pageCount;
    }

    public void drawPdf() {
        showLog(format("drawPdf path:%s %s", this.path, this.page));
        clearPageRenderInfo();

        if (this.path != null){

            // set scale
            this.setMinZoom(this.minScale);
            this.setMaxZoom(this.maxScale);
            this.setMidZoom((this.maxScale+this.minScale)/2);
            Constants.Pinch.MINIMUM_ZOOM = this.minScale;
            Constants.Pinch.MAXIMUM_ZOOM = this.maxScale;

            Configurator configurator;

            if (this.path.startsWith("content://")) {
                ContentResolver contentResolver = getContext().getContentResolver();
                InputStream inputStream = null;
                Uri uri = Uri.parse(this.path);
                try {
                    inputStream = contentResolver.openInputStream(uri);
                } catch (FileNotFoundException e) {
                    throw new RuntimeException(e.getMessage());
                }
                configurator = this.fromStream(inputStream);
            } else {
                configurator = this.fromUri(getURI(this.path));
            }

            configurator.defaultPage(this.page-1)
                .swipeHorizontal(this.horizontal)
                .onPageChange(this)
                .onLoad(this)
                .onError(this)
                .onDraw(this)
                .onPageScroll(this)
                .spacing(this.spacing)
                .password(this.password)
                .enableAntialiasing(this.enableAntialiasing)
                .pageFitPolicy(this.fitPolicy)
                .pageSnap(this.pageSnap)
                .autoSpacing(this.autoSpacing)
                .pageFling(this.pageFling)
                .enableSwipe(!this.singlePage && this.scrollEnabled)
                .enableDoubletap(!this.singlePage && this.enableDoubleTapZoom)
                .enableAnnotationRendering(this.enableAnnotationRendering)
                .linkHandler(this)
            ;

            if (enableRTL) {
                try {
                    int pageCount = getPdfPageCount(new File(this.path));
                    int[] reversedPages = new int[pageCount];
                    for (int i=0; i<pageCount; i++) {
                        reversedPages[i] = pageCount-1 - i;
                    }
                    configurator.pages(reversedPages);
                    if(this.page != 1){
                        this.page = pageCount;
                    }
                } catch (IOException e) {
                    Log.e("error", "error while reading PDF", e);
                }
            }

            if (this.singlePage) {
                configurator.pages(this.page-1);
                setTouchesEnabled(false);
            } else {
                configurator.onTap(this);
            }

            configurator.load();
            updateAnnotationOverlayConfig();
            if (annotationOverlayView != null) {
                annotationOverlayView.invalidate();
            }
        }
    }

    public void setEnableDoubleTapZoom(boolean enableDoubleTapZoom) {
        this.enableDoubleTapZoom = enableDoubleTapZoom;
        updateAnnotationOverlayConfig();
    }

    public void setAnnotations(String annotations) {
        this.annotations = annotations;
        if (annotationOverlayView != null) {
            annotationOverlayView.replaceAnnotations(annotations);
        }
    }

    public void setAnnotationMode(boolean annotationMode) {
        this.annotationMode = annotationMode;
        updateAnnotationOverlayConfig();
    }

    public void setAnnotationTool(String annotationTool) {
        this.annotationTool = annotationTool;
        updateAnnotationOverlayConfig();
    }

    public void setAnnotationEditable(boolean annotationEditable) {
        this.annotationEditable = annotationEditable;
        updateAnnotationOverlayConfig();
    }

    public void setAnnotationIdMode(String annotationIdMode) {
        this.annotationIdMode = annotationIdMode;
        updateAnnotationOverlayConfig();
    }

    public void setAnnotationInkColor(String annotationInkColor) {
        this.annotationInkColor = TextUtils.isEmpty(annotationInkColor) ? "#111111" : annotationInkColor;
        updateAnnotationOverlayConfig();
    }

    public void setAnnotationInkThickness(float annotationInkThickness) {
        this.annotationInkThickness = annotationInkThickness > 0f ? annotationInkThickness : 2f;
        updateAnnotationOverlayConfig();
    }

    public void cleanup() {
        stopAutoScroll();
        if (!this.isRecycled()) {
            this.recycle();
        }
    }

    public void setPath(String path) {
        this.path = path;
    }

    // page start from 1
    public void setPage(int page) {
        this.page = Math.max(page, 1);
        this.handlePage(this.page - 1);
    }

    public void setEnableRTL(boolean enableRTL) {
        this.enableRTL = enableRTL;
        updateAnnotationOverlayConfig();
    }

    public void setScale(float scale) {
        this.scale = scale;
    }

    public void setMinScale(float minScale) {
        this.minScale = minScale;
    }

    public void setMaxScale(float maxScale) {
        this.maxScale = maxScale;
    }

    public void setHorizontal(boolean horizontal) {
        this.horizontal = horizontal;
        updateAnnotationOverlayConfig();
    }

    public void setScrollEnabled(boolean scrollEnabled) {
        this.scrollEnabled = scrollEnabled;
    }

    public void setSpacing(int spacing) {
        this.spacing = spacing;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public void setEnableAntialiasing(boolean enableAntialiasing) {
        this.enableAntialiasing = enableAntialiasing;
    }

    public void setEnableAnnotationRendering(boolean enableAnnotationRendering) {
        this.enableAnnotationRendering = enableAnnotationRendering;
    }

    public void setEnablePaging(boolean enablePaging) {
        this.enablePaging = enablePaging;
        if (this.enablePaging) {
            this.autoSpacing = true;
            this.pageFling = true;
            this.pageSnap = true;
        } else {
            this.autoSpacing = false;
            this.pageFling = false;
            this.pageSnap = false;
        }
        updateAnnotationOverlayConfig();
    }

    public void setFitPolicy(int fitPolicy) {
        switch(fitPolicy){
            case 0:
                this.fitPolicy = FitPolicy.WIDTH;
                break;
            case 1:
                this.fitPolicy = FitPolicy.HEIGHT;
                break;
            case 2:
            default:
            {
                this.fitPolicy = FitPolicy.BOTH;
                break;
            }
        }

    }

    public void setSinglePage(boolean singlePage) {
        this.singlePage = singlePage;
        updateAnnotationOverlayConfig();
    }

    private boolean isAnnotationEditingSupported() {
        return !this.horizontal && !this.enablePaging && !this.enableRTL && !this.singlePage;
    }

    private void updateAnnotationOverlayConfig() {
        if (annotationOverlayView != null) {
            annotationOverlayView.setConfiguration(
                this.annotationMode,
                this.annotationTool,
                this.annotationEditable,
                this.annotationIdMode,
                isAnnotationEditingSupported(),
                this.annotationInkColor,
                this.annotationInkThickness
            );
        }
    }

    private class AnnotationOverlayView extends FrameLayout {
        private final java.util.ArrayList<JSONObject> draftAnnotations = new java.util.ArrayList<>();
        private JSONObject activeInkAnnotation;
        private JSONObject activeMarkupAnnotation;
        private JSONObject activeTextAnnotation;
        private PointF markupStartNormalized;
        private EditText activeEditText;
        private String selectedAnnotationId;
        private JSONObject activeSelectionAnnotation;
        private String activeSelectionHandle = "body";
        private String activeSelectionMode = "none";
        private RectF activeSelectionStartBounds;
        private JSONArray activeSelectionStartPoints;
        private int activeSelectionPageIndex = -1;
        private float activeSelectionDownX;
        private float activeSelectionDownY;
        private boolean activeSelectionHasMoved;
        private final float touchSlop;
        private boolean annotationModeEnabled = false;
        private String tool = "select";
        private boolean editable = true;
        private String idMode = "auto";
        private boolean supported = true;
        private String inkColor = "#111111";
        private float inkThickness = 2f;

        AnnotationOverlayView(Context context) {
            super(context);
            setWillNotDraw(false);
            setBackgroundColor(Color.TRANSPARENT);
            setClickable(true);
            touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
        }

        void setConfiguration(boolean annotationMode, String annotationTool, boolean annotationEditable, String annotationIdMode, boolean annotationEditingSupported, String annotationInkColor, float annotationInkThickness) {
            annotationModeEnabled = annotationMode;
            tool = normalizeAnnotationType(annotationTool == null ? "select" : annotationTool);
            editable = annotationEditable;
            idMode = annotationIdMode == null ? "auto" : annotationIdMode;
            supported = annotationEditingSupported;
            inkColor = TextUtils.isEmpty(annotationInkColor) ? "#111111" : annotationInkColor;
            inkThickness = annotationInkThickness > 0f ? annotationInkThickness : 2f;

            if (!annotationModeEnabled || !editable || !supported) {
                commitTextEditingIfNeeded();
            }

            if (!annotationModeEnabled || !editable || !supported) {
                clearSelectionInteraction();
            }

            invalidate();
        }

        void deleteSelectedAnnotation() {
            JSONObject selectedAnnotation = getSelectedAnnotation();
            if (selectedAnnotation != null) {
                deleteAnnotation(selectedAnnotation);
            }
        }

        void deleteAllAnnotations() {
            commitTextEditingIfNeeded();
            draftAnnotations.clear();
            selectedAnnotationId = null;
            clearSelectionInteraction();
            invalidate();
        }

        void replaceAnnotations(String json) {
            draftAnnotations.clear();
            clearSelectionInteraction();
            if (TextUtils.isEmpty(json)) {
                invalidate();
                return;
            }

            try {
                JSONArray annotationsArray;
                try {
                    JSONObject document = new JSONObject(json);
                    annotationsArray = document.optJSONArray("annotations");
                } catch (JSONException objectError) {
                    annotationsArray = null;
                }

                if (annotationsArray == null) {
                    annotationsArray = new JSONArray(json);
                }

                for (int i = 0; i < annotationsArray.length(); i++) {
                    JSONObject source = annotationsArray.optJSONObject(i);
                    if (source == null) {
                        continue;
                    }

                    JSONObject annotation = new JSONObject(source.toString());
                    String type = normalizeAnnotationType(annotation.optString("type", null));
                    if (!TextUtils.isEmpty(type)) {
                        annotation.put("type", type);
                    }
                    if (!annotation.has("id")) {
                        annotation.put("id", nextLocalAnnotationId());
                    }
                    if (!annotation.has("page")) {
                        annotation.put("page", 1);
                    }
                    draftAnnotations.add(annotation);
                }
            } catch (JSONException ignored) {
            }

            invalidate();
        }

        String serializeDocument() {
            JSONObject document = new JSONObject();
            try {
                document.put("editable", editable);
                document.put("idMode", idMode);
                document.put("annotations", new JSONArray(draftAnnotations));
                return document.toString();
            } catch (JSONException e) {
                return "{}";
            }
        }

        @Override
        public boolean dispatchTouchEvent(MotionEvent event) {
            if (activeEditText != null && event.getActionMasked() == MotionEvent.ACTION_DOWN && !isPointInsideView(event.getX(), event.getY(), activeEditText)) {
                commitTextEditingIfNeeded();
            }

            return super.dispatchTouchEvent(event);
        }

        @Override
        public boolean onInterceptTouchEvent(MotionEvent ev) {
            if (!annotationModeEnabled || !editable || !supported) {
                return false;
            }

            if (ev.getPointerCount() > 1) {
                commitTextEditingIfNeeded();
                clearSelectionInteraction();
                return false;
            }

            String currentTool = tool == null ? "select" : tool;
            if ("select".equals(currentTool)) {
                return hitTestAnnotation(ev.getX(), ev.getY(), true) != null;
            }

            return !TextUtils.isEmpty(currentTool);
        }

        private boolean dispatchToParentPdfView(MotionEvent event) {
            return PdfView.this.dispatchToParentTouchListener(event);
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (!annotationModeEnabled || !editable || !supported) {
                return false;
            }

            if (event.getPointerCount() > 1) {
                commitTextEditingIfNeeded();
                clearSelectionInteraction();
                return dispatchToParentPdfView(event);
            }

            String currentTool = tool == null ? "select" : tool;
            if ("select".equals(currentTool)) {
                return handleSelectTouch(event);
            }

            int action = event.getActionMasked();
            if ("ink".equals(currentTool)) {
                if (action == MotionEvent.ACTION_DOWN) {
                    AnnotationHit hit = hitTest(event.getX(), event.getY());
                    if (hit == null) {
                        return false;
                    }
                    beginInk(hit, event.getX(), event.getY());
                    return true;
                } else if (action == MotionEvent.ACTION_MOVE) {
                    AnnotationHit hit = hitTest(event.getX(), event.getY());
                    if (hit != null) {
                        appendInkPoint(hit, event.getX(), event.getY());
                    }
                    return true;
                } else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                    endInk();
                    return true;
                }
            } else if ("text".equals(currentTool)) {
                if (action == MotionEvent.ACTION_UP) {
                    AnnotationHit hit = hitTest(event.getX(), event.getY());
                    if (hit != null) {
                        createTextAnnotation(hit, event.getX(), event.getY());
                        return true;
                    }
                }
            }

            return false;
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);

            if (PdfView.this.getPageCount() <= 0) {
                return;
            }

            Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

            for (JSONObject annotation : draftAnnotations) {
                int pageIndex = annotation.optInt("page", 1) - 1;
                if (pageIndex < 0 || pageIndex >= PdfView.this.getPageCount()) {
                    continue;
                }

                String type = normalizeAnnotationType(annotation.optString("type", ""));
                RectF rect = viewRectForAnnotation(annotation, pageIndex);
                if (rect == null && !"ink".equals(type)) {
                    continue;
                }

                if ("ink".equals(type)) {
                    JSONArray points = annotation.optJSONArray("points");
                    if (points == null || points.length() == 0) {
                        continue;
                    }

                    if (points.length() == 1) {
                        JSONObject point = points.optJSONObject(0);
                        if (point != null) {
                            float pageX = (float) point.optDouble("x", 0f);
                            float pageY = (float) point.optDouble("y", 0f);
                            PointF viewPoint = viewPointForNormalizedPoint(pageIndex, pageX, pageY);
                            float radius = Math.max(1f, (float) styleFor(annotation).optDouble("thickness", 2.0)) / 2f;
                            Paint dotPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
                            dotPaint.setStyle(Paint.Style.FILL);
                            dotPaint.setColor(annotationColor(annotation, Color.BLACK));
                            canvas.drawCircle(viewPoint.x, viewPoint.y, radius, dotPaint);
                        }
                        continue;
                    }

                    Path path = new Path();
                    boolean first = true;
                    for (int i = 0; i < points.length(); i++) {
                        JSONObject point = points.optJSONObject(i);
                        if (point == null) {
                            continue;
                        }

                        float pageX = (float) point.optDouble("x", 0f);
                        float pageY = (float) point.optDouble("y", 0f);
                        PointF viewPoint = viewPointForNormalizedPoint(pageIndex, pageX, pageY);
                        if (first) {
                            path.moveTo(viewPoint.x, viewPoint.y);
                            first = false;
                        } else {
                            path.lineTo(viewPoint.x, viewPoint.y);
                        }
                    }

                    strokePaint.setStyle(Paint.Style.STROKE);
                    strokePaint.setStrokeJoin(Paint.Join.ROUND);
                    strokePaint.setStrokeCap(Paint.Cap.ROUND);
                    strokePaint.setStrokeWidth(Math.max(1f, (float) styleFor(annotation).optDouble("thickness", 2.0)));
                    strokePaint.setColor(annotationColor(annotation, Color.BLACK));
                    canvas.drawPath(path, strokePaint);
                } else if ("text".equals(type)) {
                    fillPaint.setColor(Color.argb(200, 255, 255, 255));
                    canvas.drawRoundRect(rect, 4f, 4f, fillPaint);

                    strokePaint.setStyle(Paint.Style.STROKE);
                    strokePaint.setStrokeWidth(1f);
                    strokePaint.setColor(annotationColor(annotation, Color.rgb(34, 68, 170)));
                    canvas.drawRoundRect(rect, 4f, 4f, strokePaint);

                    textPaint.setColor(strokePaint.getColor());
                    textPaint.setTextSize((float) styleFor(annotation).optDouble("fontSize", 15.0));
                    textPaint.setTextAlign(Paint.Align.LEFT);
                    String text = annotation.optString("text", "");
                    canvas.drawText(text, rect.left + 8f, rect.top + Math.max(20f, textPaint.getTextSize() + 6f), textPaint);
                } else if ("highlight".equals(type)) {
                    fillPaint.setColor(annotationColor(annotation, annotationFillColor(type)));
                    canvas.drawRect(rect, fillPaint);
                }
            }

            drawSelectionDecorations(canvas);
            updateEditTextFrame();
        }

        private boolean handleSelectTouch(MotionEvent event) {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_DOWN) {
                clearSelectionInteraction();

                AnnotationSelectionHit hit = hitTestAnnotation(event.getX(), event.getY(), true);
                if (hit == null) {
                    return false;
                }

                selectAnnotation(hit.annotation);
                activeSelectionAnnotation = hit.annotation;
                activeSelectionHandle = hit.hitPart;
                activeSelectionMode = "resize".equals(hit.hitPart) ? "resize" : "move";
                activeSelectionPageIndex = hit.pageIndex;
                activeSelectionStartBounds = normalizedBoundsForAnnotation(hit.annotation);
                activeSelectionStartPoints = copyPointsForAnnotation(hit.annotation);
                activeSelectionDownX = event.getX();
                activeSelectionDownY = event.getY();
                activeSelectionHasMoved = false;

                return true;
            }

            if (activeSelectionAnnotation == null) {
                return false;
            }

            if (action == MotionEvent.ACTION_MOVE) {
                float deltaX = event.getX() - activeSelectionDownX;
                float deltaY = event.getY() - activeSelectionDownY;
                if (!activeSelectionHasMoved) {
                    if (Math.hypot(deltaX, deltaY) < touchSlop) {
                        return true;
                    }
                    activeSelectionHasMoved = true;
                }

                if ("move".equals(activeSelectionMode)) {
                    moveSelectedAnnotation(deltaX, deltaY);
                } else if ("resize".equals(activeSelectionMode)) {
                    resizeSelectedAnnotation(deltaX, deltaY);
                }
                return true;
            }

            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                if (!activeSelectionHasMoved && "body".equals(activeSelectionHandle)) {
                    // keep the annotation selected; tap selection is enough for now.
                }

                clearSelectionInteraction();
                return true;
            }

            return true;
        }

        private void drawSelectionDecorations(Canvas canvas) {
            if (!annotationModeEnabled || !editable || !supported) {
                return;
            }

            JSONObject annotation = getSelectedAnnotation();
            if (annotation == null) {
                return;
            }

            int pageIndex = annotation.optInt("page", 1) - 1;
            if (pageIndex < 0 || pageIndex >= PdfView.this.getPageCount()) {
                return;
            }

            RectF rect = viewRectForAnnotation(annotation, pageIndex);
            if (rect == null) {
                return;
            }

            Paint outlinePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            outlinePaint.setStyle(Paint.Style.STROKE);
            outlinePaint.setColor(Color.argb(220, 34, 68, 170));
            outlinePaint.setStrokeWidth(2f);

            Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            fillPaint.setStyle(Paint.Style.FILL);

            canvas.drawRoundRect(rect, 4f, 4f, outlinePaint);

            if (annotationSupportsResize(annotation)) {
                RectF resizeHandle = resizeHandleRect(rect);
                fillPaint.setColor(Color.argb(235, 34, 68, 170));
                canvas.drawRoundRect(resizeHandle, 2f, 2f, fillPaint);
            }
        }

        private void clearSelectionInteraction() {
            activeSelectionAnnotation = null;
            activeSelectionHandle = "body";
            activeSelectionMode = "none";
            activeSelectionStartBounds = null;
            activeSelectionStartPoints = null;
            activeSelectionPageIndex = -1;
            activeSelectionHasMoved = false;
            activeSelectionDownX = 0f;
            activeSelectionDownY = 0f;
        }

        private void selectAnnotation(JSONObject annotation) {
            if (annotation == null) {
                selectedAnnotationId = null;
                invalidate();
                return;
            }

            selectedAnnotationId = annotation.optString("id", null);
            invalidate();
        }

        private JSONObject getSelectedAnnotation() {
            if (TextUtils.isEmpty(selectedAnnotationId)) {
                return null;
            }

            for (int i = draftAnnotations.size() - 1; i >= 0; i--) {
                JSONObject annotation = draftAnnotations.get(i);
                if (selectedAnnotationId.equals(annotation.optString("id", null))) {
                    return annotation;
                }
            }

            return null;
        }

        private void deleteAnnotation(JSONObject annotation) {
            if (annotation == null) {
                return;
            }

            String annotationId = annotation.optString("id", null);
            for (int i = draftAnnotations.size() - 1; i >= 0; i--) {
                JSONObject candidate = draftAnnotations.get(i);
                if (annotationId != null && annotationId.equals(candidate.optString("id", null))) {
                    draftAnnotations.remove(i);
                    break;
                }
            }

            if (annotationId != null && annotationId.equals(selectedAnnotationId)) {
                selectedAnnotationId = null;
            }

            invalidate();
        }

        private RectF normalizedBoundsForAnnotation(JSONObject annotation) {
            if (annotation == null) {
                return null;
            }

            String type = annotation.optString("type", "");
            if ("ink".equals(type)) {
                JSONArray points = annotation.optJSONArray("points");
                if (points == null || points.length() == 0) {
                    return null;
                }

                float minX = Float.MAX_VALUE;
                float minY = Float.MAX_VALUE;
                float maxX = -Float.MAX_VALUE;
                float maxY = -Float.MAX_VALUE;
                for (int i = 0; i < points.length(); i++) {
                    JSONObject point = points.optJSONObject(i);
                    if (point == null) {
                        continue;
                    }

                    float x = (float) point.optDouble("x", 0f);
                    float y = (float) point.optDouble("y", 0f);
                    minX = Math.min(minX, x);
                    minY = Math.min(minY, y);
                    maxX = Math.max(maxX, x);
                    maxY = Math.max(maxY, y);
                }

                if (minX == Float.MAX_VALUE || minY == Float.MAX_VALUE || maxX == -Float.MAX_VALUE || maxY == -Float.MAX_VALUE) {
                    return null;
                }

                return new RectF(minX, minY, maxX, maxY);
            }

            JSONObject bounds = annotation.optJSONObject("bounds");
            if (bounds == null) {
                return null;
            }

            float x = (float) bounds.optDouble("x", 0f);
            float y = (float) bounds.optDouble("y", 0f);
            float width = (float) bounds.optDouble("width", 0f);
            float height = (float) bounds.optDouble("height", 0f);
            return new RectF(x, y, x + width, y + height);
        }

        private JSONArray copyPointsForAnnotation(JSONObject annotation) {
            if (annotation == null || !"ink".equals(annotation.optString("type", ""))) {
                return null;
            }

            JSONArray points = annotation.optJSONArray("points");
            if (points == null) {
                return null;
            }

            try {
                return new JSONArray(points.toString());
            } catch (JSONException ignored) {
                return null;
            }
        }

        private void moveSelectedAnnotation(float deltaX, float deltaY) {
            if (activeSelectionAnnotation == null || activeSelectionStartBounds == null || activeSelectionPageIndex < 0) {
                return;
            }

            PageRenderInfo pageRenderInfo = PdfView.this.getPageRenderInfo(activeSelectionPageIndex);
            if (pageRenderInfo == null) {
                return;
            }

            float scaledPageWidth = Math.max(1f, pageRenderInfo.width);
            float scaledPageHeight = Math.max(1f, pageRenderInfo.height);
            float normalizedDeltaX = deltaX / scaledPageWidth;
            float normalizedDeltaY = deltaY / scaledPageHeight;

            RectF newBounds = new RectF(
                activeSelectionStartBounds.left + normalizedDeltaX,
                activeSelectionStartBounds.top + normalizedDeltaY,
                activeSelectionStartBounds.right + normalizedDeltaX,
                activeSelectionStartBounds.bottom + normalizedDeltaY
            );

            setAnnotationFromNormalizedBounds(activeSelectionAnnotation, activeSelectionStartBounds, activeSelectionStartPoints, newBounds);
            invalidate();
        }

        private void resizeSelectedAnnotation(float deltaX, float deltaY) {
            if (activeSelectionAnnotation == null || activeSelectionStartBounds == null || activeSelectionPageIndex < 0) {
                return;
            }

            PageRenderInfo pageRenderInfo = PdfView.this.getPageRenderInfo(activeSelectionPageIndex);
            if (pageRenderInfo == null) {
                return;
            }

            float scaledPageWidth = Math.max(1f, pageRenderInfo.width);
            float scaledPageHeight = Math.max(1f, pageRenderInfo.height);
            float normalizedDeltaX = deltaX / scaledPageWidth;
            float normalizedDeltaY = deltaY / scaledPageHeight;

            RectF newBounds = new RectF(
                activeSelectionStartBounds.left,
                activeSelectionStartBounds.top,
                Math.max(activeSelectionStartBounds.left + 0.01f, activeSelectionStartBounds.right + normalizedDeltaX),
                Math.max(activeSelectionStartBounds.top + 0.01f, activeSelectionStartBounds.bottom + normalizedDeltaY)
            );

            setAnnotationFromNormalizedBounds(activeSelectionAnnotation, activeSelectionStartBounds, activeSelectionStartPoints, newBounds);
            invalidate();
        }

        private void setAnnotationFromNormalizedBounds(JSONObject annotation, RectF startBounds, JSONArray startPoints, RectF newBounds) {
            if (annotation == null || newBounds == null) {
                return;
            }

            String type = annotation.optString("type", "");
            if ("ink".equals(type)) {
                if (startPoints == null || startBounds == null) {
                    return;
                }

                try {
                    JSONArray points = new JSONArray();
                    float startWidth = Math.max(0.001f, startBounds.width());
                    float startHeight = Math.max(0.001f, startBounds.height());
                    float newWidth = Math.max(0.001f, newBounds.width());
                    float newHeight = Math.max(0.001f, newBounds.height());

                    for (int i = 0; i < startPoints.length(); i++) {
                        JSONObject point = startPoints.optJSONObject(i);
                        if (point == null) {
                            continue;
                        }

                        float pointX = (float) point.optDouble("x", 0f);
                        float pointY = (float) point.optDouble("y", 0f);
                        float xRatio = (pointX - startBounds.left) / startWidth;
                        float yRatio = (pointY - startBounds.top) / startHeight;

                        JSONObject transformed = new JSONObject();
                        transformed.put("x", Math.min(1f, Math.max(0f, newBounds.left + (xRatio * newWidth))));
                        transformed.put("y", Math.min(1f, Math.max(0f, newBounds.top + (yRatio * newHeight))));
                        points.put(transformed);
                    }

                    annotation.put("points", points);
                } catch (JSONException ignored) {
                }

                return;
            }

            try {
                annotation.put("bounds", new JSONObject()
                    .put("x", Math.min(1f, Math.max(0f, newBounds.left)))
                    .put("y", Math.min(1f, Math.max(0f, newBounds.top)))
                    .put("width", Math.min(1f, Math.max(0.01f, newBounds.width())))
                    .put("height", Math.min(1f, Math.max(0.01f, newBounds.height()))));
            } catch (JSONException ignored) {
            }
        }

        private RectF resizeHandleRect(RectF rect) {
            float size = Math.max(18f, Math.min(rect.width(), rect.height()) * 0.18f);
            return new RectF(rect.right - size, rect.bottom - size, rect.right, rect.bottom);
        }

        private AnnotationSelectionHit hitTestAnnotation(float x, float y, boolean includeHandles) {
            if (PdfView.this.getPageCount() <= 0) {
                return null;
            }

            for (int i = draftAnnotations.size() - 1; i >= 0; i--) {
                JSONObject annotation = draftAnnotations.get(i);
                int pageIndex = annotation.optInt("page", 1) - 1;
                if (pageIndex < 0 || pageIndex >= PdfView.this.getPageCount()) {
                    continue;
                }

                RectF rect = viewRectForAnnotation(annotation, pageIndex);
                if (rect == null) {
                    continue;
                }

                RectF hitRect = new RectF(rect);
                hitRect.inset(-12f, -12f);
                if (!hitRect.contains(x, y)) {
                    continue;
                }

                String hitPart = "body";
                if (includeHandles && selectedAnnotationId != null && selectedAnnotationId.equals(annotation.optString("id", null)) && annotationSupportsResize(annotation) && resizeHandleRect(rect).contains(x, y)) {
                    hitPart = "resize";
                }

                return new AnnotationSelectionHit(annotation, pageIndex, rect, hitPart);
            }

            return null;
        }

        private final class AnnotationSelectionHit {
            final JSONObject annotation;
            final int pageIndex;
            final RectF rect;
            final String hitPart;

            AnnotationSelectionHit(JSONObject annotation, int pageIndex, RectF rect, String hitPart) {
                this.annotation = annotation;
                this.pageIndex = pageIndex;
                this.rect = rect;
                this.hitPart = hitPart;
            }
        }

        private void beginInk(AnnotationHit hit, float x, float y) {
            try {
                JSONObject annotation = new JSONObject();
                annotation.put("id", nextLocalAnnotationId());
                annotation.put("page", hit.pageIndex + 1);
                annotation.put("type", "ink");
                annotation.put("points", new JSONArray());
                JSONObject style = new JSONObject();
                style.put("color", inkColor);
                style.put("thickness", inkThickness);
                annotation.put("style", style);
                draftAnnotations.add(annotation);
                activeInkAnnotation = annotation;
                appendInkPoint(hit, x, y);
            } catch (JSONException ignored) {
            }
        }

        private void appendInkPoint(AnnotationHit hit, float x, float y) {
            if (activeInkAnnotation == null) {
                return;
            }

            try {
                JSONArray points = activeInkAnnotation.optJSONArray("points");
                if (points == null) {
                    points = new JSONArray();
                    activeInkAnnotation.put("points", points);
                }

                PointF normalized = normalizedPointFor(hit, x, y);
                JSONObject point = new JSONObject();
                point.put("x", normalized.x);
                point.put("y", normalized.y);
                points.put(point);
                invalidate();
            } catch (JSONException ignored) {
            }
        }

        private void endInk() {
            activeInkAnnotation = null;
            invalidate();
            PdfView.this.notifyOnChangeWithMessage("strokeEnd");
        }

        private void beginMarkup(AnnotationHit hit, float x, float y, String type) {
            try {
                markupStartNormalized = normalizedPointFor(hit, x, y);
                JSONObject annotation = new JSONObject();
                annotation.put("id", nextLocalAnnotationId());
                annotation.put("page", hit.pageIndex + 1);
                annotation.put("type", normalizeAnnotationType(type));
                annotation.put("bounds", new JSONObject().put("x", markupStartNormalized.x).put("y", markupStartNormalized.y).put("width", 0).put("height", 0));
                annotation.put("style", new JSONObject());
                draftAnnotations.add(annotation);
                activeMarkupAnnotation = annotation;
                invalidate();
            } catch (JSONException ignored) {
            }
        }

        private void updateMarkup(AnnotationHit hit, float x, float y) {
            if (activeMarkupAnnotation == null || markupStartNormalized == null) {
                return;
            }

            try {
                PointF normalized = normalizedPointFor(hit, x, y);
                float minX = Math.min(markupStartNormalized.x, normalized.x);
                float minY = Math.min(markupStartNormalized.y, normalized.y);
                float maxX = Math.max(markupStartNormalized.x, normalized.x);
                float maxY = Math.max(markupStartNormalized.y, normalized.y);
                activeMarkupAnnotation.put("bounds", new JSONObject()
                    .put("x", minX)
                    .put("y", minY)
                    .put("width", Math.max(0f, maxX - minX))
                    .put("height", Math.max(0f, maxY - minY)));
                invalidate();
            } catch (JSONException ignored) {
            }
        }

        private void endMarkup() {
            activeMarkupAnnotation = null;
            markupStartNormalized = null;
            invalidate();
        }

        private void createTextAnnotation(AnnotationHit hit, float x, float y) {
            if (!editable || !supported) {
                return;
            }

            commitTextEditingIfNeeded();

            try {
                PointF normalized = normalizedPointFor(hit, x, y);
                float width = 0.25f;
                float height = 0.12f;
                float clampedX = Math.min(Math.max(normalized.x, 0f), Math.max(0f, 1f - width));
                float clampedY = Math.min(Math.max(normalized.y, 0f), Math.max(0f, 1f - height));

                JSONObject bounds = new JSONObject();
                bounds.put("x", clampedX);
                bounds.put("y", clampedY);
                bounds.put("width", width);
                bounds.put("height", height);

                JSONObject annotation = new JSONObject();
                annotation.put("id", nextLocalAnnotationId());
                annotation.put("page", hit.pageIndex + 1);
                annotation.put("type", "text");
                annotation.put("bounds", bounds);
                annotation.put("text", "");
                JSONObject style = new JSONObject();
                style.put("color", "#2244aa");
                style.put("fontSize", 15.0f);
                style.put("textAlign", "left");
                annotation.put("style", style);
                draftAnnotations.add(annotation);
                activeTextAnnotation = annotation;

                activeEditText = new EditText(getContext());
                activeEditText.setBackgroundColor(Color.argb(220, 255, 255, 255));
                activeEditText.setTextColor(Color.rgb(34, 68, 170));
                activeEditText.setPadding(12, 8, 12, 8);
                activeEditText.setSingleLine(false);
                activeEditText.setGravity(Gravity.TOP | Gravity.START);
                activeEditText.setTextSize(15f);
                activeEditText.addTextChangedListener(new TextWatcher() {
                    @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
                    @Override public void onTextChanged(CharSequence s, int start, int before, int count) { }
                    @Override public void afterTextChanged(Editable s) {
                        if (activeTextAnnotation != null) {
                            try {
                                activeTextAnnotation.put("text", s.toString());
                            } catch (JSONException ignored) {
                            }
                            invalidate();
                        }
                    }
                });

                addView(activeEditText, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
                activeEditText.requestFocus();
                updateEditTextFrame();
                invalidate();
            } catch (JSONException ignored) {
            }
        }

        void commitTextEditingIfNeeded() {
            if (activeEditText == null || activeTextAnnotation == null) {
                return;
            }

            try {
                activeTextAnnotation.put("text", activeEditText.getText() == null ? "" : activeEditText.getText().toString());
            } catch (JSONException ignored) {
            }

            activeEditText.clearFocus();
            removeView(activeEditText);
            activeEditText = null;
            activeTextAnnotation = null;
            invalidate();
        }

        private void updateEditTextFrame() {
            if (activeEditText == null || activeTextAnnotation == null) {
                return;
            }

            RectF rect = viewRectForAnnotation(activeTextAnnotation, activeTextAnnotation.optInt("page", 1) - 1);
            if (rect == null) {
                return;
            }

            ViewGroup.LayoutParams params = activeEditText.getLayoutParams();
            params.width = Math.max(1, Math.round(rect.width()));
            params.height = Math.max(1, Math.round(rect.height()));
            activeEditText.setLayoutParams(params);
            activeEditText.setX(rect.left);
            activeEditText.setY(rect.top);
        }

        private boolean isPointInsideView(float x, float y, View view) {
            if (view == null) {
                return false;
            }

            return x >= view.getX() && x <= view.getX() + view.getWidth() && y >= view.getY() && y <= view.getY() + view.getHeight();
        }

        private AnnotationHit hitTest(float x, float y) {
            if (PdfView.this.getPageCount() <= 0) {
                return null;
            }

            for (int i = 0; i < PdfView.this.getPageCount(); i++) {
                PageRenderInfo pageRenderInfo = PdfView.this.getPageRenderInfo(i);
                if (pageRenderInfo == null) {
                    continue;
                }

                if (x >= pageRenderInfo.left &&
                    x <= pageRenderInfo.left + pageRenderInfo.width &&
                    y >= pageRenderInfo.top &&
                    y <= pageRenderInfo.top + pageRenderInfo.height) {
                    return new AnnotationHit(i, pageRenderInfo);
                }
            }

            return null;
        }

        private PointF normalizedPointFor(AnnotationHit hit, float x, float y) {
            PageRenderInfo pageRenderInfo = hit.pageRenderInfo;
            float pageX = x - pageRenderInfo.left;
            float pageY = y - pageRenderInfo.top;
            return new PointF(
                pageX / Math.max(1f, pageRenderInfo.width),
                pageY / Math.max(1f, pageRenderInfo.height)
            );
        }

        private PointF viewPointForNormalizedPoint(int pageIndex, float normalizedX, float normalizedY) {
            PageRenderInfo pageRenderInfo = PdfView.this.getPageRenderInfo(pageIndex);
            if (pageRenderInfo == null) {
                return new PointF();
            }

            return new PointF(
                pageRenderInfo.left + (normalizedX * pageRenderInfo.width),
                pageRenderInfo.top + (normalizedY * pageRenderInfo.height)
            );
        }

        private RectF viewRectForAnnotation(JSONObject annotation, int pageIndex) {
            JSONObject bounds = annotation.optJSONObject("bounds");
            String type = annotation.optString("type", "");
            if (bounds == null && !"ink".equals(type)) {
                return null;
            }

            PageRenderInfo pageRenderInfo = PdfView.this.getPageRenderInfo(pageIndex);
            if (pageRenderInfo == null) {
                return null;
            }

            if ("ink".equals(type)) {
                JSONArray points = annotation.optJSONArray("points");
                if (points == null || points.length() == 0) {
                    return null;
                }

                float minX = Float.MAX_VALUE;
                float minY = Float.MAX_VALUE;
                float maxX = -Float.MAX_VALUE;
                float maxY = -Float.MAX_VALUE;
                for (int i = 0; i < points.length(); i++) {
                    JSONObject point = points.optJSONObject(i);
                    if (point == null) {
                        continue;
                    }

                    float pointX = (float) point.optDouble("x", 0f);
                    float pointY = (float) point.optDouble("y", 0f);
                    minX = Math.min(minX, pointX);
                    minY = Math.min(minY, pointY);
                    maxX = Math.max(maxX, pointX);
                    maxY = Math.max(maxY, pointY);
                }

                if (minX == Float.MAX_VALUE || minY == Float.MAX_VALUE || maxX == -Float.MAX_VALUE || maxY == -Float.MAX_VALUE) {
                    return null;
                }

                float left = pageRenderInfo.left + (minX * pageRenderInfo.width);
                float top = pageRenderInfo.top + (minY * pageRenderInfo.height);
                float right = pageRenderInfo.left + (maxX * pageRenderInfo.width);
                float bottom = pageRenderInfo.top + (maxY * pageRenderInfo.height);
                return new RectF(Math.min(left, right), Math.min(top, bottom), Math.max(left, right), Math.max(top, bottom));
            }

            float x = (float) bounds.optDouble("x", 0f);
            float y = (float) bounds.optDouble("y", 0f);
            float width = (float) bounds.optDouble("width", 0f);
            float height = (float) bounds.optDouble("height", 0f);

            float left = pageRenderInfo.left + (x * pageRenderInfo.width);
            float top = pageRenderInfo.top + (y * pageRenderInfo.height);
            float right = pageRenderInfo.left + ((x + width) * pageRenderInfo.width);
            float bottom = pageRenderInfo.top + ((y + height) * pageRenderInfo.height);

            return new RectF(Math.min(left, right), Math.min(top, bottom), Math.max(left, right), Math.max(top, bottom));
        }

        private JSONObject styleFor(JSONObject annotation) {
            JSONObject style = annotation.optJSONObject("style");
            return style == null ? new JSONObject() : style;
        }

        private String normalizeAnnotationType(String type) {
            if ("underline".equals(type) || "strikeout".equals(type)) {
                return "highlight";
            }

            return type;
        }

        private boolean annotationSupportsResize(JSONObject annotation) {
            String type = normalizeAnnotationType(annotation.optString("type", ""));
            return "text".equals(type) || "highlight".equals(type);
        }

        private int annotationColor(JSONObject annotation, int fallback) {
            String color = styleFor(annotation).optString("color", null);
            if (TextUtils.isEmpty(color)) {
                return fallback;
            }

            try {
                // Support CSS-standard #RRGGBBAA (alpha last) in addition to #RRGGBB
                if (color.startsWith("#") && color.length() == 9) {
                    int r = Integer.parseInt(color.substring(1, 3), 16);
                    int g = Integer.parseInt(color.substring(3, 5), 16);
                    int b = Integer.parseInt(color.substring(5, 7), 16);
                    int a = Integer.parseInt(color.substring(7, 9), 16);
                    return Color.argb(a, r, g, b);
                }
                return Color.parseColor(color);
            } catch (IllegalArgumentException ex) {
                return fallback;
            }
        }

        private int annotationFillColor(String type) {
            if ("highlight".equals(type) || "underline".equals(type) || "strikeout".equals(type)) {
                return Color.argb(90, 255, 230, 60);
            }

            return Color.BLACK;
        }

        private String nextLocalAnnotationId() {
            return "local-" + java.util.UUID.randomUUID().toString();
        }

        private final class AnnotationHit {
            final int pageIndex;
            final PageRenderInfo pageRenderInfo;

            AnnotationHit(int pageIndex, PageRenderInfo pageRenderInfo) {
                this.pageIndex = pageIndex;
                this.pageRenderInfo = pageRenderInfo;
            }
        }
    }

    /**
     * @see https://github.com/barteksc/AndroidPdfViewer/blob/master/android-pdf-viewer/src/main/java/com/github/barteksc/pdfviewer/link/DefaultLinkHandler.java
     */
    public void handleLinkEvent(LinkTapEvent event) {
        String uri = event.getLink().getUri();
        Integer page = event.getLink().getDestPageIdx();
        if (uri != null && !uri.isEmpty()) {
            handleUri(uri);
        } else if (page != null) {
            handlePage(page);
        }
    }

    /**
     * @see https://github.com/barteksc/AndroidPdfViewer/blob/master/android-pdf-viewer/src/main/java/com/github/barteksc/pdfviewer/link/DefaultLinkHandler.java
     */
    private void handleUri(String uri) {
        WritableMap event = Arguments.createMap();
        event.putString("message", "linkPressed|"+uri);

        ThemedReactContext context = (ThemedReactContext) getContext();
        EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
        int surfaceId = UIManagerHelper.getSurfaceId(this);

        TopChangeEvent tce = new TopChangeEvent(surfaceId, getId(), event);

        if (dispatcher != null) {
            dispatcher.dispatchEvent(tce);
        }

//        ReactContext reactContext = (ReactContext)this.getContext();
//        reactContext.getJSModule(RCTEventEmitter.class).receiveEvent(
//            this.getId(),
//            "topChange",
//            event
//        );
    }

    /**
     * @see https://github.com/barteksc/AndroidPdfViewer/blob/master/android-pdf-viewer/src/main/java/com/github/barteksc/pdfviewer/link/DefaultLinkHandler.java
     */
    private void handlePage(int page) {
        this.jumpTo(page);
    }

    public void saveAnnotations() {
        if (annotationOverlayView != null) {
            annotationOverlayView.commitTextEditingIfNeeded();
            notifyOnChangeWithMessage("annotationSaveComplete|" + annotationOverlayView.serializeDocument());
            return;
        }

        notifyOnChangeWithMessage("annotationSaveError|Annotation overlay unavailable");
    }

    public void deleteSelectedAnnotation() {
        if (annotationOverlayView != null) {
            annotationOverlayView.deleteSelectedAnnotation();
        }
    }

    public void deleteAllAnnotations() {
        if (annotationOverlayView != null) {
            annotationOverlayView.deleteAllAnnotations();
        }
    }

    private void showLog(final String str) {
        Log.d("PdfView", str);
    }

    private Uri getURI(final String uri) {
        Uri parsed = Uri.parse(uri);

        if (parsed.getScheme() == null || parsed.getScheme().isEmpty()) {
          return Uri.fromFile(new File(uri));
        }
        return parsed;
    }

    private void setTouchesEnabled(final boolean enabled) {
        setTouchesEnabled(this, enabled);
    }

    private static void setTouchesEnabled(View v, final boolean enabled) {
        if (enabled) {
            v.setOnTouchListener(null);
        } else {
            v.setOnTouchListener(new View.OnTouchListener() {
                @Override
                public boolean onTouch(View v, MotionEvent event) {
                    return true;
                }
            });
        }

        if (v instanceof ViewGroup) {
            ViewGroup vg = (ViewGroup) v;
            for (int i = 0; i < vg.getChildCount(); i++) {
                View child = vg.getChildAt(i);
                setTouchesEnabled(child, enabled);
            }
        }
    }

    // Autoscroll methods

    public void startAutoScroll(float dpPerSecond, long resumeDelayMs) {
        // Convert dp to physical pixels so scroll speed is consistent across screen densities
        float density = getResources().getDisplayMetrics().density;
        this.autoScrollPixels = dpPerSecond * density;
        this.autoScrollResumeDelay = resumeDelayMs;
        this.isAutoScrolling = true;
        this.lastFrameTimeNanos = 0;
        // Capture current position into float accumulator so doFrame never reads back
        // the rendering-quantised offset from getCurrentYOffset().
        this.accumulatedScrollOffset = -getCurrentYOffset(); // getCurrentYOffset() is negative

        if (autoScrollFrameCallback == null) {
            autoScrollFrameCallback = new Choreographer.FrameCallback() {
                @Override
                public void doFrame(long frameTimeNanos) {
                    if (!isAutoScrolling || isUserTouching) {
                        lastFrameTimeNanos = 0;
                        return;
                    }

                    // Skip first frame to establish baseline timestamp
                    if (lastFrameTimeNanos == 0) {
                        lastFrameTimeNanos = frameTimeNanos;
                        Choreographer.getInstance().postFrameCallback(this);
                        return;
                    }

                    float elapsedSeconds = (frameTimeNanos - lastFrameTimeNanos) / 1_000_000_000f;
                    lastFrameTimeNanos = frameTimeNanos;

                    // Accumulate into our own float – do NOT read getCurrentYOffset() back.
                    // barteksc may snap the rendered position to pixel boundaries; re-reading
                    // that snapped value each frame loses the fractional part and makes low
                    // speeds (< ~20 px/s) invisible.
                    accumulatedScrollOffset += autoScrollPixels * elapsedSeconds;

                    float totalHeight = 0;
                    int pageCount = getPageCount();
                    for (int i = 0; i < pageCount; i++) {
                        totalHeight += getPageSize(i).getHeight() * getZoom();
                    }
                    totalHeight += spacing * (pageCount - 1) * getZoom();
                    float maxScroll = totalHeight - getHeight();

                    if (maxScroll <= 0) {
                        stopAutoScroll();
                        dispatchAutoScrollEndEvent();
                        return;
                    }

                    if (accumulatedScrollOffset >= maxScroll) {
                        moveTo(0, -maxScroll);
                        stopAutoScroll();
                        dispatchAutoScrollEndEvent();
                        return;
                    }

                    moveTo(0, -accumulatedScrollOffset);
                    loadPages();
                    Choreographer.getInstance().postFrameCallback(this);
                }
            };
        }

        if (autoScrollResumeRunnable == null) {
            autoScrollResumeRunnable = new Runnable() {
                @Override
                public void run() {
                    if (isAutoScrolling && !isUserTouching) {
                        lastFrameTimeNanos = 0;
                        // Re-sync accumulator after user may have scrolled manually during pause.
                        accumulatedScrollOffset = -getCurrentYOffset();
                        Choreographer.getInstance().postFrameCallback(autoScrollFrameCallback);
                    }
                }
            };
        }

        Choreographer.getInstance().removeFrameCallback(autoScrollFrameCallback);
        Choreographer.getInstance().postFrameCallback(autoScrollFrameCallback);
    }

    public void stopAutoScroll() {
        this.isAutoScrolling = false;
        this.lastFrameTimeNanos = 0;
        if (autoScrollFrameCallback != null) {
            Choreographer.getInstance().removeFrameCallback(autoScrollFrameCallback);
        }
        if (autoScrollResumeHandler != null && autoScrollResumeRunnable != null) {
            autoScrollResumeHandler.removeCallbacks(autoScrollResumeRunnable);
        }
    }

    private void scheduleAutoScrollResume() {
        autoScrollResumeHandler.removeCallbacks(autoScrollResumeRunnable);
        autoScrollResumeHandler.postDelayed(autoScrollResumeRunnable, autoScrollResumeDelay);
    }

    private void dispatchAutoScrollEndEvent() {
        WritableMap event = Arguments.createMap();
        event.putString("message", "autoScrollEnd");

        ThemedReactContext context = (ThemedReactContext) getContext();
        EventDispatcher dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, getId());
        int surfaceId = UIManagerHelper.getSurfaceId(this);

        TopChangeEvent tce = new TopChangeEvent(surfaceId, getId(), event);

        if (dispatcher != null) {
            dispatcher.dispatchEvent(tce);
        }
    }
}
