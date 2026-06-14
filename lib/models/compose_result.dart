import 'recognised_item.dart';

/// A single CJK glyph paired with the horizontal centre of its bounding box.
///
/// Used to decide, from a photo of two side-by-side cards, which captured
/// component is the left half and which is the right half of a character.
class PositionedGlyph {
  /// The single CJK character.
  final String char;

  /// Horizontal centre of the glyph in image pixels — larger is further right.
  final double xCenter;

  const PositionedGlyph({required this.char, required this.xCenter});
}

/// The outcome of combining a left-hand and a right-hand component captured
/// from two side-by-side cards.
///
/// Carries full pinyin/definition information for the left part, the right
/// part, and — when the pair forms a known character — the combined character.
class ComposeResult {
  /// The left-hand component (e.g. 女).
  final RecognisedItem left;

  /// The right-hand component (e.g. 子).
  final RecognisedItem right;

  /// The character the two halves form (e.g. 好), or null when the pair does
  /// not correspond to a known left-right character.
  final RecognisedItem? combined;

  const ComposeResult({
    required this.left,
    required this.right,
    this.combined,
  });

  /// True when [left] + [right] form a recognised character.
  bool get isValid => combined != null;
}
