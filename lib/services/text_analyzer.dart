import 'package:lpinyin/lpinyin.dart';

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
      items.add(_buildItem(segmentText));
    }
    return TextAnalysis(chineseText: chineseText, items: items);
  }

  RecognisedItem _buildItem(String text) {
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
