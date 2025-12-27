import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'camera_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request permissions upfront
  await [
    Permission.camera,
    Permission.microphone,
    Permission
        .storage, // For Gallery saving if needed, though Gal handles this.
    Permission.photos, // iOS
  ].request();

  final cameras = await availableCameras();

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
      home: CameraScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}
