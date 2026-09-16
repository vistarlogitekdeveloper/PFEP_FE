/// Formatting helpers and the light/dark palette switch.
///
/// The numbers here are the ones a plant reads off a PFEP sheet, so the
/// grouping is the Indian one (lakh/crore), not thousands - `en_IN` is a
/// deliberate choice and worth pinning.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pfep_frontend/core/theme.dart';
import 'package:pfep_frontend/ui/widgets/common.dart';

void main() {
  group('fmtNum', () {
    test('groups in the Indian convention', () {
      expect(fmtNum(1000), '1,000');
      expect(fmtNum(15600), '15,600');
      expect(fmtNum(187200), '1,87,200');       // lakh
      expect(fmtNum(27144000), '2,71,44,000');  // crore
    });

    test('drops the decimal when a value is whole', () {
      expect(fmtNum(42.0), '42');
      expect(fmtNum(600), '600');
    });

    test('keeps two decimals for genuinely fractional values', () {
      expect(fmtNum(1.333333), '1.33');
      expect(fmtNum(96.75), '96.75');
    });

    test('null and empty read as a dash, not as zero', () {
      // A blank field and a measured zero are different facts on a PFEP sheet.
      expect(fmtNum(null), '-');
      expect(fmtNum(''), '-');
      expect(fmtNum(0), '0');
    });

    test('parses numeric strings, and passes non-numeric text through', () {
      expect(fmtNum('1180'), '1,180');
      expect(fmtNum('n/a'), 'n/a');
    });
  });

  group('fmtAgo', () {
    test('describes recent moments in the collector\'s words', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(fmtAgo(now), 'just now');
      expect(fmtAgo(now - const Duration(minutes: 5).inMilliseconds), '5 min ago');
      expect(fmtAgo(now - const Duration(hours: 3).inMilliseconds), '3 hr ago');
      expect(fmtAgo(now - const Duration(days: 2).inMilliseconds), '2 d ago');
    });

    test('never is not the epoch', () {
      expect(fmtAgo(null), 'never');
    });
  });

  group('theme', () {
    // Brand tokens are read as plain statics rather than through an
    // InheritedWidget, so buildTheme has to flip them. If it stops doing that,
    // light mode silently paints dark surfaces.
    test('buildTheme flips the palette', () {
      buildTheme(light: true);
      expect(Brand.isLight, isTrue);
      final lightSurface = Brand.surface;
      final lightText = Brand.txt;

      buildTheme(light: false);
      expect(Brand.isLight, isFalse);
      expect(Brand.surface, isNot(lightSurface));
      expect(Brand.txt, isNot(lightText));
    });

    test('light mode is actually light and dark is actually dark', () {
      buildTheme(light: true);
      expect(Brand.bg.computeLuminance(), greaterThan(0.5));
      expect(Brand.txt.computeLuminance(), lessThan(0.5));

      buildTheme(light: false);
      expect(Brand.bg.computeLuminance(), lessThan(0.5));
      expect(Brand.txt.computeLuminance(), greaterThan(0.5));
    });

    test('body text keeps a readable contrast against the page in both modes', () {
      for (final light in [true, false]) {
        buildTheme(light: light);
        final delta = (Brand.txt.computeLuminance() - Brand.bg.computeLuminance()).abs();
        expect(delta, greaterThan(0.5), reason: 'text on background, light=$light');
      }
    });

    test('the brand ribbon hues do not change with the mode', () {
      buildTheme(light: true);
      final pink = Brand.pink;
      buildTheme(light: false);
      expect(Brand.pink, pink);
    });
  });
}
