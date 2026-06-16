import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_char_ocr_app/models/compose_result.dart';
import 'package:chinese_char_ocr_app/services/chinese_definition_service.dart';
import 'package:chinese_char_ocr_app/services/component_map.dart';
import 'package:chinese_char_ocr_app/services/dictionary_service.dart';
import 'package:chinese_char_ocr_app/services/radical_service.dart';
import 'package:chinese_char_ocr_app/services/text_analyzer.dart';

const _cedictFixture = '''
[
  {"traditional":"好","simplified":"好","pinyinRead":"hǎo","pinyinType":"hao3","definition":["good","well"]},
  {"traditional":"我們","simplified":"我们","pinyinRead":"wǒ men","pinyinType":"wo3 men5","definition":["we","us"]},
  {"traditional":"中國","simplified":"中国","pinyinRead":"zhōng guó","pinyinType":"zhong1 guo2","definition":["China"]},
  {"traditional":"水","simplified":"水","pinyinRead":"shuǐ","pinyinType":"shui3","definition":["water"]}
]
''';

// 江 = ⿰氵工 exercises the component-form case: the decomposition table is
// keyed on the radical form 氵, not the standalone 水, mirroring the real IDS data.
const _radicalFixture =
    '{"好":{"l":"女","r":"子"},"明":{"l":"日","r":"月"},"江":{"l":"氵","r":"工"}}';

const _chineseDefsFixture = '{"好":"优点多的；使人满意的。","我们":"代词。称包括自己在内的若干人。"}';

void main() {
  group('DictionaryService', () {
    late DictionaryService dict;

    setUp(() {
      dict = DictionaryService()..loadFromString(_cedictFixture);
    });

    test('analyseText returns valid result with pinyin for known entry', () {
      final result = dict.analyseText('好');
      expect(result.isValid, isTrue);
      expect(result.pinyin, 'hǎo');
      expect(result.definitions, contains('good'));
    });

    test('analyseText rejects non-Chinese and unknown text', () {
      expect(dict.analyseText('hello').isValid, isFalse);
      expect(dict.analyseText('').isValid, isFalse);
      expect(dict.analyseText('龘').isValid, isFalse); // CJK but not in fixture
    });

    test('extractChinese strips non-CJK characters', () {
      expect(dict.extractChinese('Hello, 我们 are 好!'), '我们好');
      expect(dict.extractChinese('no chinese'), isEmpty);
    });

    test('segment prefers longest dictionary words', () {
      expect(dict.segment('我们好'), ['我们', '好']);
      expect(dict.segment('中国我们'), ['中国', '我们']);
    });

    test('segment falls back to single characters for unknown text', () {
      expect(dict.segment('龘好'), ['龘', '好']);
    });

    test('lookup returns the raw entry or null', () {
      expect(dict.lookup('中国')?.pinyinRead, 'zhōng guó');
      expect(dict.lookup('不存在'), isNull);
    });
  });

  group('RadicalService', () {
    late RadicalService radicals;

    setUp(() {
      radicals = RadicalService()..loadFromString(_radicalFixture);
    });

    test('decompose returns left and right components', () {
      final info = radicals.decompose('好');
      expect(info?.left, '女');
      expect(info?.right, '子');
      expect(info?.hasDecomposition, isTrue);
    });

    test('decompose returns null for unknown characters', () {
      expect(radicals.decompose('一'), isNull);
    });

    test('compose finds the character formed by two radicals', () {
      expect(radicals.compose('女', '子'), '好');
      expect(radicals.compose('日', '月'), '明');
      expect(radicals.compose('日', '日'), isNull);
    });

    test('isKnownLeftComponent identifies left components', () {
      expect(radicals.isKnownLeftComponent('女'), isTrue);
      expect(radicals.isKnownLeftComponent('日'), isTrue);
      // 子 and 月 are right components in the fixture
      expect(radicals.isKnownLeftComponent('子'), isFalse);
    });

    test('isKnownRightComponent identifies right components', () {
      expect(radicals.isKnownRightComponent('子'), isTrue);
      expect(radicals.isKnownRightComponent('月'), isTrue);
      // 女 is only a left component in the fixture
      expect(radicals.isKnownRightComponent('女'), isFalse);
    });

    test('left and right queries are independent — not mutually exclusive', () {
      // A character can legitimately appear on BOTH sides in a real dataset
      // (e.g. 日 in 晴/明 or 月 in 明/朋). The two methods must be independent.
      // In the fixture 日=left, 月=right; we verify neither blocks the other.
      expect(radicals.isKnownLeftComponent('日'), isTrue);
      expect(radicals.isKnownRightComponent('日'), isFalse); // not in fixture as right
      expect(radicals.isKnownRightComponent('月'), isTrue);
      expect(radicals.isKnownLeftComponent('月'), isFalse); // not in fixture as left
    });
  });

  group('ComponentMap', () {
    test('expandWithComponentVariants adds standalone↔component variants', () {
      // 水 (standalone water) → should also include 氵 (left component form)
      expect(expandWithComponentVariants(['水']), containsAll(['水', '氵']));
      // 氵 (component) → should also include 水 and 冫
      expect(expandWithComponentVariants(['氵']), containsAll(['氵', '水', '冫']));
    });

    test('preserves original rank order — OCR best guess stays first', () {
      final result = expandWithComponentVariants(['心', '日']);
      expect(result.first, '心');
      expect(result[1], '忄'); // variant inserted right after its origin
      expect(result[2], '日');
    });

    test('deduplicates when two candidates share a variant', () {
      // Both 水 and 氵 expand into each other; no duplicates should appear.
      final result = expandWithComponentVariants(['水', '氵']);
      final unique = result.toSet().toList();
      expect(result.length, unique.length);
    });

    test('characters with no variants are returned unchanged', () {
      expect(expandWithComponentVariants(['好', '明']), ['好', '明']);
    });
  });

  group('ChineseDefinitionService', () {
    test('define returns the Chinese definition or null', () {
      final defs = ChineseDefinitionService()
        ..loadFromString(_chineseDefsFixture);
      expect(defs.define('好'), contains('优点多'));
      expect(defs.define('我们'), contains('代词'));
      expect(defs.define('不存在'), isNull);
    });
  });

  group('TextAnalyzer', () {
    late TextAnalyzer analyzer;

    setUp(() {
      analyzer = TextAnalyzer(
        dictionary: DictionaryService()..loadFromString(_cedictFixture),
        radicals: RadicalService()..loadFromString(_radicalFixture),
        chineseDefinitions: ChineseDefinitionService()
          ..loadFromString(_chineseDefsFixture),
      );
    });

    test('produces word and character items in reading order', () {
      final analysis = analyzer.analyse('Hi 我们好!');
      expect(analysis.chineseText, '我们好');
      expect(analysis.items.map((i) => i.text), ['我们', '好']);
      expect(analysis.items[0].isWord, isTrue);
      expect(analysis.items[1].isWord, isFalse);
    });

    test('items carry pinyin, definitions, and radicals', () {
      final analysis = analyzer.analyse('好');
      final item = analysis.items.single;
      expect(item.pinyin, 'hǎo');
      expect(item.englishDefinitions, contains('good'));
      expect(item.chineseDefinition, contains('优点多'));
      expect(item.radicals?.left, '女');
      expect(item.radicals?.right, '子');
    });

    test('de-duplicates repeated segments', () {
      final analysis = analyzer.analyse('好好好');
      expect(analysis.items.length, 1);
    });

    test('returns empty analysis when no Chinese is present', () {
      final analysis = analyzer.analyse('only english 123');
      expect(analysis.isEmpty, isTrue);
      expect(analysis.items, isEmpty);
    });

    test('falls back to lpinyin for characters outside CEDICT', () {
      final analysis = analyzer.analyse('明');
      final item = analysis.items.single;
      expect(item.pinyin, isNotEmpty); // lpinyin fallback: míng
      expect(item.englishDefinitions, isEmpty);
      expect(item.radicals?.left, '日');
    });

    test('attaches the full-character version of a radical side form', () {
      // 氵 is the reduced form of 水; buildItem must surface 水 with its reading
      // and meaning so a learner can tell what the side "is".
      final item = analyzer.buildItem('氵');
      expect(item.hasFullForm, isTrue);
      expect(item.fullForm?.text, '水');
      expect(item.fullForm?.pinyin, 'shuǐ');
      expect(item.fullForm?.englishDefinitions, contains('water'));
      // The full character is itself a leaf — no further nesting.
      expect(item.fullForm?.fullForm, isNull);
    });

    test('a side that is already a full character has no full-form', () {
      expect(analyzer.buildItem('女').hasFullForm, isFalse);
      expect(analyzer.buildItem('工').hasFullForm, isFalse);
    });
  });

  group('TextAnalyzer card combination', () {
    late TextAnalyzer analyzer;

    setUp(() {
      analyzer = TextAnalyzer(
        dictionary: DictionaryService()..loadFromString(_cedictFixture),
        radicals: RadicalService()..loadFromString(_radicalFixture),
        chineseDefinitions: ChineseDefinitionService()
          ..loadFromString(_chineseDefsFixture),
      );
    });

    test('composeComponents combines left + right into the character', () {
      final result = analyzer.composeComponents('女', '子');
      expect(result.isValid, isTrue);
      expect(result.left.text, '女');
      expect(result.right.text, '子');
      expect(result.combined?.text, '好');
      expect(result.combined?.pinyin, 'hǎo');
      expect(result.combined?.englishDefinitions, contains('good'));
    });

    test('composeComponents reports no combined char for unknown pairs', () {
      final result = analyzer.composeComponents('女', '女');
      expect(result.isValid, isFalse);
      expect(result.combined, isNull);
      // Components are still populated so their meanings can be shown.
      expect(result.left.text, '女');
      expect(result.right.text, '女');
    });

    test('composeFromGlyphs orders parts by x position, not reading order', () {
      // 子 captured on the right (larger x), 女 on the left (smaller x):
      // the spatial order must yield 女 + 子 → 好.
      final result = analyzer.composeFromGlyphs(const [
        PositionedGlyph(char: '子', xCenter: 480),
        PositionedGlyph(char: '女', xCenter: 60),
      ]);
      expect(result, isNotNull);
      expect(result!.left.text, '女');
      expect(result.right.text, '子');
      expect(result.combined?.text, '好');
    });

    test('composeFromGlyphs needs at least two glyphs', () {
      expect(analyzer.composeFromGlyphs(const []), isNull);
      expect(
        analyzer.composeFromGlyphs(
          const [PositionedGlyph(char: '女', xCenter: 0)],
        ),
        isNull,
      );
    });

    test('composeFromCandidates uses the best top guesses when they compose',
        () {
      final result = analyzer.composeFromCandidates(['女', '安'], ['子', '好']);
      expect(result.left.text, '女');
      expect(result.right.text, '子');
      expect(result.combined?.text, '好');
    });

    test('composeFromCandidates recovers when the top OCR guess is wrong', () {
      // Left card's best guess (孑) is a near-miss; 女 is a lower candidate.
      // Only 女 + 子 forms a known character, so it must be selected.
      final result = analyzer.composeFromCandidates(['孑', '女'], ['子']);
      expect(result.left.text, '女');
      expect(result.right.text, '子');
      expect(result.combined?.text, '好');
    });

    test('composeFromCandidates falls back to top guesses when none compose',
        () {
      final result = analyzer.composeFromCandidates(['女'], ['女']);
      expect(result.isValid, isFalse);
      expect(result.left.text, '女');
      expect(result.right.text, '女');
    });

    test('composeFromCandidates expands a standalone read to its component',
        () {
      // The card shows 氵 but OCR read the standalone 水; the table is keyed on
      // 氵, so expansion must recover 氵 + 工 → 江.
      final result = analyzer.composeFromCandidates(['水'], ['工']);
      expect(result.combined?.text, '江');
      expect(result.left.text, '氵'); // the matching component form is surfaced
      expect(result.right.text, '工');
    });

    test('a recovered side carries both its component and full-character form',
        () {
      // The left side is the component 氵; the result must also offer its full
      // character 水 (shuǐ, water) so both versions are shown.
      final result = analyzer.composeFromCandidates(['水'], ['工']);
      expect(result.left.text, '氵');
      expect(result.left.fullForm?.text, '水');
      expect(result.left.fullForm?.englishDefinitions, contains('water'));
      // 工 is already a full character, so it has no separate full form.
      expect(result.right.hasFullForm, isFalse);
    });
  });

  group('TextAnalyzer.composeByGap', () {
    late TextAnalyzer analyzer;

    setUp(() {
      analyzer = TextAnalyzer(
        dictionary: DictionaryService()..loadFromString(_cedictFixture),
        radicals: RadicalService()..loadFromString(_radicalFixture),
        chineseDefinitions: ChineseDefinitionService()
          ..loadFromString(_chineseDefsFixture),
      );
    });

    test('splits two glyphs at the gap and assigns sides by x position', () {
      // 子 captured on the right (larger x), 女 on the left — spatial order,
      // not list order, must yield 女 + 子 → 好.
      final result = analyzer.composeByGap(const [
        PositionedGlyph(char: '子', xCenter: 480, area: 1000),
        PositionedGlyph(char: '女', xCenter: 60, area: 1000),
      ]);
      expect(result, isNotNull);
      expect(result!.left.text, '女');
      expect(result.right.text, '子');
      expect(result.combined?.text, '好');
    });

    test('drops a faint speck so it cannot corrupt the left/right split', () {
      // A tiny stray mark sits far to the right of both cards. Were it kept,
      // the widest gap would fall between 子 and the speck, grouping 女+子 on
      // the left and leaving the speck alone on the right — a wrong split.
      // Filtering specks (< 10% of the max area) restores 女 | 子 → 好.
      final result = analyzer.composeByGap(const [
        PositionedGlyph(char: '女', xCenter: 300, area: 1000),
        PositionedGlyph(char: '子', xCenter: 700, area: 1000),
        PositionedGlyph(char: '一', xCenter: 1300, area: 5), // speck
      ]);
      expect(result, isNotNull);
      expect(result!.left.text, '女');
      expect(result.right.text, '子');
      expect(result.combined?.text, '好');
    });

    test('ranks the prominent glyph above a same-side stray mark', () {
      // A stray mark shares the left card's side (close to 女, so it stays in
      // the left group rather than opening the widest gap) but is large enough
      // to survive speck filtering. Area ranking must still put the real
      // component 女 first so 女 + 子 → 好.
      final result = analyzer.composeByGap(const [
        PositionedGlyph(char: '一', xCenter: 40, area: 200), // left side, smaller
        PositionedGlyph(char: '女', xCenter: 120, area: 1000),
        PositionedGlyph(char: '子', xCenter: 700, area: 1000),
      ]);
      expect(result, isNotNull);
      expect(result!.left.text, '女');
      expect(result.right.text, '子');
      expect(result.combined?.text, '好');
    });

    test('recovers a component form when a card was read as its standalone',
        () {
      // Whole-frame OCR read the left card (氵) as the standalone 水. The gap
      // split assigns it left, expansion recovers 氵, and 氵 + 工 → 江.
      final result = analyzer.composeByGap(const [
        PositionedGlyph(char: '水', xCenter: 100, area: 1000),
        PositionedGlyph(char: '工', xCenter: 600, area: 1000),
      ]);
      expect(result, isNotNull);
      expect(result!.combined?.text, '江');
      expect(result.left.text, '氵');
      expect(result.right.text, '工');
    });

    test('returns null when fewer than two glyphs are present', () {
      expect(analyzer.composeByGap(const []), isNull);
      expect(
        analyzer.composeByGap(
          const [PositionedGlyph(char: '女', xCenter: 0, area: 1000)],
        ),
        isNull,
      );
    });

    test('keeps every glyph when areas are unknown (all zero)', () {
      // Defensive: if bounding-box areas are unavailable, no speck filtering is
      // applied, but the gap split still assigns sides correctly.
      final result = analyzer.composeByGap(const [
        PositionedGlyph(char: '女', xCenter: 0),
        PositionedGlyph(char: '子', xCenter: 500),
      ]);
      expect(result, isNotNull);
      expect(result!.combined?.text, '好');
    });
  });
}
