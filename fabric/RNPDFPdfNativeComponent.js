/**
 * @flow
 * @format
 */
 'use strict';

 import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';
 import codegenNativeCommands from 'react-native/Libraries/Utilities/codegenNativeCommands';
 
 type ChangeEvent = $ReadOnly<{|
   message: ?string,
 |}>;
 
 export type NativeProps = $ReadOnly<{|
   ...ViewProps,
   path: ?string,
   page: ?Int32,
   scale: ?Float,
   minScale: ?Float,
   maxScale: ?Float,
   horizontal: ?boolean,
   enablePaging: ?boolean,
   enableRTL: ?boolean,
   enableAnnotationRendering: ?boolean,
   showsHorizontalScrollIndicator: ?boolean,
   showsVerticalScrollIndicator: ?boolean,
   scrollEnabled: ?boolean,
   enableAntialiasing: ?boolean,
   enableDoubleTapZoom: ?boolean,
   fitPolicy: ?Int32,
   spacing: ?Int32,
   password: ?string,
  annotations: ?string,
  annotationMode: ?boolean,
  annotationTool: ?string,
  annotationEditable: ?boolean,
  annotationIdMode: ?string,
  annotationInkColor: ?string,
  annotationInkThickness: ?Float,
   onChange: ?BubblingEventHandler<ChangeEvent>,
   singlePage: ?boolean,
 |}>;

 interface NativeCommands {
  +setNativePage: (
    viewRef: React.ElementRef<ComponentType>,
    page: Int32,
  ) => void;
  +startNativeAutoScroll: (
    viewRef: React.ElementRef<ComponentType>,
    pixels: Double,
    resumeDelay: Double,
  ) => void;
  +stopNativeAutoScroll: (
    viewRef: React.ElementRef<ComponentType>,
  ) => void;
  +saveAnnotations: (
    viewRef: React.ElementRef<ComponentType>,
  ) => void;
  +deleteSelectedAnnotation: (
    viewRef: React.ElementRef<ComponentType>,
  ) => void;
  +deleteAllAnnotations: (
    viewRef: React.ElementRef<ComponentType>,
  ) => void;
}

export const Commands: NativeCommands = codegenNativeCommands<NativeCommands>({
  supportedCommands: ['setNativePage', 'startNativeAutoScroll', 'stopNativeAutoScroll', 'saveAnnotations', 'deleteSelectedAnnotation', 'deleteAllAnnotations'],
});

 export default codegenNativeComponent<NativeProps>('RNPDFPdfView');
