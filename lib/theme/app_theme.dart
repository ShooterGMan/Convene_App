import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

extension AppColorsExtension on BuildContext {
  AppColors get colors => Theme.of(this).brightness == Brightness.dark
      ? AppColors.dark()
      : AppColors.light();
}

class AppColors {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;

  final Color background;
  final Color surface;

  final Color textMain;
  final Color textMuted;
  final Color textLight;

  final Color accent;
  final Color accentLight;

  final Color border;
  final Color divider;
  final Color overlay;
  final Color cardShadow;
  final Color error;

  const AppColors({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.background,
    required this.surface,
    required this.textMain,
    required this.textMuted,
    required this.textLight,
    required this.accent,
    required this.accentLight,
    required this.border,
    required this.divider,
    required this.overlay,
    required this.cardShadow,
    required this.error,
  });

  factory AppColors.light() {
    return const AppColors(
      primary: Color(0xFFFF5E3A),
      primaryLight: Color(0xFFFFF0EC),
      primaryDark: Color(0xFFE04E2C),
      background: Color(0xFFF4F4F2),
      surface: Color(0xFFFFFFFF),
      textMain: Color(0xFF1C1C1E),
      textMuted: Color(0xFF8E8E93),
      textLight: Color(0xFFAEAEB2),
      accent: Color(0xFF34C759),
      accentLight: Color(0xFFEAF9EE),
      border: Color(0xFFE5E5EA),
      divider: Color(0xFFF2F2F7),
      overlay: Color(0x66000000),
      cardShadow: Color(0x0D000000),
      error: Color(0xFFFF3B30),
    );
  }

  factory AppColors.dark() {
    return const AppColors(
      primary: Color(0xFFFF5E3A),
      primaryLight: Color(0xFF3A1F18),
      primaryDark: Color(0xFFE04E2C),
      background: Color(0xFF121212),
      surface: Color(0xFF1E1E1E),
      textMain: Color(0xFFF4F4F2),
      textMuted: Color(0xFF8E8E93),
      textLight: Color(0xFF636366),
      accent: Color(0xFF32D74B),
      accentLight: Color(0xFF1A3822),
      border: Color(0xFF38383A),
      divider: Color(0xFF2C2C2E),
      overlay: Color(0xB3000000),
      cardShadow: Color(0x40000000),
      error: Color(0xFFFF453A),
    );
  }
}

class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> diffused = [
    BoxShadow(
      color: Color(0x26FF5E3A),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> bottomNav = [
    BoxShadow(
      color: Color(0x05000000),
      blurRadius: 24,
      offset: Offset(0, -4),
    ),
  ];
}

class AppRadius {
  static const double sm = 12.0;
  static const double md = 24.0;
  static const double lg = 32.0;
  static const double full = 9999.0;

  static final BorderRadius smBorder = BorderRadius.circular(sm);
  static final BorderRadius mdBorder = BorderRadius.circular(md);
  static final BorderRadius lgBorder = BorderRadius.circular(lg);
  static final BorderRadius fullBorder = BorderRadius.circular(full);
}

class AppTheme {
  static ThemeData get lightTheme {
    final colors = AppColors.light();
    return _buildTheme(colors, Brightness.light);
  }

  static ThemeData get darkTheme {
    final colors = AppColors.dark();
    return _buildTheme(colors, Brightness.dark);
  }

  static ThemeData _buildTheme(AppColors colors, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.primary,
        onPrimary: Colors.white,
        secondary: colors.accent,
        onSecondary: Colors.white,
        surface: colors.surface,
        onSurface: colors.textMain,
        error: colors.error,
        onError: Colors.white,
        outline: colors.border,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
        headlineLarge: GoogleFonts.plusJakartaSans(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: colors.textMain,
          height: 1.2,
        ),
        headlineMedium: GoogleFonts.plusJakartaSans(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: colors.textMain,
        ),
        headlineSmall: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.textMain,
        ),
        titleLarge: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textMain,
        ),
        titleMedium: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.textMain,
        ),
        bodyLarge: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.textMain,
        ),
        bodyMedium: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.textMain,
        ),
        bodySmall: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.textMuted,
        ),
        labelLarge: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: colors.textMain,
          letterSpacing: 0.5,
        ),
        labelSmall: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.textMuted,
          letterSpacing: 1.0,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface.withValues(alpha: 0.9),
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.textMain,
        ),
        iconTheme: IconThemeData(color: colors.textMain),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdBorder,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light ? Color(0xFFF9F9F9) : Color(0xFF2C2C2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.textMuted.withValues(alpha: 0.7),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.surface,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
      ),
    );
  }
}

