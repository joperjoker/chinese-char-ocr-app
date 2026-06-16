import 'package:lpinyin/lpinyin.dart';

import '../models/compose_result.dart';
import '../models/recognised_item.dart';
import 'chinese_definition_service.dart';
import 'component_map.dart';
import 'dictionary_service.dart';
import 'radical_service.dart';

/// Combines the dictionary, radical, and Chinese-definition services to turn
/// raw OCR output into displayable [RecognisedItem]s.
class TextAnalyzer {
  TextAnalyzer({
    required this.dictionary,
    required this.radicals,
    required this.chineseDefinitions,
  });

  final DictionaryService dictionary;
  final RadicalService radicals;
  final ChineseDefinitionService chineseDefinitions;

  /// Analyses [rawText] (as returned by ML Kit) and produces one item per
  /// distinct word/character, in reading order.
  ///
  /// Non-CJK characters are stripped first; the remaining text is segmented
  /// with greedy longest-match against CEDICT so multi-character words are
  /// presented as words rather than disconnected characters.
  TextAnalysis analyse(String rawText) {
    final chineseText = dictionary.extractChinese(rawText);
    if (chineseText.isEmpty) {
      return const TextAnalysis(chineseText: '', items: []);
    }

    final seen = <String>{};
    final items = <RecognisedItem>[];
    for (final segmentText in dictionary.segment(chineseText)) {
      if (!seen.add(segmentText)) continue;
      items.add(buildItem(segmentText));
    }
    return TextAnalysis(chineseText: chineseText, items: items);
  }

  /// Combines a left-hand [left] and a right-hand [right] component into the
  /// character they form — the core "card combiner" behaviour.
  ///
  /// The returned [ComposeResult] always carries full pinyin/definition
  /// information for both components; [ComposeResult.combined] is populated
  /// only when [left] + [right] correspond to a known left-right character
  /// (e.g. 女 + 子 → 好).
  ComposeResult composeComponents(String left, String right) {
    final combinedChar = radicals.compose(left, right);
    return ComposeResult(
      left: buildItem(left),
      right: buildItem(right),
      combined: combinedChar == null ? null : buildItem(combinedChar),
    );
  }

  /// Picks the spatially leftmost and rightmost glyphs from [glyphs] — the two
  /// cards held side by side — and composes them.
  ///
  /// Returns null when fewer than two glyphs were detected, so the caller can
  /// prompt the user to aim at both cards.
  ComposeResult? composeFromGlyphs(List<PositionedGlyph> glyphs) {
    if (glyphs.length < 2) return null;
    final sorted = [...glyphs]..sort((a, b) => a.xCenter.compareTo(b.xCenter));
    return composeComponents(sorted.first.char, sorted.last.char);
  }

  /// Composes two cards from OCR candidate lists for the left and right card,
  /// each ordered best-first.
  ///
  /// Each candidate is first expanded with its component/standalone variant
  /// forms (e.g. a card read as 水 also tries 氵, since the decomposition table
  /// is keyed on the component form 氵, not the standalone 水). The composition
  /// table is then used as a strong prior to correct near-miss OCR errors: the
  /// first (left, right) pair that forms a real character wins, so a slightly
  /// mis-read top guess is recovered when a lower-ranked candidate composes.
  /// Falls back to the best guess from each card when no pair forms a known
  /// character.
  ComposeResult composeFromCandidates(
    List<String> leftCandidates,
    List<String> rightCandidates,
  ) {
    final lefts = expandWithComponentVariants(leftCandidates);
    final rights = expandWithComponentVariants(rightCandidates);
    for (final left in lefts) {
      for (final right in rights) {
        final combinedChar = radicals.compose(left, right);
        if (combinedChar != null) {
          return ComposeResult(
            left: buildItem(left),
            right: buildItem(right),
            combined: buildItem(combinedChar),
          );
        }
      }
    }
    return composeComponents(lefts.first, rights.first);
  }

  /// Composes two cards from a flat list of CJK glyphs detected across the
  /// whole frame, each tagged with its horizontal centre and bounding-box area.
  ///
  /// The glyphs are split into a left group and a right group at the widest
  /// horizontal gap between them — the physical space between the two cards —
  /// after dropping faint specks (< 10% of the largest glyph's area) so a stray
  /// mark cannot open a false gap. Each side is then ranked by area and
  /// composed. Geometry-independent: the split follows the real gap between the
  /// cards rather than any fixed pixel boundary, so the left card is always
  /// assigned to the left and the right card to the right.
  ///
  /// Returns null when fewer than two glyphs survive, so the caller can fall
  /// back to per-card cropping or prompt the user to aim at both cards.
  ComposeResult? composeByGap(List<PositionedGlyph> glyphs) {
    if (glyphs.length < 2) return null;

    final maxArea = glyphs.fold<double>(0, (m, g) => g.area > m ? g.area : m);
    // When areas are unknown (all zero), keep every glyph.
    final strong = maxArea > 0
        ? glyphs.where((g) => g.area >= 0.10 * maxArea).toList()
        : [...glyphs];
    if (strong.length < 2) return null;

    strong.sort((a, b) => a.xCenter.compareTo(b.xCenter));
    var splitIndex = 1;
    var widestGap = -1.0;
    for (var i = 1; i < strong.length; i++) {
      final gap = strong[i].xCenter - strong[i - 1].xCenter;
      if (gap > widestGap) {
        widestGap = gap;
        splitIndex = i;
      }
    }

    final left = _rankByArea(strong.sublist(0, splitIndex));
    final right = _rankByArea(strong.sublist(splitIndex));
    if (left.isEmpty || right.isEmpty) return null;
    return composeFromCandidates(left, right);
  }

  /// Ranks one side's glyphs by bounding-box area (prominent first), de-dupes,
  /// and caps the list. Variant expansion is applied later by
  /// [composeFromCandidates], so this returns the raw best-first characters.
  List<String> _rankByArea(List<PositionedGlyph> group) {
    final sorted = [...group]..sort((a, b) => b.area.compareTo(a.area));
    final seen = <String>{};
    final base = <String>[];
    for (final g in sorted) {
      if (seen.add(g.char)) base.add(g.char);
      if (base.length >= 5) break;
    }
    return base;
  }

  /// Builds a fully-populated [RecognisedItem] (pinyin, bilingual definitions,
  /// and — for single characters — radical decomposition) for [text].
  RecognisedItem buildItem(String text) {
    final entry = dictionary.lookup(text);

    // Pinyin priority: CEDICT tone-marked reading → lpinyin fallback.
    var pinyin = entry?.pinyinRead ?? '';
    if (pinyin.isEmpty) {
      pinyin = PinyinHelper.getPinyinE(
        text,
        separator: ' ',
        format: PinyinFormat.WITH_TONE_MARK,
      );
    }

    return RecognisedItem(
      text: text,
      pinyin: pinyin.trim(),
      englishDefinitions: entry?.definition ?? const [],
      chineseDefinition: chineseDefinitions.define(text),
      radicals: text.runes.length == 1 ? radicals.decompose(text) : null,
    );
  }
}
