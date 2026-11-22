import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/core/theme/dark_mode.dart';
import 'package:smart_scrolling/core/theme/light_mode.dart';
import 'package:smart_scrolling/core/theme/theme_extensions.dart';

double contrast(Color a, Color b) {
  final hi = a.computeLuminance(), lo = b.computeLuminance();
  return (hi > lo ? hi + 0.05 : lo + 0.05) / (hi > lo ? lo + 0.05 : hi + 0.05);
}

void main() {
  for (final (name, brightness) in [
    ('light', Brightness.light),
    ('dark', Brightness.dark),
  ]) {
    for (final highContrast in [false, true]) {
      test(
        '$name mode text pairs reach 4.5:1 (high contrast: $highContrast)',
        () {
          final c = AppColors.generate(brightness, highContrast: highContrast);
          final pairs = {
            'text on background': contrast(c.text, c.background),
            'text on card': contrast(c.text, c.card),
            'text on cardMuted': contrast(c.text, c.cardMuted),
            'onPrimary on primary': contrast(c.onPrimary, c.primary),
          };
          pairs.forEach(
            (pair, ratio) =>
                expect(ratio, greaterThanOrEqualTo(4.5), reason: pair),
          );
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    test(
      '${brightness.name} mode use colors are readable as text on the card',
      () {
        final c = AppColors.generate(brightness);
        final uses = {
          'like': c.like,
          'later': c.later,
          'correct': c.correct,
          'wrong': c.wrong,
          'due': c.due,
          'concept': c.concept,
          'quote': c.quote,
          'news': c.news,
          'research': c.research,
          'myth': c.myth,
          'image': c.image,
          'video': c.video,
          'audio': c.audio,
        };
        uses.forEach(
          (name, color) => expect(
            contrast(color, c.card),
            greaterThanOrEqualTo(4.5),
            reason: name,
          ),
        );
      },
    );
  }

  test('both themes carry the colors', () {
    expect(lightMode().extension<AppColors>(), isNotNull);
    expect(darkMode().extension<AppColors>(), isNotNull);
  });

  test('Idea is the Concept format and unknown formats use the main color', () {
    final c = AppColors.generate(Brightness.light);
    expect(c.format('Idea'), c.concept);
    expect(c.format('Nope'), c.primary);
  });
}
