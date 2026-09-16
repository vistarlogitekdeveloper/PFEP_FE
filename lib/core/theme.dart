

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens transcribed from the approved Vistar PFEP prototype
/// (`design/prototype.html`). Names mirror the CSS custom properties so the two
/// can be diffed: `--surface2` is [Brand.surface2], `--txt3` is [Brand.txt3].
///
/// Surface and text tokens are *getters*, not constants, because the prototype
/// ships both a dark and a light theme (`body.light`). [Brand.isLight] is set
/// from the theme provider before `MaterialApp` rebuilds, so every widget below
/// picks up the new palette on the same frame. The brand ribbon hues are the
/// same in both modes and stay `const`.
class Brand {
  /* ---- brand ribbon — identical in both themes -------------------------- */
  static const purple = Color(0xFF7A1FB0);
  static const violet = Color(0xFF9B30C9);
  static const magenta = Color(0xFFC018C0);
  static const pink = Color(0xFFE0218A);
  static const red = Color(0xFFC8102E);
  static const orangeRed = Color(0xFFF0480C);
  static const orange = Color(0xFFF06000);
  static const amber = Color(0xFFF0C000);
  static const yellow = Color(0xFFF0E060);
  static const cream = Color(0xFFFFF6CC);

  /* ---- theme switch ----------------------------------------------------- */
  static bool isLight = false;
  static _Palette get _p => isLight ? _light : _dark;

  /* ---- surfaces --------------------------------------------------------- */
  static Color get bg => _p.bg;
  static Color get bg2 => _p.bg2;
  static Color get surface => _p.surface;
  static Color get surface2 => _p.surface2;
  static Color get surface3 => _p.surface3;
  static Color get line => _p.line;
  static Color get line2 => _p.line2;

  static Color get txt => _p.txt;
  static Color get txt2 => _p.txt2;
  static Color get txt3 => _p.txt3;

  static Color get ok => _p.ok;
  static Color get warn => _p.warn;
  static Color get bad => _p.bad;
  static Color get info => _p.info;

  /// Track colour behind a progress bar (`.bar`).
  static Color get track => _p.track;

  /* ---- radii ------------------------------------------------------------ */
  static const r = 16.0;
  static const rSm = 11.0;
  static const rLg = 22.0;

  /// `--ribbon`: linear-gradient(115deg, ...). 115deg in CSS runs from the
  /// bottom-left toward the top-right, which is this begin/end pair.
  static const ribbon = LinearGradient(
    begin: Alignment(-1, 0.36),
    end: Alignment(1, -0.36),
    colors: [
      Color(0xFF7A1FB0),
      Color(0xFFB81FB8),
      Color(0xFFE0218A),
      Color(0xFFD11630),
      Color(0xFFF0480C),
      Color(0xFFF06000),
      Color(0xFFF0C000),
      Color(0xFFF7EE9A),
    ],
    stops: [0.0, 0.22, 0.40, 0.56, 0.70, 0.80, 0.92, 1.0],
  );

  /// `--ribbon-soft`
  static const ribbonSoft = LinearGradient(
    begin: Alignment(-1, 0.36),
    end: Alignment(1, -0.36),
    colors: [Color(0xE69B30C9), Color(0xE6E0218A), Color(0xE6F0480C), Color(0xE6F0C000)],
  );

  static List<BoxShadow> get shadow => _p.shadow;
  static List<BoxShadow> get glow => _p.glow;

  /// `.card` is a vertical gradient, not a flat fill.
  static Gradient get cardFill => _p.cardFill;

  /// `#side`
  static Gradient get sideFill => _p.sideFill;

  /// `#top`
  static Color get topFill => _p.topFill;

  /// The three radial washes behind everything (`#ambient`).
  static List<AmbientWash> get ambient => _p.ambient;

  /// `.nav.on` background.
  static Gradient get navOnFill => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0x24E0218A), Color(0x0D7A1FB0)],
      );

  /// One stable colour per record status, used by charts and accents.
  static Color status(String s) => switch (s) {
        'Approved' => ok,
        'Submitted' => warn,
        'In Progress' => info,
        'Rejected' => bad,
        _ => txt3,
      };

  /// Pill tone for a status, matching the prototype's `.p-*` classes.
  static PillTone statusTone(String s) => switch (s) {
        'Approved' => PillTone.ok,
        'Submitted' => PillTone.amber,
        'In Progress' => PillTone.info,
        'Rejected' => PillTone.bad,
        _ => PillTone.neutral,
      };
}

/// A radial wash in the ambient background: size and position as fractions of
/// the viewport, transcribed from the prototype's `radial-gradient()` stack.
class AmbientWash {
  const AmbientWash(this.alignment, this.radius, this.color);

  final Alignment alignment;
  final double radius;
  final Color color;
}

class _Palette {
  const _Palette({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.line2,
    required this.txt,
    required this.txt2,
    required this.txt3,
    required this.ok,
    required this.warn,
    required this.bad,
    required this.info,
    required this.track,
    required this.cardFill,
    required this.sideFill,
    required this.topFill,
    required this.ambient,
    required this.shadow,
    required this.glow,
  });

  final Color bg, bg2, surface, surface2, surface3, line, line2;
  final Color txt, txt2, txt3, ok, warn, bad, info, track, topFill;
  final Gradient cardFill, sideFill;
  final List<AmbientWash> ambient;
  final List<BoxShadow> shadow, glow;
}

const _dark = _Palette(
  bg: Color(0xFF070611),
  bg2: Color(0xFF0B0A18),
  surface: Color(0xFF110F1E),
  surface2: Color(0xFF16142A),
  surface3: Color(0xFF1D1A33),
  line: Color(0x14FFFFFF),
  line2: Color(0x21FFFFFF),
  txt: Color(0xFFF2EEFB),
  txt2: Color(0xFFB9B2D6),
  txt3: Color(0xFF7E769B),
  ok: Color(0xFF34D399),
  warn: Color(0xFFFBBF24),
  bad: Color(0xFFFB6F84),
  info: Color(0xFF5BA8FF),
  track: Color(0x12FFFFFF),
  cardFill: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xB316142A), Color(0xB3110F1E)],
  ),
  sideFill: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xEB0B0A18), Color(0xEB070611)],
  ),
  topFill: Color(0x9E0B0A18),
  ambient: [
    AmbientWash(Alignment(-0.76, -1.16), 1.15, Color(0x387A1FB0)),
    AmbientWash(Alignment(1.10, -0.84), 1.05, Color(0x29E0218A)),
    AmbientWash(Alignment(0.60, 1.20), 1.25, Color(0x1FF06000)),
  ],
  shadow: [
    BoxShadow(color: Color(0xD9000000), blurRadius: 60, spreadRadius: -28, offset: Offset(0, 24)),
  ],
  glow: [
    BoxShadow(color: Color(0x66C018C0), blurRadius: 50, spreadRadius: -22, offset: Offset(0, 18)),
  ],
);

const _light = _Palette(
  bg: Color(0xFFF5F3FB),
  bg2: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFF3F0FA),
  surface3: Color(0xFFEAE5F6),
  line: Color(0x1A180C30),
  line2: Color(0x2B180C30),
  txt: Color(0xFF1D1533),
  txt2: Color(0xFF4C4268),
  txt3: Color(0xFF8A82A8),
  ok: Color(0xFF0E9F6E),
  warn: Color(0xFFB45309),
  bad: Color(0xFFE11D48),
  info: Color(0xFF2563EB),
  track: Color(0x17180C30),
  cardFill: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xEBFFFFFF), Color(0xDBFAF8FE)],
  ),
  sideFill: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xEBFFFFFF), Color(0xEBF8F6FD)],
  ),
  topFill: Color(0xB8FFFFFF),
  ambient: [
    AmbientWash(Alignment(-0.76, -1.16), 1.15, Color(0x219B30C9)),
    AmbientWash(Alignment(1.10, -0.84), 1.05, Color(0x1AE0218A)),
    AmbientWash(Alignment(0.60, 1.20), 1.25, Color(0x1AF09628)),
  ],
  shadow: [
    BoxShadow(color: Color(0x47341A5A), blurRadius: 60, spreadRadius: -30, offset: Offset(0, 24)),
  ],
  glow: [
    BoxShadow(color: Color(0x47C018C0), blurRadius: 50, spreadRadius: -24, offset: Offset(0, 18)),
  ],
);

/// The prototype's `.p-*` pill palette. Each tone has its own translucent
/// background and a shifted ink colour in each theme — not just an opacity of
/// the base hue, which is why these are spelled out rather than derived.
enum PillTone {
  info,
  amber,
  violet,
  pink,
  ok,
  orange,
  bad,
  neutral;

  Color get fill => switch (this) {
        PillTone.info => Brand.isLight ? const Color(0x1A2563EB) : const Color(0x245BA8FF),
        PillTone.amber => Brand.isLight ? const Color(0x1AB45309) : const Color(0x24F0C000),
        PillTone.violet => Brand.isLight ? const Color(0x1A7A1FB0) : const Color(0x2E9B30C9),
        PillTone.pink => Brand.isLight ? const Color(0x1AE0218A) : const Color(0x29E0218A),
        PillTone.ok => Brand.isLight ? const Color(0x1A0E9F6E) : const Color(0x2434D399),
        PillTone.orange => Brand.isLight ? const Color(0x1AF06000) : const Color(0x29F06000),
        PillTone.bad => Brand.isLight ? const Color(0x17E11D48) : const Color(0x24FB6F84),
        PillTone.neutral => Brand.isLight ? const Color(0x12180C30) : const Color(0x12FFFFFF),
      };

  Color get ink => switch (this) {
        PillTone.info => Brand.isLight ? const Color(0xFF1D4ED8) : const Color(0xFF8CC2FF),
        PillTone.amber => Brand.isLight ? const Color(0xFF92590A) : const Color(0xFFF5D45E),
        PillTone.violet => Brand.isLight ? const Color(0xFF7A1FB0) : const Color(0xFFCE96EA),
        PillTone.pink => Brand.isLight ? const Color(0xFFB0136A) : const Color(0xFFF7A8CF),
        PillTone.ok => Brand.isLight ? const Color(0xFF047857) : const Color(0xFF6EE7B7),
        PillTone.orange => Brand.isLight ? const Color(0xFFB24A02) : const Color(0xFFFFA362),
        PillTone.bad => Brand.isLight ? const Color(0xFFBE123C) : const Color(0xFFFFA0AE),
        PillTone.neutral => Brand.txt2,
      };

  Color get dot => switch (this) {
        PillTone.info => Brand.info,
        PillTone.amber => Brand.amber,
        PillTone.violet => Brand.violet,
        PillTone.pink => Brand.pink,
        PillTone.ok => Brand.ok,
        PillTone.orange => Brand.orange,
        PillTone.bad => Brand.bad,
        PillTone.neutral => Brand.txt3,
      };
}

/// `.alertbox` tones — background, border and ink differ per theme.
enum AlertTone {
  bad,
  ok,
  warn,
  info;

  Color get fill => switch (this) {
        AlertTone.bad => Brand.isLight ? const Color(0x0FE11D48) : const Color(0x14FB6F84),
        AlertTone.ok => Brand.isLight ? const Color(0x120E9F6E) : const Color(0x1234D399),
        AlertTone.warn => Brand.isLight ? const Color(0x12B45309) : const Color(0x12F0C000),
        AlertTone.info => Brand.isLight ? const Color(0x0F2563EB) : const Color(0x125BA8FF),
      };

  Color get border => switch (this) {
        AlertTone.bad => Brand.isLight ? const Color(0x40E11D48) : const Color(0x47FB6F84),
        AlertTone.ok => Brand.isLight ? const Color(0x470E9F6E) : const Color(0x3D34D399),
        AlertTone.warn => Brand.isLight ? const Color(0x42B45309) : const Color(0x42F0C000),
        AlertTone.info => Brand.isLight ? const Color(0x3D2563EB) : const Color(0x3D5BA8FF),
      };

  Color get ink => switch (this) {
        AlertTone.bad => Brand.isLight ? const Color(0xFF9F1239) : const Color(0xFFFFC0CA),
        AlertTone.ok => Brand.isLight ? const Color(0xFF065F46) : const Color(0xFFA7F3D0),
        AlertTone.warn => Brand.isLight ? const Color(0xFF92400E) : const Color(0xFFF7DE93),
        AlertTone.info => Brand.isLight ? const Color(0xFF1E40AF) : const Color(0xFFBBD9FF),
      };

  Color get icon => switch (this) {
        AlertTone.bad => Brand.bad,
        AlertTone.ok => Brand.ok,
        AlertTone.warn => Brand.warn,
        AlertTone.info => Brand.info,
      };
}

/* ------------------------------------------------------------- typography */

/// Headings use Bricolage Grotesque with tight tracking, as in the prototype.
TextStyle display({
  double size = 29,
  FontWeight weight = FontWeight.w800,
  Color? color,
  double height = 1.1,
}) =>
    GoogleFonts.bricolageGrotesque(
      fontSize: size,
      fontWeight: weight,
      color: color ?? Brand.txt,
      height: height,
      letterSpacing: -0.4,
    );

/// Body text is Manrope.
TextStyle body({
  double size = 13,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
  double letterSpacing = 0.1,
  TextDecoration? decoration,
}) =>
    GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color ?? Brand.txt,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    );

/// `.mono` in the prototype is not a monospace face — it is Manrope with
/// tabular figures, so part numbers and quantities line up in a column without
/// looking like source code.
TextStyle mono({double size = 13, FontWeight weight = FontWeight.w700, Color? color}) =>
    GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color ?? Brand.txt,
      letterSpacing: 0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// `.lbl` — the small uppercase field label.
TextStyle fieldLabel({Color? color}) => GoogleFonts.manrope(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: color ?? Brand.txt3,
    );

/// `.navgrp` and the page-header crumb.
TextStyle eyebrow({double size = 10, Color? color, double tracking = 1.1}) => GoogleFonts.manrope(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: tracking,
      color: color ?? Brand.txt3,
    );

ThemeData buildTheme({required bool light}) {
  Brand.isLight = light;
  final base = light ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);
  final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(
    bodyColor: Brand.txt,
    displayColor: Brand.txt,
  );

  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Brand.bg,
    textTheme: text,
    colorScheme: base.colorScheme.copyWith(
      primary: Brand.pink,
      secondary: Brand.violet,
      surface: Brand.surface,
      error: Brand.bad,
      onPrimary: Colors.white,
      onSurface: Brand.txt,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      titleTextStyle: display(size: 17),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.r),
        side: BorderSide(color: Brand.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: Brand.line, space: 1, thickness: 1),
    // `.inp`
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: body(size: 14, color: Brand.txt3),
      labelStyle: body(size: 13, color: Brand.txt2),
      border: _border(Brand.line),
      enabledBorder: _border(Brand.line),
      focusedBorder: _border(Brand.pink.withValues(alpha: 0.6), width: 1.4),
      errorBorder: _border(Brand.bad.withValues(alpha: 0.65)),
      focusedErrorBorder: _border(Brand.bad.withValues(alpha: 0.65), width: 1.4),
      errorStyle: body(size: 11, color: Brand.bad),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.pink,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.rSm)),
        textStyle: body(size: 14, weight: FontWeight.w700),
      ),
    ),
    // `.btn-ghost`
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.txt,
        backgroundColor: Brand.surface2,
        side: BorderSide(color: Brand.line),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: body(size: 13, weight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Brand.pink,
        textStyle: body(size: 13, weight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Brand.surface2,
      side: BorderSide(color: Brand.line),
      labelStyle: body(size: 12.5, weight: FontWeight.w700, color: Brand.txt2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Brand.surface3,
      contentTextStyle: body(size: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.rLg),
        side: BorderSide(color: Brand.line2),
      ),
      titleTextStyle: display(size: 19),
      contentTextStyle: body(size: 13, color: Brand.txt2, height: 1.5),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: Brand.pink,
      linearTrackColor: Brand.track,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.bg2,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Brand.pink.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(
        body(size: 10.5, weight: FontWeight.w700, color: Brand.txt2),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: Brand.txt2,
      textColor: Brand.txt,
      dense: true,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Brand.surface3,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.line2),
      ),
      textStyle: body(size: 11.5, color: Brand.txt2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Brand.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: Brand.line2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.pink : Brand.txt3,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.pink : Colors.transparent,
      ),
      side: BorderSide(color: Brand.line2, width: 1.4),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Brand.surface2,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

OutlineInputBorder _border(Color c, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Brand.rSm),
      borderSide: BorderSide(color: c, width: width),
    );

/// The ambient wash behind every screen (`#ambient`): three soft radials plus a
/// very faint brand swoosh. Sits at the root so it shows through the
/// translucent sidebar and top bar.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: ColoredBox(color: Brand.bg)),
      for (final w in Brand.ambient)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: w.alignment,
                radius: w.radius,
                colors: [w.color, w.color.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      // #ambient .swoosh { right:-6%; top:50%; width:62vmax; height:62vmax }
      Positioned.fill(
        child: IgnorePointer(
          child: LayoutBuilder(
            builder: (context, c) {
              final vmax = c.maxWidth > c.maxHeight ? c.maxWidth : c.maxHeight;
              final size = vmax * 0.62;
              return Stack(children: [
                Positioned(
                  right: -c.maxWidth * 0.06,
                  top: (c.maxHeight - size) / 2,
                  width: size,
                  height: size,
                  child: Opacity(
                    opacity: Brand.isLight ? 0.035 : 0.05,
                    child: Transform.rotate(
                      angle: 0.07,
                      child: Image.asset(
                        'assets/brand/vistar_s.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
      Positioned.fill(child: child),
    ]);
  }
}
