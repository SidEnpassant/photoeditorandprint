import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'photo_preview_screen.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

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
  int _frameCount = 0;
  bool _isIntensityPanelOpen = true;

  Uint8List? _previewImageBytes;
  img.Image? _lastProcessedImage;
  bool _isProcessingFrame = false;
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

      await _controller!.startImageStream(_processCameraImage);
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  void _processCameraImage(CameraImage cameraImage) async {
    _frameCount++;
    if (_frameCount % 3 != 0) return;
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;
    try {
      img.Image rgbImage = _convertYUV420toImage(cameraImage);
      img.Image filtered = _selectedFilter == 0
          ? rgbImage
          : _applyFilterToImage(rgbImage, _selectedFilter, _filterIntensity);
      final pngBytes = img.encodePng(filtered);
      final imageBytes = Uint8List.fromList(pngBytes);
      if (mounted) {
        setState(() {
          _previewImageBytes = imageBytes;
          _lastProcessedImage = filtered;
        });
      }
    } catch (e) {
      debugPrint("Error processing frame: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  img.Image _convertYUV420toImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;
    final img.Image imgBuffer = img.Image(width, height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final int index = y * width + x;
        final int yp = image.planes[0].bytes[index];
        final int up = image.planes[1].bytes[uvIndex];
        final int vp = image.planes[2].bytes[uvIndex];
        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
        imgBuffer.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return imgBuffer;
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() {
      _isCameraInitialized = false;
      _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
      _previewImageBytes = null;
      _lastProcessedImage = null;
    });
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = CameraController(
      _cameras[_selectedCameraIdx],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    setState(() => _isCameraInitialized = true);
    await _controller!.startImageStream(_processCameraImage);
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
      _frameCount = 0;
      _previewImageBytes = null;
      _lastProcessedImage = null;
    });
  }

  img.Image _applyFilterToImage(
    img.Image image,
    int filterIdx,
    double intensity,
  ) {
    switch (filterIdx) {
      case 1:
        return img.colorOffset(
          image,
          red: (40 * intensity).toInt(),
          green: (20 * intensity).toInt(),
          blue: (-30 * intensity).toInt(),
        );
      case 2:
        var bw = img.grayscale(image);
        if (bw == null) return image;
        return bw;
      case 3:
        return img.adjustColor(image, saturation: 1 + 0.2 * intensity);
      case 4:
        var sep = img.sepia(image, amount: (100 * intensity).toInt());
        if (sep == null) return image;
        return sep;
      case 5:
        return img.adjustColor(image, gamma: 1 + 0.5 * intensity);
      case 6:
        return img.colorOffset(image, blue: (30 * intensity).toInt());
      case 7:
        return img.colorOffset(image, red: (30 * intensity).toInt());
      case 8:
        final bright = img.brightness(image, (40 * intensity).toInt());
        if (bright != null) return bright;
        return image;

      case 9:
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
      if (_lastProcessedImage != null && _selectedFilter != 0) {
        final tempDir = await getTemporaryDirectory();
        final filteredPath =
            '${tempDir.path}/filtered_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(
          filteredPath,
        ).writeAsBytes(img.encodeJpg(_lastProcessedImage!));
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
        return;
      }
      final file = await _controller!.takePicture();
      final rawBytes = await File(file.path).readAsBytes();
      img.Image? captured = img.decodeImage(rawBytes);
      if (captured != null) {
        final filtered = _applyFilterToImage(
          captured,
          _selectedFilter,
          _filterIntensity,
        );
        final tempDir = await getTemporaryDirectory();
        final filteredPath =
            '${tempDir.path}/filtered_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(filteredPath).writeAsBytes(img.encodeJpg(filtered));
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
      } else {
        setState(() => _error = 'Image decode error');
      }
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
        setState(() {
          _focusPoint = null;
        });
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

  ColorFilter? _getColorFilter(int index, [double intensity = 1.0]) {
    switch (index) {
      case 1:
        return ColorFilter.mode(
          Color(0xFF704214).withOpacity(intensity),
          BlendMode.modulate,
        );
      case 2:
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
      case 3:
        return ColorFilter.matrix(<double>[
          1 + 0.2 * intensity,
          0,
          0,
          0,
          0,
          0,
          1 + 0.2 * intensity,
          0,
          0,
          0,
          0,
          0,
          1 + 0.2 * intensity,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
      case 4:
        return ColorFilter.mode(
          Color(0xFF00BFFF).withOpacity(intensity),
          BlendMode.screen,
        );
      case 5:
        return ColorFilter.mode(
          Color(0xFFFF69B4).withOpacity(intensity),
          BlendMode.lighten,
        );
      case 6:
        return ColorFilter.mode(
          Color(0xFF00FFFF).withOpacity(intensity),
          BlendMode.modulate,
        );
      case 7:
        return ColorFilter.mode(
          Color(0xFFFFA500).withOpacity(intensity),
          BlendMode.modulate,
        );
      case 8:
        return ColorFilter.matrix(<double>[
          1 + 0.3 * intensity,
          0,
          0,
          0,
          30 * intensity,
          0,
          1 + 0.3 * intensity,
          0,
          0,
          30 * intensity,
          0,
          0,
          1 + 0.3 * intensity,
          0,
          30 * intensity,
          0,
          0,
          0,
          1,
          0,
        ]);
      case 9:
        return ColorFilter.matrix(<double>[
          1 - 0.3 * intensity,
          0,
          0,
          0,
          0,
          0,
          1 - 0.3 * intensity,
          0,
          0,
          0,
          0,
          0,
          1 - 0.3 * intensity,
          0,
          0,
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
    _controller?.stopImageStream();
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
                                        _frameCount = 0;
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
                                        if (_previewImageBytes != null)
                                          Image.memory(
                                            _previewImageBytes!,
                                            fit: BoxFit.cover,
                                          )
                                        else
                                          CameraPreview(_controller!),
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
