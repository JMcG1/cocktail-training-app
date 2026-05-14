import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const background = Color(0xFF111315);
  const panel = Color(0xFF171A1D);
  const panelAlt = Color(0xFF1F2428);
  const highlight = Color(0xFFE7C67A);
  const accent = Color(0xFF54C7B8);
  const warning = Color(0xFFF3A35C);
  const danger = Color(0xFFE87777);

  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = base.textTheme.apply(
    bodyColor: Colors.white,
    displayColor: Colors.white,
    fontFamily: 'Manrope',
  );
  final displayTheme = base.textTheme.apply(
    bodyColor: Colors.white,
    displayColor: Colors.white,
    fontFamily: 'DMSerifDisplay',
  );

  return base.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: highlight,
      surface: panel,
      surfaceContainerHighest: panelAlt,
      error: danger,
    ),
    textTheme: textTheme.copyWith(
      headlineLarge: displayTheme.headlineLarge,
      headlineMedium: displayTheme.headlineMedium,
      headlineSmall: displayTheme.headlineSmall,
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF262C31)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: panelAlt,
      selectedColor: accent.withValues(alpha: 0.2),
      side: const BorderSide(color: Color(0xFF2C343B)),
      labelStyle: textTheme.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panelAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFF2A3137)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFF2A3137)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: accent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: panel,
      indicatorColor: highlight.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: background,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Color(0xFF2E3940)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    dividerColor: const Color(0xFF293037),
    extensions: const <ThemeExtension<dynamic>>[
      AppStatusColors(warning: warning, highlight: highlight, accent: accent),
    ],
  );
}

class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.warning,
    required this.highlight,
    required this.accent,
  });

  final Color warning;
  final Color highlight;
  final Color accent;

  @override
  ThemeExtension<AppStatusColors> copyWith({
    Color? warning,
    Color? highlight,
    Color? accent,
  }) {
    return AppStatusColors(
      warning: warning ?? this.warning,
      highlight: highlight ?? this.highlight,
      accent: accent ?? this.accent,
    );
  }

  @override
  ThemeExtension<AppStatusColors> lerp(
    covariant ThemeExtension<AppStatusColors>? other,
    double t,
  ) {
    if (other is! AppStatusColors) {
      return this;
    }

    return AppStatusColors(
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      highlight: Color.lerp(highlight, other.highlight, t) ?? highlight,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
    );
  }
}
