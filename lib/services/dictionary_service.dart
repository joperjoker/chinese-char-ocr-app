import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/dict_entry.dart';

/// Outcome of [DictionaryService.analyseText].
class AnalysisResult {
  /// Whether the input was confirmed as a Simplified Chinese entry in CEDICT.
  final bool isValid;

  /// Tone-marked Hanyu Pinyin from the dictionary (e.g. "nǐ hǎo").
  /// Non-null only when [isValid] is true.
  final String? pinyin;

  /// Numeric-tone Pinyin from the dictionary (e.g. "ni3 hao3").
  /// Non-null only when [isValid] is true.
  final String? pinyinNumeric;

  /// English definitions from the dictionary entry.
  /// Non-null only when [isValid] is true.
  final List<String>? definitions;

  const AnalysisResult._({
    required this.isValid,
    this.pinyin,
    this.pinyinNumeric,
    this.definitions,
  });

  /// The text was not found in the dictionary or contained no CJK codepoints.
  const AnalysisResult.invalid()
      : isValid = false,
        pinyin = null,
        pinyinNumeric = null,
        definitions = null;

  /// The text was matched to [entry] in the local CEDICT dictionary.
  factory AnalysisResult.valid(DictEntry entry) => AnalysisResult._(
        isValid: true,
        pinyin: entry.pinyinRead.isNotEmpty ? entry.pinyinRead : null,
        pinyinNumeric: entry.pinyinType.isNotEmpty ? entry.pinyinType : null,
        definitions: entry.definition.isNotEmpty ? entry.definition : null,
      );

  @override
  String toString() => isValid
      ? 'AnalysisResult.valid(pinyin: $pinyin)'
      : 'AnalysisResult.invalid()';
}

/// Service that loads the local CEDICT-derived JSON dictionary and provides
/// Simplified Chinese character verification with Hanyu Pinyin lookup.
class DictionaryService {
  static const _assetPath = 'assets/dict/cedictJSON.json';

  // Unicode ranges that cover CJK ideographs used in Simplified Chinese.
  // Each record is an inclusive (start, end) pair of Unicode code points.
  static const _cjkRanges = [
    (0x3400, 0x4DBF), // CJK Extension A
    (0x4E00, 0x9FFF), // CJK Unified Ideographs (core block)
    (0xF900, 0xFAFF), // CJK Compatibility Ideographs
  ];

  /// Lazily-populated index: simplified text → dictionary entry.
  Map<String, DictEntry>? _index;

  /// Longest dictionary word considered during [segment]. CEDICT words are
  /// rarely longer than four characters; bounding the search keeps
  /// segmentation linear.
  static const _maxWordLength = 4;

  /// Loads the CEDICT JSON asset into memory.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> load() async {
    if (_index != null) return;
    loadFromString(await rootBundle.loadString(_assetPath));
  }

  /// Parses [json] (the CEDICT entry array) into the lookup index.
  /// Exposed separately from [load] so tests can inject fixture data.
  void loadFromString(String json) {
    final list =
        (jsonDecode(json) as List<dynamic>).cast<Map<String, dynamic>>();
    _index = {
      for (final entry in list.map(DictEntry.fromJson)) entry.simplified: entry,
    };
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Analyses OCR-detected [text] and cross-references it against the local
  /// CEDICT dictionary to verify it as a real Simplified Chinese character
  /// or word.
  ///
  /// Returns [AnalysisResult.valid] — with the tone-marked Hanyu Pinyin set —
  /// when the text is found in the dictionary.
  ///
  /// Returns [AnalysisResult.invalid] when:
  /// - [text] is empty or contains no CJK codepoints, or
  /// - [text] is not present in the dictionary.
  ///
  /// Throws [StateError] if called before [load] completes.
  AnalysisResult analyseText(String text) {
    _assertLoaded();
    final candidate = text.trim();
    if (candidate.isEmpty || !containsChineseCharacter(candidate)) {
      return const AnalysisResult.invalid();
    }
    final entry = _index![candidate];
    return entry != null
        ? AnalysisResult.valid(entry)
        : const AnalysisResult.invalid();
  }

  /// Returns true if [text] contains at least one CJK ideograph codepoint
  /// in the ranges used by Simplified Chinese.
  bool containsChineseCharacter(String text) =>
      text.runes.any(_isCjkCodePoint);

  /// Returns only the CJK ideograph characters of [text], in original order.
  /// Latin letters, digits, punctuation, and whitespace are dropped.
  String extractChinese(String text) => String.fromCharCodes(
        text.runes.where(_isCjkCodePoint),
      );

  /// Greedy longest-match segmentation of [text] against the dictionary.
  ///
  /// Starting at each position, the longest dictionary word (up to
  /// [_maxWordLength] characters) is taken; when no multi-character word
  /// matches, the single character is emitted on its own. The concatenation
  /// of the returned segments always equals [text].
  List<String> segment(String text) {
    _assertLoaded();
    final runes = text.runes.toList();
    final segments = <String>[];
    var i = 0;
    while (i < runes.length) {
      var matched = false;
      final maxLen =
          runes.length - i < _maxWordLength ? runes.length - i : _maxWordLength;
      for (var len = maxLen; len >= 2; len--) {
        final candidate = String.fromCharCodes(runes.sublist(i, i + len));
        if (_index!.containsKey(candidate)) {
          segments.add(candidate);
          i += len;
          matched = true;
          break;
        }
      }
      if (!matched) {
        segments.add(String.fromCharCode(runes[i]));
        i += 1;
      }
    }
    return segments;
  }

  /// Direct entry lookup — returns null when [simplified] is absent.
  ///
  /// Prefer [analyseText] for validated lookups; use this only when you need
  /// the raw [DictEntry].
  DictEntry? lookup(String simplified) {
    _assertLoaded();
    return _index![simplified];
  }

  /// Whether the dictionary has been loaded into memory.
  bool get isLoaded => _index != null;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _isCjkCodePoint(int cp) =>
      _cjkRanges.any((r) => cp >= r.$1 && cp <= r.$2);

  void _assertLoaded() {
    if (_index == null) {
      throw StateError('DictionaryService: call load() before using the service.');
    }
  }
}
