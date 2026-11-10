import 'package:flutter/material.dart';

class SonicColors {
  static const background = Color(0xFF05080F);
  static const panel = Color(0xE60B1220);
  static const panelBorder = Color(0x3355E6FF);
  static const cyan = Color(0xFF00E5FF);
  static const cyanDim = Color(0xFF1B6F7F);
  static const magenta = Color(0xFFFF3DCB);
  static const text = Color(0xFFE6F7FF);
  static const textDim = Color(0xFF7A93A8);
  static const grid = Color(0xFF12324A);
}

ThemeData buildSonicTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: SonicColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: SonicColors.cyan,
      secondary: SonicColors.magenta,
      surface: const Color(0xFF0B1220),
    ),
    textTheme: base.textTheme.apply(bodyColor: SonicColors.text, displayColor: SonicColors.text),
    sliderTheme: const SliderThemeData(
      activeTrackColor: SonicColors.cyan,
      thumbColor: SonicColors.cyan,
      inactiveTrackColor: SonicColors.grid,
    ),
  );
}

BoxDecoration panelDecoration({Color? glow}) => BoxDecoration(
      color: SonicColors.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: glow ?? SonicColors.panelBorder),
      boxShadow: [
        if (glow != null) BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 1),
      ],
    );
