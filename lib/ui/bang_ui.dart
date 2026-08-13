import 'package:flutter/material.dart';

abstract final class BangColors {
  static const ink = Color(0xff120a07);
  static const walnut = Color(0xff28150d);
  static const panel = Color(0xff321b11);
  static const panelRaised = Color(0xff432619);
  static const felt = Color(0xff174a35);
  static const feltDark = Color(0xff0d3025);
  static const paper = Color(0xfff2dfae);
  static const paperDark = Color(0xffd3b778);
  static const brass = Color(0xffffc85a);
  static const brassDark = Color(0xffa96a24);
  static const oxblood = Color(0xff9f2f25);
  static const defense = Color(0xff7ca8c9);
  static const success = Color(0xff79c66a);
  static const muted = Color(0xffc8b89f);
}

const bangGold = BangColors.brass;
const bangInk = BangColors.ink;
const bangPanel = BangColors.panel;

abstract final class BangMotion {
  static const instant = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 220);
  static const reveal = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;

  static bool reduce(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration resolve(BuildContext context, Duration duration) =>
      reduce(context) ? Duration.zero : duration;
}

ThemeData bangTheme() {
  const scheme = ColorScheme.dark(
    surface: BangColors.ink,
    onSurface: Colors.white,
    primary: BangColors.brass,
    onPrimary: BangColors.ink,
    secondary: BangColors.paper,
    onSecondary: BangColors.ink,
    error: Color(0xffff7165),
    onError: BangColors.ink,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: BangColors.ink,
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
      fontFamily: 'sans-serif',
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: BangColors.walnut,
      foregroundColor: Colors.white,
      toolbarHeight: 48,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: BangColors.paper,
        fontSize: 17,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: BangColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        color: BangColors.paper,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: BangColors.paper,
      contentTextStyle: const TextStyle(
        color: BangColors.ink,
        fontWeight: FontWeight.w700,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BangColors.ink.withValues(alpha: .72),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff765135)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff765135)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BangColors.brass, width: 1.5),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BangColors.brass,
      linearTrackColor: Color(0xff4b2b1c),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: BangColors.brass,
        foregroundColor: BangColors.ink,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: BangColors.brass,
        foregroundColor: BangColors.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: BangColors.paper,
        side: const BorderSide(color: Color(0xff8b623e)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: BangColors.brass,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

Route<T> bangRoute<T>(Widget child) => PageRouteBuilder<T>(
  pageBuilder: (_, _, _) => child,
  transitionDuration: BangMotion.standard,
  reverseTransitionDuration: BangMotion.fast,
  transitionsBuilder: (context, animation, _, child) {
    if (BangMotion.reduce(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: BangMotion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.025, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);

class BangScenicBackground extends StatelessWidget {
  const BangScenicBackground({
    super.key,
    required this.child,
    this.asset = 'assets/images/wild_west_town.png',
    this.overlay = .56,
  });

  final Widget child;
  final String asset;
  final double overlay;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          cacheWidth:
              (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.05,
            colors: [
              BangColors.ink.withValues(alpha: overlay * .35),
              BangColors.ink.withValues(alpha: overlay),
            ],
          ),
        ),
      ),
      child,
    ],
  );
}

class BangPanel extends StatelessWidget {
  const BangPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.paper = false,
    this.felt = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool paper;
  final bool felt;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: paper
            ? const [BangColors.paper, Color(0xffdec58b)]
            : felt
            ? const [BangColors.felt, BangColors.feltDark]
            : const [BangColors.panelRaised, BangColors.panel],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: paper ? BangColors.paperDark : const Color(0xff765135),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
        BoxShadow(color: Color(0x1affd37a), blurRadius: 2),
      ],
    ),
    child: Padding(
      padding: padding,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: paper ? BangColors.ink : Colors.white),
        child: child,
      ),
    ),
  );
}

class BangButton extends StatefulWidget {
  const BangButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.secondary = false,
    this.danger = false,
    this.minWidth = 160,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool secondary;
  final bool danger;
  final double minWidth;

  @override
  State<BangButton> createState() => _BangButtonState();
}

class _BangButtonState extends State<BangButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final background = widget.danger
        ? BangColors.oxblood
        : widget.secondary
        ? BangColors.panelRaised
        : BangColors.brass;
    final foreground = widget.secondary ? BangColors.paper : BangColors.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedScale(
        duration: BangMotion.resolve(context, BangMotion.instant),
        curve: BangMotion.curve,
        scale: _pressed && enabled ? .96 : 1,
        child: Listener(
          onPointerDown: enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onPointerUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onPointerCancel: enabled
              ? (_) => setState(() => _pressed = false)
              : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.minWidth,
              minHeight: 46,
            ),
            child: FilledButton.icon(
              onPressed: enabled ? widget.onPressed : null,
              icon: widget.loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                  : Icon(widget.icon ?? Icons.arrow_forward_rounded, size: 20),
              label: Text(widget.label),
              style: FilledButton.styleFrom(
                backgroundColor: background,
                foregroundColor: foreground,
                disabledBackgroundColor: background.withValues(alpha: .42),
                disabledForegroundColor: foreground.withValues(alpha: .6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: widget.secondary
                        ? const Color(0xff8b623e)
                        : const Color(0xffffdf8d),
                  ),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                  fontSize: 13,
                ),
                elevation: 4,
                shadowColor: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BangIconButton extends StatelessWidget {
  const BangIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    style: IconButton.styleFrom(
      foregroundColor: BangColors.paper,
      backgroundColor: BangColors.ink.withValues(alpha: .7),
      disabledForegroundColor: BangColors.muted.withValues(alpha: .35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xff765135)),
      ),
    ),
    icon: Icon(icon, size: 21),
  );
}

class BangStatusPill extends StatelessWidget {
  const BangStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: .62)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 10,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
