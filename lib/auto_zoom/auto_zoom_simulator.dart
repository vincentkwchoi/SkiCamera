import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math';
import 'auto_zoom_controller.dart';

class AutoZoomSimulator extends StatefulWidget {
  const AutoZoomSimulator({super.key});

  @override
  State<AutoZoomSimulator> createState() => _AutoZoomSimulatorState();
}

class _AutoZoomSimulatorState extends State<AutoZoomSimulator>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final AutoZoomManager _manager = AutoZoomManager();

  // Simulation State
  Rect _virtualSkier = const Rect.fromLTWH(0.45, 0.45, 0.1, 0.2); // Normalized
  Rect _currentCrop = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
  double _lastFrameTime = 0.0;

  // Tuning State
  double _kp = 1.0;
  double _kd = 2.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    double currentTime = elapsed.inMicroseconds / 1e6;
    double dt = currentTime - _lastFrameTime;
    _lastFrameTime = currentTime;

    if (dt > 0.1) dt = 0.016; // Cap large dt (e.g. paused)

    setState(() {
      _currentCrop = _manager.update(_virtualSkier, dt);
    });
  }

  void _updateSkierPosition(Offset localPos, Size size) {
    double dx = (localPos.dx / size.width).clamp(0.0, 1.0);
    double dy = (localPos.dy / size.height).clamp(0.0, 1.0);

    // Keep size, move center
    setState(() {
      double w = _virtualSkier.width;
      double h = _virtualSkier.height;
      _virtualSkier = Rect.fromCenter(
        center: Offset(dx, dy),
        width: w,
        height: h,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auto-Zoom Simulator')),
      body: Column(
        children: [
          // Viewport
          Expanded(
            flex: 3,
            child: Listener(
              onPointerSignal: (event) {
                // Not supported on mobile touches directly
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onScaleUpdate: (details) {
                      // Handle Pan (Movement)
                      // focalPoint is global, localFocalPoint is local to the widget
                      _updateSkierPosition(
                        details.localFocalPoint,
                        constraints.biggest,
                      );

                      // Handle Scale (Pinch to resize)
                      if (details.scale != 1.0) {
                        // Simple implementation:
                        // If scale > 1, grow. If < 1, shrink.
                        // But details.scale is cumulative from start of gesture.
                        // We need to apply relative change or just base it on current gesture.
                        // For simplicity in simulator, let's just use the slider for size
                        // and keep this gesture for moving (Pan is part of ScaleUpdate).
                      }
                    },
                    child: Container(
                      color: Colors.grey[900],
                      width: double.infinity,
                      height: double.infinity,
                      child: CustomPaint(
                        painter: SimulatorPainter(
                          skier: _virtualSkier,
                          crop: _currentCrop,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Controls
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[200],
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                // Added scroll view for safety on small screens
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text("Skier Size: "),
                        Expanded(
                          child: Slider(
                            value: _virtualSkier.height,
                            min: 0.05,
                            max: 0.8,
                            onChanged: (v) {
                              setState(() {
                                double aspect =
                                    _virtualSkier.width / _virtualSkier.height;
                                double h = v;
                                double w = h * aspect;
                                _virtualSkier = Rect.fromCenter(
                                  center: _virtualSkier.center,
                                  width: w,
                                  height: h,
                                );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      "PID Tuning (Kp: ${_kp.toStringAsFixed(2)}, Kd: ${_kd.toStringAsFixed(2)})",
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text("Kp (React): "),
                        Expanded(
                          child: Slider(
                            value: _kp,
                            min: 0.1,
                            max: 5.0,
                            onChanged: (v) {
                              setState(() {
                                _kp = v;
                                _manager.tune(kp: _kp, kd: _kd);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text("Kd (Damp):  "),
                        Expanded(
                          child: Slider(
                            value: _kd,
                            min: 0.0,
                            max: 5.0,
                            onChanged: (v) {
                              setState(() {
                                _kd = v;
                                _manager.tune(kp: _kp, kd: _kd);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _kd = 2 * sqrt(_kp);
                          _manager.tune(kp: _kp, kd: _kd);
                        });
                      },
                      child: const Text("Set Critical Damping"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SimulatorPainter extends CustomPainter {
  final Rect skier;
  final Rect crop;

  SimulatorPainter({required this.skier, required this.crop});

  @override
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Full Sensor Boundary (Grey Outline)
    Paint sensorPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(Offset.zero & size, sensorPaint);

    // 2. Draw Skier (Green) relative to Full Sensor
    Paint skierPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;
    Rect screenSkier = Rect.fromLTWH(
      skier.left * size.width,
      skier.top * size.height,
      skier.width * size.width,
      skier.height * size.height,
    );
    canvas.drawRect(screenSkier, skierPaint);

    // 3. Draw Digital Crop (Yellow Outline)
    Paint cropPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    Rect screenCrop = Rect.fromLTWH(
      crop.left * size.width,
      crop.top * size.height,
      crop.width * size.width,
      crop.height * size.height,
    );
    canvas.drawRect(screenCrop, cropPaint);

    // 4. Draw Center of Crop
    canvas.drawCircle(
      screenCrop.center,
      5.0,
      cropPaint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
