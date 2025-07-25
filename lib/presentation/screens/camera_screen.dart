import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'photo_preview_screen.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _isCameraInitialized = false;
  int _selectedCameraIdx = 0;
  int _selectedFilter = 0;
  final List<String> _filters = [
    'None',
    'Vintage',
    'B&W',
    'Color+',
    'Artistic',
    'Party',
    'Cool',
    'Warm',
    'Bright',
    'Dark',
  ];
  bool _flashOn = false;
  int _timer = 0;
  String? _error;
  double _filterIntensity = 0.5;
  int _countdown = 0;
  Offset? _focusPoint;
  bool _isIntensityPanelOpen = true;

  // Removed conflicting preview variables
  File? _lastPhotoFile;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found');
        return;
      }
      setState(() {
        _cameras = cameras;
      });
      _controller = CameraController(
        _cameras[_selectedCameraIdx],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _controller!.initialize();
      setState(() => _isCameraInitialized = true);

      // Removed image stream processing for better performance
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() {
      _isCameraInitialized = false;
    });

    await _controller?.dispose();
    setState(() {
      _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
    });

    _controller = CameraController(
      _cameras[_selectedCameraIdx],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    setState(() => _isCameraInitialized = true);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    _flashOn = !_flashOn;
    await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  Future<void> _changeFilter(int newFilterIndex) async {
    if (_selectedFilter == newFilterIndex) return;
    setState(() {
      _selectedFilter = newFilterIndex;
    });
  }

  // Optimized filter processing in isolate
  static Future<Uint8List> _processImageInIsolate(List<dynamic> args) async {
    final Uint8List imageBytes = args[0];
    final int filterIdx = args[1];
    final double intensity = args[2];

    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    img.Image filtered = _applyFilterToImageStatic(image, filterIdx, intensity);
    return Uint8List.fromList(img.encodeJpg(filtered));
  }

  static img.Image _applyFilterToImageStatic(
    img.Image image,
    int filterIdx,
    double intensity,
  ) {
    switch (filterIdx) {
      case 1: // Vintage
        return img.colorOffset(
          image,
          red: (40 * intensity).toInt(),
          green: (20 * intensity).toInt(),
          blue: (-30 * intensity).toInt(),
        );
      case 2: // B&W
        var bw = img.grayscale(image);
        if (bw == null) return image;
        return bw;
      case 3: // Color+
        return img.adjustColor(image, saturation: 1 + 0.2 * intensity);
      case 4: // Artistic
        var sep = img.sepia(image, amount: (100 * intensity).toInt());
        if (sep == null) return image;
        return sep;
      case 5: // Party
        return img.adjustColor(image, gamma: 1 + 0.5 * intensity);
      case 6: // Cool
        return img.colorOffset(image, blue: (30 * intensity).toInt());
      case 7: // Warm
        return img.colorOffset(image, red: (30 * intensity).toInt());
      case 8: // Bright
        final bright = img.brightness(image, (40 * intensity).toInt());
        if (bright != null) return bright;
        return image;
      case 9: // Dark
        final dark = img.brightness(image, (-40 * intensity).toInt());
        if (dark != null) return dark;
        return image;
      default:
        return image;
    }
  }

  Future<void> _capturePhoto() async {
    if (!_isCameraInitialized || _controller == null) return;
    try {
      final file = await _controller!.takePicture();
      final rawBytes = await File(file.path).readAsBytes();

      // Process image in background if filter is applied
      Uint8List processedBytes;
      if (_selectedFilter == 0) {
        processedBytes = rawBytes;
      } else {
        // Use compute for heavy processing
        processedBytes = await compute(_processImageInIsolate, [
          rawBytes,
          _selectedFilter,
          _filterIntensity,
        ]);
      }

      final tempDir = await getTemporaryDirectory();
      final filteredPath =
          '${tempDir.path}/filtered_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(filteredPath).writeAsBytes(processedBytes);

      setState(() {
        _lastPhotoFile = File(filteredPath);
      });

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PhotoPreviewScreen(
            photoPath: filteredPath,
            filterIndex: _selectedFilter,
            filters: _filters,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Capture error: $e');
    }
  }

  Future<void> _onTapToFocus(
    TapUpDetails details,
    BoxConstraints constraints,
  ) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPosition = box.globalToLocal(details.globalPosition);
    final double x = localPosition.dx / constraints.maxWidth;
    final double y = localPosition.dy / constraints.maxHeight;
    try {
      await _controller!.setFocusPoint(Offset(x, y));
      setState(() {
        _focusPoint = Offset(x, y);
      });
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _focusPoint = null;
          });
        }
      });
    } catch (_) {}
  }

  Future<void> _startTimerAndCapture() async {
    if (_timer == 0) {
      await _capturePhoto();
      return;
    }
    setState(() {
      _countdown = _timer;
    });
    while (_countdown > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() {
        _countdown--;
      });
    }
    await _capturePhoto();
  }

  // Optimized ColorFilter system - single source of truth
  ColorFilter? _getColorFilter(int index, [double intensity = 1.0]) {
    switch (index) {
      case 1: // Vintage
        return ColorFilter.mode(
          Color(0xFF704214).withOpacity(0.3 * intensity),
          BlendMode.overlay,
        );
      case 2: // B&W
        return ColorFilter.matrix(<double>[
          0.2126 * intensity + (1 - intensity),
          0.7152 * intensity,
          0.0722 * intensity,
          0,
          0,
          0.2126 * intensity,
          0.7152 * intensity + (1 - intensity),
          0.0722 * intensity,
          0,
          0,
          0.2126 * intensity,
          0.7152 * intensity,
          0.0722 * intensity + (1 - intensity),
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
      case 3: // Color+
        final sat = 1 + 0.3 * intensity;
        return ColorFilter.matrix(<double>[
          0.213 + 0.787 * sat,
          0.715 - 0.715 * sat,
          0.072 - 0.072 * sat,
          0,
          0,
          0.213 - 0.213 * sat,
          0.715 + 0.285 * sat,
          0.072 - 0.072 * sat,
          0,
          0,
          0.213 - 0.213 * sat,
          0.715 - 0.715 * sat,
          0.072 + 0.928 * sat,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
      case 4: // Artistic (Sepia-like)
        return ColorFilter.matrix(<double>[
          0.393 + 0.607 * (1 - intensity),
          0.769 - 0.769 * (1 - intensity),
          0.189 - 0.189 * (1 - intensity),
          0,
          0,
          0.349 - 0.349 * (1 - intensity),
          0.686 + 0.314 * (1 - intensity),
          0.168 - 0.168 * (1 - intensity),
          0,
          0,
          0.272 - 0.272 * (1 - intensity),
          0.534 - 0.534 * (1 - intensity),
          0.131 + 0.869 * (1 - intensity),
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
      case 5: // Party (Bright/Gamma)
        final gamma = 1 + 0.3 * intensity;
        return ColorFilter.matrix(<double>[
          gamma,
          0,
          0,
          0,
          10 * intensity,
          0,
          gamma,
          0,
          0,
          10 * intensity,
          0,
          0,
          gamma,
          0,
          10 * intensity,
          0,
          0,
          0,
          1,
          0,
        ]);
      case 6: // Cool
        return ColorFilter.mode(
          Color(0xFF00BFFF).withOpacity(0.15 * intensity),
          BlendMode.overlay,
        );
      case 7: // Warm
        return ColorFilter.mode(
          Color(0xFFFFA500).withOpacity(0.2 * intensity),
          BlendMode.overlay,
        );
      case 8: // Bright
        return ColorFilter.matrix(<double>[
          1,
          0,
          0,
          0,
          30 * intensity,
          0,
          1,
          0,
          0,
          30 * intensity,
          0,
          0,
          1,
          0,
          30 * intensity,
          0,
          0,
          0,
          1,
          0,
        ]);
      case 9: // Dark
        return ColorFilter.matrix(<double>[
          0.8,
          0,
          0,
          0,
          -20 * intensity,
          0,
          0.8,
          0,
          0,
          -20 * intensity,
          0,
          0,
          0.8,
          0,
          -20 * intensity,
          0,
          0,
          0,
          1,
          0,
        ]);
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1A1A1A),
                    const Color(0xFF0F0F0F),
                    Colors.black.withOpacity(0.95),
                  ],
                ),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C5CE7),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Filters',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ListView.builder(
                        itemCount: _filters.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: GestureDetector(
                            onTap: () => _changeFilter(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                gradient: _selectedFilter == index
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF6C5CE7),
                                          Color(0xFF5A4FCF),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: _selectedFilter == index
                                    ? null
                                    : const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedFilter == index
                                      ? const Color(0xFF6C5CE7).withOpacity(0.3)
                                      : Colors.white.withOpacity(0.05),
                                  width: 1,
                                ),
                                boxShadow: _selectedFilter == index
                                    ? [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF6C5CE7,
                                          ).withOpacity(0.3),
                                          blurRadius: 15,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                              child: Center(
                                child: Text(
                                  _filters[index],
                                  style: TextStyle(
                                    color: _selectedFilter == index
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.7),
                                    fontWeight: _selectedFilter == index
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            if (_selectedFilter != 0)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _isIntensityPanelOpen ? 80 : 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF1A1A1A),
                      const Color(0xFF0F0F0F),
                      Colors.black.withOpacity(0.95),
                    ],
                  ),
                  border: Border(
                    right: BorderSide(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _isIntensityPanelOpen = !_isIntensityPanelOpen;
                        }),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _isIntensityPanelOpen
                                ? Icons.chevron_left
                                : Icons.chevron_right,
                            color: Colors.white.withOpacity(0.7),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    if (_isIntensityPanelOpen)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.05),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              RotatedBox(
                                quarterTurns: 3,
                                child: Text(
                                  'Intensity',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: const Color(0xFF6C5CE7),
                                      inactiveTrackColor: Colors.white
                                          .withOpacity(0.1),
                                      thumbColor: const Color(0xFF6C5CE7),
                                      overlayColor: const Color(
                                        0xFF6C5CE7,
                                      ).withOpacity(0.2),
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 8,
                                      ),
                                      trackHeight: 4,
                                    ),
                                    child: Slider(
                                      value: _filterIntensity,
                                      min: 0.0,
                                      max: 1.0,
                                      divisions: 100,
                                      onChanged: (val) => setState(() {
                                        _filterIntensity = val;
                                      }),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${(_filterIntensity * 100).toInt()}%',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(color: Color(0xFF000000)),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: _error != null
                                ? Container(
                                    color: const Color(0xFF1A1A1A),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.error_outline,
                                            color: Colors.red.withOpacity(0.7),
                                            size: 48,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            _error!,
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : !_isCameraInitialized
                                ? Container(
                                    color: const Color(0xFF1A1A1A),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Color(0xFF6C5CE7),
                                            ),
                                        strokeWidth: 3,
                                      ),
                                    ),
                                  )
                                : GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) =>
                                        _onTapToFocus(details, constraints),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // Single source camera preview with consistent filter
                                        ColorFiltered(
                                          colorFilter:
                                              _getColorFilter(
                                                _selectedFilter,
                                                _filterIntensity,
                                              ) ??
                                              const ColorFilter.mode(
                                                Colors.transparent,
                                                BlendMode.multiply,
                                              ),
                                          child: CameraPreview(_controller!),
                                        ),
                                        if (_countdown > 0)
                                          Center(
                                            child: Container(
                                              padding: const EdgeInsets.all(32),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(
                                                  0.8,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(50),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFF6C5CE7,
                                                  ),
                                                  width: 3,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFF6C5CE7,
                                                    ).withOpacity(0.5),
                                                    blurRadius: 20,
                                                    offset: const Offset(0, 0),
                                                  ),
                                                ],
                                              ),
                                              child: Text(
                                                '$_countdown',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 72,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (_focusPoint != null)
                                          Positioned(
                                            left:
                                                _focusPoint!.dx *
                                                    constraints.maxWidth -
                                                30,
                                            top:
                                                _focusPoint!.dy *
                                                    constraints.maxHeight -
                                                30,
                                            child: Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFF6C5CE7,
                                                  ),
                                                  width: 2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                              child: const Icon(
                                                Icons.center_focus_strong,
                                                color: Color(0xFF6C5CE7),
                                                size: 32,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              width: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1A1A1A),
                    const Color(0xFF0F0F0F),
                    Colors.black.withOpacity(0.95),
                  ],
                ),
                border: Border(
                  left: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _cameras.isNotEmpty && _selectedCameraIdx == 1
                            ? Icons.camera_front_rounded
                            : Icons.camera_rear_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: _cameras.length > 1 ? _switchCamera : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _flashOn
                          ? const Color(0xFF6C5CE7).withOpacity(0.2)
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: _flashOn
                            ? const Color(0xFF6C5CE7)
                            : Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _flashOn
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: _flashOn
                            ? const Color(0xFF6C5CE7)
                            : Colors.white,
                        size: 28,
                      ),
                      onPressed: _toggleFlash,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: Colors.white.withOpacity(0.7),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Timer',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _timer,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF2A2A2A),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 0,
                                child: Text('No Timer'),
                              ),
                              DropdownMenuItem(
                                value: 3,
                                child: Text('3 seconds'),
                              ),
                              DropdownMenuItem(
                                value: 5,
                                child: Text('5 seconds'),
                              ),
                              DropdownMenuItem(
                                value: 10,
                                child: Text('10 seconds'),
                              ),
                            ],
                            onChanged: (val) =>
                                setState(() => _timer = val ?? 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  if (_lastPhotoFile != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        children: [
                          Text(
                            'Last Photo',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(
                                _lastPhotoFile!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: _countdown > 0
                          ? LinearGradient(
                              colors: [
                                Colors.grey.withOpacity(0.5),
                                Colors.grey.withOpacity(0.3),
                              ],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF6C5CE7), Color(0xFF5A4FCF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 3,
                      ),
                      boxShadow: _countdown > 0
                          ? null
                          : [
                              BoxShadow(
                                color: const Color(0xFF6C5CE7).withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                    ),
                    child: ElevatedButton(
                      onPressed: _countdown > 0 ? null : _startTimerAndCapture,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
