import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:gal/gal.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'dart:io';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isRecording = false;
  double _currentZoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _lastVolume = 0.5;

  // Method Channel for Native Volume Events (Android)
  static const platform = MethodChannel('com.example.skicamera/volume');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    if (Platform.isAndroid) {
      _setupMethodChannel();
    } else if (Platform.isIOS) {
      _setupVolumeController();
    }
    WakelockPlus.enable();
  }

  Future<void> _initializeCamera() async {
    // Select the main back camera
    final camera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
      _maxZoomLevel = await _controller!.getMaxZoomLevel();
      _minZoomLevel = await _controller!.getMinZoomLevel();
      setState(() {});

      // Immediate Record Implementation
      // Wait a brief moment to ensure UI is ready, then start recording
      Future.delayed(const Duration(milliseconds: 1000), () async {
        try {
          if (mounted &&
              !_isRecording &&
              _controller != null &&
              _controller!.value.isInitialized) {
            await _toggleRecording();
          }
        } catch (e) {
          debugPrint("Error starting auto-record: $e");
        }
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeUp':
          await _zoom(true);
          break;
        case 'volumeDown':
          await _zoom(false);
          break;
        case 'recordToggle':
          await _toggleRecording();
          break;
      }
    });
  }

  Future<void> _setupVolumeController() async {
    try {
      _lastVolume = await FlutterVolumeController.getVolume() ?? 0.5;
    } catch (_) {}

    FlutterVolumeController.addListener((volume) {
      if (volume > _lastVolume) {
        _zoom(true);
      } else if (volume < _lastVolume) {
        _zoom(false);
      }
      _lastVolume = volume;
    });
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      final XFile videoFile = await _controller!.stopVideoRecording();
      setState(() {
        _isRecording = false;
      });
      // Save to gallery
      try {
        await Gal.putVideo(videoFile.path);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Saved to Gallery!')));
        }
      } catch (e) {
        debugPrint('Error saving to gallery: $e');
      }
    } else {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
      });
    }
  }

  Future<void> _zoom(bool zoomIn) async {
    if (_controller == null) return;

    // Zoom step
    double step = 0.5;
    double newZoom = zoomIn
        ? _currentZoomLevel + step
        : _currentZoomLevel - step;

    if (newZoom < _minZoomLevel) newZoom = _minZoomLevel;
    if (newZoom > _maxZoomLevel) newZoom = _maxZoomLevel;

    if (newZoom != _currentZoomLevel) {
      await _controller!.setZoomLevel(newZoom);
      setState(() {
        _currentZoomLevel = newZoom;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    if (Platform.isAndroid) {
      platform.setMethodCallHandler(null);
    } else {
      FlutterVolumeController.removeListener();
    }
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          CameraPreview(_controller!),

          // UI Overlays
          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentZoomLevel.toStringAsFixed(1)}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_isRecording)
                        const Icon(Icons.circle, color: Colors.red, size: 32),
                    ],
                  ),
                ),

                const Spacer(),

                // Instructions
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    "Volume Buttons to Zoom\nLong press to Start/Stop Recording",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
