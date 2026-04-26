import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFD9A35F),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFD9A35F),
      onPrimary: const Color(0xFF101318),
      secondary: const Color(0xFF7DA388),
      tertiary: const Color(0xFFB57962),
      surface: const Color(0xFF141A21),
      onSurface: const Color(0xFFF4ECDD),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: baseScheme,
    );

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0D1117),
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: const Color(0xFFF8F2E7),
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: const Color(0xFFF8F2E7),
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFFF2EBDD),
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFFF2EBDD),
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          height: 1.5,
          color: const Color(0xFFE2DACF),
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          height: 1.45,
          color: const Color(0xFFBDB6AA),
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: const Color(0xFFD9A35F).withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: selected ? const Color(0xFFF6EEDF) : const Color(0xFF9E9A91),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          },
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF161E27),
        hintStyle: const TextStyle(color: Color(0xFF8A887F)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: const Color(0xFFD9A35F).withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(
            color: Color(0xFFD9A35F),
            width: 1.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFD9A35F),
          foregroundColor: const Color(0xFF101318),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFF2EBDD),
          side: BorderSide(
            color: const Color(0xFFD9A35F).withValues(alpha: 0.18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(
          color: const Color(0xFFD9A35F).withValues(alpha: 0.14),
        ),
        backgroundColor: const Color(0xFF171F27),
        labelStyle: const TextStyle(
          color: Color(0xFFE7DDCD),
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerColor: const Color(0x22F4ECDD),
    );
  }
}
