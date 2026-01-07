import 'dart:ui';
import 'dart:math';

/// A standard PD Controller (Integral is omitted for auto-zoom stability).
class PIDController {
  double kp;
  double kd;
  double _prevError = 0.0;

  PIDController({required this.kp, required this.kd});

  /// Calculates the control output (velocity).
  /// [error]: The difference between Target and Current.
  /// [dt]: Delta time in seconds.
  double update(double error, double dt) {
    if (dt <= 0) return 0.0;

    // Derivative term: Rate of change of error
    double derivative = (error - _prevError) / dt;
    _prevError = error;

    return (kp * error) + (kd * derivative);
  }

  void reset() {
    _prevError = 0.0;
  }
}

/// Exponential Moving Average (EMA) filter.
/// [alpha] determines Smoothing vs. Lag.
/// High alpha (e.g. 0.8) = Fast response, low smoothing.
/// Low alpha (e.g. 0.1) = Slow response, high smoothing.
class SmoothingFilter {
  double alpha;
  double? _prevValue;

  SmoothingFilter({this.alpha = 0.5});

  double filter(double rawValue) {
    // If first frame, initialize with raw value
    if (_prevValue == null) {
      _prevValue = rawValue;
      return rawValue;
    }

    // EMA Formula: value = alpha * raw + (1 - alpha) * prev
    double newValue = (alpha * rawValue) + ((1.0 - alpha) * _prevValue!);
    _prevValue = newValue;
    return newValue;
  }

  double? get currentValue => _prevValue;

  void reset() {
    _prevValue = null;
  }
}

/// Manager that orchestrates the Auto-Zoom and Auto-Pan pipeline.
class AutoZoomManager {
  // --- Components ---
  final PIDController _zoomPid = PIDController(
    kp: 1.0,
    kd: 0.5, // Start with less damping to ensure movement
  );
  final PIDController _panXPid = PIDController(kp: 1.0, kd: 0.5);
  final PIDController _panYPid = PIDController(kp: 1.0, kd: 0.5);

  final SmoothingFilter _heightSmoother = SmoothingFilter(alpha: 0.2);
  final SmoothingFilter _centerXSmoother = SmoothingFilter(alpha: 0.2);
  final SmoothingFilter _centerYSmoother = SmoothingFilter(alpha: 0.2);

  // "Sticky Framing" Intent Detectors (Very slow EMA)
  final SmoothingFilter _targetFramingXIntent = SmoothingFilter(
    alpha: 0.05,
  ); // ~1s lag
  final SmoothingFilter _targetFramingYIntent = SmoothingFilter(alpha: 0.05);

  // --- State ---
  double _currentZoomScale = 1.0; // 1.0 = Full Frame
  Offset _currentCropCenter = const Offset(
    0.5,
    0.5,
  ); // (0.5, 0.5) = Center of sensor

  // --- Configuration ---
  double targetSubjectHeightRatio = 0.4; // Skier should fill 40% of height
  double maxZoomSpeed = 2.0; // Units per second (log scale)
  double maxPanSpeed = 1.5; // Units per second (normalized)

  int _debugCounter = 0;

  // Expose tuning params
  void tune({double? kp, double? kd, double? alpha}) {
    if (kp != null) {
      _zoomPid.kp = kp;
      _zoomPid.kd = kd ?? 2 * sqrt(kp); // Critical damping auto-calculation

      _panXPid.kp = kp;
      _panXPid.kd = _zoomPid.kd;
      _panYPid.kp = kp;
      _panYPid.kd = _zoomPid.kd;
    }
    if (alpha != null) {
      _heightSmoother.alpha = alpha;
      _centerXSmoother.alpha = alpha;
      _centerYSmoother.alpha = alpha;
    }
  }

  /// Main Update Loop
  /// [skierRect]: Normalized bounding box of skier (0.0-1.0 coords).
  /// [dt]: Delta time in seconds.
  /// Returns: The new Digital Crop Rect (normalized).
  Rect update(Rect skierRect, double dt) {
    if (dt <= 0)
      return _getRectFromCenterAndScale(_currentCropCenter, _currentZoomScale);

    // 1. Smooth the Input (Perception)
    double smoothedHeight = _heightSmoother.filter(skierRect.height);
    double smoothedCenterX = _centerXSmoother.filter(skierRect.center.dx);
    double smoothedCenterY = _centerYSmoother.filter(skierRect.center.dy);
    // Offset smoothedCenter = Offset(smoothedCenterX, smoothedCenterY);

    // 2. Identify Operator Intent (Sticky Framing)
    // Dynamic Setpoint based on operator's framing history
    double targetPanX = _targetFramingXIntent.filter(smoothedCenterX);
    double targetPanY = _targetFramingYIntent.filter(smoothedCenterY);

    // 3. ZOOM Logic (PID)
    // We work in Log space for zoom to make it linear to human perception
    // 3. ZOOM Logic (Simple P-Control on Velocity)
    // Complex PID on Scale Velocity proved unstable/oscillatory in tests.
    // Switching to direct P-Control:
    // If Error > 0 (Subject too small), we need to Shrink Scale (Zoom In).
    // Velocity should be negative relative to scale size.

    double currentSkierHeightInCrop = smoothedHeight / _currentZoomScale;
    double zoomError = targetSubjectHeightRatio - currentSkierHeightInCrop;

    // Zoom Speed Factor (Gain)
    // If Error is 0.1, we want to change scale by some amount.
    double kZoom = 1.0;

    // If Error > 0 (Too small), we want Scale to DECREASE.
    // So Change = -Error * Gain * dt
    double scaleChange = -zoomError * kZoom * dt;

    // Apply
    _currentZoomScale += scaleChange;

    // We skip PID class for Zoom for now to rely on simple logic first.
    // double zoomVelocity = _zoomPid.update(zoomError, dt);
    double zoomVelocity =
        scaleChange / (dt > 0 ? dt : 0.016); // For debug display

    // Clamp Scale
    // FIX: If we allow 1.0 (Full Frame), we CANNOT PAN at all.
    // If we want "Sticky Framing" to work even when "zoomed out",
    // we technically can't pan if there's no room.
    // However, if the user moves the skier to the edge,
    // we should validly NOT move the crop if it's full size.
    // BUT the user says "Auto Pan does not work".
    // This happens because the Skier is SMALL (Green Box in screenshot is small).
    // Target Height Ratio is 0.4.
    // If Skier is small, we should be Zooming IN.
    // Why is it not Zooming IN?
    // User set Skier Size slider?
    // Screenshot: Skier Size looks ~0.2.
    // Slider is at ~0.3?
    // If ZoomPID isn't zooming, maybe gain is too low or logic is inverted?
    // Logic: _currentZoomScale -= zoomVelocity * dt;
    // If Error > 0 (Too small), Vel > 0 -> Scale decreases (Zooms IN). Correct.

    _currentZoomScale = _currentZoomScale.clamp(0.1, 1.0);

    // 4. PAN Logic (PID)
    // We want the CropCenter to move such that the Skier is at [targetPanX, targetPanY] RELATIVE TO THE CROP?
    // No, Sticky Framing says: "If I hold skier at 0.9 of sensor, keep him at 0.9 of sensor".
    // Wait, if I zoom in, 0.9 of sensor is 0.9 of sensor.
    // The CropRect is defined in Sensor Coordinates.

    // Error = TargetCenter - CurrentCropCenter ?
    // If TargetFraming is 0.9 (Right side). Skier is at 0.9.
    // We want the Crop to be centered such that Skier is still visible?
    // Actually, "Sticky Framing" usually means:
    // "Keep the Digital Crop Center close to the Skier Center, but offset by the framing preference".

    // Let's simplify for "Auto-Pan" logic specified in doc:
    // "PID to move the Digital Crop window center towards the P_target".
    // Doc says: P_target = EMA(P_current).
    // "Error = P_target - P_subject_in_crop".
    // This implies we control Crop Position to match Target.

    // Let's try: We want the Crop Center to follow the Skier Center.
    // TargetCropCenter = SmoothedSkierCenter.
    // BUT filtered by intent.

    // If I hold skier at 0.9. TargetPanX = 0.9.
    // This is the position of SKIER in SENSOR coords.
    // If I Zoom in to 2x (Scale 0.5).
    // The Crop must be placed such that 0.9 is visible.
    // If CropCenter is 0.9, then Crop covers [0.65, 1.15].
    // Skier at 0.9 is in the middle of crop.

    // 4. PAN Logic (PID)
    // We drive the _currentCropCenter towards the Intent Target (Sticky Framing)
    // instead of the raw Subject Center.

    double panXError = targetPanX - _currentCropCenter.dx;
    double panYError = targetPanY - _currentCropCenter.dy;

    double panXVel = _panXPid.update(panXError, dt);
    double panYVel = _panYPid.update(panYError, dt);

    panXVel = panXVel.clamp(-maxPanSpeed, maxPanSpeed);
    panYVel = panYVel.clamp(-maxPanSpeed, maxPanSpeed);

    _currentCropCenter += Offset(panXVel * dt, panYVel * dt);

    // Clamp Center so Crop stays within Sensor
    double halfScale = _currentZoomScale / 2.0;
    double minCenter = halfScale;
    double maxCenter = 1.0 - halfScale;

    double clampedX = _currentCropCenter.dx.clamp(minCenter, maxCenter);
    double clampedY = _currentCropCenter.dy.clamp(minCenter, maxCenter);
    _currentCropCenter = Offset(clampedX, clampedY);

    // DEBUG LOG
    // Only print every ~60 frames or on significant change to avoid spam
    if (_debugCounter++ % 60 == 0) {
      // Approx once per sec
      print(
        "AUTOZOOM DEBUG: SkierH=${smoothedHeight.toStringAsFixed(3)} "
        "Err=${zoomError.toStringAsFixed(3)} "
        "Scale=${_currentZoomScale.toStringAsFixed(3)} "
        "SkierX=${smoothedCenterX.toStringAsFixed(3)} "
        "TargetX=${targetPanX.toStringAsFixed(3)} "
        "CropX=${_currentCropCenter.dx.toStringAsFixed(3)} "
        "PanErr=${panXError.toStringAsFixed(3)}",
      );
    }

    return _getRectFromCenterAndScale(_currentCropCenter, _currentZoomScale);
  }

  Rect _getRectFromCenterAndScale(Offset center, double scale) {
    double half = scale / 2.0;
    return Rect.fromLTRB(
      center.dx - half,
      center.dy - half,
      center.dx + half,
      center.dy + half,
    );
  }
}
