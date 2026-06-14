import 'package:flutter/material.dart';

import '../models/compose_result.dart';
import '../widgets/item_card.dart';

/// Presents the outcome of combining two cards: a big equation
/// (左 ＋ 右 ＝ 字), the combined character (when the pair forms one), and a
/// detail card for the left part, the right part and the combined character.
class ComposeResultScreen extends StatelessWidget {
  const ComposeResultScreen({
    super.key,
    required this.result,
    required this.elapsedMs,
  });

  final ComposeResult result;
  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    final combined = result.combined;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F2),
      appBar: AppBar(
        title: const Text('组合结果 · Combination'),
        backgroundColor: const Color(0xFFB71C1C),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _EquationHeader(
            left: result.left.text,
            right: result.right.text,
            combined: combined?.text,
            elapsedMs: elapsedMs,
          ),
          if (combined != null) ...[
            const _SectionLabel('组合字 · Combined character'),
            ItemCard(item: combined, emphasis: true),
          ] else
            const _NoCombinationNotice(),
          const _SectionLabel('部件 · Components'),
          ItemCard(item: result.left, label: '左 · Left'),
          ItemCard(item: result.right, label: '右 · Right'),
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

// ─────────────────────────────────────────────────────────────────────────────
// Equation header — 左 ＋ 右 ＝ 字
// ─────────────────────────────────────────────────────────────────────────────

class _EquationHeader extends StatelessWidget {
  const _EquationHeader({
    required this.left,
    required this.right,
    required this.combined,
    required this.elapsedMs,
  });

  final String left;
  final String right;
  final String? combined;
  final int elapsedMs;

  @override
  Widget build(BuildContext context) {
    final seconds = (elapsedMs / 1000).toStringAsFixed(1);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '左 + 右 = 字',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  '$seconds s',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Glyph(left),
                const _Operator('＋'),
                _Glyph(right),
                const _Operator('＝'),
                _Glyph(combined ?? '？', highlight: combined != null),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.char, {this.highlight = false});

  final String char;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFB71C1C) : const Color(0xFFFBEAEA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        char,
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w600,
          color: highlight ? Colors.white : const Color(0xFFB71C1C),
        ),
      ),
    );
  }
}

class _Operator extends StatelessWidget {
  const _Operator(this.symbol);

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        symbol,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9E9E9E),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notice shown when the two parts do not form a known character
// ─────────────────────────────────────────────────────────────────────────────

class _NoCombinationNotice extends StatelessWidget {
  const _NoCombinationNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFE65100), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '这两个部件无法组成已知的左右结构汉字。\n'
              'These two parts do not form a character I recognise. '
              'Check the cards are the left and right halves and try again.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Colors.brown.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

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
