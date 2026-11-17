import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Centralny design system aplikacji — styl „liquid glass”.
///
/// Czerń i odcienie szarości. Ekran główny leży na czarnym tle z miękkim,
/// białym światłem, a karty, statystyki i pola są taflami szkła z jasną
/// krawędzią. Kolor pojawia się tylko w statusie sali: zielony i czerwony.
/// Akcentem jest biel (zaznaczone elementy: białe tło, czarny tekst).
/// Pozostałe ekrany i okna dialogowe używają pełnych (nieprzezroczystych)
/// powierzchni w tej samej kolorystyce, żeby tekst był zawsze czytelny.
class AppColors {
  AppColors._();

  // ── Powierzchnie pełne ────────────────────────────────────────────────
  /// Tło ekranów (czerń).
  static const Color background = Color(0xFF000000);

  /// Pełne tło kart na zwykłych ekranach, dialogów i arkuszy.
  static const Color surface = Color(0xFF141414);

  /// Jaśniejsza pełna powierzchnia (menu, wyróżnienia).
  static const Color surfaceAlt = Color(0xFF1F1F1F);

  /// Obramowania na pełnych powierzchniach.
  static const Color stroke = Color(0xFF2A2A2A);

  // ── Szkło ─────────────────────────────────────────────────────────────
  /// Wypełnienie tafli szkła.
  static const Color glass = Color(0x14FFFFFF);

  /// Mocniejsze szkło (nagłówki kart, puste paski).
  static const Color glassHi = Color(0x24FFFFFF);

  /// Jasna krawędź tafli szkła.
  static const Color glassStroke = Color(0x29FFFFFF);

  // ── Akcenty ───────────────────────────────────────────────────────────
  static const Color primary = Color(0xFFF2F2F2);
  static const Color onPrimary = Color(0xFF000000);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFD4D4D4);
  static const Color danger = Color(0xFFFF453A);
  static const Color cyan = Color(0xFFBDBDBD);

  // ── Tekst ─────────────────────────────────────────────────────────────
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0x99FFFFFF);
  static const Color textFaint = Color(0x59FFFFFF);

  // ── Promienie ─────────────────────────────────────────────────────────
  static const double radiusCard = 8;
  static const double radiusControl = 6;
  static const double radiusPill = 6;

  /// Dekoracja tafli szkła: delikatny jasny gradient i jasna krawędź.
  static BoxDecoration glassDecoration({
    double radius = radiusCard,
    Color? borderColor,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x1FFFFFFF), Color(0x08FFFFFF)],
      ),
      border: Border.all(color: borderColor ?? glassStroke, width: 1),
    );
  }
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
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: AppColors.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
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
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
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
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
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

/// Tło pod szkłem: czerń z dwiema miękkimi plamami białego światła.
class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF111111), Color(0xFF000000), Color(0xFF0A0A0A)],
              ),
            ),
          ),
        ),
        _glow(const Alignment(-1.1, -1.05), 0.10, 420),
        _glow(const Alignment(1.2, 0.35), 0.06, 360),
        Positioned.fill(child: child),
      ],
    );
  }

  static Widget _glow(Alignment alignment, double strength, double size) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: strength),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tafla matowego szkła z rozmyciem tego, co pod spodem.
/// Używana oszczędnie (rozmycie jest kosztowne) — dla dużych elementów.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  const Glass({
    super.key,
    required this.child,
    this.radius = AppColors.radiusCard,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: AppColors.glassDecoration(radius: radius),
          child: child,
        ),
      ),
    );
  }
}
