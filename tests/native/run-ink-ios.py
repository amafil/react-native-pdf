#!/usr/bin/env python3
"""Run the production Ink overlay against UIKit/PDFKit on a booted simulator.

The private overlay lives in the React Native view's translation unit. Extract
its declarations/implementation verbatim to test it without a React app host.
This exercises the real overlay, but does not simulate physical multitouch.
"""
import argparse
from pathlib import Path
import platform
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', default='booted', help='Booted simulator UDID')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
source = (root / 'ios/RNPDFPdf/RNPDFPdfView.mm').read_text()
interface = source[source.index('@interface RNPDFAnnotationOverlay'):source.index('@interface RNPDFPdfView()')]
implementation = source[source.index('static UIColor *RNPDFColorFromHexString'):source.index('\n#ifdef RCT_NEW_ARCH_ENABLED\nClass<RCTComponentViewProtocol>')]
recognizer = source[source.index('@interface RNPDFInkGestureRecognizer'):source.index('@class RNPDFAnnotationOverlay;')]
tests = Path(__file__).with_name('ink-ios.mm').read_text()
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='pdf-ink-tests-') as output:
    generated = Path(output) / 'ink.mm'
    executable = Path(output) / 'ink-tests'
    generated.write_text('#import <UIKit/UIKit.h>\n#import <UIKit/UIGestureRecognizerSubclass.h>\n#import <PDFKit/PDFKit.h>\n' + recognizer + interface + implementation + tests)
    subprocess.run([
        'xcrun', 'clang++', '-fobjc-arc', '-fmodules',
        f'-fmodules-cache-path={output}/modules', '-isysroot', sdk,
        '-target', f'{platform.machine()}-apple-ios15.1-simulator',
        '-framework', 'UIKit', '-framework', 'PDFKit', '-framework', 'Foundation',
        '-framework', 'CoreGraphics', str(generated), '-o', str(executable),
    ], check=True)
    subprocess.run(['xcrun', 'simctl', 'spawn', args.device, str(executable)], check=True)
