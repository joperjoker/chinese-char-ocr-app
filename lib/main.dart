import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/capture_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait so the camera sensor-rotation calculations are stable.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Render behind the status bar and navigation bar for a true full-screen
  // camera preview.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const ChineseCharOcrApp());
}

class ChineseCharOcrApp extends StatelessWidget {
  const ChineseCharOcrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chinese Character OCR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB71C1C)),
        useMaterial3: true,
      ),
      home: const CaptureScreen(),
    );
  }
}
