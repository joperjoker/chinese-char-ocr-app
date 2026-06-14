import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recognised_item.dart';

/// A card presenting one character or word: a large character tile, tone-marked
/// pinyin, an optional left-right radical breakdown (女 ＋ 子 → 好) and bilingual
/// definitions.
///
/// Shared by the scan-results screen and the card-combination screen so the two
/// stay visually consistent.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.item,
    this.label,
    this.emphasis = false,
  });

  final RecognisedItem item;

  /// Optional small heading shown above the card (e.g. "左 · Left",
  /// "组合 · Combined"). Hidden when null.
  final String? label;

  /// When true the card is outlined to highlight it as the key answer.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final radicals = item.radicals;
    final hasRadicals = radicals?.hasDecomposition ?? false;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: emphasis
            ? const BorderSide(color: Color(0xFFB71C1C), width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB71C1C),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Big character tile ────────────────────────────────────
                Container(
                  constraints:
                      const BoxConstraints(minWidth: 64, minHeight: 64),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBEAEA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      item.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // ── Details column ────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.pinyin.isNotEmpty ? item.pinyin : '—',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE65100),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          CopyButton(text: item.text),
                        ],
                      ),

                      // Radical decomposition row, e.g.  女 ＋ 子 → 好
                      if (hasRadicals)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              RadicalChip(label: radicals!.left!),
                              const Text('＋',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.black38)),
                              RadicalChip(label: radicals.right!),
                              const Text('→',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.black38)),
                              RadicalChip(label: item.text, highlight: true),
                            ],
                          ),
                        ),

                      // English definitions (CEDICT)
                      if (item.englishDefinitions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final def
                                  in item.englishDefinitions.take(4))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '• $def',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.35,
                                      color: Color(0xFF424242),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                      // Chinese definition (xinhua)
                      if (item.chineseDefinition != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F4F2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '中文释义：${item.chineseDefinition}',
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.5,
                                color: Color(0xFF616161),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small rounded tag used in the radical-decomposition row.
class RadicalChip extends StatelessWidget {
  const RadicalChip({super.key, required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFB71C1C) : const Color(0xFFF0E7E5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: highlight ? Colors.white : const Color(0xFF5D4037),
        ),
      ),
    );
  }
}

/// Copies [text] to the clipboard and shows a brief confirmation.
class CopyButton extends StatelessWidget {
  const CopyButton({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Copy',
      icon: Icon(Icons.copy_rounded, size: 18, color: Colors.grey.shade500),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('已复制 Copied: $text'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
      },
    );
  }
}
