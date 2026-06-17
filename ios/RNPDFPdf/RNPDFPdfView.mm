/**
 * Copyright (c) 2017-present, Wonday (@wonday.org)
 * All rights reserved.
 *
 * This source code is licensed under the MIT-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RNPDFPdfView.h"

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <PDFKit/PDFKit.h>

#if __has_include(<React/RCTAssert.h>)
#import <React/RCTBridgeModule.h>
#import <React/RCTEventDispatcher.h>
#import <React/UIView+React.h>
#import <React/RCTLog.h>
#import <React/RCTBlobManager.h>
#else
#import "RCTBridgeModule.h"
#import "RCTEventDispatcher.h"
#import "UIView+React.h"
#import "RCTLog.h"
#import <RCTBlobManager.h">
#endif

#ifdef RCT_NEW_ARCH_ENABLED
#import <React/RCTConversions.h>
#import <React/RCTFabricComponentsPlugins.h>
#import <react/renderer/components/rnpdf/ComponentDescriptors.h>
#import <react/renderer/components/rnpdf/Props.h>
#import <react/renderer/components/rnpdf/RCTComponentViewHelpers.h>

// Some RN private method hacking below similar to how it is done in RNScreens:
// https://github.com/software-mansion/react-native-screens/blob/90e548739f35b5ded2524a9d6410033fc233f586/ios/RNSScreenStackHeaderConfig.mm#L30
@interface RCTBridge (Private)
+ (RCTBridge *)currentBridge;
@end

#endif

#ifndef __OPTIMIZE__
// only output log when debug
#define DLog( s, ... ) NSLog( @"<%p %@:(%d)> %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )
#else
#define DLog( s, ... )
#endif

// output log both debug and release
#define RLog( s, ... ) NSLog( @"<%p %@:(%d)> %@", self, [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, [NSString stringWithFormat:(s), ##__VA_ARGS__] )

const float MAX_SCALE = 3.0f;
const float MIN_SCALE = 1.0f;
static void *RNPDFPdfScrollViewContentOffsetContext = &RNPDFPdfScrollViewContentOffsetContext;

@class RNPDFAnnotationOverlay;

@interface RNPDFAnnotationOverlay : UIView <UITextViewDelegate>
@property(nonatomic, weak) PDFView *pdfView;
@property(nonatomic, weak) PDFDocument *pdfDocument;
@property(nonatomic, assign) BOOL annotationMode;
@property(nonatomic, assign) BOOL annotationEditable;
@property(nonatomic, copy) NSString *annotationTool;
@property(nonatomic, copy) NSString *annotationIdMode;
@property(nonatomic, copy) NSString *annotationInkColor;
@property(nonatomic, assign) CGFloat annotationInkThickness;

- (void)replaceAnnotationsJSONString:(NSString *)json editable:(BOOL)editable idMode:(NSString *)idMode;
- (void)setAnnotationMode:(BOOL)annotationMode tool:(NSString *)tool editable:(BOOL)editable idMode:(NSString *)idMode;
- (void)setInkDefaultsColor:(NSString *)color thickness:(CGFloat)thickness;
- (void)beginInkAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page;
- (void)appendInkPointAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page;
- (void)endInk;
- (void)beginMarkupAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page type:(NSString *)type;
- (void)updateMarkupAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page;
- (void)endMarkup;
- (void)createTextAnnotationAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page;
- (NSDictionary *)annotationSelectionHitAtPoint:(CGPoint)point includeHandles:(BOOL)includeHandles;
- (void)selectAnnotation:(NSDictionary *)annotation;
- (void)clearSelection;
- (void)deleteAnnotation:(NSDictionary *)annotation;
- (void)deleteSelectedAnnotation;
- (void)deleteAllAnnotations;
- (void)refreshDisplay;
- (void)beginSelectionInteractionAtPoint:(CGPoint)point hit:(NSDictionary *)hit;
- (void)updateSelectionInteractionAtPoint:(CGPoint)point;
- (void)endSelectionInteraction;
- (void)commitTextEditingIfNeeded;
- (NSString *)serializedDocumentJSONStringWithEditable:(BOOL)editable idMode:(NSString *)idMode;
@end

@interface RNPDFPdfView() <PDFDocumentDelegate, PDFViewDelegate
#ifdef RCT_NEW_ARCH_ENABLED
, RCTRNPDFPdfViewViewProtocol
#endif
>
@end

@implementation RNPDFPdfView
{
    RCTBridge *_bridge;
    PDFDocument *_pdfDocument;
    PDFView *_pdfView;
    NSString *_loadedDocumentPath;
    PDFOutline *root;
    float _fixScaleFactor;
    bool _initialed;
    NSArray<NSString *> *_changedProps;
    UITapGestureRecognizer *_doubleTapRecognizer;
    UITapGestureRecognizer *_singleTapRecognizer;
    UIPinchGestureRecognizer *_pinchRecognizer;
    UILongPressGestureRecognizer *_longPressRecognizer;
    UITapGestureRecognizer *_doubleTapEmptyRecognizer;
    UIPanGestureRecognizer *_annotationPanRecognizer;
    RNPDFAnnotationOverlay *_annotationOverlay;

    // Autoscroll
    CADisplayLink *_displayLink;
    NSTimer *_autoScrollResumeTimer;
    CGFloat _autoScrollPixels;        // points per second (dp maps 1:1 to iOS points)
    NSTimeInterval _autoScrollResumeDelay;
    BOOL _isAutoScrolling;
    BOOL _isUserDragging;
    UIScrollView *_pdfScrollView;
    UIPanGestureRecognizer *_pdfScrollPanRecognizer;
    BOOL _isObservingPdfScrollView;
    CGFloat _autoScrollCurrentOffset; // float accumulator – avoids re-reading UIKit's quantized contentOffset
}

#ifdef RCT_NEW_ARCH_ENABLED

using namespace facebook::react;

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<RNPDFPdfViewComponentDescriptor>();
}

// Needed because of this: https://github.com/facebook/react-native/pull/37274
+ (void)load
{
  [super load];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        static const auto defaultProps = std::make_shared<const RNPDFPdfViewProps>();
        _props = defaultProps;
        [self initCommonProps];
    }
    return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
    const auto &newProps = *std::static_pointer_cast<const RNPDFPdfViewProps>(props);
    NSMutableArray<NSString *> *updatedPropNames = [NSMutableArray new];
    {
        NSString *newPath = RCTNSStringFromStringNilIfEmpty(newProps.path);
        if (_path != newPath && ![_path isEqualToString:newPath]) {
            _path = newPath;
            [updatedPropNames addObject:@"path"];
        }
    }
    if (_page != newProps.page) {
        _page = newProps.page;
        [updatedPropNames addObject:@"page"];
    }
    if (_scale != newProps.scale) {
        _scale = newProps.scale;
        [updatedPropNames addObject:@"scale"];
    }
    if (_minScale != newProps.minScale) {
        _minScale = newProps.minScale;
        [updatedPropNames addObject:@"minScale"];
    }
    if (_maxScale != newProps.maxScale) {
        _maxScale = newProps.maxScale;
        [updatedPropNames addObject:@"maxScale"];
    }
    if (_horizontal != newProps.horizontal) {
        _horizontal = newProps.horizontal;
        [updatedPropNames addObject:@"horizontal"];
    }
    if (_enablePaging != newProps.enablePaging) {
        _enablePaging = newProps.enablePaging;
        [updatedPropNames addObject:@"enablePaging"];
    }
    if (_enableRTL != newProps.enableRTL) {
        _enableRTL = newProps.enableRTL;
        [updatedPropNames addObject:@"enableRTL"];
    }
    if (_enableAnnotationRendering != newProps.enableAnnotationRendering) {
        _enableAnnotationRendering = newProps.enableAnnotationRendering;
        [updatedPropNames addObject:@"enableAnnotationRendering"];
    }
    if (_enableDoubleTapZoom != newProps.enableDoubleTapZoom) {
        _enableDoubleTapZoom = newProps.enableDoubleTapZoom;
        [updatedPropNames addObject:@"enableDoubleTapZoom"];
    }
    {
        NSString *newAnnotations = RCTNSStringFromStringNilIfEmpty(newProps.annotations);
        if (_annotations != newAnnotations && ![_annotations isEqualToString:newAnnotations]) {
            _annotations = newAnnotations;
            [updatedPropNames addObject:@"annotations"];
        }
    }
    if (_annotationMode != newProps.annotationMode) {
        _annotationMode = newProps.annotationMode;
        [updatedPropNames addObject:@"annotationMode"];
    }
    if (_annotationTool != RCTNSStringFromStringNilIfEmpty(newProps.annotationTool)) {
        _annotationTool = RCTNSStringFromStringNilIfEmpty(newProps.annotationTool);
        [updatedPropNames addObject:@"annotationTool"];
    }
    if (_annotationEditable != newProps.annotationEditable) {
        _annotationEditable = newProps.annotationEditable;
        [updatedPropNames addObject:@"annotationEditable"];
    }
    if (_annotationIdMode != RCTNSStringFromStringNilIfEmpty(newProps.annotationIdMode)) {
        _annotationIdMode = RCTNSStringFromStringNilIfEmpty(newProps.annotationIdMode);
        [updatedPropNames addObject:@"annotationIdMode"];
    }
    if (_annotationInkColor != RCTNSStringFromStringNilIfEmpty(newProps.annotationInkColor)) {
        _annotationInkColor = RCTNSStringFromStringNilIfEmpty(newProps.annotationInkColor);
        [updatedPropNames addObject:@"annotationInkColor"];
    }
    if (_annotationInkThickness != newProps.annotationInkThickness) {
        _annotationInkThickness = newProps.annotationInkThickness;
        [updatedPropNames addObject:@"annotationInkThickness"];
    }
    if (_fitPolicy != newProps.fitPolicy) {
        _fitPolicy = newProps.fitPolicy;
        [updatedPropNames addObject:@"fitPolicy"];
    }
    if (_spacing != newProps.spacing) {
        _spacing = newProps.spacing;
        [updatedPropNames addObject:@"spacing"];
    }
    if (_password != RCTNSStringFromStringNilIfEmpty(newProps.password)) {
        _password = RCTNSStringFromStringNilIfEmpty(newProps.password);
        [updatedPropNames addObject:@"password"];
    }
    if (_singlePage != newProps.singlePage) {
        _singlePage = newProps.singlePage;
        [updatedPropNames addObject:@"singlePage"];
    }
    if (_showsHorizontalScrollIndicator != newProps.showsHorizontalScrollIndicator) {
        _showsHorizontalScrollIndicator = newProps.showsHorizontalScrollIndicator;
        [updatedPropNames addObject:@"showsHorizontalScrollIndicator"];
    }
    if (_showsVerticalScrollIndicator != newProps.showsVerticalScrollIndicator) {
        _showsVerticalScrollIndicator = newProps.showsVerticalScrollIndicator;
        [updatedPropNames addObject:@"showsVerticalScrollIndicator"];
    }

    if (_scrollEnabled != newProps.scrollEnabled) {
        _scrollEnabled = newProps.scrollEnabled;
        [updatedPropNames addObject:@"scrollEnabled"];
    }

    [super updateProps:props oldProps:oldProps];
    [self didSetProps:updatedPropNames];

    if (_annotationOverlay) {
        if ([updatedPropNames containsObject:@"annotations"] || [updatedPropNames containsObject:@"path"]) {
            [_annotationOverlay replaceAnnotationsJSONString:_annotations editable:_annotationEditable idMode:_annotationIdMode];
        }
        [_annotationOverlay setAnnotationMode:_annotationMode tool:_annotationTool editable:_annotationEditable idMode:_annotationIdMode];
        [_annotationOverlay setInkDefaultsColor:_annotationInkColor thickness:_annotationInkThickness];
        _annotationOverlay.pdfView = _pdfView;
        _annotationOverlay.pdfDocument = _pdfDocument;
    }
}

// already added in case https://github.com/facebook/react-native/pull/35378 has been merged
- (BOOL)shouldBeRecycled
{
    return NO;
}

- (void)prepareForRecycle
{
    [super prepareForRecycle];

    [self stopAutoScroll];
    [self unbindPdfScrollViewObservation];

    [_pdfView removeFromSuperview];
    _pdfDocument = Nil;
    _pdfView = Nil;
    //Remove notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewDocumentChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewPageChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewScaleChangedNotification" object:nil];

    // remove old recognizers before adding new ones
    [self removeGestureRecognizer:_doubleTapRecognizer];
    [self removeGestureRecognizer:_singleTapRecognizer];
    [self removeGestureRecognizer:_pinchRecognizer];
    [self removeGestureRecognizer:_longPressRecognizer];
    [self removeGestureRecognizer:_doubleTapEmptyRecognizer];
    [self removeGestureRecognizer:_annotationPanRecognizer];

    [_annotationOverlay removeFromSuperview];
    _annotationOverlay = nil;

    [self initCommonProps];
}

- (void)updateLayoutMetrics:(const facebook::react::LayoutMetrics &)layoutMetrics oldLayoutMetrics:(const facebook::react::LayoutMetrics &)oldLayoutMetrics
{
    // Fabric equivalent of `reactSetFrame` method
    [super updateLayoutMetrics:layoutMetrics oldLayoutMetrics:oldLayoutMetrics];
    _pdfView.frame = CGRectMake(0, 0, layoutMetrics.frame.size.width, layoutMetrics.frame.size.height);
    _annotationOverlay.frame = CGRectMake(0, 0, layoutMetrics.frame.size.width, layoutMetrics.frame.size.height);

    NSMutableArray *mProps = [_changedProps mutableCopy];
    if (_initialed) {
        [mProps removeObject:@"path"];
    }
    _initialed = YES;

    [self didSetProps:mProps];
}

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args
{
  RCTRNPDFPdfViewHandleCommand(self, commandName, args);
}

- (void)setNativePage:(NSInteger)page
{
    _page = page;
    [self didSetProps:[NSArray arrayWithObject:@"page"]];
}

- (void)startNativeAutoScroll:(double)pixels resumeDelay:(double)resumeDelay
{
    [self startAutoScroll:(CGFloat)pixels resumeDelay:(NSTimeInterval)(resumeDelay / 1000.0)];
}

- (void)stopNativeAutoScroll
{
    [self stopAutoScroll];
}

#endif

- (instancetype)initWithBridge:(RCTBridge *)bridge
{
    self = [super init];
    if (self) {
        _bridge = bridge;
        [self initCommonProps];
    }

    return self;
}

- (void)initCommonProps
{
    _path = nil;
    _loadedDocumentPath = nil;
    _password = nil;
    _annotations = nil;
    _annotationMode = NO;
    _annotationEditable = NO;
    _annotationTool = nil;
    _annotationIdMode = nil;
    _page = 1;
    _scale = 1;
    _minScale = MIN_SCALE;
    _maxScale = MAX_SCALE;
    _horizontal = NO;
    _enablePaging = NO;
    _enableRTL = NO;
    _enableAnnotationRendering = YES;
    _enableDoubleTapZoom = YES;
    _fitPolicy = 2;
    _spacing = 10;
    _singlePage = NO;
    _showsHorizontalScrollIndicator = YES;
    _showsVerticalScrollIndicator = YES;
    _scrollEnabled = YES;
    _annotationInkColor = @"#111111";
    _annotationInkThickness = 2.0f;
    _enableTextSelection = YES;
    _selectedText = nil;
    _currentPDFSelection = nil;

    // init and config PDFView
    _pdfView = [[PDFView alloc] initWithFrame:CGRectMake(0, 0, 500, 500)];
    _pdfView.displayMode = kPDFDisplaySinglePageContinuous;
    _pdfView.autoScales = YES;
    _pdfView.displaysPageBreaks = YES;
    _pdfView.displayBox = kPDFDisplayBoxCropBox;
    _pdfView.backgroundColor = [UIColor clearColor];

    _fixScaleFactor = -1.0f;
    _initialed = NO;
    _changedProps = NULL;

    // Autoscroll defaults
    _autoScrollPixels = 15.0f;   // dp/sec
    _autoScrollResumeDelay = 3.0;
    _isAutoScrolling = NO;
    _isUserDragging = NO;
    _pdfScrollView = nil;
    _pdfScrollPanRecognizer = nil;
    _isObservingPdfScrollView = NO;
    _autoScrollCurrentOffset = 0.0;

    [self addSubview:_pdfView];
    _annotationOverlay = [[RNPDFAnnotationOverlay alloc] initWithFrame:self.bounds];
    _annotationOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _annotationOverlay.backgroundColor = UIColor.clearColor;
    _annotationOverlay.userInteractionEnabled = YES;
    [_annotationOverlay setInkDefaultsColor:_annotationInkColor thickness:_annotationInkThickness];
    [self addSubview:_annotationOverlay];
    [self bringSubviewToFront:_annotationOverlay];


    // register notification
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(onDocumentChanged:) name:PDFViewDocumentChangedNotification object:_pdfView];
    [center addObserver:self selector:@selector(onPageChanged:) name:PDFViewPageChangedNotification object:_pdfView];
    [center addObserver:self selector:@selector(onScaleChanged:) name:PDFViewScaleChangedNotification object:_pdfView];

    [[_pdfView document] setDelegate: self];
    [_pdfView setDelegate: self];

    // Disable built-in double tap, so as not to conflict with custom recognizers.
    for (UIGestureRecognizer *recognizer in _pdfView.gestureRecognizers) {
        if ([recognizer isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)recognizer;
            if (tap.numberOfTapsRequired == 2) {
                recognizer.enabled = NO;
            }
        }
    }

    [self bindTap];

    // Register for selection change notifications
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                         selector:@selector(handleSelectionChanged:) 
                                             name:PDFViewSelectionChangedNotification 
                                           object:_pdfView];
}

- (void)PDFViewWillClickOnLink:(PDFView *)sender withURL:(NSURL *)url
{
    NSString *_url = url.absoluteString;
    [self notifyOnChangeWithMessage:
                     [[NSString alloc] initWithString:
                      [NSString stringWithFormat:
                       @"linkPressed|%s", _url.UTF8String]]];
}

- (void)handleSelectionChanged:(NSNotification *)notification
{
    if (!_enableTextSelection || notification.object != _pdfView) return;
    
    // Store a copy of the selection to avoid it being cleared
    _currentPDFSelection = [_pdfView.currentSelection copy];
    
    if (_currentPDFSelection && _currentPDFSelection.string.length > 0) {
        _selectedText = _currentPDFSelection.string;
        
        // Use the existing onChange callback with a message format
        [self notifyOnChangeWithMessage:
         [[NSString alloc] initWithString:
          [NSString stringWithFormat:@"textSelected|%@", _selectedText]]];
    } else {
        _selectedText = nil;
        
        // Use the existing onChange callback for clearing
        [self notifyOnChangeWithMessage:@"textSelectionCleared"];
    }
}

- (void)didSetProps:(NSArray<NSString *> *)changedProps
{
    if (!_initialed) {

        _changedProps = changedProps;

        BOOL needsDocumentLoad = _path.length > 0 && (_pdfDocument == Nil || ![_loadedDocumentPath isEqualToString:_path]);
        if (needsDocumentLoad) {
            if (_pdfDocument != Nil) {
                _pdfDocument = Nil;
            }
            _loadedDocumentPath = nil;

            if ([_path hasPrefix:@"blob:"]) {
                RCTBlobManager *blobManager = [
#ifdef RCT_NEW_ARCH_ENABLED
        [RCTBridge currentBridge]
#else
        _bridge
#endif // RCT_NEW_ARCH_ENABLED
                    moduleForName:@"BlobModule"];
                NSURL *blobURL = [NSURL URLWithString:_path];
                NSData *blobData = [blobManager resolveURL:blobURL];
                if (blobData != nil) {
                    _pdfDocument = [[PDFDocument alloc] initWithData:blobData];
                }
            } else {
                NSString *decodedPath = (__bridge_transfer NSString *)CFURLCreateStringByReplacingPercentEscapes(NULL, (CFStringRef)_path, CFSTR(""));
                if (decodedPath != nil) {
                    _path = decodedPath;
                }
                NSURL *fileURL = [NSURL fileURLWithPath:_path];
                _pdfDocument = [[PDFDocument alloc] initWithURL:fileURL];
            }

            if (_pdfDocument) {
                if (_pdfDocument.isLocked && ![_pdfDocument unlockWithPassword:_password]) {
                    [self notifyOnChangeWithMessage:@"error|Password required or incorrect password."];
                    _pdfDocument = Nil;
                    return;
                }

                _loadedDocumentPath = [_path copy];
                _pdfView.document = _pdfDocument;
                if (_annotationOverlay) {
                    _annotationOverlay.pdfView = _pdfView;
                    _annotationOverlay.pdfDocument = _pdfDocument;
                }
            } else {
                [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"error|Load pdf failed. path=%s",_path.UTF8String]]];
                _pdfDocument = Nil;
                return;
            }
        }

    } else {

        BOOL needsDocumentLoad = _path.length > 0 && (_pdfDocument == Nil || ![_loadedDocumentPath isEqualToString:_path]);

        if (needsDocumentLoad) {


            if (_pdfDocument != Nil) {
                //Release old doc
                _pdfDocument = Nil;
            }
            _loadedDocumentPath = nil;
            
            if ([_path hasPrefix:@"blob:"]) {
                RCTBlobManager *blobManager = [
#ifdef RCT_NEW_ARCH_ENABLED
        [RCTBridge currentBridge]
#else
        _bridge
#endif // RCT_NEW_ARCH_ENABLED
                    moduleForName:@"BlobModule"];
                NSURL *blobURL = [NSURL URLWithString:_path];
                NSData *blobData = [blobManager resolveURL:blobURL];
                if (blobData != nil) {
                    _pdfDocument = [[PDFDocument alloc] initWithData:blobData];
                }
            } else {
            
                // decode file path
                NSString *decodedPath = (__bridge_transfer NSString *)CFURLCreateStringByReplacingPercentEscapes(NULL, (CFStringRef)_path, CFSTR(""));
                if (decodedPath != nil) {
                    _path = decodedPath;
                }
                NSURL *fileURL = [NSURL fileURLWithPath:_path];
                _pdfDocument = [[PDFDocument alloc] initWithURL:fileURL];
            }

            if (_pdfDocument) {

                //check need password or not
                if (_pdfDocument.isLocked && ![_pdfDocument unlockWithPassword:_password]) {

                    [self notifyOnChangeWithMessage:@"error|Password required or incorrect password."];

                    _pdfDocument = Nil;
                    return;
                }

                _loadedDocumentPath = [_path copy];
                _pdfView.document = _pdfDocument;
                if (_annotationOverlay) {
                    _annotationOverlay.pdfView = _pdfView;
                    _annotationOverlay.pdfDocument = _pdfDocument;
                }
            } else {

                [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"error|Load pdf failed. path=%s",_path.UTF8String]]];

                _pdfDocument = Nil;
                return;
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"spacing"])) {
            if (_horizontal) {
                _pdfView.pageBreakMargins = UIEdgeInsetsMake(0,_spacing,0,0);
                if (_spacing==0) {
                    if (@available(iOS 12.0, *)) {
                        _pdfView.pageShadowsEnabled = NO;
                    }
                } else {
                    if (@available(iOS 12.0, *)) {
                        _pdfView.pageShadowsEnabled = YES;
                    }
                }
            } else {
                _pdfView.pageBreakMargins = UIEdgeInsetsMake(0,0,_spacing,0);
                if (_spacing==0) {
                    if (@available(iOS 12.0, *)) {
                        _pdfView.pageShadowsEnabled = NO;
                    }
                } else {
                    if (@available(iOS 12.0, *)) {
                        _pdfView.pageShadowsEnabled = YES;
                    }
                }
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"enableRTL"])) {
            _pdfView.displaysRTL = _enableRTL;
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"enableAnnotationRendering"])) {
            if (!_enableAnnotationRendering) {
                for (unsigned long i=0; i<_pdfView.document.pageCount; i++) {
                    PDFPage *pdfPage = [_pdfView.document pageAtIndex:i];
                    for (unsigned long j=0; j<pdfPage.annotations.count; j++) {
                        pdfPage.annotations[j].shouldDisplay = _enableAnnotationRendering;
                    }
                }
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"fitPolicy"] || [changedProps containsObject:@"minScale"] || [changedProps containsObject:@"maxScale"])) {

            PDFPage *pdfPage = _pdfView.currentPage ? _pdfView.currentPage : [_pdfDocument pageAtIndex:_pdfDocument.pageCount-1];
            CGRect pdfPageRect = [pdfPage boundsForBox:kPDFDisplayBoxCropBox];

            // some pdf with rotation, then adjust it
            if (pdfPage.rotation == 90 || pdfPage.rotation == 270) {
                pdfPageRect = CGRectMake(0, 0, pdfPageRect.size.height, pdfPageRect.size.width);
            }

            if (_fitPolicy == 0) {
                _fixScaleFactor = self.frame.size.width/pdfPageRect.size.width;
                _pdfView.scaleFactor = _scale * _fixScaleFactor;
                _pdfView.minScaleFactor = _fixScaleFactor*_minScale;
                _pdfView.maxScaleFactor = _fixScaleFactor*_maxScale;
            } else if (_fitPolicy == 1) {
                _fixScaleFactor = self.frame.size.height/pdfPageRect.size.height;
                _pdfView.scaleFactor = _scale * _fixScaleFactor;
                _pdfView.minScaleFactor = _fixScaleFactor*_minScale;
                _pdfView.maxScaleFactor = _fixScaleFactor*_maxScale;
            } else {
                float pageAspect = pdfPageRect.size.width/pdfPageRect.size.height;
                float reactViewAspect = self.frame.size.width/self.frame.size.height;
                if (reactViewAspect>pageAspect) {
                    _fixScaleFactor = self.frame.size.height/pdfPageRect.size.height;
                    _pdfView.scaleFactor = _scale * _fixScaleFactor;
                    _pdfView.minScaleFactor = _fixScaleFactor*_minScale;
                    _pdfView.maxScaleFactor = _fixScaleFactor*_maxScale;
                } else {
                    _fixScaleFactor = self.frame.size.width/pdfPageRect.size.width;
                    _pdfView.scaleFactor = _scale * _fixScaleFactor;
                    _pdfView.minScaleFactor = _fixScaleFactor*_minScale;
                    _pdfView.maxScaleFactor = _fixScaleFactor*_maxScale;
                }
            }

        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"scale"])) {
            _pdfView.scaleFactor = _scale * _fixScaleFactor;
            if (_pdfView.scaleFactor>_pdfView.maxScaleFactor) _pdfView.scaleFactor = _pdfView.maxScaleFactor;
            if (_pdfView.scaleFactor<_pdfView.minScaleFactor) _pdfView.scaleFactor = _pdfView.minScaleFactor;
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"horizontal"])) {
            if (_horizontal) {
                _pdfView.displayDirection = kPDFDisplayDirectionHorizontal;
                _pdfView.pageBreakMargins = UIEdgeInsetsMake(0,_spacing,0,0);
            } else {
                _pdfView.displayDirection = kPDFDisplayDirectionVertical;
                _pdfView.pageBreakMargins = UIEdgeInsetsMake(0,0,_spacing,0);
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"enablePaging"])) {
            if (_enablePaging) {
                [_pdfView usePageViewController:YES withViewOptions:@{UIPageViewControllerOptionSpineLocationKey:@(UIPageViewControllerSpineLocationMin),UIPageViewControllerOptionInterPageSpacingKey:@(_spacing)}];
            } else {
                [_pdfView usePageViewController:NO withViewOptions:Nil];
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"singlePage"])) {
            if (_singlePage) {
                _pdfView.displayMode = kPDFDisplaySinglePage;
                _pdfView.userInteractionEnabled = NO;
            } else {
                _pdfView.displayMode = kPDFDisplaySinglePageContinuous;
                _pdfView.userInteractionEnabled = YES;
            }
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"showsHorizontalScrollIndicator"] || [changedProps containsObject:@"showsVerticalScrollIndicator"])) {
            [self setScrollIndicators:self horizontal:_showsHorizontalScrollIndicator vertical:_showsVerticalScrollIndicator depth:0];
        }

        if ([changedProps containsObject:@"path"] ||
            [changedProps containsObject:@"scrollEnabled"] ||
            [changedProps containsObject:@"annotationMode"] ||
            [changedProps containsObject:@"enablePaging"] ||
            [changedProps containsObject:@"singlePage"]) {
            [self updatePdfScrollInteractionMode];
        }

        if (_pdfDocument && ([changedProps containsObject:@"path"] || [changedProps containsObject:@"enablePaging"] || [changedProps containsObject:@"horizontal"] || [changedProps containsObject:@"page"])) {

            PDFPage *pdfPage = [_pdfDocument pageAtIndex:_page-1];
            if (pdfPage && _page == 1) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->_pdfView goToFirstPage:nil];
                    for (UIView *subview in self->_pdfView.subviews) {
                        if ([subview isKindOfClass:[UIScrollView class]]) {
                            UIScrollView *scrollView = (UIScrollView *)subview;
                            [scrollView setContentOffset:CGPointMake(0, 0) animated:NO];
                            break;
                        }
                    }
                });
            } else if (pdfPage) {
                CGRect pdfPageRect = [pdfPage boundsForBox:kPDFDisplayBoxCropBox];

                // some pdf with rotation, then adjust it
                if (pdfPage.rotation == 90 || pdfPage.rotation == 270) {
                    pdfPageRect = CGRectMake(0, 0, pdfPageRect.size.height, pdfPageRect.size.width);
                }

                CGPoint pointLeftTop = CGPointMake(0, pdfPageRect.size.height);
                PDFDestination *pdfDest = [[PDFDestination alloc] initWithPage:pdfPage atPoint:pointLeftTop];
                [_pdfView goToDestination:pdfDest];
                _pdfView.scaleFactor = _fixScaleFactor*_scale;
            }
        }

        if (_annotationOverlay) {
            if ([changedProps containsObject:@"annotations"] || [changedProps containsObject:@"path"]) {
                [_annotationOverlay replaceAnnotationsJSONString:_annotations editable:_annotationEditable idMode:_annotationIdMode];
            }
            [_annotationOverlay setAnnotationMode:_annotationMode tool:_annotationTool editable:_annotationEditable idMode:_annotationIdMode];
            [_annotationOverlay setInkDefaultsColor:_annotationInkColor thickness:_annotationInkThickness];
            _annotationOverlay.pdfView = _pdfView;
            _annotationOverlay.pdfDocument = _pdfDocument;
        }

        _pdfView.backgroundColor = [UIColor clearColor];
        [_pdfView layoutDocumentView];
        [self refreshPdfScrollViewBinding];
        [self setNeedsDisplay];
    }
}


- (void)reactSetFrame:(CGRect)frame
{
    [super reactSetFrame:frame];
    _pdfView.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);

    NSMutableArray *mProps = [_changedProps mutableCopy];
    if (_initialed) {
        [mProps removeObject:@"path"];
    }
    _initialed = YES;

    [self didSetProps:mProps];
}


- (void)notifyOnChangeWithMessage:(NSString *)message
{
#ifdef RCT_NEW_ARCH_ENABLED
    if (_eventEmitter != nullptr) {
             std::dynamic_pointer_cast<const RNPDFPdfViewEventEmitter>(_eventEmitter)
                 ->onChange(RNPDFPdfViewEventEmitter::OnChange{.message = RCTStringFromNSString(message)});
           }
#else
    _onChange(@{ @"message": message});
#endif
}

- (void)dealloc{

    [self stopAutoScroll];
    [self unbindPdfScrollViewObservation];

    _pdfDocument = Nil;
    _pdfView = Nil;

    //Remove notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewDocumentChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewPageChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PDFViewScaleChangedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:PDFViewSelectionChangedNotification object:nil];
    
    _doubleTapRecognizer = nil;
    _singleTapRecognizer = nil;
    _pinchRecognizer = nil;
    _longPressRecognizer = nil;
    _doubleTapEmptyRecognizer = nil;
}

#pragma mark notification process
- (void)onDocumentChanged:(NSNotification *)noti
{

    if (_pdfDocument) {

        unsigned long numberOfPages = _pdfDocument.pageCount;
        PDFPage *page = [_pdfDocument pageAtIndex:_pdfDocument.pageCount-1];
        CGSize pageSize = [_pdfView rowSizeForPage:page];
        NSString *jsonString = [self getTableContents];

        [self notifyOnChangeWithMessage:
         [[NSString alloc] initWithString:[NSString stringWithFormat:@"loadComplete|%lu|%f|%f|%@", numberOfPages, pageSize.width, pageSize.height,jsonString]]];
    }

}

-(NSString *) getTableContents
{

    NSMutableArray<PDFOutline *> *arrTableOfContents = [[NSMutableArray alloc] init];

    if (_pdfDocument.outlineRoot) {

        PDFOutline *currentRoot = _pdfDocument.outlineRoot;
        NSMutableArray<PDFOutline *> *stack = [[NSMutableArray alloc] init];

        [stack addObject:currentRoot];

        while (stack.count > 0) {

            PDFOutline *currentOutline = stack.lastObject;
            [stack removeLastObject];

            if (currentOutline.label.length > 0){
                [arrTableOfContents addObject:currentOutline];
            }

            for ( NSInteger i= currentOutline.numberOfChildren; i > 0; i-- )
            {
                [stack addObject:[currentOutline childAtIndex:i-1]];
            }
        }
    }

    NSMutableArray *arrParentsContents = [[NSMutableArray alloc] init];

    for ( NSInteger i= 0; i < arrTableOfContents.count; i++ )
    {
        PDFOutline *currentOutline = [arrTableOfContents objectAtIndex:i];

        NSInteger indentationLevel = -1;

        PDFOutline *parentOutline = currentOutline.parent;

        while (parentOutline != nil) {
            indentationLevel += 1;
            parentOutline = parentOutline.parent;
        }

        if (indentationLevel == 0) {

            NSMutableDictionary *DXParentsContent = [[NSMutableDictionary alloc] init];

            [DXParentsContent setObject:[[NSMutableArray alloc] init] forKey:@"children"];
            [DXParentsContent setObject:@"" forKey:@"mNativePtr"];
            [DXParentsContent setObject:[NSString stringWithFormat:@"%lu", [_pdfDocument indexForPage:currentOutline.destination.page]] forKey:@"pageIdx"];
            [DXParentsContent setObject:currentOutline.label forKey:@"title"];

            //currentOutlin
            //mNativePtr
            [arrParentsContents addObject:DXParentsContent];
        }
        else {
            NSMutableDictionary *DXParentsContent = [arrParentsContents lastObject];

            NSMutableArray *arrChildren = [DXParentsContent valueForKey:@"children"];

            while (indentationLevel > 1) {
                NSMutableDictionary *DXchild = [arrChildren lastObject];
                arrChildren = [DXchild valueForKey:@"children"];
                indentationLevel--;
            }

            NSMutableDictionary *DXChildContent = [[NSMutableDictionary alloc] init];
            [DXChildContent setObject:[[NSMutableArray alloc] init] forKey:@"children"];
            [DXChildContent setObject:@"" forKey:@"mNativePtr"];
            [DXChildContent setObject:[NSString stringWithFormat:@"%lu", [_pdfDocument indexForPage:currentOutline.destination.page]] forKey:@"pageIdx"];
            [DXChildContent setObject:currentOutline.label forKey:@"title"];
            [arrChildren addObject:DXChildContent];

        }
    }

    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:arrParentsContents options:NSJSONWritingPrettyPrinted error:&error];

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    return jsonString;

}

- (void)onPageChanged:(NSNotification *)noti
{

    if (_pdfDocument) {
        PDFPage *currentPage = _pdfView.currentPage;
        unsigned long page = [_pdfDocument indexForPage:currentPage];
        unsigned long numberOfPages = _pdfDocument.pageCount;

        [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"pageChanged|%lu|%lu", page+1, numberOfPages]]];
    }

    [_annotationOverlay refreshDisplay];

}

- (void)onScaleChanged:(NSNotification *)noti
{

    if (_initialed && _fixScaleFactor>0) {
        if (_scale != _pdfView.scaleFactor/_fixScaleFactor) {
            _scale = _pdfView.scaleFactor/_fixScaleFactor;
            [self notifyOnChangeWithMessage:[[NSString alloc] initWithString:[NSString stringWithFormat:@"scaleChanged|%f", _scale]]];
        }
    }

    [_annotationOverlay refreshDisplay];
}

#pragma mark gesture process

/**
 *  Empty double tap handler
 *
 *
 */
- (void)handleDoubleTapEmpty:(UITapGestureRecognizer *)recognizer {}

/**
 *  Tap
 *  zoom reset or zoom in
 *
 *  @param recognizer
 */
- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer
{

    // Prevent double tap from selecting text.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_pdfView clearSelection];
    });

    // Event appears to be consumed; broadcast for JS.
    // _onChange(@{ @"message": @"pageDoubleTap" });

    if (!_enableDoubleTapZoom) {
        return;
    }

    // Cycle through min/mid/max scale factors to be consistent with Android
    float min = self->_pdfView.minScaleFactor/self->_fixScaleFactor;
    float max = self->_pdfView.maxScaleFactor/self->_fixScaleFactor;
    float mid = (max - min) / 2 + min;
    float scale = self->_scale;
    if (self->_scale < mid) {
        scale = mid;
    } else if (self->_scale < max) {
        scale = max;
    } else {
        scale = min;
    }

    CGFloat newScale = scale * self->_fixScaleFactor;
    CGPoint tapPoint = [recognizer locationInView:self->_pdfView];

    PDFPage *tappedPdfPage = [_pdfView pageForPoint:tapPoint nearest:NO];
    PDFPage *pageRef;
    if (tappedPdfPage) {
        pageRef = tappedPdfPage;
    }   else {
        pageRef = self->_pdfView.currentPage;
    }
    tapPoint = [self->_pdfView convertPoint:tapPoint toPage:pageRef];

    CGRect tempZoomRect = CGRectZero;
    tempZoomRect.size.width = self->_pdfView.frame.size.width;
    tempZoomRect.size.height = 1;
    tempZoomRect.origin = tapPoint;

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{
            [self->_pdfView setScaleFactor:newScale];

            [self->_pdfView goToRect:tempZoomRect onPage:pageRef];
            CGPoint defZoomOrigin = [self->_pdfView convertPoint:tempZoomRect.origin fromPage:pageRef];
            defZoomOrigin.x = defZoomOrigin.x - self->_pdfView.frame.size.width / 2;
            defZoomOrigin.y = defZoomOrigin.y - self->_pdfView.frame.size.height / 2;
            defZoomOrigin = [self->_pdfView convertPoint:defZoomOrigin toPage:pageRef];
            CGRect defZoomRect =  CGRectOffset(
                tempZoomRect,
                defZoomOrigin.x - tempZoomRect.origin.x,
                defZoomOrigin.y - tempZoomRect.origin.y
            );
            [self->_pdfView goToRect:defZoomRect onPage:pageRef];

            [self setNeedsDisplay];
            [self onScaleChanged:Nil];
        }];
    });
}

/**
 *  Single Tap
 *  stop zoom
 *
 *  @param recognizer
 */
- (void)handleSingleTap:(UITapGestureRecognizer *)sender
{
    //_pdfView.scaleFactor = _pdfView.minScaleFactor;

    CGPoint point = [sender locationInView:self];
    PDFPage *pdfPage = [_pdfView pageForPoint:point nearest:NO];
    if (pdfPage) {
        unsigned long page = [_pdfDocument indexForPage:pdfPage];
        if (_annotationMode && _annotationEditable) {
            if ([_annotationTool isEqualToString:@"select"]) {
                [_annotationOverlay commitTextEditingIfNeeded];

                NSDictionary *hit = [_annotationOverlay annotationSelectionHitAtPoint:point includeHandles:YES];
                if (hit) {
                    NSDictionary *annotation = hit[@"annotation"];
                    [_annotationOverlay selectAnnotation:annotation];

                    return;
                }

                [_annotationOverlay clearSelection];
                [self notifyOnChangeWithMessage:
                 [[NSString alloc] initWithString:[NSString stringWithFormat:@"pageSingleTap|%lu|%f|%f", page+1, point.x, point.y]]];
                return;
            }

            if ([_annotationTool isEqualToString:@"text"]) {
                [_annotationOverlay createTextAnnotationAtViewPoint:point page:pdfPage];
                return;
            }

            if ([_annotationTool isEqualToString:@"ink"]) {
                [_annotationOverlay beginInkAtViewPoint:point page:pdfPage];
                [_annotationOverlay endInk];
                [self notifyOnChangeWithMessage:@"strokeEnd"];
                return;
            }
        }

        [self notifyOnChangeWithMessage:
         [[NSString alloc] initWithString:[NSString stringWithFormat:@"pageSingleTap|%lu|%f|%f", page+1, point.x, point.y]]];
    }

    //[self setNeedsDisplay];
    //[self onScaleChanged:Nil];


}

/**
 *  Pinch
 *
 *
 *  @param recognizer
 */
-(void)handlePinch:(UIPinchGestureRecognizer *)sender{
    [self onScaleChanged:Nil];
}

/**
 *  Do nothing on long Press
 *
 *
 */
- (void)handleLongPress:(UILongPressGestureRecognizer *)sender{

}

- (void)handleAnnotationPan:(UIPanGestureRecognizer *)sender
{
    if (!_annotationMode || !_annotationEditable || _annotationTool == nil) {
        return;
    }

    CGPoint point = [sender locationInView:self];
    PDFPage *pdfPage = [_pdfDocument pageAtIndex:MAX(0, [_pdfDocument indexForPage:[_pdfView pageForPoint:point nearest:NO]])];
    if (!pdfPage) {
        return;
    }

    if ([_annotationTool isEqualToString:@"select"]) {
        if (sender.state == UIGestureRecognizerStateBegan) {
            [_annotationOverlay commitTextEditingIfNeeded];

            NSDictionary *hit = [_annotationOverlay annotationSelectionHitAtPoint:point includeHandles:YES];
            if (!hit) {
                return;
            }

            [_annotationOverlay selectAnnotation:hit[@"annotation"]];
            [_annotationOverlay beginSelectionInteractionAtPoint:point hit:hit];
        } else if (sender.state == UIGestureRecognizerStateChanged) {
            [_annotationOverlay updateSelectionInteractionAtPoint:point];
        } else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled || sender.state == UIGestureRecognizerStateFailed) {
            [_annotationOverlay endSelectionInteraction];
        }
        return;
    }

    if (sender.state == UIGestureRecognizerStateBegan) {
        if ([_annotationTool isEqualToString:@"ink"]) {
            [_annotationOverlay beginInkAtViewPoint:point page:pdfPage];
        }
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        if ([_annotationTool isEqualToString:@"ink"]) {
            [_annotationOverlay appendInkPointAtViewPoint:point page:pdfPage];
        }
    } else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled || sender.state == UIGestureRecognizerStateFailed) {
        if ([_annotationTool isEqualToString:@"ink"]) {
            [_annotationOverlay endInk];
            [self notifyOnChangeWithMessage:@"strokeEnd"];
        }
    }
}

- (void)saveAnnotations
{
    if (_annotationOverlay) {
        [_annotationOverlay commitTextEditingIfNeeded];
        NSString *jsonString = [_annotationOverlay serializedDocumentJSONStringWithEditable:_annotationEditable idMode:_annotationIdMode];
        [self notifyOnChangeWithMessage:[NSString stringWithFormat:@"annotationSaveComplete|%@", jsonString]];
        return;
    }

    [self notifyOnChangeWithMessage:@"annotationSaveError|Annotation overlay unavailable"];
}

- (void)deleteSelectedAnnotation
{
    if (_annotationOverlay) {
        [_annotationOverlay commitTextEditingIfNeeded];
        [_annotationOverlay deleteSelectedAnnotation];
    }
}

- (void)deleteAllAnnotations
{
    if (_annotationOverlay) {
        [_annotationOverlay commitTextEditingIfNeeded];
        [_annotationOverlay deleteAllAnnotations];
    }
}

/**
 *  Bind tap
 *
 *
 */
- (void)bindTap
{
    UITapGestureRecognizer *doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handleDoubleTap:)];
    //trigger by one finger and double touch
    doubleTapRecognizer.numberOfTapsRequired = 2;
    doubleTapRecognizer.numberOfTouchesRequired = 1;
    doubleTapRecognizer.delegate = self;

    [self addGestureRecognizer:doubleTapRecognizer];
    _doubleTapRecognizer = doubleTapRecognizer;

    UITapGestureRecognizer *singleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handleSingleTap:)];
    //trigger by one finger and one touch
    singleTapRecognizer.numberOfTapsRequired = 1;
    singleTapRecognizer.numberOfTouchesRequired = 1;
    singleTapRecognizer.delegate = self;

    [self addGestureRecognizer:singleTapRecognizer];
    _singleTapRecognizer = singleTapRecognizer;

    [singleTapRecognizer requireGestureRecognizerToFail:doubleTapRecognizer];

    UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handlePinch:)];
    [self addGestureRecognizer:pinchRecognizer];
    _pinchRecognizer = pinchRecognizer;

    pinchRecognizer.delegate = self;

    UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                            action:@selector(handleLongPress:)];
    // Making sure the allowable movement isn not too narrow
    longPressRecognizer.allowableMovement=100;
    // Important: The duration must be long enough to allow taps but not longer than the period in which view opens the magnifying glass
    longPressRecognizer.minimumPressDuration=0.3;

    [self addGestureRecognizer:longPressRecognizer];
    _longPressRecognizer = longPressRecognizer;

    UIPanGestureRecognizer *annotationPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                                              action:@selector(handleAnnotationPan:)];
    annotationPanRecognizer.maximumNumberOfTouches = 1;
    annotationPanRecognizer.minimumNumberOfTouches = 1;
    annotationPanRecognizer.delegate = self;
    annotationPanRecognizer.cancelsTouchesInView = YES;
    [self addGestureRecognizer:annotationPanRecognizer];
    _annotationPanRecognizer = annotationPanRecognizer;

    // Override the _pdfView double tap gesture recognizer so that it doesn't confilict with custom double tap
    UITapGestureRecognizer *doubleTapEmptyRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(handleDoubleTapEmpty:)];
    doubleTapEmptyRecognizer.numberOfTapsRequired = 2;
    [_pdfView addGestureRecognizer:doubleTapEmptyRecognizer];
    _doubleTapEmptyRecognizer = doubleTapEmptyRecognizer;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer

{
    if (gestureRecognizer == _annotationPanRecognizer) {
        if (!_annotationMode || !_annotationEditable || _annotationTool == nil) {
            return NO;
        }

        if ([_annotationTool isEqualToString:@"select"]) {
            CGPoint point = [gestureRecognizer locationInView:self];
            return [_annotationOverlay annotationSelectionHitAtPoint:point includeHandles:YES] != nil;
        }

        return [_annotationTool isEqualToString:@"ink"];
    }

    return !_singlePage;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (gestureRecognizer == _annotationPanRecognizer || otherGestureRecognizer == _annotationPanRecognizer) {
        return NO;
    }

    return !_singlePage;
}

- (void)setScrollIndicators:(UIView *)view horizontal:(BOOL)horizontal vertical:(BOOL)vertical depth:(int)depth {
    // max depth, prevent infinite loop
    if (depth > 10) {
        return;
    }
    
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)view;
        scrollView.showsHorizontalScrollIndicator = horizontal;
        scrollView.showsVerticalScrollIndicator = vertical;
    }
    
    for (UIView *subview in view.subviews) {
        [self setScrollIndicators:subview horizontal:horizontal vertical:vertical depth:depth + 1];
    }
}

- (void)updatePdfScrollInteractionMode
{
    [self refreshPdfScrollViewBinding];
    [self applyScrollInteractionModeToView:_pdfView depth:0];
}

- (void)unbindPdfScrollViewObservation
{
    if (_pdfScrollPanRecognizer != nil) {
        [_pdfScrollPanRecognizer removeTarget:self action:@selector(handlePdfScrollPanGesture:)];
        _pdfScrollPanRecognizer = nil;
    }

    if (_isObservingPdfScrollView && _pdfScrollView != nil) {
        [_pdfScrollView removeObserver:self forKeyPath:@"contentOffset" context:RNPDFPdfScrollViewContentOffsetContext];
        _isObservingPdfScrollView = NO;
    }

    _pdfScrollView = nil;
}

- (UIScrollView *)preferredPdfScrollViewInView:(UIView *)view depth:(int)depth
{
    if (view == nil || depth > 10) {
        return nil;
    }

    UIScrollView *bestScrollView = nil;
    CGFloat bestScrollableExtent = 0.0f;

    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)view;
        CGFloat verticalOverflow = MAX(scrollView.contentSize.height - scrollView.bounds.size.height, 0.0f);
        CGFloat horizontalOverflow = MAX(scrollView.contentSize.width - scrollView.bounds.size.width, 0.0f);
        bestScrollableExtent = MAX(verticalOverflow, horizontalOverflow);
        bestScrollView = scrollView;
    }

    for (UIView *subview in view.subviews) {
        UIScrollView *candidate = [self preferredPdfScrollViewInView:subview depth:depth + 1];
        if (!candidate) {
            continue;
        }

        CGFloat candidateVerticalOverflow = MAX(candidate.contentSize.height - candidate.bounds.size.height, 0.0f);
        CGFloat candidateHorizontalOverflow = MAX(candidate.contentSize.width - candidate.bounds.size.width, 0.0f);
        CGFloat candidateScrollableExtent = MAX(candidateVerticalOverflow, candidateHorizontalOverflow);
        if (bestScrollView == nil || candidateScrollableExtent >= bestScrollableExtent) {
            bestScrollView = candidate;
            bestScrollableExtent = candidateScrollableExtent;
        }
    }

    return bestScrollView;
}

- (void)refreshPdfScrollViewBinding
{
    UIScrollView *preferredScrollView = [self preferredPdfScrollViewInView:_pdfView depth:0];
    if (preferredScrollView == _pdfScrollView) {
        return;
    }

    [self unbindPdfScrollViewObservation];

    _pdfScrollView = preferredScrollView;

    if (preferredScrollView) {
        _pdfScrollPanRecognizer = preferredScrollView.panGestureRecognizer;
        if (_pdfScrollPanRecognizer != nil) {
            [_pdfScrollPanRecognizer addTarget:self action:@selector(handlePdfScrollPanGesture:)];
        }

        [preferredScrollView addObserver:self
                              forKeyPath:@"contentOffset"
                                 options:NSKeyValueObservingOptionNew
                                 context:RNPDFPdfScrollViewContentOffsetContext];
        _isObservingPdfScrollView = YES;

        [_annotationOverlay refreshDisplay];
    }
}

- (void)applyScrollInteractionModeToView:(UIView *)view depth:(int)depth
{
    if (view == nil || depth > 10) {
        return;
    }

    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)view;
        scrollView.scrollEnabled = _scrollEnabled && !_singlePage;

        UIPanGestureRecognizer *panRecognizer = scrollView.panGestureRecognizer;
        if (panRecognizer != nil) {
            panRecognizer.minimumNumberOfTouches = _annotationMode ? 2 : 1;
        }
    }

    for (UIView *subview in view.subviews) {
        [self applyScrollInteractionModeToView:subview depth:depth + 1];
    }
}

#pragma mark - Autoscroll

- (UIScrollView *)findPdfScrollView
{
    [self refreshPdfScrollViewBinding];
    if (_pdfScrollView) return _pdfScrollView;
    return nil;
}

- (void)startAutoScroll:(CGFloat)dpPerSecond resumeDelay:(NSTimeInterval)resumeDelay
{
    // dp maps 1:1 to iOS points (both are ~160 dpi logical units)
    _autoScrollPixels = dpPerSecond;
    _autoScrollResumeDelay = resumeDelay;
    _isAutoScrolling = YES;

    UIScrollView *sv = [self findPdfScrollView];
    // Capture the current scroll position into our float accumulator so that
    // displayLinkTick never reads back UIKit's pixel-quantized contentOffset.
    if (sv) {
        _autoScrollCurrentOffset = sv.contentOffset.y;
    }
    [self startDisplayLink];
}

- (void)stopAutoScroll
{
    _isAutoScrolling = NO;
    [self stopDisplayLink];
    [_autoScrollResumeTimer invalidate];
    _autoScrollResumeTimer = nil;
}

- (void)startDisplayLink
{
    [_displayLink invalidate];
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkTick:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink
{
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)displayLinkTick:(CADisplayLink *)link
{
    UIScrollView *scrollView = [self findPdfScrollView];
    if (!scrollView || _isUserDragging) return;

    // Frame-rate-independent: use actual elapsed frame time (e.g. 1/60 or 1/120 on ProMotion)
    CGFloat frameDuration = (CGFloat)(link.targetTimestamp - link.timestamp);

    // Accumulate into our own float – do NOT read contentOffset back from UIKit.
    // UIKit / PDFKit quantises contentOffset to physical pixel boundaries (1/scale pts
    // on Retina displays). If we re-read that quantised value every frame we lose the
    // fractional part, making scrollSpeeds below ~20 px/s invisible on @3x devices.
    _autoScrollCurrentOffset += _autoScrollPixels * frameDuration;

    CGFloat maxOffsetY = scrollView.contentSize.height - scrollView.bounds.size.height;
    if (maxOffsetY <= 0) {
        [self stopAutoScroll];
        [self notifyOnChangeWithMessage:@"autoScrollEnd"];
        return;
    }

    if (_autoScrollCurrentOffset >= maxOffsetY) {
        [scrollView setContentOffset:CGPointMake(scrollView.contentOffset.x, maxOffsetY) animated:NO];
        [self stopAutoScroll];
        [self notifyOnChangeWithMessage:@"autoScrollEnd"];
        return;
    }

    [scrollView setContentOffset:CGPointMake(scrollView.contentOffset.x, _autoScrollCurrentOffset) animated:NO];
}

- (void)scheduleAutoScrollResume
{
    [_autoScrollResumeTimer invalidate];
    _autoScrollResumeTimer = [NSTimer scheduledTimerWithTimeInterval:_autoScrollResumeDelay
                                                             target:self
                                                           selector:@selector(autoScrollResumeFromTimer:)
                                                           userInfo:nil
                                                            repeats:NO];
}

- (void)autoScrollResumeFromTimer:(NSTimer *)timer
{
    if (_isAutoScrolling && !_isUserDragging) {
        // Re-sync the float accumulator with the actual scroll position after
        // the user may have scrolled manually during the pause.
        if (_pdfScrollView) {
            _autoScrollCurrentOffset = _pdfScrollView.contentOffset.y;
        }
        [self startDisplayLink];
    }
}

- (void)handlePdfScrollPanGesture:(UIPanGestureRecognizer *)gestureRecognizer
{
    if (!_isAutoScrolling || gestureRecognizer != _pdfScrollPanRecognizer) {
        return;
    }

    UIGestureRecognizerState state = gestureRecognizer.state;
    if (state == UIGestureRecognizerStateBegan) {
        _isUserDragging = YES;
        [self stopDisplayLink];
        [_autoScrollResumeTimer invalidate];
        _autoScrollResumeTimer = nil;
        return;
    }

    if ((state == UIGestureRecognizerStateEnded ||
         state == UIGestureRecognizerStateCancelled ||
         state == UIGestureRecognizerStateFailed) &&
        _pdfScrollView != nil &&
        !_pdfScrollView.isDragging &&
        !_pdfScrollView.isDecelerating) {
        _isUserDragging = NO;
        [self scheduleAutoScrollResume];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if (context == RNPDFPdfScrollViewContentOffsetContext) {
        if (object == _pdfScrollView) {
            [_annotationOverlay refreshDisplay];

            if (_isAutoScrolling &&
                _isUserDragging &&
                _pdfScrollView != nil &&
                !_pdfScrollView.isDragging &&
                !_pdfScrollView.isDecelerating) {
                _isUserDragging = NO;
                [self scheduleAutoScrollResume];
            }
        }
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end

static UIColor *RNPDFColorFromHexString(NSString *hexString, UIColor *fallback)
{
    if (![hexString isKindOfClass:[NSString class]] || hexString.length == 0) {
        return fallback;
    }

    NSString *cleanHex = [[hexString stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    unsigned int rgbValue = 0;
    if (cleanHex.length == 6) {
        NSScanner *scanner = [NSScanner scannerWithString:cleanHex];
        [scanner scanHexInt:&rgbValue];
        return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16) / 255.0f
                               green:((rgbValue & 0x00FF00) >> 8) / 255.0f
                                blue:(rgbValue & 0x0000FF) / 255.0f
                               alpha:1.0f];
    }

    if (cleanHex.length == 8) {
        NSScanner *scanner = [NSScanner scannerWithString:cleanHex];
        [scanner scanHexInt:&rgbValue];
        // CSS/RN standard: #RRGGBBAA (alpha is last two hex digits)
        return [UIColor colorWithRed:((rgbValue & 0xFF000000) >> 24) / 255.0f
                               green:((rgbValue & 0x00FF0000) >> 16) / 255.0f
                                blue:((rgbValue & 0x0000FF00) >> 8) / 255.0f
                               alpha:(rgbValue & 0x000000FF) / 255.0f];
    }

    return fallback;
}

static NSString *RNPDFGenerateAnnotationId(void)
{
    return [[NSUUID UUID] UUIDString];
}

@implementation RNPDFAnnotationOverlay
{
    NSMutableArray<NSMutableDictionary *> *_draftAnnotations;
    NSMutableDictionary *_activeInkAnnotation;
    NSMutableDictionary *_activeMarkupAnnotation;
    NSMutableDictionary *_activeTextAnnotation;
    NSString *_selectedAnnotationId;
    NSMutableDictionary *_activeSelectionAnnotation;
    NSString *_activeSelectionMode;
    NSString *_activeSelectionHandle;
    CGPoint _selectionStartPoint;
    CGRect _selectionStartBounds;
    NSArray *_selectionStartPoints;
    NSInteger _selectionPageIndex;
    CGPoint _activeMarkupStartNormalized;
    UITextView *_activeTextView;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        _draftAnnotations = [NSMutableArray new];
        _annotationMode = NO;
        _annotationEditable = YES;
        _annotationTool = @"select";
        _annotationIdMode = @"auto";
        _annotationInkColor = @"#111111";
        _annotationInkThickness = 2.0f;
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
    }
    return self;
}

- (void)setPdfView:(PDFView *)pdfView
{
    _pdfView = pdfView;
    [self refreshDisplay];
}

- (void)setPdfDocument:(PDFDocument *)pdfDocument
{
    _pdfDocument = pdfDocument;
    [self refreshDisplay];
}

- (void)replaceAnnotationsJSONString:(NSString *)json editable:(BOOL)editable idMode:(NSString *)idMode
{
    self.annotationEditable = editable;
    self.annotationIdMode = idMode ?: @"auto";

    NSArray *parsedAnnotations = [self parseAnnotationsFromJSONString:json];
    _draftAnnotations = [parsedAnnotations mutableCopy] ?: [NSMutableArray new];

    [self commitTextEditingIfNeeded];
    [self refreshDisplay];
}

- (void)setAnnotationMode:(BOOL)annotationMode tool:(NSString *)tool editable:(BOOL)editable idMode:(NSString *)idMode
{
    _annotationMode = annotationMode;
    _annotationEditable = editable;
    _annotationTool = [self normalizedAnnotationType:(tool ?: @"select")];
    _annotationIdMode = idMode ?: @"auto";

    if (!annotationMode) {
        [self commitTextEditingIfNeeded];
    }
}

- (void)setInkDefaultsColor:(NSString *)color thickness:(CGFloat)thickness
{
    _annotationInkColor = color.length > 0 ? color : @"#111111";
    _annotationInkThickness = thickness > 0 ? thickness : 2.0f;
}

- (NSString *)normalizedAnnotationType:(NSString *)type
{
    if ([type isEqualToString:@"underline"] || [type isEqualToString:@"strikeout"]) {
        return @"highlight";
    }

    return type;
}

- (BOOL)annotationSupportsResize:(NSDictionary *)annotation
{
    NSString *type = [self normalizedAnnotationType:annotation[@"type"]];
    return [type isEqualToString:@"text"] || [type isEqualToString:@"highlight"];
}

- (NSArray *)parseAnnotationsFromJSONString:(NSString *)json
{
    if (![json isKindOfClass:[NSString class]] || json.length == 0) {
        return @[];
    }

    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @[];
    }

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error || !parsed) {
        return @[];
    }

    NSArray *items = nil;
    if ([parsed isKindOfClass:[NSDictionary class]]) {
        id candidate = parsed[@"annotations"];
        if ([candidate isKindOfClass:[NSArray class]]) {
            items = candidate;
        }
    } else if ([parsed isKindOfClass:[NSArray class]]) {
        items = parsed;
    }

    if (![items isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray *normalized = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSMutableDictionary *annotation = [item mutableCopy];
        NSString *type = [self normalizedAnnotationType:annotation[@"type"]];
        if (type.length > 0) {
            annotation[@"type"] = type;
        }
        if (!annotation[@"id"]) {
            annotation[@"id"] = RNPDFGenerateAnnotationId();
        }
        if (!annotation[@"page"]) {
            annotation[@"page"] = @(1);
        }
        [normalized addObject:annotation];
    }

    return normalized;
}

- (NSString *)serializedDocumentJSONStringWithEditable:(BOOL)editable idMode:(NSString *)idMode
{
    NSMutableDictionary *document = [NSMutableDictionary dictionary];
    document[@"editable"] = @(editable);
    document[@"idMode"] = idMode ?: @"auto";
    document[@"annotations"] = [_draftAnnotations copy] ?: @[];

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:document options:0 error:&error];
    if (error || !data) {
        return @"{}";
    }

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

- (void)refreshDisplay
{
    [self setNeedsDisplay];
    [self updateActiveTextEditorFrame];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (_activeTextView) {
        if (CGRectContainsPoint(_activeTextView.frame, point)) {
            return _activeTextView;
        }

        return self;
    }

    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (_activeTextView) {
        [self commitTextEditingIfNeeded];
    }

    [super touchesBegan:touches withEvent:event];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self updateActiveTextEditorFrame];
}

- (CGPoint)normalizedPointForViewPoint:(CGPoint)viewPoint page:(PDFPage *)page
{
    if (!self.pdfView || !page) {
        return CGPointZero;
    }

    CGPoint pagePoint = [self.pdfView convertPoint:viewPoint toPage:page];
    CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxCropBox];
    if (page.rotation == 90 || page.rotation == 270) {
        pageBounds = CGRectMake(0, 0, pageBounds.size.height, pageBounds.size.width);
    }

    CGFloat width = MAX(pageBounds.size.width, 1.0f);
    CGFloat height = MAX(pageBounds.size.height, 1.0f);
    return CGPointMake(pagePoint.x / width, 1.0f - (pagePoint.y / height));
}

- (CGPoint)viewPointForNormalizedPoint:(CGPoint)normalizedPoint page:(PDFPage *)page
{
    if (!self.pdfView || !page) {
        return CGPointZero;
    }

    CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxCropBox];
    if (page.rotation == 90 || page.rotation == 270) {
        pageBounds = CGRectMake(0, 0, pageBounds.size.height, pageBounds.size.width);
    }

    CGFloat width = MAX(pageBounds.size.width, 1.0f);
    CGFloat height = MAX(pageBounds.size.height, 1.0f);
    CGPoint pagePoint = CGPointMake(normalizedPoint.x * width, (1.0f - normalizedPoint.y) * height);
    return [self.pdfView convertPoint:pagePoint fromPage:page];
}

- (CGRect)viewRectForNormalizedBounds:(NSDictionary *)bounds page:(PDFPage *)page
{
    if (!bounds || !page) {
        return CGRectZero;
    }

    CGFloat x = [bounds[@"x"] doubleValue];
    CGFloat y = [bounds[@"y"] doubleValue];
    CGFloat width = [bounds[@"width"] doubleValue];
    CGFloat height = [bounds[@"height"] doubleValue];

    CGPoint topLeft = [self viewPointForNormalizedPoint:CGPointMake(x, y) page:page];
    CGPoint topRight = [self viewPointForNormalizedPoint:CGPointMake(x + width, y) page:page];
    CGPoint bottomLeft = [self viewPointForNormalizedPoint:CGPointMake(x, y + height) page:page];
    CGPoint bottomRight = [self viewPointForNormalizedPoint:CGPointMake(x + width, y + height) page:page];

    CGFloat minX = MIN(MIN(topLeft.x, topRight.x), MIN(bottomLeft.x, bottomRight.x));
    CGFloat maxX = MAX(MAX(topLeft.x, topRight.x), MAX(bottomLeft.x, bottomRight.x));
    CGFloat minY = MIN(MIN(topLeft.y, topRight.y), MIN(bottomLeft.y, bottomRight.y));
    CGFloat maxY = MAX(MAX(topLeft.y, topRight.y), MAX(bottomLeft.y, bottomRight.y));

    return CGRectMake(minX, minY, MAX(maxX - minX, 1.0f), MAX(maxY - minY, 1.0f));
}

- (CGRect)viewRectForAnnotation:(NSDictionary *)annotation page:(PDFPage *)page
{
    if (!annotation || !page) {
        return CGRectZero;
    }

    NSString *type = annotation[@"type"];
    if ([type isEqualToString:@"ink"]) {
        NSArray *points = annotation[@"points"];
        if (![points isKindOfClass:[NSArray class]] || points.count == 0) {
            return CGRectZero;
        }

        CGFloat minX = CGFLOAT_MAX;
        CGFloat minY = CGFLOAT_MAX;
        CGFloat maxX = -CGFLOAT_MAX;
        CGFloat maxY = -CGFLOAT_MAX;

        for (NSDictionary *point in points) {
            if (![point isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            CGPoint viewPoint = [self viewPointForNormalizedPoint:CGPointMake([point[@"x"] doubleValue], [point[@"y"] doubleValue]) page:page];
            minX = MIN(minX, viewPoint.x);
            minY = MIN(minY, viewPoint.y);
            maxX = MAX(maxX, viewPoint.x);
            maxY = MAX(maxY, viewPoint.y);
        }

        if (minX == CGFLOAT_MAX || minY == CGFLOAT_MAX || maxX == -CGFLOAT_MAX || maxY == -CGFLOAT_MAX) {
            return CGRectZero;
        }

        return CGRectMake(minX, minY, MAX(maxX - minX, 1.0f), MAX(maxY - minY, 1.0f));
    }

    NSDictionary *bounds = annotation[@"bounds"];
    return [self viewRectForNormalizedBounds:bounds page:page];
}

- (CGRect)normalizedBoundsForAnnotation:(NSDictionary *)annotation
{
    if (!annotation) {
        return CGRectZero;
    }

    NSString *type = annotation[@"type"];
    if ([type isEqualToString:@"ink"]) {
        NSArray *points = annotation[@"points"];
        if (![points isKindOfClass:[NSArray class]] || points.count == 0) {
            return CGRectZero;
        }

        CGFloat minX = CGFLOAT_MAX;
        CGFloat minY = CGFLOAT_MAX;
        CGFloat maxX = -CGFLOAT_MAX;
        CGFloat maxY = -CGFLOAT_MAX;

        for (NSDictionary *point in points) {
            if (![point isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            CGFloat x = [point[@"x"] doubleValue];
            CGFloat y = [point[@"y"] doubleValue];
            minX = MIN(minX, x);
            minY = MIN(minY, y);
            maxX = MAX(maxX, x);
            maxY = MAX(maxY, y);
        }

        if (minX == CGFLOAT_MAX || minY == CGFLOAT_MAX || maxX == -CGFLOAT_MAX || maxY == -CGFLOAT_MAX) {
            return CGRectZero;
        }

        return CGRectMake(minX, minY, MAX(maxX - minX, 0.001f), MAX(maxY - minY, 0.001f));
    }

    NSDictionary *bounds = annotation[@"bounds"];
    if (![bounds isKindOfClass:[NSDictionary class]]) {
        return CGRectZero;
    }

    CGFloat x = [bounds[@"x"] doubleValue];
    CGFloat y = [bounds[@"y"] doubleValue];
    CGFloat width = [bounds[@"width"] doubleValue];
    CGFloat height = [bounds[@"height"] doubleValue];
    return CGRectMake(x, y, MAX(width, 0.001f), MAX(height, 0.001f));
}

- (NSArray *)copyPointsForAnnotation:(NSDictionary *)annotation
{
    if (![annotation[@"type"] isEqualToString:@"ink"]) {
        return nil;
    }

    NSArray *points = annotation[@"points"];
    if (![points isKindOfClass:[NSArray class]]) {
        return nil;
    }

    return [points copy];
}

- (NSDictionary *)selectedAnnotation
{
    if (_selectedAnnotationId.length == 0) {
        return nil;
    }

    for (NSDictionary *annotation in [_draftAnnotations reverseObjectEnumerator]) {
        if ([_selectedAnnotationId isEqualToString:annotation[@"id"]]) {
            return annotation;
        }
    }

    return nil;
}

- (CGRect)resizeHandleRectForRect:(CGRect)rect
{
    CGFloat size = MAX(16.0f, MIN(rect.size.width, rect.size.height) * 0.18f);
    return CGRectMake(CGRectGetMaxX(rect) - size, CGRectGetMaxY(rect) - size, size, size);
}

- (NSDictionary *)annotationSelectionHitAtPoint:(CGPoint)point includeHandles:(BOOL)includeHandles
{
    if (!self.pdfDocument || _draftAnnotations.count == 0) {
        return nil;
    }

    PDFPage *page = [self.pdfView pageForPoint:point nearest:NO];
    if (!page) {
        return nil;
    }

    NSInteger pageIndex = [self.pdfDocument indexForPage:page];
    for (NSDictionary *annotation in [_draftAnnotations reverseObjectEnumerator]) {
        NSNumber *annotationPageNumber = annotation[@"page"];
        if (!annotationPageNumber || annotationPageNumber.integerValue - 1 != pageIndex) {
            continue;
        }

        CGRect rect = [self viewRectForAnnotation:annotation page:page];
        if (CGRectIsEmpty(rect)) {
            continue;
        }

        CGRect hitRect = CGRectInset(rect, -12.0f, -12.0f);
        if (!CGRectContainsPoint(hitRect, point)) {
            continue;
        }

        NSString *hitPart = @"body";
        if (includeHandles && [_selectedAnnotationId isEqualToString:annotation[@"id"]] && [self annotationSupportsResize:annotation] && CGRectContainsPoint([self resizeHandleRectForRect:rect], point)) {
            hitPart = @"resize";
        }

        return @{@"annotation": annotation,
                 @"pageIndex": @(pageIndex),
                 @"hitPart": hitPart,
                 @"rect": [NSValue valueWithCGRect:rect]};
    }

    return nil;
}

- (void)selectAnnotation:(NSDictionary *)annotation
{
    _selectedAnnotationId = [annotation[@"id"] copy];
    [self refreshDisplay];
}

- (void)clearSelection
{
    _selectedAnnotationId = nil;
    [self refreshDisplay];
}

- (void)deleteAnnotation:(NSDictionary *)annotation
{
    if (!annotation) {
        return;
    }

    [self commitTextEditingIfNeeded];

    NSString *annotationId = annotation[@"id"];
    if (annotationId.length == 0) {
        return;
    }

    NSUInteger removeIndex = NSNotFound;
    for (NSUInteger index = 0; index < _draftAnnotations.count; index++) {
        NSDictionary *candidate = _draftAnnotations[index];
        if ([annotationId isEqualToString:candidate[@"id"]]) {
            removeIndex = index;
            break;
        }
    }

    if (removeIndex != NSNotFound) {
        [_draftAnnotations removeObjectAtIndex:removeIndex];
    }

    if ([_selectedAnnotationId isEqualToString:annotationId]) {
        _selectedAnnotationId = nil;
    }

    [self endSelectionInteraction];

    [self refreshDisplay];
}

- (void)deleteSelectedAnnotation
{
    NSDictionary *annotation = [self selectedAnnotation];
    if (annotation) {
        [self deleteAnnotation:annotation];
    }
}

- (void)deleteAllAnnotations
{
    [self commitTextEditingIfNeeded];
    [_draftAnnotations removeAllObjects];
    _selectedAnnotationId = nil;
    [self endSelectionInteraction];
    [self refreshDisplay];
}

- (void)beginSelectionInteractionAtPoint:(CGPoint)point hit:(NSDictionary *)hit
{
    NSDictionary *annotation = hit[@"annotation"];
    if (![annotation isKindOfClass:[NSDictionary class]]) {
        return;
    }

    _activeSelectionAnnotation = (NSMutableDictionary *)annotation;
    _activeSelectionMode = [hit[@"hitPart"] isEqualToString:@"resize"] ? @"resize" : @"move";
    _activeSelectionHandle = hit[@"hitPart"] ?: @"body";
    _selectionStartPoint = point;
    _selectionPageIndex = [hit[@"pageIndex"] integerValue];
    _selectionStartBounds = [self normalizedBoundsForAnnotation:annotation];
    _selectionStartPoints = [self copyPointsForAnnotation:annotation];
}

- (void)updateSelectionInteractionAtPoint:(CGPoint)point
{
    if (!_activeSelectionAnnotation || _selectionPageIndex < 0 || !_pdfDocument || _selectionPageIndex >= _pdfDocument.pageCount) {
        return;
    }

    PDFPage *page = [_pdfDocument pageAtIndex:_selectionPageIndex];
    if (!page) {
        return;
    }

    CGPoint startNormalized = [self normalizedPointForViewPoint:_selectionStartPoint page:page];
    CGPoint currentNormalized = [self normalizedPointForViewPoint:point page:page];
    CGFloat deltaX = currentNormalized.x - startNormalized.x;
    CGFloat deltaY = currentNormalized.y - startNormalized.y;

    CGRect newBounds = _selectionStartBounds;
    if ([_activeSelectionMode isEqualToString:@"resize"]) {
        newBounds.size.width = MAX(0.01f, _selectionStartBounds.size.width + deltaX);
        newBounds.size.height = MAX(0.01f, _selectionStartBounds.size.height + deltaY);
    } else {
        newBounds.origin.x = _selectionStartBounds.origin.x + deltaX;
        newBounds.origin.y = _selectionStartBounds.origin.y + deltaY;
    }

    [self applySelectionBounds:newBounds toAnnotation:_activeSelectionAnnotation startBounds:_selectionStartBounds startPoints:_selectionStartPoints];
    [self refreshDisplay];
}

- (void)endSelectionInteraction
{
    _activeSelectionAnnotation = nil;
    _activeSelectionMode = nil;
    _activeSelectionHandle = nil;
    _selectionStartPoints = nil;
    _selectionPageIndex = -1;
}

- (void)applySelectionBounds:(CGRect)newBounds toAnnotation:(NSMutableDictionary *)annotation startBounds:(CGRect)startBounds startPoints:(NSArray *)startPoints
{
    if (!annotation) {
        return;
    }

    NSString *type = annotation[@"type"];
    if ([type isEqualToString:@"ink"]) {
        if (![startPoints isKindOfClass:[NSArray class]]) {
            return;
        }

        CGFloat startWidth = MAX(startBounds.size.width, 0.001f);
        CGFloat startHeight = MAX(startBounds.size.height, 0.001f);
        CGFloat newWidth = MAX(newBounds.size.width, 0.001f);
        CGFloat newHeight = MAX(newBounds.size.height, 0.001f);

        NSMutableArray *transformedPoints = [NSMutableArray arrayWithCapacity:startPoints.count];
        for (NSDictionary *point in startPoints) {
            if (![point isKindOfClass:[NSDictionary class]]) {
                continue;
            }

            CGFloat pointX = [point[@"x"] doubleValue];
            CGFloat pointY = [point[@"y"] doubleValue];
            CGFloat xRatio = (pointX - startBounds.origin.x) / startWidth;
            CGFloat yRatio = (pointY - startBounds.origin.y) / startHeight;
            CGFloat x = MIN(1.0f, MAX(0.0f, newBounds.origin.x + (xRatio * newWidth)));
            CGFloat y = MIN(1.0f, MAX(0.0f, newBounds.origin.y + (yRatio * newHeight)));
            [transformedPoints addObject:@{@"x": @(x), @"y": @(y)}];
        }

        annotation[@"points"] = transformedPoints;
        return;
    }

    CGFloat x = MIN(1.0f, MAX(0.0f, newBounds.origin.x));
    CGFloat y = MIN(1.0f, MAX(0.0f, newBounds.origin.y));
    CGFloat width = MIN(1.0f, MAX(0.01f, newBounds.size.width));
    CGFloat height = MIN(1.0f, MAX(0.01f, newBounds.size.height));
    annotation[@"bounds"] = @{@"x": @(x),
                               @"y": @(y),
                               @"width": @(width),
                               @"height": @(height)};
}

- (void)drawSelectionDecoration
{
    if (!_annotationMode || !_annotationEditable || ![_annotationTool isEqualToString:@"select"]) {
        return;
    }

    NSDictionary *annotation = [self selectedAnnotation];
    if (!annotation) {
        return;
    }

    NSNumber *pageIndexValue = annotation[@"page"];
    NSInteger pageIndex = pageIndexValue.integerValue - 1;
    if (pageIndex < 0 || pageIndex >= _pdfDocument.pageCount) {
        return;
    }

    PDFPage *page = [_pdfDocument pageAtIndex:pageIndex];
    CGRect rect = [self viewRectForAnnotation:annotation page:page];
    if (CGRectIsEmpty(rect)) {
        return;
    }

    UIColor *outlineColor = [UIColor colorWithRed:0.13 green:0.27 blue:0.67 alpha:0.9];
    UIBezierPath *outlinePath = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:4.0f];
    outlinePath.lineWidth = 2.0f;
    [outlineColor setStroke];
    [outlinePath stroke];

    if ([self annotationSupportsResize:annotation]) {
        CGRect resizeHandle = [self resizeHandleRectForRect:rect];
        [[UIColor colorWithRed:0.13 green:0.27 blue:0.67 alpha:0.95] setFill];
        UIBezierPath *resizePath = [UIBezierPath bezierPathWithRoundedRect:resizeHandle cornerRadius:2.0f];
        [resizePath fill];
    }
}

- (NSDictionary *)normalizedBoundsForViewRect:(CGRect)viewRect page:(PDFPage *)page
{
    if (!self.pdfView || !page) {
        return @{@"x": @0, @"y": @0, @"width": @0, @"height": @0};
    }

    CGPoint topLeft = [self normalizedPointForViewPoint:viewRect.origin page:page];
    CGPoint bottomRight = [self normalizedPointForViewPoint:CGPointMake(CGRectGetMaxX(viewRect), CGRectGetMaxY(viewRect)) page:page];

    CGFloat minX = MIN(topLeft.x, bottomRight.x);
    CGFloat maxX = MAX(topLeft.x, bottomRight.x);
    CGFloat minY = MIN(topLeft.y, bottomRight.y);
    CGFloat maxY = MAX(topLeft.y, bottomRight.y);

    return @{@"x": @(MAX(0, minX)),
             @"y": @(MAX(0, minY)),
             @"width": @(MAX(0, maxX - minX)),
             @"height": @(MAX(0, maxY - minY))};
}

- (NSString *)nextLocalAnnotationId
{
    return [NSString stringWithFormat:@"local-%@", RNPDFGenerateAnnotationId()];
}

- (UIColor *)colorForAnnotationType:(NSString *)type style:(NSDictionary *)style
{
    NSString *normalizedType = [self normalizedAnnotationType:type];
    NSString *colorString = [style isKindOfClass:[NSDictionary class]] ? style[@"color"] : nil;
    if (colorString) {
        return RNPDFColorFromHexString(colorString, UIColor.blackColor);
    }

    if ([normalizedType isEqualToString:@"highlight"]) {
        return [UIColor colorWithRed:1.0 green:0.93 blue:0.2 alpha:0.35];
    }
    if ([normalizedType isEqualToString:@"text"]) {
        return [UIColor colorWithRed:0.13 green:0.27 blue:0.67 alpha:1.0];
    }

    return UIColor.blackColor;
}

- (CGFloat)lineWidthForAnnotation:(NSDictionary *)annotation
{
    NSDictionary *style = [annotation[@"style"] isKindOfClass:[NSDictionary class]] ? annotation[@"style"] : nil;
    NSNumber *thickness = style[@"thickness"];
    if ([thickness isKindOfClass:[NSNumber class]]) {
        return MAX(1.0f, thickness.floatValue);
    }

    return 2.0f;
}

- (UIFont *)fontForAnnotation:(NSDictionary *)annotation
{
    NSDictionary *style = [annotation[@"style"] isKindOfClass:[NSDictionary class]] ? annotation[@"style"] : nil;
    NSNumber *fontSize = style[@"fontSize"];
    CGFloat size = [fontSize isKindOfClass:[NSNumber class]] ? MAX(10.0f, fontSize.floatValue) : 15.0f;
    return [UIFont systemFontOfSize:size];
}

- (NSTextAlignment)alignmentForAnnotation:(NSDictionary *)annotation
{
    NSDictionary *style = [annotation[@"style"] isKindOfClass:[NSDictionary class]] ? annotation[@"style"] : nil;
    NSString *alignment = style[@"textAlign"];
    if ([alignment isEqualToString:@"center"]) {
        return NSTextAlignmentCenter;
    }
    if ([alignment isEqualToString:@"right"]) {
        return NSTextAlignmentRight;
    }

    return NSTextAlignmentLeft;
}

- (void)drawRect:(CGRect)rect
{
    [super drawRect:rect];

    if (!_pdfDocument || _draftAnnotations.count == 0) {
        return;
    }

    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return;
    }

    for (NSDictionary *annotation in _draftAnnotations) {
        NSNumber *pageIndexValue = annotation[@"page"];
        NSInteger pageIndex = pageIndexValue.integerValue - 1;
        if (pageIndex < 0 || pageIndex >= _pdfDocument.pageCount) {
            continue;
        }

        PDFPage *page = [_pdfDocument pageAtIndex:pageIndex];
        NSString *type = [self normalizedAnnotationType:annotation[@"type"]];
        if ([type isEqualToString:@"ink"]) {
            NSArray *points = annotation[@"points"];
            if (points.count == 0) {
                continue;
            }

            if (points.count == 1) {
                NSDictionary *point = points[0];
                CGPoint normalizedPoint = CGPointMake([point[@"x"] doubleValue], [point[@"y"] doubleValue]);
                CGPoint viewPoint = [self viewPointForNormalizedPoint:normalizedPoint page:page];
                CGFloat radius = [self lineWidthForAnnotation:annotation] / 2.0;
                CGRect dotRect = CGRectMake(viewPoint.x - radius, viewPoint.y - radius, radius * 2, radius * 2);
                [[self colorForAnnotationType:type style:annotation[@"style"]] setFill];
                [[UIBezierPath bezierPathWithOvalInRect:dotRect] fill];
                continue;
            }

            UIBezierPath *path = [UIBezierPath bezierPath];
            BOOL firstPoint = YES;
            for (NSDictionary *point in points) {
                CGPoint normalizedPoint = CGPointMake([point[@"x"] doubleValue], [point[@"y"] doubleValue]);
                CGPoint viewPoint = [self viewPointForNormalizedPoint:normalizedPoint page:page];
                if (firstPoint) {
                    [path moveToPoint:viewPoint];
                    firstPoint = NO;
                } else {
                    [path addLineToPoint:viewPoint];
                }
            }

            [[self colorForAnnotationType:type style:annotation[@"style"]] setStroke];
            path.lineWidth = [self lineWidthForAnnotation:annotation];
            path.lineJoinStyle = kCGLineJoinRound;
            path.lineCapStyle = kCGLineCapRound;
            [path stroke];
        } else if ([type isEqualToString:@"text"]) {
            NSDictionary *bounds = annotation[@"bounds"];
            CGRect viewRect = [self viewRectForNormalizedBounds:bounds page:page];
            if (CGRectIsEmpty(viewRect)) {
                continue;
            }

            UIColor *borderColor = [self colorForAnnotationType:type style:annotation[@"style"]];
            [[UIColor colorWithWhite:1.0 alpha:0.78] setFill];
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:viewRect cornerRadius:4.0f];
            [path fill];
            [borderColor setStroke];
            path.lineWidth = 1.0f;
            [path stroke];

            NSString *text = annotation[@"text"];
            if (![text isKindOfClass:[NSString class]]) {
                text = @"";
            }

            NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
            paragraphStyle.alignment = [self alignmentForAnnotation:annotation];
            NSDictionary *attributes = @{
                NSFontAttributeName: [self fontForAnnotation:annotation],
                NSForegroundColorAttributeName: borderColor,
                NSParagraphStyleAttributeName: paragraphStyle,
            };
            [text drawInRect:CGRectInset(viewRect, 6.0f, 4.0f) withAttributes:attributes];
        } else if ([type isEqualToString:@"highlight"]) {
            NSDictionary *bounds = annotation[@"bounds"];
            CGRect viewRect = [self viewRectForNormalizedBounds:bounds page:page];
            if (CGRectIsEmpty(viewRect)) {
                continue;
            }

            UIColor *fillColor = [self colorForAnnotationType:type style:annotation[@"style"]];
            CGContextSetFillColorWithColor(context, fillColor.CGColor);
            CGContextFillRect(context, viewRect);
        }
    }

    [self drawSelectionDecoration];
}

- (void)beginInkAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page
{
    if (!self.annotationEditable || !page) {
        return;
    }

    NSMutableDictionary *annotation = [@{
        @"id": [self nextLocalAnnotationId],
        @"page": @([_pdfDocument indexForPage:page] + 1),
        @"type": @"ink",
        @"points": [NSMutableArray array],
        @"style": @{@"color": _annotationInkColor ?: @"#111111", @"thickness": @(_annotationInkThickness > 0 ? _annotationInkThickness : 2.0f)}
    } mutableCopy];

    [_draftAnnotations addObject:annotation];
    _activeInkAnnotation = annotation;
    [self appendInkPointAtViewPoint:viewPoint page:page];
}

- (void)appendInkPointAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page
{
    if (!_activeInkAnnotation || !page) {
        return;
    }

    CGPoint normalizedPoint = [self normalizedPointForViewPoint:viewPoint page:page];
    NSMutableArray *points = _activeInkAnnotation[@"points"];
    if (![points isKindOfClass:[NSMutableArray class]]) {
        points = [NSMutableArray array];
        _activeInkAnnotation[@"points"] = points;
    }

    [points addObject:@{@"x": @(normalizedPoint.x), @"y": @(normalizedPoint.y)}];
    [self refreshDisplay];
}

- (void)endInk
{
    _activeInkAnnotation = nil;
    [self refreshDisplay];
}

- (void)beginMarkupAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page type:(NSString *)type
{
    if (!self.annotationEditable || !page) {
        return;
    }

    CGPoint normalizedPoint = [self normalizedPointForViewPoint:viewPoint page:page];
    _activeMarkupStartNormalized = normalizedPoint;

    NSMutableDictionary *annotation = [@{
        @"id": [self nextLocalAnnotationId],
        @"page": @([_pdfDocument indexForPage:page] + 1),
        @"type": @"highlight",
        @"bounds": @{@"x": @(normalizedPoint.x), @"y": @(normalizedPoint.y), @"width": @0, @"height": @0},
        @"style": @{}
    } mutableCopy];

    [_draftAnnotations addObject:annotation];
    _activeMarkupAnnotation = annotation;
    [self refreshDisplay];
}

- (void)updateMarkupAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page
{
    if (!_activeMarkupAnnotation || !page) {
        return;
    }

    CGPoint currentPoint = [self normalizedPointForViewPoint:viewPoint page:page];
    CGFloat minX = MIN(_activeMarkupStartNormalized.x, currentPoint.x);
    CGFloat minY = MIN(_activeMarkupStartNormalized.y, currentPoint.y);
    CGFloat maxX = MAX(_activeMarkupStartNormalized.x, currentPoint.x);
    CGFloat maxY = MAX(_activeMarkupStartNormalized.y, currentPoint.y);

    _activeMarkupAnnotation[@"bounds"] = @{@"x": @(minX), @"y": @(minY), @"width": @(MAX(0, maxX - minX)), @"height": @(MAX(0, maxY - minY))};
    [self refreshDisplay];
}

- (void)endMarkup
{
    _activeMarkupAnnotation = nil;
    [self refreshDisplay];
}

- (void)createTextAnnotationAtViewPoint:(CGPoint)viewPoint page:(PDFPage *)page
{
    if (!self.annotationEditable || !page) {
        return;
    }

    [self commitTextEditingIfNeeded];

    CGPoint normalizedPoint = [self normalizedPointForViewPoint:viewPoint page:page];
    CGFloat width = 0.25f;
    CGFloat height = 0.12f;
    CGFloat maxX = MAX(0.0f, 1.0f - width);
    CGFloat maxY = MAX(0.0f, 1.0f - height);
    CGFloat x = MIN(MAX(normalizedPoint.x, 0.0f), maxX);
    CGFloat y = MIN(MAX(normalizedPoint.y, 0.0f), maxY);
    NSDictionary *bounds = @{@"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height)};

    NSMutableDictionary *annotation = [@{
        @"id": [self nextLocalAnnotationId],
        @"page": @([_pdfDocument indexForPage:page] + 1),
        @"type": @"text",
        @"bounds": bounds,
        @"text": @"",
        @"style": @{@"color": @"#2244aa", @"fontSize": @(15.0f), @"textAlign": @"left"}
    } mutableCopy];

    [_draftAnnotations addObject:annotation];
    _activeTextAnnotation = annotation;

    UITextView *textView = [[UITextView alloc] initWithFrame:[self viewRectForNormalizedBounds:bounds page:page]];
    textView.delegate = self;
    textView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9f];
    textView.layer.borderColor = [UIColor colorWithRed:0.2 green:0.4 blue:1.0 alpha:0.9].CGColor;
    textView.layer.borderWidth = 1.0f;
    textView.layer.cornerRadius = 4.0f;
    textView.clipsToBounds = YES;
    textView.textColor = [self colorForAnnotationType:@"text" style:annotation[@"style"]];
    textView.font = [self fontForAnnotation:annotation];
    textView.textAlignment = [self alignmentForAnnotation:annotation];
    textView.scrollEnabled = YES;
    textView.returnKeyType = UIReturnKeyDefault;

    if (_activeTextView) {
        [_activeTextView removeFromSuperview];
    }

    _activeTextView = textView;
    [self addSubview:_activeTextView];
    [_activeTextView becomeFirstResponder];
    [self refreshDisplay];
}

- (void)updateActiveTextEditorFrame
{
    if (!_activeTextView || !_activeTextAnnotation || !self.pdfDocument || !self.pdfView) {
        return;
    }

    NSNumber *pageNumber = _activeTextAnnotation[@"page"];
    NSInteger pageIndex = pageNumber.integerValue - 1;
    if (pageIndex < 0 || pageIndex >= self.pdfDocument.pageCount) {
        return;
    }

    PDFPage *page = [self.pdfDocument pageAtIndex:pageIndex];
    _activeTextView.frame = [self viewRectForNormalizedBounds:_activeTextAnnotation[@"bounds"] page:page];
}

- (void)commitTextEditingIfNeeded
{
    if (!_activeTextView || !_activeTextAnnotation) {
        return;
    }

    _activeTextAnnotation[@"text"] = _activeTextView.text ?: @"";
    [_activeTextView resignFirstResponder];
    [_activeTextView removeFromSuperview];
    _activeTextView = nil;
    _activeTextAnnotation = nil;
    [self refreshDisplay];
}

- (void)textViewDidChange:(UITextView *)textView
{
    if (textView == _activeTextView && _activeTextAnnotation) {
        _activeTextAnnotation[@"text"] = textView.text ?: @"";
        [self setNeedsDisplay];
    }
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    if (textView == _activeTextView) {
        [self commitTextEditingIfNeeded];
    }
}

@end

#ifdef RCT_NEW_ARCH_ENABLED
Class<RCTComponentViewProtocol> RNPDFPdfViewCls(void)
{
    return RNPDFPdfView.class;
}

#endif
