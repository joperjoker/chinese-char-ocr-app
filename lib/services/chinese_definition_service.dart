import 'dart:convert';
import 'package:flutter/services.dart';

/// Loads the simplified-Chinese definition table (built at CI time from the
/// MIT-licensed pwxcoo/chinese-xinhua dataset) and provides word → Chinese
/// definition lookups.
class ChineseDefinitionService {
  static const _assetPath = 'assets/dict/chinese_defs.json';

  /// word → Chinese-language definition
  Map<String, String>? _index;

  /// Loads the definitions asset into memory.
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> load() async {
    if (_index != null) return;
    loadFromString(await rootBundle.loadString(_assetPath));
  }

  /// Parses [json] (a flat {word: definition} object) into the lookup index.
  /// Exposed separately from [load] so tests can inject fixture data.
  void loadFromString(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    _index = map.map((key, value) => MapEntry(key, value as String));
  }

  /// The Chinese-language definition of [word], or null when absent.
  String? define(String word) => _index?[word];

  bool get isLoaded => _index != null;
}
