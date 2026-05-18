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

  /// Loads the decomposition asset into memory.
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> load() async {
    if (_index != null) return;
    final raw = await rootBundle.loadString(_assetPath);
    final map = jsonDecode(raw) as Map<String, dynamic>;

    final index = <String, RadicalInfo>{};
    final reverse = <String, String>{};
    for (final kv in map.entries) {
      final entry = kv.value as Map<String, dynamic>;
      final l = entry['l'] as String?;
      final r = entry['r'] as String?;
      index[kv.key] = RadicalInfo(left: l, right: r);
      if (l != null && r != null) {
        reverse['$l$r'] = kv.key;
      }
    }
    _index = index;
    _reverseIndex = reverse;
  }

  /// Returns the left/right decomposition of [character], or null when none exists.
  RadicalInfo? decompose(String character) => _index?[character];

  /// Returns the character formed by [left] and [right] radicals, or null.
  String? compose(String left, String right) => _reverseIndex?['$left$right'];

  bool get isLoaded => _index != null;
}
