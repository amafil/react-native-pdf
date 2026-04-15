/**
 * Copyright (c) 2017-present, Wonday (@wonday.org)
 * All rights reserved.
 *
 * This source code is licensed under the MIT-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "RNPDFPdfViewManager.h"
#import "RNPDFPdfView.h"

#if __has_include(<React/RCTUIManager.h>)
#import <React/RCTUIManager.h>
#else
#import "RCTUIManager.h"
#endif


@implementation RNPDFPdfViewManager

RCT_EXPORT_MODULE()

- (UIView *)view
{
    if([[[UIDevice currentDevice] systemVersion] compare:@"11.0" options:NSNumericSearch] == NSOrderedDescending
       || [[[UIDevice currentDevice] systemVersion] compare:@"11.0" options:NSNumericSearch] == NSOrderedSame) {
        return [[RNPDFPdfView alloc] initWithBridge:self.bridge];
    } else {
        return NULL;
    }
  
}

RCT_EXPORT_VIEW_PROPERTY(path, NSString);
RCT_EXPORT_VIEW_PROPERTY(page, int);
RCT_EXPORT_VIEW_PROPERTY(scale, float);
RCT_EXPORT_VIEW_PROPERTY(minScale, float);
RCT_EXPORT_VIEW_PROPERTY(maxScale, float);
RCT_EXPORT_VIEW_PROPERTY(horizontal, BOOL);
RCT_EXPORT_VIEW_PROPERTY(showsHorizontalScrollIndicator, BOOL);
RCT_EXPORT_VIEW_PROPERTY(showsVerticalScrollIndicator, BOOL);
RCT_EXPORT_VIEW_PROPERTY(scrollEnabled, BOOL);
RCT_EXPORT_VIEW_PROPERTY(enablePaging, BOOL);
RCT_EXPORT_VIEW_PROPERTY(enableRTL, BOOL);
RCT_EXPORT_VIEW_PROPERTY(enableAnnotationRendering, BOOL);
RCT_EXPORT_VIEW_PROPERTY(enableDoubleTapZoom, BOOL);
RCT_EXPORT_VIEW_PROPERTY(fitPolicy, int);
RCT_EXPORT_VIEW_PROPERTY(spacing, int);
RCT_EXPORT_VIEW_PROPERTY(password, NSString);
RCT_EXPORT_VIEW_PROPERTY(onChange, RCTBubblingEventBlock);
RCT_EXPORT_VIEW_PROPERTY(singlePage, BOOL);
RCT_EXPORT_VIEW_PROPERTY(enableTextSelection, BOOL);
RCT_EXPORT_VIEW_PROPERTY(onTextSelectionChange, RCTBubblingEventBlock);

RCT_EXPORT_METHOD(startAutoScroll:(nonnull NSNumber *)reactTag
                  dpPerSecond:(double)dpPerSecond
                  resumeDelay:(double)resumeDelay)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        RNPDFPdfView *view = (RNPDFPdfView *)viewRegistry[reactTag];
        if ([view isKindOfClass:[RNPDFPdfView class]]) {
            [view startAutoScroll:(CGFloat)dpPerSecond resumeDelay:(NSTimeInterval)(resumeDelay / 1000.0)];
        }
    }];
}

RCT_EXPORT_METHOD(stopAutoScroll:(nonnull NSNumber *)reactTag)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        RNPDFPdfView *view = (RNPDFPdfView *)viewRegistry[reactTag];
        if ([view isKindOfClass:[RNPDFPdfView class]]) {
            [view stopAutoScroll];
        }
    }];
}

RCT_EXPORT_METHOD(supportPDFKit:(RCTResponseSenderBlock)callback)
{
    if([[[UIDevice currentDevice] systemVersion] compare:@"11.0" options:NSNumericSearch] == NSOrderedDescending
       || [[[UIDevice currentDevice] systemVersion] compare:@"11.0" options:NSNumericSearch] == NSOrderedSame) {
        callback(@[@YES]);
    } else {
        callback(@[@NO]);
    }
    
}

+ (BOOL)requiresMainQueueSetup {
    return YES;
}


- (void)dealloc{
}

@end
