import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Parses the flat {word: definition} object into a lookup map.
/// Top-level so [compute] can run it on a background isolate.
Map<String, String> parseChineseDefs(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  return map.map((key, value) => MapEntry(key, value as String));
}

/// Loads the simplified-Chinese definition table (built at CI time from the
/// MIT-licensed pwxcoo/chinese-xinhua dataset) and provides word → Chinese
/// definition lookups.
class ChineseDefinitionService {
  static const _assetPath = 'assets/dict/chinese_defs.json';

  /// word → Chinese-language definition
  Map<String, String>? _index;

  /// Loads the definitions asset into memory, parsing on a background
  /// isolate so the UI thread stays responsive.
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> load() async {
    if (_index != null) return;
    final raw = await rootBundle.loadString(_assetPath);
    _index = await compute(parseChineseDefs, raw);
  }

  /// Parses [json] (a flat {word: definition} object) into the lookup index.
  /// Exposed separately from [load] so tests can inject fixture data.
  void loadFromString(String json) {
    _index = parseChineseDefs(json);
  }

  /// The Chinese-language definition of [word], or null when absent.
  String? define(String word) => _index?[word];

  bool get isLoaded => _index != null;
}
