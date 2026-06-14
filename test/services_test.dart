import 'package:flutter_test/flutter_test.dart';

import 'package:chinese_char_ocr_app/models/compose_result.dart';
import 'package:chinese_char_ocr_app/services/chinese_definition_service.dart';
import 'package:chinese_char_ocr_app/services/dictionary_service.dart';
import 'package:chinese_char_ocr_app/services/radical_service.dart';
import 'package:chinese_char_ocr_app/services/text_analyzer.dart';

const _cedictFixture = '''
[
  {"traditional":"好","simplified":"好","pinyinRead":"hǎo","pinyinType":"hao3","definition":["good","well"]},
  {"traditional":"我們","simplified":"我们","pinyinRead":"wǒ men","pinyinType":"wo3 men5","definition":["we","us"]},
  {"traditional":"中國","simplified":"中国","pinyinRead":"zhōng guó","pinyinType":"zhong1 guo2","definition":["China"]}
]
''';

const _radicalFixture = '{"好":{"l":"女","r":"子"},"明":{"l":"日","r":"月"}}';

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
  });
}
