import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'camera_screen.dart';
import 'auto_zoom/auto_zoom_simulator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request permissions upfront
  // Request permissions upfront (Skip on macOS to avoid plugin issues for Simulator)
  try {
    if (!Platform.isMacOS) {
      await [
        Permission.camera,
        Permission.microphone,
        Permission.storage,
        Permission.photos,
      ].request();
    }
  } catch (e) {
    debugPrint("Error requesting permissions: $e");
  }

  List<CameraDescription> cameras = [];
  try {
    if (!Platform.isMacOS) {
      cameras = await availableCameras();
    }
  } catch (e) {
    debugPrint("Error fetching cameras: $e");
  }

  runApp(SkiCameraApp(cameras: cameras));
}

class SkiCameraApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const SkiCameraApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ski Cam',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: DevMenuScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DevMenuScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  const DevMenuScreen({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ski Camera Dev")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CameraScreen(cameras: cameras),
                ),
              ),
              child: const Text("Open Camera"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AutoZoomSimulator()),
              ),
              child: const Text("Open Auto-Zoom Simulator"),
            ),
          ],
        ),
      ),
    );
  }
}
