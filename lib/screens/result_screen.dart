import 'package:flutter/material.dart';

import '../models/recognised_item.dart';
import '../widgets/item_card.dart';

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
            for (final item in words) ItemCard(item: item),
          ],
          if (characters.isNotEmpty) ...[
            const _SectionLabel('汉字 · Characters'),
            for (final item in characters) ItemCard(item: item),
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
                CopyButton(text: text),
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

// Item card, radical chip and copy button now live in widgets/item_card.dart
// and are shared with the card-combination results screen.
