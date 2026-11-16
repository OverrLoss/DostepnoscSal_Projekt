import 'package:flutter/material.dart';

/// Centralny design system aplikacji.
///
/// Styl oznakowania budynku uczelni: grafitowe tło, ciepła biel tekstu,
/// jeden mosiężny akcent (jak tabliczki na drzwiach sal), małe zaokrąglenia,
/// bez cieni. Zieleń i czerwień są zarezerwowane wyłącznie dla statusu sali.
class AppColors {
  AppColors._();

  // ── Powierzchnie ──────────────────────────────────────────────────────
  /// Główne tło aplikacji (grafit).
  static const Color background = Color(0xFF1A1D22);

  /// Tło kart i kafelków.
  static const Color surface = Color(0xFF22262D);

  /// Jaśniejsza powierzchnia (menu, pola formularzy, wyróżnione elementy).
  static const Color surfaceAlt = Color(0xFF2B3038);

  /// Subtelne obramowania kart.
  static const Color stroke = Color(0xFF353A44);

  // ── Akcenty ───────────────────────────────────────────────────────────
  /// Jedyny akcent — mosiądz, jak tabliczki na drzwiach sal.
  static const Color primary = Color(0xFFD4A955);

  /// Tekst i ikony na tle w kolorze akcentu.
  static const Color onPrimary = Color(0xFF1A1D22);

  /// Sukces / wolna sala.
  static const Color success = Color(0xFF4CAF7F);

  /// Ostrzeżenie.
  static const Color warning = Color(0xFFE08A3C);

  /// Błąd / zajęta sala.
  static const Color danger = Color(0xFFE0625A);

  /// Dodatkowy akcent (cyjan — tryb TV itp.).
  static const Color cyan = Color(0xFF8AB4C8);

  // ── Tekst ─────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFEDEBE6);
  static const Color textSecondary = Color(0xFF9C9FA6);
  static const Color textFaint = Color(0xFF6B6F78);

  // ── Promienie ─────────────────────────────────────────────────────────
  static const double radiusCard = 10;
  static const double radiusControl = 8;
  static const double radiusPill = 8;
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.cyan,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          side: const BorderSide(color: AppColors.stroke),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: AppColors.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.success;
          }
          return AppColors.surfaceAlt;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return AppColors.stroke;
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        hintStyle: const TextStyle(color: AppColors.textFaint),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusControl),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusControl),
          borderSide: const BorderSide(color: AppColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusControl),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.stroke),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.16),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusControl),
        ),
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          );
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
    );
  }
}
