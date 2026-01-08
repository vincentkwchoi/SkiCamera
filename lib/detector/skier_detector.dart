import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class SkierDetector {
  ObjectDetector? _objectDetector;
  bool _isBusy = false;
  int _frameCounter = 0;

  // Throttle frequency (process every Nth frame)
  // 30fps / 3 = 10fps processing
  final int _throttleFrameSkip = 3;

  SkierDetector() {
    _initializeDetector();
  }

  void _initializeDetector() {
    // configured for reliability over speed, as we are throttling anyway
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  /// Processes a CameraImage (from CameraController)
  Future<Rect?> processFrame(
    CameraImage image,
    int sensorOrientation, {
    Function(int, int, int, String)? debugCallback,
  }) async {
    return _processGeneral(
      image.width,
      image.height,
      image.format.raw,
      image.planes
          .map((p) => _PlaneWrapper(p.bytes, p.bytesPerRow, p.bytesPerPixel))
          .toList(),
      sensorOrientation,
      debugCallback: debugCallback,
    );
  }

  /// Processes CameraImageData (directly from CameraPlatform bypass)
  Future<Rect?> processPlatformFrame(
    CameraImageData data,
    int sensorOrientation, {
    Function(int, int, int, String)? debugCallback,
  }) async {
    return _processGeneral(
      data.width,
      data.height,
      data.format.raw,
      data.planes
          .map((p) => _PlaneWrapper(p.bytes, p.bytesPerRow, p.bytesPerPixel))
          .toList(),
      sensorOrientation,
      debugCallback: debugCallback,
    );
  }

  Future<Rect?> _processGeneral(
    int width,
    int height,
    int rawFormat,
    List<_PlaneWrapper> planes,
    int sensorOrientation, {
    Function(int, int, int, String)? debugCallback,
  }) async {
    if (_objectDetector == null) return null;

    _frameCounter++;
    if (_frameCounter % _throttleFrameSkip != 0) return null;

    if (_isBusy) return null;
    _isBusy = true;

    try {
      final inputImage = _inputImageFromData(
        width,
        height,
        rawFormat,
        planes,
        sensorOrientation,
      );
      if (inputImage == null) {
        debugCallback?.call(
          rawFormat,
          sensorOrientation,
          -1,
          "Error: Conv Failed",
        );
        return null;
      }

      final objects = await _objectDetector!.processImage(inputImage);
      final labelSummary = objects
          .map((o) => o.labels.isEmpty ? "Obj" : o.labels.first.text)
          .join(',');

      debugCallback?.call(
        rawFormat,
        sensorOrientation,
        objects.length,
        labelSummary,
      );

      return _selectBestSkier(objects, width.toDouble(), height.toDouble());
    } catch (e) {
      debugPrint("SkierDetector Error: $e");
      debugCallback?.call(-999, sensorOrientation, -2, "Exc: $e");
      return null;
    } finally {
      _isBusy = false;
    }
  }

  Rect? _selectBestSkier(
    List<DetectedObject> objects,
    double imgWidth,
    double imgHeight,
  ) {
    if (objects.isEmpty) return null;

    final center = Offset(imgWidth / 2, imgHeight / 2);
    DetectedObject? bestObj;
    double minDistance = double.infinity;

    for (var obj in objects) {
      debugPrint(
        "DEBUG: Detected Object: ${obj.labels.map((l) => l.text).join(', ')} @ ${obj.boundingBox}",
      );

      final rect = obj.boundingBox;
      final objCenter = rect.center;
      final dist = (objCenter - center).distanceSquared;

      if (dist < minDistance) {
        minDistance = dist;
        bestObj = obj;
      }
    }

    return bestObj?.boundingBox;
  }

  InputImage? _inputImageFromData(
    int width,
    int height,
    int rawFormat,
    List<_PlaneWrapper> planes,
    int sensorOrientation,
  ) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final format = InputImageFormatValue.fromRawValue(rawFormat);
      if (format == null) return null;

      final allBytes = WriteBuffer();
      for (final plane in planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final size = Size(width.toDouble(), height.toDouble());
      final imageRotation = InputImageRotationValue.fromRawValue(
        sensorOrientation,
      );
      if (imageRotation == null) return null;

      final inputImageMetadata = InputImageMetadata(
        size: size,
        rotation: imageRotation,
        format: format,
        bytesPerRow: planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (rawFormat == 17) {
        final allBytes = WriteBuffer();
        for (final plane in planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        final imageRotation = InputImageRotationValue.fromRawValue(
          sensorOrientation,
        );
        if (imageRotation == null) return null;

        final inputImageMetadata = InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: imageRotation,
          format: InputImageFormat.nv21,
          bytesPerRow: planes[0].bytesPerRow,
        );
        return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
      }

      if (planes.length == 3) {
        final planeY = planes[0];
        final planeU = planes[1];
        final planeV = planes[2];

        final Uint8List yBuffer = planeY.bytes;
        final int yRowStride = planeY.bytesPerRow;
        final Uint8List uBuffer = planeU.bytes;
        final Uint8List vBuffer = planeV.bytes;
        final int uvRowStride = planeU.bytesPerRow;
        final int uvPixelStride = planeU.bytesPerPixel ?? 1;

        final int ySize = width * height;
        final int uvSize = width * height ~/ 2;
        final Uint8List nv21Bytes = Uint8List(ySize + uvSize);

        int idY = 0;
        for (int y = 0; y < height; y++) {
          final int rowOffset = y * yRowStride;
          for (int x = 0; x < width; x++) {
            nv21Bytes[idY++] = yBuffer[rowOffset + x];
          }
        }

        int idUV = ySize;
        final int uvHeight = height ~/ 2;
        final int uvWidth = width ~/ 2;

        for (int y = 0; y < uvHeight; y++) {
          final int rowOffset = y * uvRowStride;
          for (int x = 0; x < uvWidth; x++) {
            final int bufferIndex = rowOffset + (x * uvPixelStride);
            if (bufferIndex < vBuffer.length) {
              nv21Bytes[idUV++] = vBuffer[bufferIndex];
            } else {
              nv21Bytes[idUV++] = 0;
            }
            if (bufferIndex < uBuffer.length) {
              nv21Bytes[idUV++] = uBuffer[bufferIndex];
            } else {
              nv21Bytes[idUV++] = 0;
            }
          }
        }

        final imageRotation = InputImageRotationValue.fromRawValue(
          sensorOrientation,
        );
        if (imageRotation == null) return null;

        final inputImageMetadata = InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: imageRotation,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        );

        return InputImage.fromBytes(
          bytes: nv21Bytes,
          metadata: inputImageMetadata,
        );
      }
    }
    return null;
  }

  void dispose() {
    _objectDetector?.close();
  }
}

class _PlaneWrapper {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  _PlaneWrapper(this.bytes, this.bytesPerRow, this.bytesPerPixel);
}
