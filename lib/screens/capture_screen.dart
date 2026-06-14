import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/chinese_definition_service.dart';
import '../services/crash_breadcrumbs.dart';
import '../services/dictionary_service.dart';
import '../services/image_sanitizer.dart';
import '../services/radical_service.dart';
import '../services/text_analyzer.dart';
import 'result_screen.dart';

/// Camera capture screen.
///
/// Point the camera at Chinese text and tap the shutter: the frame is
/// photographed, recognised with ML Kit, and the analysis (pinyin, radical
/// decomposition, bilingual definitions) is presented on a [ResultScreen].
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _cameraAvailable = false;

  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.chinese);

  final DictionaryService _dict = DictionaryService();
  final RadicalService _radicals = RadicalService();
  final ChineseDefinitionService _chineseDefs = ChineseDefinitionService();
  late final TextAnalyzer _analyzer = TextAnalyzer(
    dictionary: _dict,
    radicals: _radicals,
    chineseDefinitions: _chineseDefs,
  );

  bool _initialising = true;
  String _initMessage = 'Initialising…';
  bool _capturing = false;
  bool _torchOn = false;

  // Set from the persisted breadcrumb when a previous capture died mid-pipeline
  // (e.g. a native crash that Dart cannot catch). Surfaced as a subtle,
  // dismissible banner so the failing step is visible without a debugger.
  String? _previousCrashStep;
  bool _crashBannerDismissed = false;

  // ── Lifecycle ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreviousCrash();
    _init();
  }

  /// Reads the breadcrumb left by a previous run. A non-null value means the
  /// last capture did not finish — the value names the step it stopped at.
  Future<void> _loadPreviousCrash() async {
    final step = await CrashBreadcrumbs.readPrevious();
    if (step != null && mounted) {
      setState(() => _previousCrashStep = step);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      // Null the reference immediately so no rebuild can access the disposed
      // controller before the camera re-initialises on resume.
      if (mounted) {
        setState(() {
          _camera = null;
          _cameraAvailable = false;
          _initialising = true;
          _initMessage = 'Starting camera…';
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Initialisation ────────────────────────────────────────────────────────────

  Future<void> _init() async {
    if (mounted) setState(() => _initMessage = 'Loading dictionary…');
    try {
      await _dict.load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _initialising = false;
          _initMessage = 'Failed to load dictionary asset.';
        });
      }
      return;
    }

    // Radical and Chinese-definition data are supplementary — the app
    // degrades gracefully without either.
    if (mounted) setState(() => _initMessage = 'Loading radicals…');
    try {
      await _radicals.load();
    } catch (_) {}

    if (mounted) setState(() => _initMessage = 'Loading definitions…');
    try {
      await _chineseDefs.load();
    } catch (_) {}

    if (mounted) setState(() => _initMessage = 'Starting camera…');
    await _initCamera();
  }

  Future<void> _initCamera() async {
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (_) {
      cameras = const [];
    }

    if (cameras.isEmpty) {
      if (mounted) {
        setState(() {
          _cameraAvailable = false;
          _initialising = false;
          _initMessage = 'No camera available on this device.';
        });
      }
      return;
    }

    // Prefer the back-facing camera for document/text scanning.
    final description = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      description,
      // 1080p balances small-text legibility against ML Kit latency, keeping
      // shutter-to-result comfortably inside the 2-second budget.
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    try {
      await controller.initialize();
    } catch (_) {
      if (mounted) {
        setState(() {
          _cameraAvailable = false;
          _initialising = false;
          _initMessage = 'Camera permission denied or unavailable.';
        });
      }
      return;
    }

    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _camera = controller;
      _cameraAvailable = true;
      _initialising = false;
      _torchOn = false;
    });
  }

  // ── Capture pipeline ───────────────────────────────────────────────────────────

  Future<void> _capture() async {
    final controller = _camera;
    if (controller == null || _capturing) return;

    setState(() {
      _capturing = true;
      // A fresh attempt supersedes any earlier crash diagnostic.
      _previousCrashStep = null;
    });
    final stopwatch = Stopwatch()..start();
    String? sanitisedPath;
    XFile? shot;
    try {
      // Breadcrumbs survive a native crash: the next launch reports the last
      // step that completed, pinpointing where the process died.
      await CrashBreadcrumbs.mark('1 shutter tapped (taking photo)');
      shot = await controller.takePicture();

      await CrashBreadcrumbs.mark('2 photo taken (preparing image)');
      // Re-encode to a plain bounded-size PNG so ML Kit's native decoder
      // never sees exotic flagship JPEG variants (e.g. Ultra HDR gain maps).
      sanitisedPath = await ImageSanitizer.sanitise(shot.path);
      final ocrPath = sanitisedPath ?? shot.path;

      await CrashBreadcrumbs.mark('3 image prepared (recognising text)');
      final recognised = await _textRecognizer
          .processImage(InputImage.fromFilePath(ocrPath));

      await CrashBreadcrumbs.mark('4 text recognised (analysing)');
      stopwatch.stop();

      final analysis = _analyzer.analyse(recognised.text);
      await CrashBreadcrumbs.mark('5 analysis done (opening results)');
      if (!mounted) return;

      if (analysis.isEmpty) {
        await CrashBreadcrumbs.clear();
        _showMessage('未识别到中文 — no Chinese characters detected. Try again.');
        return;
      }

      await CrashBreadcrumbs.clear();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            analysis: analysis,
            elapsedMs: stopwatch.elapsedMilliseconds,
          ),
        ),
      );
    } catch (_) {
      await CrashBreadcrumbs.clear();
      if (mounted) _showMessage('Recognition failed — please try again.');
    } finally {
      // Best-effort cleanup of temporary image files.
      if (shot != null) File(shot.path).delete().ignore();
      if (sanitisedPath != null) File(sanitisedPath).delete().ignore();
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _camera;
    if (controller == null) return;
    try {
      await controller
          .setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // Devices without a flash unit throw — ignore and leave the state as-is.
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_initialising) return _buildBootScreen();
    if (!_cameraAvailable) return _buildNoCameraScreen();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildCameraLayer(),
            const _ViewfinderFrame(),
            _buildTopBar(),
            _buildBottomPanel(),
            if (_previousCrashStep != null && !_crashBannerDismissed)
              _CrashDiagnosticBanner(
                step: _previousCrashStep!,
                onDismiss: () =>
                    setState(() => _crashBannerDismissed = true),
              ),
            if (_capturing) const _ProcessingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildBootScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _initMessage,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoCameraScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_initMessage, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _initCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraLayer() {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    // previewSize reports sensor dimensions in landscape orientation; swapping
    // width/height gives the correct portrait aspect ratio so the FittedBox
    // fills the screen without letterboxing.
    final sensorSize = controller.value.previewSize!;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: sensorSize.height,
          height: sensorSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Text(
                  '中文 OCR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _toggleTorch,
                  tooltip: _torchOn ? 'Torch off' : 'Torch on',
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: _torchOn ? Colors.amber : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 32),
                child: Text(
                  '对准中文字符，点击快门识别\nAim at Chinese text, tap the shutter',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _ShutterButton(
                  enabled: !_capturing,
                  onTap: _capture,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Shutter button
// ────────────────────────────────────────────────────────────────────────────────

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture and recognise',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? const Color(0xFFD32F2F) : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Processing overlay shown while recognition is in flight
// ────────────────────────────────────────────────────────────────────────────────

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              '识别中… Recognising…',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Viewfinder corner-bracket overlay
// ────────────────────────────────────────────────────────────────────────────────

/// A subtle, dismissible banner shown when the previous capture attempt ended
/// mid-pipeline (typically a native crash). It names the last completed step,
/// turning an otherwise opaque crash into actionable diagnostics.
class _CrashDiagnosticBanner extends StatelessWidget {
  const _CrashDiagnosticBanner({required this.step, required this.onDismiss});

  final String step;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.of(context).padding.top + 56,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Previous scan stopped at: $step',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewfinderFrame extends StatelessWidget {
  const _ViewfinderFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: const Size(240, 240),
        painter: _CornerBracketPainter(),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const arm = 28.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawLine(const Offset(0, arm), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(arm, 0), paint);
    // Top-right
    canvas.drawLine(Offset(w - arm, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, arm), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - arm), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(arm, h), paint);
    // Bottom-right
    canvas.drawLine(Offset(w, h - arm), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w - arm, h), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
