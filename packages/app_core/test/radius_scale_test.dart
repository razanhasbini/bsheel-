import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards `QuestSpacing.radiusScale` against drift.
///
/// `CLAUDE.md` promises that a reskin only touches the three files in
/// `packages/app_core/lib/theme/`. Radius literals scattered through the
/// widgets break that promise silently — there is nothing to fail when
/// someone types `BorderRadius.circular(21)`, so 79 of them accumulated.
///
/// This test is the thing that fails. It reads the Dart source of every
/// package that consumes the theme and rejects a radius literal that is not
/// a step the design uses, or (with a shrinking allowlist) a literal at all.
///
/// It scans source text rather than the widget tree on purpose: a golden
/// test only covers the screens it renders, and the drift showed up on
/// screens nobody had a test for.
void main() {
  /// Package `lib/` trees that consume `QuestSpacing`, relative to
  /// `packages/app_core` — the directory `flutter test` runs in.
  const roots = <String>[
    'lib',
    '../shared_ui/lib',
    '../../apps/mobile_app/lib',
  ];

  /// How many radius literals still hold an *on-scale* value as a number
  /// instead of the token that names it.
  ///
  /// These render correctly today — they are all steps the design uses — but
  /// each is a place a reskin would have to visit, so `CLAUDE.md`'s promise
  /// that the theme files are the only ones to edit is not yet literally
  /// true. Migrating them changes no pixels; it just was not the job that
  /// found them.
  ///
  /// So this is a ratchet, not a target: the count may fall, never rise.
  /// Tokenise a few, drop the number, and it can never come back.
  /// Lowered from 158 when `feed_page.dart`'s four remaining literals were
  /// tokenised — the merge of PR #52 pushed the count to 159 and the ratchet
  /// caught it, which is what it is for.
  const onScaleLiteralBudget = 155;

  /// `BorderRadius.circular(11)`, `Radius.circular(11.0)`, and the same
  /// inside `BorderRadius.all/only/vertical/horizontal`. A non-literal
  /// argument — an identifier, a token, arithmetic — is not matched, so
  /// `inner(radiusMeterTrack, 3)` and the arc radii in `_RaysPainter` are
  /// left alone.
  final literalRadius = RegExp(
    r'(?:BorderRadius|Radius)\.circular\(\s*(\d+(?:\.\d+)?)\s*\)',
  );

  /// Every `.dart` file under [roots], as (relative path, source) pairs.
  List<({String path, String source})> sources() {
    final out = <({String path, String source})>[];
    for (final root in roots) {
      final dir = Directory(root);
      expect(
        dir.existsSync(),
        isTrue,
        reason:
            'Scan root "$root" is missing. Either the monorepo layout moved '
            'and this list needs updating, or this test is running from '
            '${Directory.current.path} instead of packages/app_core — '
            'either way it is no longer guarding anything.',
      );
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        out.add((
          path: f.path.replaceFirst('$root/', ''),
          source: f.readAsStringSync(),
        ));
      }
    }
    return out;
  }

  test('every radius literal is a step on the scale', () {
    final offScale = <String>[];
    var literals = 0;

    for (final file in sources()) {
      final lines = file.source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final m in literalRadius.allMatches(lines[i])) {
          literals++;
          final value = double.parse(m.group(1)!);
          if (!QuestSpacing.radiusScale.contains(value)) {
            offScale.add('${file.path}:${i + 1}  circular($value)');
          }
        }
      }
    }

    // A regex that stops matching would otherwise make this test pass by
    // finding nothing at all.
    expect(
      literals,
      greaterThan(20),
      reason: 'Found only $literals radius literals across $roots, which '
          'means the pattern has stopped matching rather than that the '
          'codebase got tidy. Fix the pattern.',
    );

    expect(
      offScale,
      isEmpty,
      reason: 'These radii are not steps the design uses:\n'
          '  ${offScale.join('\n  ')}\n\n'
          'The scale is ${(QuestSpacing.radiusScale.toList()..sort())}, in '
          'packages/app_core/lib/theme/quest_spacing.dart. Pick the token '
          'whose role matches. If the design really does use a new step, '
          'add it there as a named token and say where it came from — do '
          'not snap a measured value onto a neighbour, and do not add the '
          'literal here.',
    );
  });

  test('un-tokenised on-scale literals only ever decrease', () {
    final untokenised = <String>[];

    for (final file in sources()) {
      final lines = file.source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final m in literalRadius.allMatches(lines[i])) {
          untokenised.add('${file.path}:${i + 1}  circular(${m.group(1)})');
        }
      }
    }

    expect(
      untokenised.length,
      lessThanOrEqualTo(onScaleLiteralBudget),
      reason: 'Radius literals went from $onScaleLiteralBudget to '
          '${untokenised.length}. Use the QuestSpacing token that names the '
          'value instead of writing the number:\n  '
          '${untokenised.join('\n  ')}',
    );

    // Once the last one is gone, delete the budget and assert `isEmpty`
    // instead — a ratchet that has reached zero should say so.
    if (untokenised.length < onScaleLiteralBudget) {
      fail(
        'Good news, and an edit to make: only ${untokenised.length} radius '
        'literals are left, but onScaleLiteralBudget in this file still '
        'says $onScaleLiteralBudget. Lower it to ${untokenised.length} so '
        'the ones you fixed cannot come back.',
      );
    }
  });

  test('the scale is exactly the named tokens', () {
    // Stops a value being slipped into `radiusScale` without a token to
    // name it, which would re-open the door this test is closing.
    expect(QuestSpacing.radiusScale, {
      QuestSpacing.radiusPip,
      QuestSpacing.radiusSegment,
      QuestSpacing.radiusDot,
      QuestSpacing.radiusBadge,
      QuestSpacing.radiusMeterTrack,
      QuestSpacing.radiusChip,
      QuestSpacing.radiusGlyph,
      QuestSpacing.radiusSm,
      QuestSpacing.radiusButton,
      QuestSpacing.radiusControl,
      QuestSpacing.radiusPanel,
      QuestSpacing.radiusMd,
      QuestSpacing.radiusOption,
      QuestSpacing.radiusCard,
      QuestSpacing.radiusLg,
      QuestSpacing.radiusXl,
      QuestSpacing.radiusTile,
      QuestSpacing.radiusSheet,
      QuestSpacing.radiusFull,
    });
    // radiusHero aliases radiusLg (18), so the set is one short of the
    // token count.
    expect(QuestSpacing.radiusScale, hasLength(19));
    expect(QuestSpacing.radiusHero, QuestSpacing.radiusLg);
  });

  group('inner()', () {
    test('takes the inset off the outer radius', () {
      expect(QuestSpacing.inner(QuestSpacing.radiusMeterTrack, 3), 4);
      expect(QuestSpacing.inner(QuestSpacing.radiusChip, 4), 4);
      expect(
        QuestSpacing.inner(QuestSpacing.radiusXl, QuestSpacing.cardBorderWidth),
        20,
      );
    });

    test('clamps at zero rather than going negative', () {
      expect(QuestSpacing.inner(QuestSpacing.radiusPip, 8), 0);
      expect(QuestSpacing.inner(0, 0), 0);
    });
  });
}
