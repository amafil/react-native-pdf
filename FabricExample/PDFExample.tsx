/**
 * Copyright (c) 2017-present, Wonday (@wonday.org)
 * All rights reserved.
 *
 * This source code is licensed under the MIT-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  StyleSheet,
  Pressable,
  View,
  Text,
  Platform,
  StatusBar,
  Modal,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import Pdf from 'react-native-pdf';
import Orientation from 'react-native-orientation-locker';


type OrientationType = 'LANDSCAPE-LEFT' | 'LANDSCAPE-RIGHT' | 'PORTRAIT' | string;

// ── Design tokens ──────────────────────────────────────────────────────────────
const colors = {
  bg:           '#000000',
  toolbarBg:    '#1C1C1E',
  surface:      '#2C2C2E',
  sheetBg:      '#1C1C1E',
  sectionBg:    '#2C2C2E',
  accent:       '#0A84FF',
  accentActive: '#30D158',
  disabledBg:   '#3A3A3C',
  disabledText: '#636366',
  text:         '#FFFFFF',
  textSecondary:'#AEAEB2',
  border:       '#38383A',
  scrim:        'rgba(0,0,0,0.55)',
};

// ── Small icon-style button (toolbar) ─────────────────────────────────────────
interface IconBtnProps {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  testID?: string;
  accessibilityLabel: string;
  accessibilityHint?: string;
}
function IconBtn({ label, onPress, disabled = false, testID, accessibilityLabel, accessibilityHint }: IconBtnProps) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      testID={testID}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityHint={accessibilityHint}
      accessibilityState={{ disabled }}
      hitSlop={6}
      style={({ pressed }) => [
        styles.iconBtn,
        disabled && styles.iconBtnDisabled,
        pressed && !disabled && styles.iconBtnPressed,
      ]}
    >
      <Text style={[styles.iconBtnText, disabled && styles.iconBtnTextDisabled]}>
        {label}
      </Text>
    </Pressable>
  );
}

// ── Sheet stepper row ─────────────────────────────────────────────────────────
interface StepperRowProps {
  label: string;
  value: string;
  onDecrement: () => void;
  onIncrement: () => void;
  decrementDisabled?: boolean;
  incrementDisabled?: boolean;
  accessibilityLabel: string;
}
function StepperRow({ label, value, onDecrement, onIncrement, decrementDisabled, incrementDisabled, accessibilityLabel }: StepperRowProps) {
  return (
    <View style={styles.sheetRow} accessible accessibilityLabel={accessibilityLabel}>
      <Text style={styles.sheetRowLabel}>{label}</Text>
      <View style={styles.stepper}>
        <Pressable
          onPress={onDecrement}
          disabled={decrementDisabled}
          accessibilityRole="button"
          accessibilityLabel={`Decrease ${label}`}
          accessibilityState={{ disabled: decrementDisabled }}
          hitSlop={6}
          style={({ pressed }) => [styles.stepBtn, decrementDisabled && styles.stepBtnDisabled, pressed && !decrementDisabled && styles.stepBtnPressed]}
        >
          <Text style={[styles.stepBtnText, decrementDisabled && styles.stepBtnTextDisabled]}>−</Text>
        </Pressable>
        <Text style={styles.stepValue}>{value}</Text>
        <Pressable
          onPress={onIncrement}
          disabled={incrementDisabled}
          accessibilityRole="button"
          accessibilityLabel={`Increase ${label}`}
          accessibilityState={{ disabled: incrementDisabled }}
          hitSlop={6}
          style={({ pressed }) => [styles.stepBtn, incrementDisabled && styles.stepBtnDisabled, pressed && !incrementDisabled && styles.stepBtnPressed]}
        >
          <Text style={[styles.stepBtnText, incrementDisabled && styles.stepBtnTextDisabled]}>+</Text>
        </Pressable>
      </View>
    </View>
  );
}

// ── Sheet toggle row ──────────────────────────────────────────────────────────
interface ToggleRowProps {
  label: string;
  value: boolean;
  onToggle: () => void;
  trueLabel?: string;
  falseLabel?: string;
  activeColor?: string;
}
function ToggleRow({ label, value, onToggle, trueLabel = 'On', falseLabel = 'Off', activeColor }: ToggleRowProps) {
  return (
    <View style={styles.sheetRow}>
      <Text style={styles.sheetRowLabel}>{label}</Text>
      <Pressable
        onPress={onToggle}
        accessibilityRole="switch"
        accessibilityLabel={label}
        accessibilityState={{ checked: value }}
        style={({ pressed }) => [
          styles.togglePill,
          value && { backgroundColor: activeColor ?? colors.accentActive },
          pressed && styles.iconBtnPressed,
        ]}
      >
        <Text style={[styles.togglePillText, value && styles.togglePillTextActive]}>
          {value ? trueLabel : falseLabel}
        </Text>
      </Pressable>
    </View>
  );
}

// ── Sheet segment row (two-option picker) ─────────────────────────────────────
interface SegmentRowProps {
  label: string;
  options: { label: string; value: boolean }[];
  current: boolean;
  onSelect: (v: boolean) => void;
}
function SegmentRow({ label, options, current, onSelect }: SegmentRowProps) {
  return (
    <View style={styles.sheetRow}>
      <Text style={styles.sheetRowLabel}>{label}</Text>
      <View style={styles.segment}>
        {options.map(opt => (
          <Pressable
            key={String(opt.value)}
            onPress={() => onSelect(opt.value)}
            accessibilityRole="radio"
            accessibilityLabel={opt.label}
            accessibilityState={{ selected: current === opt.value }}
            style={[styles.segmentOption, current === opt.value && styles.segmentOptionSelected]}
          >
            <Text style={[styles.segmentOptionText, current === opt.value && styles.segmentOptionTextSelected]}>
              {opt.label}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

// ── Sheet section header ───────────────────────────────────────────────────────
function SectionHeader({ title }: { title: string }) {
  return <Text style={styles.sectionHeader}>{title}</Text>;
}

// ── Hairline ──────────────────────────────────────────────────────────────────
function Hairline() {
  return <View style={styles.hairline} />;
}

// ── Main component ─────────────────────────────────────────────────────────────
export default function PDFExample() {
  const pdfRef = useRef<any>(null);

  const [page, setPage]                 = useState(1);
  const [scale, setScale]               = useState(1);
  const [numberOfPages, setNumberOfPages] = useState(0);
  const [horizontal, setHorizontal]     = useState(false);
  const [showScrollbars, setShowScrollbars] = useState(true);
  const [isAutoScrolling, setIsAutoScrolling] = useState(false);
  const [autoScrollSpeed, setAutoScrollSpeed] = useState(15);
  const [autoScrollResumeDelay, setAutoScrollResumeDelay] = useState(3000);
  const [settingsOpen, setSettingsOpen] = useState(false);

  const onOrientationChange = useCallback((orientation: OrientationType) => {
    const isLandscape = orientation === 'LANDSCAPE-LEFT' || orientation === 'LANDSCAPE-RIGHT';
    setHorizontal(isLandscape);
  }, []);

  useEffect(() => {
    Orientation.addOrientationListener(onOrientationChange);
    return () => Orientation.removeOrientationListener(onOrientationChange);
  }, [onOrientationChange]);

  const prePage = useCallback(() => {
    const target = Math.max(1, page - 1);
    pdfRef.current?.setPage(target);
  }, [page]);

  const nextPage = useCallback(() => {
    const target = Math.min(numberOfPages, page + 1);
    pdfRef.current?.setPage(target);
  }, [page, numberOfPages]);

  const zoomOut = useCallback(() => {
    setScale(prev => +(Math.max(1, prev / 1.2)).toFixed(2));
  }, []);

  const zoomIn = useCallback(() => {
    setScale(prev => +(Math.min(3, prev * 1.2)).toFixed(2));
  }, []);

  const toggleAutoScroll = useCallback(() => {
    if (isAutoScrolling) {
      pdfRef.current?.stopAutoScroll();
      setIsAutoScrolling(false);
    } else {
      pdfRef.current?.startAutoScroll(autoScrollSpeed, autoScrollResumeDelay);
      setIsAutoScrolling(true);
    }
  }, [isAutoScrolling, autoScrollSpeed, autoScrollResumeDelay]);

  const adjustSpeed = useCallback((delta: number) => {
    setAutoScrollSpeed(prev => {
      const next = Math.min(120, Math.max(5, prev + delta));
      if (isAutoScrolling) {
        pdfRef.current?.stopAutoScroll();
        pdfRef.current?.startAutoScroll(next, autoScrollResumeDelay);
      }
      return next;
    });
  }, [isAutoScrolling, autoScrollResumeDelay]);

  const adjustResumeDelay = useCallback((delta: number) => {
    setAutoScrollResumeDelay(prev => {
      const next = Math.min(10000, Math.max(500, prev + delta));
      if (isAutoScrolling) {
        pdfRef.current?.stopAutoScroll();
        pdfRef.current?.startAutoScroll(autoScrollSpeed, next);
      }
      return next;
    });
  }, [isAutoScrolling, autoScrollSpeed]);

  const source =
    Platform.OS === 'windows'
      ? { uri: 'ms-appx:///test.pdf' }
      : { uri: 'https://ontheline.trincoll.edu/images/bookdown/sample-local-pdf.pdf', cache: true };

  const scaleLabel = `${Math.round(scale * 100)}%`;
  const pageLabel  = numberOfPages > 0 ? `${page} / ${numberOfPages}` : '— / —';

  return (
    <SafeAreaView style={styles.container} edges={{ top: 'maximum' }}>
      <StatusBar barStyle="light-content" backgroundColor={colors.toolbarBg} />

      {/* ── Toolbar: single row ───────────────────────────────────────────── */}
      <View style={styles.toolbar}>
        {/* Page navigation */}
        <View style={styles.controlGroup} accessible accessibilityLabel="Page navigation">
          <IconBtn
            label="‹"
            onPress={prePage}
            disabled={page <= 1}
            accessibilityLabel="Previous page"
            accessibilityHint={page > 1 ? `Go to page ${page - 1}` : undefined}
          />
          <Text style={styles.counterText} accessibilityLabel={`Page ${page} of ${numberOfPages}`}>
            {pageLabel}
          </Text>
          <IconBtn
            label="›"
            onPress={nextPage}
            disabled={page >= numberOfPages}
            testID="NextPage"
            accessibilityLabel="Next page"
            accessibilityHint={page < numberOfPages ? `Go to page ${page + 1}` : undefined}
          />
        </View>

        <View style={styles.toolbarDivider} />

        {/* Zoom */}
        <View style={styles.controlGroup} accessible accessibilityLabel="Zoom controls">
          <IconBtn label="−" onPress={zoomOut} disabled={scale <= 1} accessibilityLabel="Zoom out" />
          <Text style={styles.counterText} accessibilityLabel={`Zoom ${scaleLabel}`}>
            {scaleLabel}
          </Text>
          <IconBtn label="+" onPress={zoomIn} disabled={scale >= 3} accessibilityLabel="Zoom in" />
        </View>

        <View style={{ flex: 1 }} />

        {/* Settings gear */}
        <Pressable
          onPress={() => setSettingsOpen(true)}
          accessibilityRole="button"
          accessibilityLabel="Open settings"
          accessibilityHint="Layout, scrollbars, auto-scroll"
          hitSlop={6}
          style={({ pressed }) => [styles.gearBtn, pressed && styles.iconBtnPressed]}
        >
          <Text style={styles.gearText}>⚙</Text>
          {isAutoScrolling && <View style={styles.gearBadge} />}
        </Pressable>
      </View>

      {/* ── PDF viewer ───────────────────────────────────────────────────────── */}
      <View style={styles.pdfWrapper}>
        <Pdf
          ref={pdfRef}
          trustAllCerts={false}
          source={source}
          scale={scale}
          horizontal={horizontal}
          showsVerticalScrollIndicator={showScrollbars}
          showsHorizontalScrollIndicator={showScrollbars}
          onLoadComplete={(pages: number, filePath: string, dims: { width: number; height: number }, tableContents: unknown) => {
            setNumberOfPages(pages);
            console.log(`total pages: ${pages}`, tableContents, dims, filePath);
          }}
          onPageChanged={(p: number, total: number) => {
            setPage(p);
            console.log(`page: ${p} / ${total}`);
          }}
          onError={(error: unknown) => console.log(error)}
          onAutoScrollEnd={() => {
            setIsAutoScrolling(false);
            console.log('Auto scroll ended');
          }}
          style={{ flex: 1 }}
          accessibilityLabel="PDF document viewer"
        />
      </View>

      {/* ── Settings bottom sheet ─────────────────────────────────────────────── */}
      <Modal
        visible={settingsOpen}
        transparent
        animationType="slide"
        onRequestClose={() => setSettingsOpen(false)}
        accessibilityViewIsModal
      >
        {/* Scrim */}
        <Pressable
          style={styles.scrim}
          onPress={() => setSettingsOpen(false)}
          accessibilityLabel="Close settings"
          accessibilityRole="button"
        />

        {/* Sheet */}
        <View style={styles.sheet}>
          {/* Handle */}
          <View style={styles.sheetHandle} accessibilityElementsHidden />

          {/* Sheet header */}
          <View style={styles.sheetHeader}>
            <Text style={styles.sheetTitle}>Settings</Text>
            <Pressable
              onPress={() => setSettingsOpen(false)}
              accessibilityRole="button"
              accessibilityLabel="Close settings"
              hitSlop={8}
              style={({ pressed }) => [styles.closeBtn, pressed && styles.iconBtnPressed]}
            >
              <Text style={styles.closeBtnText}>✕</Text>
            </Pressable>
          </View>

          <ScrollView
            showsVerticalScrollIndicator={false}
            contentContainerStyle={styles.sheetContent}
            keyboardShouldPersistTaps="handled"
          >
            {/* Layout section */}
            <SectionHeader title="LAYOUT" />
            <View style={styles.sheetSection}>
              <SegmentRow
                label="Scroll direction"
                options={[{ label: '↕ Vertical', value: false }, { label: '↔ Horizontal', value: true }]}
                current={horizontal}
                onSelect={setHorizontal}
              />
              <Hairline />
              <ToggleRow
                label="Scrollbars"
                value={showScrollbars}
                onToggle={() => setShowScrollbars(s => !s)}
                trueLabel="Visible"
                falseLabel="Hidden"
                activeColor={colors.accent}
              />
            </View>

            {/* Auto-scroll section */}
            <SectionHeader title="AUTO SCROLL" />
            <View style={styles.sheetSection}>
              <ToggleRow
                label="Auto scroll"
                value={isAutoScrolling}
                onToggle={toggleAutoScroll}
                trueLabel="On"
                falseLabel="Off"
                activeColor={colors.accentActive}
              />
              <Hairline />
              <StepperRow
                label="Speed"
                value={`${autoScrollSpeed} px/s`}
                onDecrement={() => adjustSpeed(-5)}
                onIncrement={() => adjustSpeed(5)}
                decrementDisabled={autoScrollSpeed <= 5}
                incrementDisabled={autoScrollSpeed >= 120}
                accessibilityLabel={`Scroll speed: ${autoScrollSpeed} pixels per second`}
              />
              <Hairline />
              <StepperRow
                label="Resume delay"
                value={`${autoScrollResumeDelay} ms`}
                onDecrement={() => adjustResumeDelay(-500)}
                onIncrement={() => adjustResumeDelay(500)}
                decrementDisabled={autoScrollResumeDelay <= 500}
                incrementDisabled={autoScrollResumeDelay >= 10000}
                accessibilityLabel={`Resume delay: ${autoScrollResumeDelay} milliseconds`}
              />
            </View>
          </ScrollView>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

// ── Styles ────────────────────────────────────────────────────────────────────
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  pdfWrapper: {
    flex: 1,
    alignSelf: 'stretch',
  },

  // ── Toolbar ────────────────────────────────────────────────────────────────
  toolbar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.toolbarBg,
    paddingHorizontal: 12,
    paddingVertical: 8,
    gap: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  toolbarDivider: {
    width: StyleSheet.hairlineWidth,
    height: 22,
    backgroundColor: colors.border,
    marginHorizontal: 2,
  },
  controlGroup: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  counterText: {
    color: colors.text,
    fontSize: 13,
    fontWeight: '500',
    minWidth: 52,
    textAlign: 'center',
  },

  // ── Icon buttons (toolbar) ─────────────────────────────────────────────────
  iconBtn: {
    minWidth: 44,
    minHeight: 36,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 8,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconBtnDisabled: {
    backgroundColor: colors.disabledBg,
  },
  iconBtnPressed: {
    opacity: 0.6,
  },
  iconBtnText: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  iconBtnTextDisabled: {
    color: colors.disabledText,
  },

  // ── Gear button ────────────────────────────────────────────────────────────
  gearBtn: {
    width: 44,
    height: 36,
    borderRadius: 8,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  gearText: {
    fontSize: 18,
    color: colors.textSecondary,
  },
  gearBadge: {
    position: 'absolute',
    top: 5,
    right: 5,
    width: 7,
    height: 7,
    borderRadius: 4,
    backgroundColor: colors.accentActive,
  },

  // ── Bottom sheet ───────────────────────────────────────────────────────────
  scrim: {
    flex: 1,
    backgroundColor: colors.scrim,
  },
  sheet: {
    backgroundColor: colors.sheetBg,
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    paddingBottom: 32,
    maxHeight: '75%',
  },
  sheetHandle: {
    alignSelf: 'center',
    marginTop: 10,
    width: 36,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.border,
  },
  sheetHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  sheetTitle: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '600',
  },
  closeBtn: {
    width: 30,
    height: 30,
    borderRadius: 15,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  closeBtnText: {
    color: colors.textSecondary,
    fontSize: 13,
    fontWeight: '700',
  },
  sheetContent: {
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 8,
  },

  // ── Sheet sections ─────────────────────────────────────────────────────────
  sectionHeader: {
    color: colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 0.6,
    marginTop: 12,
    marginBottom: 6,
    marginLeft: 4,
  },
  sheetSection: {
    backgroundColor: colors.sectionBg,
    borderRadius: 12,
    overflow: 'hidden',
  },
  sheetRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 13,
  },
  sheetRowLabel: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '400',
    flex: 1,
  },
  hairline: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
    marginLeft: 16,
  },

  // ── Toggle pill ────────────────────────────────────────────────────────────
  togglePill: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 20,
    backgroundColor: colors.surface,
    minWidth: 64,
    alignItems: 'center',
  },
  togglePillText: {
    color: colors.textSecondary,
    fontSize: 13,
    fontWeight: '600',
  },
  togglePillTextActive: {
    color: '#000000',
  },

  // ── Stepper ────────────────────────────────────────────────────────────────
  stepper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: 10,
    overflow: 'hidden',
  },
  stepBtn: {
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepBtnDisabled: {
    opacity: 0.35,
  },
  stepBtnPressed: {
    backgroundColor: colors.disabledBg,
  },
  stepBtnText: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '400',
    lineHeight: 22,
  },
  stepBtnTextDisabled: {
    color: colors.disabledText,
  },
  stepValue: {
    color: colors.text,
    fontSize: 13,
    fontWeight: '500',
    minWidth: 72,
    textAlign: 'center',
  },

  // ── Segment control ────────────────────────────────────────────────────────
  segment: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: 10,
    overflow: 'hidden',
  },
  segmentOption: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    alignItems: 'center',
    justifyContent: 'center',
  },
  segmentOptionSelected: {
    backgroundColor: colors.accent,
  },
  segmentOptionText: {
    color: colors.textSecondary,
    fontSize: 13,
    fontWeight: '500',
  },
  segmentOptionTextSelected: {
    color: '#FFFFFF',
    fontWeight: '600',
  },
});