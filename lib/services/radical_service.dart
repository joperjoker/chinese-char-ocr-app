import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/radical_info.dart';

/// Loads the IDS-derived left-right decomposition table and provides
/// character decomposition and radical composition lookups.
class RadicalService {
  static const _assetPath = 'assets/radicals/decomp.json';

  /// character → left/right radical info
  Map<String, RadicalInfo>? _index;

  /// "leftright" → combined character (reverse index for composition)
  Map<String, String>? _reverseIndex;

  /// All characters that appear as the LEFT component in at least one entry.
  Set<String>? _knownLefts;

  /// All characters that appear as the RIGHT component in at least one entry.
  Set<String>? _knownRights;

  /// Loads the decomposition asset into memory.
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> load() async {
    if (_index != null) return;
    loadFromString(await rootBundle.loadString(_assetPath));
  }

  /// Parses [json] (a {char: {l, r}} object) into the lookup indexes.
  /// Exposed separately from [load] so tests can inject fixture data.
  void loadFromString(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;

    final index = <String, RadicalInfo>{};
    final reverse = <String, String>{};
    final lefts = <String>{};
    final rights = <String>{};
    for (final kv in map.entries) {
      final entry = kv.value as Map<String, dynamic>;
      final l = entry['l'] as String?;
      final r = entry['r'] as String?;
      index[kv.key] = RadicalInfo(left: l, right: r);
      if (l != null && r != null) {
        reverse['$l$r'] = kv.key;
        lefts.add(l);
        rights.add(r);
      }
    }
    _index = index;
    _reverseIndex = reverse;
    _knownLefts = lefts;
    _knownRights = rights;
  }

  /// Returns the left/right decomposition of [character], or null when none exists.
  RadicalInfo? decompose(String character) => _index?[character];

  /// Returns the character formed by [left] and [right] radicals, or null.
  String? compose(String left, String right) => _reverseIndex?['$left$right'];

  /// True when [char] appears as a left-side component in any known character.
  bool isKnownLeftComponent(String char) => _knownLefts?.contains(char) ?? false;

  /// True when [char] appears as a right-side component in any known character.
  bool isKnownRightComponent(String char) => _knownRights?.contains(char) ?? false;

  bool get isLoaded => _index != null;
}
