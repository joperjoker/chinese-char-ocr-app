import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_char_ocr_app/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ChineseCharOcrApp());
    // The app title rendered on screen is '中文 OCR' in the top bar overlay,
    // not the MaterialApp.title string which is only used by the OS task switcher.
    // The loading screen shows a CircularProgressIndicator while the dictionary
    // and camera initialise, so we verify the root widget is present.
    expect(find.byType(ChineseCharOcrApp), findsOneWidget);
  });
}
