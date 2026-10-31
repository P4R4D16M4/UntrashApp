// Untrash look (UntrashOS design/untrash.css): near-black blue-grey
// surfaces, teal accent, the green-to-cyan gradient for the main action.
import 'package:flutter/material.dart';

class Ut {
  static const bg0 = Color(0xFF080B0E);
  static const bg1 = Color(0xFF0D1115);
  static const bg2 = Color(0xFF12171C);
  static const bg3 = Color(0xFF181E24);
  static const bg4 = Color(0xFF202830);
  static const line = Color(0x12FFFFFF);
  static const line2 = Color(0x1FFFFFFF);
  static const fg = Color(0xFFE9EEF2);
  static const fg2 = Color(0xFFAAB4BD);
  static const fg3 = Color(0xFF7B8792);
  static const onAccent = Color(0xFF04170F);
  static const teal = Color(0xFF05C7AF);
  static const accentFg = Color(0xFF39DCC4);
  static const ok = Color(0xFF5DEF6B);
  static const info = Color(0xFF00C8C9);
  static const warn = Color(0xFFF4B54A);
  static const danger = Color(0xFFFF5F6D);
  static const dangerSolid = Color(0xFFC8394A);
  static const grad = LinearGradient(
    begin: Alignment(-1, -0.4),
    end: Alignment(1, 0.4),
    colors: [Color(0xFF6FF06B), Color(0xFF19D6A6), Color(0xFF00BFD0)],
    stops: [0, .55, 1],
  );
  static const rSm = 7.0, rMd = 10.0, rLg = 14.0, rXl = 20.0;
}

ThemeData untrashTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: Ut.teal,
      onPrimary: Ut.onAccent,
      secondary: Ut.info,
      surface: Ut.bg2,
      onSurface: Ut.fg,
      error: Ut.danger,
    ),
    scaffoldBackgroundColor: Ut.bg1,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Ut.fg, displayColor: Ut.fg),
    appBarTheme: const AppBarTheme(backgroundColor: Ut.bg1, foregroundColor: Ut.fg, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: Ut.bg2,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ut.rLg),
        side: const BorderSide(color: Ut.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Ut.bg3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ut.rMd),
        borderSide: const BorderSide(color: Ut.line2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ut.rMd),
        borderSide: const BorderSide(color: Ut.line2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ut.rMd),
        borderSide: const BorderSide(color: Ut.teal, width: 2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Ut.fg,
        side: const BorderSide(color: Ut.line2),
        backgroundColor: Ut.bg3,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ut.rMd)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Ut.accentFg)),
    dividerTheme: const DividerThemeData(color: Ut.line, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Ut.bg2,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ut.rXl))),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Ut.bg4,
      contentTextStyle: TextStyle(color: Ut.fg),
    ),
  );
}

/// The main action: gradient pill as in the Desk.
class GradButton extends StatelessWidget {
  const GradButton({super.key, required this.label, this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: Ut.grad, borderRadius: BorderRadius.circular(Ut.rMd)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Ut.rMd),
            onTap: onPressed,
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, color: Ut.onAccent, size: 20), const SizedBox(width: 8)],
                  Text(
                    label,
                    style: const TextStyle(color: Ut.onAccent, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(color: Ut.fg3, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.1),
    ),
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color.withValues(alpha: .5), blurRadius: 6)],
    ),
  );
}
