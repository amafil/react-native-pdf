// Compiled after the production overlay by run-ink-ios.py.

// Touch stand-in for deterministic recognizer state transitions, not OS routing.
@interface InkTestTouch : NSObject
@end
@implementation InkTestTouch
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(50, 50); }
@end

// UIKit owns state transitions during real event dispatch. Store state locally
// here so production touch handlers can be tested without injecting OS events.
@interface InkTestGesture : RNPDFInkGestureRecognizer {
    UIGestureRecognizerState _testState;
}
@end
@implementation InkTestGesture
- (UIGestureRecognizerState)state { return _testState; }
- (void)setState:(UIGestureRecognizerState)state { _testState = state; }
@end

static int checks = 0;
static void check(BOOL condition, NSString *name) {
    checks++;
    if (!condition) { NSLog(@"FAILED: %@", name); exit(1); }
}
static NSArray *saved(RNPDFAnnotationOverlay *overlay) {
    NSString *json = [overlay serializedDocumentJSONStringWithEditable:YES idMode:@"auto"];
    return [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil][@"annotations"];
}
int main() { @autoreleasepool {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(600, 800)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *c) { [[UIColor whiteColor] setFill]; UIRectFill(CGRectMake(0, 0, 600, 800)); }];
    PDFDocument *doc = [PDFDocument new];
    PDFPage *page = [[PDFPage alloc] initWithImage:image];
    PDFPage *page2 = [[PDFPage alloc] initWithImage:image];
    [doc insertPage:page atIndex:0]; [doc insertPage:page2 atIndex:1];
    PDFView *view = [[PDFView alloc] initWithFrame:CGRectMake(0, 0, 600, 800)]; view.document = doc;
    RNPDFAnnotationOverlay *overlay = [[RNPDFAnnotationOverlay alloc] initWithFrame:view.bounds];
    overlay.pdfView = view; overlay.pdfDocument = doc;
    NSMutableArray *events = [NSMutableArray new];
    overlay.onInkEvent = ^(NSString *event) { [events addObject:event]; };
    [overlay setAnnotationMode:YES tool:@"ink" editable:YES idMode:@"auto"];
    [overlay beginInkAtViewPoint:CGPointMake(50,50) page:page];
    check(saved(overlay).count == 0, @"provisional stroke excluded from save");
    [overlay endInk];
    check(saved(overlay).count == 1, @"tap creates one stroke");
    check([events.lastObject isEqual:@"strokeEnd"], @"confirmed stroke event");
    check([events containsObject:@"annotationUndoStateChanged|true"], @"undo becomes available");
    [overlay beginInkAtViewPoint:CGPointMake(70,70) page:page];
    [overlay appendInkPointAtViewPoint:CGPointMake(80,80) page:page];
    [overlay cancelInk];
    check(saved(overlay).count == 1, @"cancel leaves prior strokes unchanged");
    check([events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == 'strokeEnd'"]].count == 1, @"cancel emits no strokeEnd");
    [overlay beginInkAtViewPoint:CGPointMake(70,70) page:page];
    [overlay appendInkPointAtViewPoint:CGPointMake(80,80) page:page2];
    [overlay appendInkPointAtViewPoint:CGPointMake(90,90) page:page];
    check(saved(overlay).count == 1, @"page boundary remains provisional");
    [overlay cancelInk];
    check(saved(overlay).count == 1, @"second finger can cancel after page boundary");
    [overlay beginInkAtViewPoint:CGPointMake(70,70) page:page2]; [overlay endInk];
    check(saved(overlay).count == 2, @"second-page stroke committed");
    NSString *echo = [overlay serializedDocumentJSONStringWithEditable:YES idMode:@"auto"];
    [overlay replaceAnnotationsJSONString:echo editable:YES idMode:@"auto"];
    [overlay undoLastInkStroke];
    check(saved(overlay).count == 1 && [saved(overlay)[0][@"page"] intValue] == 1, @"undo across pages survives save echo");
    [overlay beginInkAtViewPoint:CGPointMake(70,70) page:page]; [overlay endInk];
    [overlay deleteAnnotation:saved(overlay).lastObject];
    [overlay undoLastInkStroke];
    check(saved(overlay).count == 0, @"undo skips already deleted stroke");
    [overlay undoLastInkStroke];
    check(saved(overlay).count == 0 && [events.lastObject isEqual:@"annotationUndoStateChanged|false"], @"empty undo no-op");
    [overlay beginInkAtViewPoint:CGPointMake(70,70) page:page]; [overlay endInk];
    [overlay setAnnotationMode:NO tool:@"ink" editable:YES idMode:@"auto"];
    [overlay setAnnotationMode:YES tool:@"ink" editable:YES idMode:@"auto"];
    [overlay undoLastInkStroke];
    check(saved(overlay).count == 1, @"session reset protects previously saved stroke");
    [overlay beginInkAtViewPoint:CGPointMake(70,70) page:page]; [overlay endInk];
    [overlay setAnnotationMode:YES tool:@"select" editable:YES idMode:@"auto"];
    [overlay undoLastInkStroke];
    check(saved(overlay).count == 1, @"tool switch keeps undo history");
    [overlay deleteAllAnnotations];
    check(saved(overlay).count == 0 && [events.lastObject isEqual:@"annotationUndoStateChanged|false"], @"clear all resets history");
    [overlay replaceAnnotationsJSONString:@"{\"annotations\":[{\"type\":\"text\"},{\"type\":\"highlight\"},{\"type\":\"ink\",\"id\":\"existing\",\"page\":1,\"points\":[]}]}" editable:YES idMode:@"auto"];
    check(saved(overlay).count == 1, @"non-Ink types ignored");
    [overlay undoLastInkStroke];
    check(saved(overlay).count == 1, @"replacement document resets history");
    RNPDFInkGestureRecognizer *gesture = [InkTestGesture new];
    [view addGestureRecognizer:gesture];
    UIEvent *event = [UIEvent new];
    NSSet *first = [NSSet setWithObject:[InkTestTouch new]];
    NSSet *second = [NSSet setWithObject:[InkTestTouch new]];
    [gesture touchesBegan:first withEvent:event];
    check(gesture.state == UIGestureRecognizerStateBegan, @"one finger starts immediately");
    [gesture touchesMoved:first withEvent:event];
    [gesture touchesBegan:second withEvent:event];
    check(gesture.state == UIGestureRecognizerStateCancelled, @"late second finger cancels drawing");
    [gesture touchesMoved:first withEvent:event];
    [gesture touchesEnded:second withEvent:event];
    check(gesture.state == UIGestureRecognizerStateCancelled, @"remaining finger cannot restart drawing");
    RNPDFInkGestureRecognizer *twoFinger = [InkTestGesture new];
    [view addGestureRecognizer:twoFinger];
    [twoFinger touchesBegan:[first setByAddingObjectsFromSet:second] withEvent:event];
    check(twoFinger.state == UIGestureRecognizerStateFailed, @"simultaneous fingers never start drawing");
    NSLog(@"PASS: %d native Ink checks", checks);
} return 0; }
