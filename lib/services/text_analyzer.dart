import 'package:lpinyin/lpinyin.dart';

import '../models/compose_result.dart';
import '../models/recognised_item.dart';
import 'chinese_definition_service.dart';
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
  /// The composition table is used as a strong prior to correct near-miss OCR
  /// errors: the first (left, right) pair that forms a real character wins, so
  /// a slightly mis-read top guess is recovered when a lower-ranked candidate
  /// composes. Falls back to the best guess from each card when no pair forms a
  /// known character.
  ComposeResult composeFromCandidates(
    List<String> leftCandidates,
    List<String> rightCandidates,
  ) {
    for (final left in leftCandidates) {
      for (final right in rightCandidates) {
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
    return composeComponents(leftCandidates.first, rightCandidates.first);
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
