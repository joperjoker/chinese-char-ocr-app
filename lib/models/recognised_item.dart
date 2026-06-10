import 'radical_info.dart';

/// A single analysed unit of recognised text — either one Chinese character
/// or a multi-character dictionary word.
class RecognisedItem {
  /// The simplified Chinese character or word.
  final String text;

  /// Tone-marked Hanyu Pinyin (e.g. "nǐ hǎo"). Empty when unavailable.
  final String pinyin;

  /// English definitions from CEDICT. Empty when the text is not in CEDICT.
  final List<String> englishDefinitions;

  /// Chinese-language definition from the xinhua dataset, or null.
  final String? chineseDefinition;

  /// Left/right radical decomposition — single characters only.
  final RadicalInfo? radicals;

  const RecognisedItem({
    required this.text,
    required this.pinyin,
    this.englishDefinitions = const [],
    this.chineseDefinition,
    this.radicals,
  });

  /// True when this item is a multi-character word.
  bool get isWord => text.runes.length > 1;
}

/// The full analysis of one recognised frame.
class TextAnalysis {
  /// The recognised text reduced to its CJK characters, in reading order.
  final String chineseText;

  /// Words and characters found in [chineseText], in reading order,
  /// de-duplicated.
  final List<RecognisedItem> items;

  const TextAnalysis({required this.chineseText, required this.items});

  bool get isEmpty => chineseText.isEmpty;
}
