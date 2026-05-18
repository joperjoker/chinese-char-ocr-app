import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:lpinyin/lpinyin.dart';
import '../models/radical_info.dart';
import '../services/dictionary_service.dart';
import '../services/radical_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> with WidgetsBindingObserver {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _camera;
  bool _cameraAvailable = false;
  bool _isStreaming = false;

  // Guard preventing concurrent ML Kit calls on successive frames.
  bool _isProcessing = false;

  // Metadata from the last processed frame, needed by the coordinate mapper.
  Size _lastImageSize = Size.zero;
  int _sensorOrientation = 90;

  // ── ML Kit text recogniser – configured for Chinese (Simplified + Traditional)
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.chinese,
  );

  // ── Services ──────────────────────────────────────────────────────────────
  final DictionaryService _dict = DictionaryService();
  final RadicalService _radicals = RadicalService();

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _initialising = true;
  String _initMessage = 'Initialising…';
  List<_OcrLine> _results = [];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
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
      _stopStream();
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

  // ── Initialisation ────────────────────────────────────────────────────────

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

    if (mounted) setState(() => _initMessage = 'Loading radicals…');
    try {
      await _radicals.load();
    } catch (_) {
      // Radical data is supplementary — the app continues without decomposition.
    }

    if (mounted) setState(() => _initMessage = 'Starting camera…');
    await _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();

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
      ResolutionPreset.high,
      enableAudio: false,
      // Choose the native format for each platform so ML Kit can decode
      // frames without an extra colour-space conversion.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await controller.initialize();
    if (!mounted) return;

    setState(() {
      _camera = controller;
      _cameraAvailable = true;
      _initialising = false;
      _sensorOrientation = description.sensorOrientation;
    });

    _startStream();
  }

  // ── Continuous image-stream pipeline ─────────────────────────────────────

  void _startStream() {
    if (_camera == null || _isStreaming) return;
    _camera!.startImageStream(_onCameraFrame);
    setState(() => _isStreaming = true);
  }

  void _stopStream() {
    if (!_isStreaming) return;
    _camera?.stopImageStream();
    if (mounted) setState(() => _isStreaming = false);
  }

  /// Callback fired for every frame delivered by the camera.
  ///
  /// The [_isProcessing] flag ensures only one ML Kit call runs at a time;
  /// excess frames are silently dropped until the previous call resolves.
  void _onCameraFrame(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;
    _processFrame(image).whenComplete(() => _isProcessing = false);
  }

  Future<void> _processFrame(CameraImage image) async {
    final inputImage = _toInputImage(image);
    if (inputImage == null) return;

    // Snapshot the image dimensions for the overlay coordinate mapper.
    _lastImageSize = Size(image.width.toDouble(), image.height.toDouble());

    try {
      final recognised = await _textRecognizer.processImage(inputImage);
      final lines = _parseRecognised(recognised);
      if (mounted) setState(() => _results = lines);
    } catch (_) {
      // Transient ML Kit errors (format mismatch, rotation edge-cases) are
      // expected during the first few frames of a stream; skip silently.
    }
  }

  // ── CameraImage → InputImage conversion ───────────────────────────────────

  /// Converts a raw [CameraImage] from the camera stream into the
  /// [InputImage] format expected by Google ML Kit.
  ///
  /// Returns null when the image format cannot be mapped (unsupported
  /// platform pixel format), allowing the caller to skip that frame.
  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;

    // Map the camera plugin's raw format integer to an ML Kit format constant.
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // Concatenate all plane byte buffers into a single contiguous byte array.
    // • Android YUV_420_888 has three planes (Y, U, V).
    // • iOS BGRA8888 has a single interleaved plane.
    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    // The sensor orientation (0 / 90 / 180 / 270 °) tells ML Kit how to
    // rotate the raw frame so that text appears upright for recognition.
    final rotation =
        InputImageRotationValue.fromRawValue(
          camera.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;

    return InputImage.fromBytes(
      bytes: allBytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  // ── Result parsing ────────────────────────────────────────────────────────

  List<_OcrLine> _parseRecognised(RecognizedText recognised) {
    final results = <_OcrLine>[];
    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;

        final analysis = _dict.analyseText(text);

        // Pinyin priority: CEDICT dictionary entry → lpinyin fallback.
        final String pinyin;
        if (analysis.isValid && analysis.pinyin != null) {
          pinyin = analysis.pinyin!;
        } else if (_dict.containsChineseCharacter(text)) {
          pinyin = PinyinHelper.getPinyinE(text);
        } else {
          pinyin = '';
        }

        // Radical decomposition is only meaningful for single CJK characters.
        final RadicalInfo? radicals =
            text.runes.length == 1 ? _radicals.decompose(text) : null;

        results.add(_OcrLine(
          text: text,
          pinyin: pinyin,
          analysis: analysis,
          radicals: radicals,
          imageBoundingBox: line.boundingBox,
        ));
      }
    }
    return results;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
            _buildResultsOverlay(),
            _buildTopBar(),
            const _ViewfinderFrame(),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  // ── Boot / error screens ──────────────────────────────────────────────────

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_initMessage),
          ],
        ),
      ),
    );
  }

  // ── Camera layer (full-screen, cover-fill) ────────────────────────────────

  Widget _buildCameraLayer() {
    final controller = _camera!;
    // previewSize reports sensor dimensions in landscape orientation.
    // Swapping width/height gives the correct portrait aspect ratio for the
    // FittedBox so the preview fills the screen without letterboxing.
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

  // ── Top bar ───────────────────────────────────────────────────────────────

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
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                _ScanIndicator(active: _isStreaming),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Results overlay (on-camera positioned labels) ─────────────────────────

  /// Builds floating labels placed at each ML Kit bounding box that the
  /// dictionary confirmed as a real Simplified Chinese entry.
  Widget _buildResultsOverlay() {
    final validResults = _results.where((l) => l.analysis.isValid).toList();
    if (validResults.isEmpty || _lastImageSize == Size.zero) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        final mapper = _CoordinateMapper(
          imageSize: _lastImageSize,
          sensorOrientation: _sensorOrientation,
          screenSize: screenSize,
        );

        return Stack(
          children: [
            for (final line in validResults)
              _buildOverlayLabel(line, mapper, screenSize),
          ],
        );
      },
    );
  }

  Widget _buildOverlayLabel(
    _OcrLine line,
    _CoordinateMapper mapper,
    Size screenSize,
  ) {
    final screenRect = mapper.toScreenRect(line.imageBoundingBox);

    if (screenRect == null ||
        screenRect.right < 0 ||
        screenRect.left > screenSize.width ||
        screenRect.bottom < 0 ||
        screenRect.top > screenSize.height) {
      return const SizedBox.shrink();
    }

    // Allocate more vertical space when a radical row is shown so the label
    // doesn't clip above the screen edge.
    final hasRadicals = line.radicals?.hasDecomposition ?? false;
    final labelHeight = hasRadicals ? 104.0 : 72.0;
    final top = (screenRect.top - labelHeight - 6)
        .clamp(0.0, screenSize.height - labelHeight);
    final left = screenRect.left.clamp(0.0, screenSize.width - 10);

    return Positioned(
      left: left,
      top: top,
      child: _ResultLabel(
        text: line.text,
        pinyin: line.pinyin,
        radicals: line.radicals,
      ),
    );
  }

  // ── Bottom controls panel ─────────────────────────────────────────────────

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
              if (_results.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Point the camera at Chinese characters',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ControlButton(
            icon: _isStreaming
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
            label: _isStreaming ? 'Pause' : 'Resume',
            onTap: () => _isStreaming ? _stopStream() : _startStream(),
          ),
          const SizedBox(width: 48),
          _ControlButton(
            icon: Icons.layers_clear,
            label: 'Clear',
            onTap: () => setState(() => _results = []),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Viewfinder corner-bracket overlay
// ─────────────────────────────────────────────────────────────────────────────

class _ViewfinderFrame extends StatelessWidget {
  const _ViewfinderFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: const Size(220, 220),
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

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing scan-active indicator
// ─────────────────────────────────────────────────────────────────────────────

class _ScanIndicator extends StatefulWidget {
  const _ScanIndicator({required this.active});
  final bool active;

  @override
  State<_ScanIndicator> createState() => _ScanIndicatorState();
}

class _ScanIndicatorState extends State<_ScanIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didUpdateWidget(_ScanIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    widget.active ? _controller.repeat(reverse: true) : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: Colors.white38),
          SizedBox(width: 6),
          Text('Paused',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _opacity,
          child: const Icon(Icons.circle, size: 8, color: Colors.redAccent),
        ),
        const SizedBox(width: 6),
        const Text(
          'Scanning',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom control button
// ─────────────────────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────────────

class _OcrLine {
  const _OcrLine({
    required this.text,
    required this.pinyin,
    required this.analysis,
    this.radicals,
    this.imageBoundingBox,
  });

  final String text;
  final String pinyin;
  final AnalysisResult analysis;

  /// Left/right radical decomposition — present only for single CJK characters
  /// that exist in the IDS decomposition table.
  final RadicalInfo? radicals;

  /// Bounding box in raw camera-image coordinate space, as returned by ML Kit.
  final Rect? imageBoundingBox;
}

// ─────────────────────────────────────────────────────────────────────────────
// Coordinate mapper — image space → screen space
// ─────────────────────────────────────────────────────────────────────────────

/// Transforms ML Kit bounding boxes from raw camera-image coordinates to
/// on-screen pixel coordinates, accounting for:
///
/// 1. **Sensor rotation** — Android camera sensors typically report landscape
///    pixels (width > height). The [sensorOrientation] value tells us how many
///    degrees CCW the sensor is rotated relative to the device's natural
///    (portrait) orientation. We apply the inverse rotation to convert image
///    coordinates into portrait display coordinates.
///
/// 2. **FittedBox(cover) scaling** — the camera preview is rendered inside a
///    `FittedBox(fit: BoxFit.cover)` that scales the preview to fill the
///    screen, cropping whichever dimension is narrower. We apply the same
///    scale and offset so that overlay positions align with the preview pixels.
class _CoordinateMapper {
  const _CoordinateMapper({
    required this.imageSize,
    required this.sensorOrientation,
    required this.screenSize,
  });

  final Size imageSize;
  final int sensorOrientation;
  final Size screenSize;

  Rect? toScreenRect(Rect? imageRect) {
    if (imageRect == null) return null;

    final double imgW = imageSize.width;
    final double imgH = imageSize.height;

    // ── Step 1: rotate image coordinates to portrait display coordinates ────
    //
    //   θ = 90  → portrait_x = imgH − imgY,  portrait_y = imgX
    //   θ = 270 → portrait_x = imgY,          portrait_y = imgW − imgX
    //   θ = 180 → portrait_x = imgW − imgX,   portrait_y = imgH − imgY
    //   θ = 0   → no change

    final Rect portrait;
    final double pW, pH;

    switch (sensorOrientation) {
      case 90:
        pW = imgH;
        pH = imgW;
        portrait = Rect.fromLTRB(
          imgH - imageRect.bottom,
          imageRect.left,
          imgH - imageRect.top,
          imageRect.right,
        );
      case 270:
        pW = imgH;
        pH = imgW;
        portrait = Rect.fromLTRB(
          imageRect.top,
          imgW - imageRect.right,
          imageRect.bottom,
          imgW - imageRect.left,
        );
      case 180:
        pW = imgW;
        pH = imgH;
        portrait = Rect.fromLTRB(
          imgW - imageRect.right,
          imgH - imageRect.bottom,
          imgW - imageRect.left,
          imgH - imageRect.top,
        );
      default: // 0°
        pW = imgW;
        pH = imgH;
        portrait = imageRect;
    }

    // ── Step 2: apply the FittedBox(cover) scale + crop offset ──────────────
    //
    //   scale  = max(screenW / pW, screenH / pH)
    //   offset = ((screenW − pW·scale) / 2,  (screenH − pH·scale) / 2)

    final double scale =
        math.max(screenSize.width / pW, screenSize.height / pH);
    final double dx = (screenSize.width - pW * scale) / 2;
    final double dy = (screenSize.height - pH * scale) / 2;

    return Rect.fromLTRB(
      portrait.left * scale + dx,
      portrait.top * scale + dy,
      portrait.right * scale + dx,
      portrait.bottom * scale + dy,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result label — radical decomposition + character + pinyin card
// ─────────────────────────────────────────────────────────────────────────────

class _ResultLabel extends StatelessWidget {
  const _ResultLabel({
    required this.text,
    required this.pinyin,
    this.radicals,
  });

  final String text;
  final String pinyin;
  final RadicalInfo? radicals;

  @override
  Widget build(BuildContext context) {
    final hasRadicals = radicals?.hasDecomposition ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(192),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Radical row ─────────────────────────────────────────────────────
          if (hasRadicals) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RadicalChip(label: radicals!.left!),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '＋',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                _RadicalChip(label: radicals!.right!),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '→',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],

          // ── Recognised character ───────────────────────────────────────────
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),

          // ── Hanyu Pinyin ──────────────────────────────────────────────────
          if (pinyin.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                pinyin,
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small chip showing a single radical character.
class _RadicalChip extends StatelessWidget {
  const _RadicalChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
