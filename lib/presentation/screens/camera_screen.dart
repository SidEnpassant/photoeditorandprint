import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'photo_preview_screen.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data'; // Added for Uint8List

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

  // For real-time filter preview
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
        ResolutionPreset.medium, // Preview
        enableAudio: false,
      );
      await _controller!.initialize();
      setState(() => _isCameraInitialized = true);
      _controller!.startImageStream(_processCameraImage);
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  void _processCameraImage(CameraImage cameraImage) async {
    _frameCount++;
    // Throttle: process every 3rd frame only
    if (_frameCount % 3 != 0) return;
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;
    try {
      // Convert YUV to RGB
      img.Image rgbImage = _convertYUV420toImage(cameraImage);
      // Apply filter
      img.Image filtered = _applyFilterToImage(
        rgbImage,
        _selectedFilter,
        _filterIntensity,
      );
      _lastProcessedImage = filtered;
      // Encode to PNG for display
      final pngBytes = img.encodePng(filtered);
      setState(() {
        _previewImageBytes = Uint8List.fromList(pngBytes);
      });
    } catch (_) {
      // ignore errors for now
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
      ResolutionPreset.medium, // Use medium for preview performance
      enableAudio: false,
    );
    await _controller!.initialize();
    setState(() => _isCameraInitialized = true);
    _controller!.startImageStream(_processCameraImage);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    _flashOn = !_flashOn;
    await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  img.Image _applyFilterToImage(
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
      if (_lastProcessedImage != null) {
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
      // fallback: use the camera's takePicture if no processed frame
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
      // Optionally, show a focus indicator for a short time
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
      case 1: // Vintage
        return ColorFilter.mode(
          Color(0xFF704214).withOpacity(intensity),
          BlendMode.modulate,
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
      case 4: // Artistic
        return ColorFilter.mode(
          Color(0xFF00BFFF).withOpacity(intensity),
          BlendMode.screen,
        );
      case 5: // Party
        return ColorFilter.mode(
          Color(0xFFFF69B4).withOpacity(intensity),
          BlendMode.lighten,
        );
      case 6: // Cool
        return ColorFilter.mode(
          Color(0xFF00FFFF).withOpacity(intensity),
          BlendMode.modulate,
        );
      case 7: // Warm
        return ColorFilter.mode(
          Color(0xFFFFA500).withOpacity(intensity),
          BlendMode.modulate,
        );
      case 8: // Bright
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
      case 9: // Dark
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Row(
          children: [
            // Left: Filter selection
            Container(
              width: 120,
              color: Colors.grey[900],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filters.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedFilter = index;
                            _frameCount = 0;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _selectedFilter == index
                                  ? Colors.blueAccent
                                  : Colors.grey[800],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            child: Center(
                              child: Text(
                                _filters[index],
                                style: TextStyle(
                                  color: _selectedFilter == index
                                      ? Colors.white
                                      : Colors.grey[300],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedFilter != 0)
                    Column(
                      children: [
                        const Text(
                          'Intensity',
                          style: TextStyle(color: Colors.white),
                        ),
                        Slider(
                          value: _filterIntensity,
                          min: 0.0,
                          max: 1.0,
                          divisions: 100,
                          label: (_filterIntensity * 100).toInt().toString(),
                          onChanged: (val) => setState(() {
                            _filterIntensity = val;
                            _frameCount = 0;
                          }),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Center: Camera preview
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _error != null
                        ? Center(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 18,
                              ),
                            ),
                          )
                        : !_isCameraInitialized
                        ? const Center(child: CircularProgressIndicator())
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
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(40),
                                      ),
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        '$_countdown',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 64,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_focusPoint != null)
                                  Positioned(
                                    left:
                                        _focusPoint!.dx * constraints.maxWidth -
                                        20,
                                    top:
                                        _focusPoint!.dy *
                                            constraints.maxHeight -
                                        20,
                                    child: Icon(
                                      Icons.filter_center_focus,
                                      color: Colors.yellow,
                                      size: 40,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  );
                },
              ),
            ),
            // Right: Camera controls
            Container(
              width: 180,
              color: Colors.grey[900],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      _cameras.isNotEmpty && _selectedCameraIdx == 1
                          ? Icons.camera_front
                          : Icons.camera_rear,
                      color: Colors.white,
                      size: 36,
                    ),
                    onPressed: _cameras.length > 1 ? _switchCamera : null,
                  ),
                  const SizedBox(height: 16),
                  IconButton(
                    icon: Icon(
                      _flashOn ? Icons.flash_on : Icons.flash_off,
                      color: Colors.yellow,
                      size: 36,
                    ),
                    onPressed: _toggleFlash,
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<int>(
                    value: _timer,
                    dropdownColor: Colors.grey[900],
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('No Timer')),
                      DropdownMenuItem(value: 3, child: Text('3s')),
                      DropdownMenuItem(value: 5, child: Text('5s')),
                      DropdownMenuItem(value: 10, child: Text('10s')),
                    ],
                    onChanged: (val) => setState(() => _timer = val ?? 0),
                  ),
                  const SizedBox(height: 32),
                  if (_lastPhotoFile != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _lastPhotoFile!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _countdown > 0 ? null : _startTimerAndCapture,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(24),
                      backgroundColor: Colors.blueAccent,
                    ),
                    child: const Icon(
                      Icons.camera,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
