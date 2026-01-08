package com.vcnt.skicamera.shared

import kotlin.math.sqrt

/**
 * Manager that orchestrates the Auto-Zoom and Auto-Pan pipeline.
 */
class AutoZoomManager {
    // --- Components ---
    private val zoomPid = PIDController(kp = 1.0, kd = 0.5)
    private val panXPid = PIDController(kp = 1.0, kd = 0.5)
    private val panYPid = PIDController(kp = 1.0, kd = 0.5)

    private val heightSmoother = SmoothingFilter(alpha = 0.2)
    private val centerXSmoother = SmoothingFilter(alpha = 0.2)
    private val centerYSmoother = SmoothingFilter(alpha = 0.2)

    // "Sticky Framing" Intent Detectors (Very slow EMA)
    private val targetFramingXIntent = SmoothingFilter(alpha = 0.05) // ~1s lag
    private val targetFramingYIntent = SmoothingFilter(alpha = 0.05)

    // --- State ---
    private var currentZoomScale: Double = 1.0 // 1.0 = Full Frame
    private var currentCropCenterX: Double = 0.5 // (0.5, 0.5) = Center of sensor
    private var currentCropCenterY: Double = 0.5

    // --- Configuration ---
    var targetSubjectHeightRatio: Double = 0.8 // Skier should fill 80% of height
    var maxZoomSpeed: Double = 5.0 // Units per second
    var maxPanSpeed: Double = 5.0 // Units per second

    /**
     * Main Update Loop
     * @param skierRect Normalized bounding box of skier (0.0-1.0 coords).
     * @param dt Delta time in seconds.
     * @return The new Digital Crop Rect (normalized).
     */
    fun update(skierRect: Rect, dt: Double): Rect {
        if (dt <= 0) {
            return getRectFromCenterAndScale(currentCropCenterX, currentCropCenterY, currentZoomScale)
        }

        // 1. Smooth the Input (Perception)
        val smoothedHeight = heightSmoother.filter(skierRect.height)
        val smoothedCenterX = centerXSmoother.filter(skierRect.centerX)
        val smoothedCenterY = centerYSmoother.filter(skierRect.centerY)

        // 2. Identify Operator Intent (Sticky Framing)
        val targetPanX = targetFramingXIntent.filter(smoothedCenterX)
        val targetPanY = targetFramingYIntent.filter(smoothedCenterY)

        // 3. ZOOM Logic
        // Calculate how much the subject fills the CURRENT CROP
        val currentSkierHeightInCrop = smoothedHeight / currentZoomScale
        val zoomError = targetSubjectHeightRatio - currentSkierHeightInCrop

        // Zoom Speed Factor (Gain)
        // Let's increase this for more visible reaction during debugging
        val kZoom = 10.0 

        // If Error > 0 (Too small), we want Scale to DECREASE (zoom in).
        val scaleChange = -zoomError * kZoom * dt
        currentZoomScale += scaleChange

        // Log for debugging
        println("ZoomDebug: err=$zoomError, h_crop=$currentSkierHeightInCrop, scale=$currentZoomScale")

        // Clamp Scale
        currentZoomScale = currentZoomScale.coerceIn(0.1, 1.0)

        // 4. PAN Logic (PID)
        val panXError = targetPanX - currentCropCenterX
        val panYError = targetPanY - currentCropCenterY

        val panXVel = panXPid.update(panXError, dt).coerceIn(-maxPanSpeed, maxPanSpeed)
        val panYVel = panYPid.update(panYError, dt).coerceIn(-maxPanSpeed, maxPanSpeed)

        currentCropCenterX += panXVel * dt
        currentCropCenterY += panYVel * dt

        // Clamp Center so Crop stays within Sensor
        val halfScale = currentZoomScale / 2.0
        val minCenter = halfScale
        val maxCenter = 1.0 - halfScale

        currentCropCenterX = currentCropCenterX.coerceIn(minCenter, maxCenter)
        currentCropCenterY = currentCropCenterY.coerceIn(minCenter, maxCenter)

        return getRectFromCenterAndScale(currentCropCenterX, currentCropCenterY, currentZoomScale)
    }

    private fun getRectFromCenterAndScale(cx: Double, cy: Double, scale: Double): Rect {
        val half = scale / 2.0
        return Rect.fromLTRB(
            cx - half,
            cy - half,
            cx + half,
            cy + half
        )
    }

    fun tune(kp: Double? = null, kd: Double? = null, alpha: Double? = null) {
        kp?.let {
            zoomPid.kp = it
            zoomPid.kd = kd ?: (2.0 * sqrt(it))
            panXPid.kp = it
            panXPid.kd = zoomPid.kd
            panYPid.kp = it
            panYPid.kd = zoomPid.kd
        }
        alpha?.let {
            heightSmoother.alpha = it
            centerXSmoother.alpha = it
            centerYSmoother.alpha = it
        }
    }
}
