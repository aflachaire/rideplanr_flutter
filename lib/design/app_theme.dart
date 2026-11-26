import 'package:flutter/material.dart';

/// Port of the iOS `AppTheme` design tokens. Colors come in light/dark pairs,
/// resolved through the ambient [Brightness] like UIKit dynamic colors.
class AppTheme {
  AppTheme._();

  // Static accents (identical in both appearances, like the iOS app).
  static const Color gold = Color.fromRGBO(226, 187, 16, 1); // 0.886/0.733/0.063
  static const Color success = Color.fromRGBO(59, 237, 120, 1); // 0.23/0.93/0.47
  static const Color cyan = Color.fromRGBO(102, 209, 232, 1); // 0.40/0.82/0.91
  static const Color mint = Color.fromRGBO(145, 217, 189, 1); // 0.57/0.85/0.74
  static const Color blue = Color.fromRGBO(110, 161, 250, 1); // 0.43/0.63/0.98
  static const Color coral = Color.fromRGBO(240, 125, 107, 1); // 0.94/0.49/0.42

  static const Color _backgroundLight = Color.fromRGBO(245, 247, 252, 1);
  static const Color _backgroundDark = Color.fromRGBO(13, 18, 26, 1);
  static const Color _surfaceLight = Color.fromRGBO(255, 255, 255, 0.94);
  static const Color _surfaceDark = Color.fromRGBO(26, 33, 43, 1);
  static const Color _elevatedLight = Color.fromRGBO(235, 240, 247, 1);
  static const Color _elevatedDark = Color.fromRGBO(36, 43, 56, 1);
  static const Color _borderLight = Color.fromRGBO(20, 31, 46, 0.10);
  static const Color _borderDark = Color.fromRGBO(255, 255, 255, 0.08);
  static const Color _textPrimaryLight = Color.fromRGBO(20, 28, 41, 1);
  static const Color _textPrimaryDark = Colors.white;
  static const Color _textSecondaryLight = Color.fromRGBO(77, 92, 112, 0.92);
  static const Color _textSecondaryDark = Color.fromRGBO(255, 255, 255, 0.68);
  static const Color _textOnAccentLight = Color.fromRGBO(28, 26, 20, 1);
  static const Color _textOnAccentDark = Color.fromRGBO(15, 18, 23, 1);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      _isDark(context) ? _backgroundDark : _backgroundLight;

  static Color surface(BuildContext context) =>
      _isDark(context) ? _surfaceDark : _surfaceLight;

  static Color elevated(BuildContext context) =>
      _isDark(context) ? _elevatedDark : _elevatedLight;

  static Color border(BuildContext context) =>
      _isDark(context) ? _borderDark : _borderLight;

  static Color textPrimary(BuildContext context) =>
      _isDark(context) ? _textPrimaryDark : _textPrimaryLight;

  static Color textSecondary(BuildContext context) =>
      _isDark(context) ? _textSecondaryDark : _textSecondaryLight;

  static Color textOnAccent(BuildContext context) =>
      _isDark(context) ? _textOnAccentDark : _textOnAccentLight;

  static ThemeData themeData(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? _backgroundDark : _backgroundLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: gold,
        brightness: brightness,
        surface: isDark ? _backgroundDark : _backgroundLight,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}

/// Port of the iOS `appCardStyle()` modifier: padded, rounded surface card
/// with a hairline border.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: child,
    );
  }
}
