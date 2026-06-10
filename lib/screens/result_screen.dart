import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recognised_item.dart';

/// Presents the analysis of one captured frame: the recognised text followed
/// by a card per word/character with pinyin, radical decomposition, and
/// bilingual definitions.
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.analysis,
    required this.elapsedMs,
  });

  final TextAnalysis analysis;
  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    final words = analysis.items.where((i) => i.isWord).toList();
    final characters = analysis.items.where((i) => !i.isWord).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F2),
      appBar: AppBar(
        title: const Text('识别结果 · Results'),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _RecognisedTextHeader(
            text: analysis.chineseText,
            elapsedMs: elapsedMs,
          ),
          if (words.isNotEmpty) ...[
            const _SectionLabel('词语 · Words'),
            for (final item in words) _ItemCard(item: item),
          ],
          if (characters.isNotEmpty) ...[
            const _SectionLabel('汉字 · Characters'),
            for (final item in characters) _ItemCard(item: item),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pop(),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.camera_alt),
        label: const Text('再拍 Scan again'),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Header — full recognised text + timing
// ───────────────────────────────────────────────────────────────────────────────

class _RecognisedTextHeader extends StatelessWidget {
  const _RecognisedTextHeader({required this.text, required this.elapsedMs});

  final String text;
  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    final seconds = (elapsedMs / 1000).toStringAsFixed(1);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '识别文本 Recognised text',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Icon(Icons.timer_outlined,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  '$seconds s',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontSize: 26,
                      height: 1.4,
                      color: Color(0xFF212121),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _CopyButton(text: text),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Section label
// ───────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB71C1C),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Item card — character/word + pinyin + radicals + definitions
// ───────────────────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final RecognisedItem item;

  @override
  Widget build(BuildContext context) {
    final radicals = item.radicals;
    final hasRadicals = radicals?.hasDecomposition ?? false;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Big character tile ────────────────────────────────────
            Container(
              constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
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
                      _CopyButton(text: item.text),
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
                          _RadicalChip(label: radicals!.left!),
                          const Text('＋',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black38)),
                          _RadicalChip(label: radicals.right!),
                          const Text('→',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black38)),
                          _RadicalChip(label: item.text, highlight: true),
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
                          for (final def in item.englishDefinitions.take(4))
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
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Small widgets
// ───────────────────────────────────────────────────────────────────────────────

class _RadicalChip extends StatelessWidget {
  const _RadicalChip({required this.label, this.highlight = false});

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

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});

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
