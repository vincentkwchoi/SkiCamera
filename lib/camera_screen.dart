import 'dart:async';
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:gal/gal.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'dart:io';

import 'detector/skier_detector.dart';
import 'auto_zoom/auto_zoom_controller.dart';

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

  // Auto-Zoom & Detection
  late SkierDetector _skierDetector;
  final AutoZoomManager _autoZoomManager = AutoZoomManager();
  bool _isProcessingFrame = false;

  // Method Channel for Native Volume Events (Android)
  static const platform = MethodChannel('com.example.skicamera/volume');

  // UI State
  String _debugStatusText = "Status: Init";
  StreamSubscription<CameraImageData>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize Detector
    _skierDetector = SkierDetector();

    _initializeCamera();
    if (Platform.isAndroid) {
      _setupMethodChannel();
    } else if (Platform.isIOS) {
      _setupVolumeController();
    }
    WakelockPlus.enable();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_isRecording) {
        debugPrint(
          "Lifecycle: Stopping recording due to inactive/paused state.",
        );
        _toggleRecording();
      }
    }
  }

  Future<void> _initializeCamera() async {
    final camera = widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      _maxZoomLevel = await _controller!.getMaxZoomLevel();
      _minZoomLevel = await _controller!.getMinZoomLevel();
      setState(() {});

      // Start Image Stream via bypass
      _startAutoZoomStream(camera.sensorOrientation);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _stopAutoZoomStream() async {
    debugPrint("DEBUG: Stopping AutoZoom Stream...");
    await _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  Future<void> _startAutoZoomStream(
    int sensorOrientation, {
    int retryCount = 0,
  }) async {
    if (_controller == null) return;

    try {
      debugPrint("DEBUG: Bypassing Controller for startImageStream...");

      await _stopAutoZoomStream();

      int frameCount = 0;
      int lastFrameCount = 0;

      // 1. Get the stream from Platform directly (Bypasses Controller recording check)
      final stream = CameraPlatform.instance.onStreamedFrameAvailable(
        _controller!.cameraId,
      );

      _streamSubscription = stream.listen((CameraImageData imageData) async {
        frameCount++;
        if (frameCount % 30 == 0) {
          debugPrint(
            "DEBUG: Stream Heartbeat (Frame $frameCount). Recording: $_isRecording",
          );
        }

        if (_isProcessingFrame) return;
        _isProcessingFrame = true;

        try {
          // 2. Detect Skier
          final Rect? skierRect = await _skierDetector.processPlatformFrame(
            imageData,
            sensorOrientation,
            debugCallback: (fmt, rot, count, labels) {
              if (count == 0 && mounted && frameCount % 10 == 0) {
                setState(
                  () => _debugStatusText = "F:$fmt Cnt:$count (Searching...)",
                );
              }
            },
          );

          if (skierRect != null) {
            double w = imageData.width.toDouble();
            double h = imageData.height.toDouble();

            if (sensorOrientation == 90 || sensorOrientation == 270) {
              w = imageData.height.toDouble();
              h = imageData.width.toDouble();
            }

            final normalizedRect = Rect.fromLTRB(
              skierRect.left / w,
              skierRect.top / h,
              skierRect.right / w,
              skierRect.bottom / h,
            );

            // 3. Update Zoom
            final cropRect = _autoZoomManager.update(normalizedRect, 0.1);
            double targetScale = 1.0 / cropRect.width;

            await _setZoomSafe(targetScale);

            if (mounted && frameCount % 5 == 0) {
              setState(
                () => _debugStatusText =
                    "Found! Zoom Tgt:${targetScale.toStringAsFixed(2)}x Curr:${_currentZoomLevel.toStringAsFixed(2)}x",
              );
            }
          }
        } catch (e) {
          debugPrint("AutoZoom Loop Error: $e");
        } finally {
          _isProcessingFrame = false;
        }
      });

      // 4. Persistence Heartbeat: Check if frames actually start arriving
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted &&
            _streamSubscription != null &&
            frameCount == lastFrameCount) {
          debugPrint("DEBUG: No frames arrived in 2s. RetryCount: $retryCount");
          if (retryCount < 2) {
            _startAutoZoomStream(sensorOrientation, retryCount: retryCount + 1);
          } else {
            if (mounted) {
              setState(
                () => _debugStatusText = "Stream Stuck. Restart Recording?",
              );
            }
          }
        }
        lastFrameCount = frameCount;
      });

      debugPrint("DEBUG: CameraPlatform bypass listener attached.");
    } catch (e) {
      debugPrint("DEBUG: Start Stream Bypass Error: $e");
      if (mounted) setState(() => _debugStatusText = "Stream Err: $e");
    }
  }

  DateTime _lastZoomTime = DateTime.now();

  Future<void> _setZoomSafe(double zoom) async {
    if (_controller == null) return;

    if (DateTime.now().difference(_lastZoomTime).inMilliseconds < 100) return;
    _lastZoomTime = DateTime.now();

    double target = zoom.clamp(_minZoomLevel, _maxZoomLevel);

    if ((target - _currentZoomLevel).abs() > 0.01) {
      try {
        await _controller!
            .setZoomLevel(target)
            .timeout(const Duration(milliseconds: 200));
        _currentZoomLevel = target;
      } catch (e) {
        debugPrint("Zoom Set Error: $e");
      }
    }
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeUp':
          await _zoomManual(true);
          break;
        case 'volumeDown':
          await _zoomManual(false);
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
        _zoomManual(true);
      } else if (volume < _lastVolume) {
        _zoomManual(false);
      }
      _lastVolume = volume;
    });
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // 1. Always stop stream before toggling session
      await _stopAutoZoomStream();

      if (_isRecording) {
        debugPrint("DEBUG: Stopping Video Recording...");
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

        // 2. Settlement Delay for Stop (500ms)
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        debugPrint("DEBUG: Starting Video Recording...");
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
        });

        // 3. Settlement Delay for Start (1500ms) - Slow session reconfiguration
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      // 4. Restart Stream
      if (mounted) {
        debugPrint("DEBUG: Restarting stream after session change...");
        _startAutoZoomStream(_controller!.description.sensorOrientation);
      }
    } catch (e) {
      debugPrint("Toggle Recording Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _zoomManual(bool zoomIn) async {
    if (_controller == null) return;
    double step = 0.5;
    double newZoom = zoomIn
        ? _currentZoomLevel + step
        : _currentZoomLevel - step;
    await _setZoomSafe(newZoom);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streamSubscription?.cancel();
    _skierDetector.dispose();
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
      body: GestureDetector(
        onTap: _toggleRecording,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_controller!),
            SafeArea(
              child: Column(
                children: [
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      _isRecording ? "Recording" : "Tap Screen to Start",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _debugStatusText,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
