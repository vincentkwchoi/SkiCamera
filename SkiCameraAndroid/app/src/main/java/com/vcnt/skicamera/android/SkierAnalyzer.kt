package com.vcnt.skicamera.android

import android.util.Log
import androidx.annotation.OptIn
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.objects.ObjectDetection
import com.google.mlkit.vision.objects.defaults.ObjectDetectorOptions
import com.vcnt.skicamera.shared.AutoZoomManager
import com.vcnt.skicamera.shared.Rect as SharedRect

class SkierAnalyzer(
    private val autoZoomManager: AutoZoomManager,
    private val onZoomResult: (SharedRect, Double, String, String, SharedRect?, Boolean) -> Unit // crop, height, label, meta, detection, isZooming
) : ImageAnalysis.Analyzer {

    init {
        Log.d("SkiCamera", "SkierAnalyzer initialized")
    }

    private val options = ObjectDetectorOptions.Builder()
        .setDetectorMode(ObjectDetectorOptions.STREAM_MODE)
        .enableMultipleObjects()
        .enableClassification() // Required for labels like "Person"
        .build()

    private val detector = ObjectDetection.getClient(options)

    @OptIn(ExperimentalGetImage::class)
    override fun analyze(imageProxy: ImageProxy) {
        // High priority log to confirm flow
        Log.i("SkiCamera", "--> ANALYZE FRAME [${imageProxy.width}x${imageProxy.height}]")
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val rotation = imageProxy.imageInfo.rotationDegrees
            val image = InputImage.fromMediaImage(mediaImage, rotation)
            
            detector.process(image)
                .addOnSuccessListener { objects ->
                    // 1. Try to find Person first
                    val person = objects.find { it.labels.any { l -> l.text.equals("Person", ignoreCase = true) } }
                    val labels = objects.flatMap { it.labels }.joinToString { it.text }
                    
                    val bestObject = person ?: objects.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }

                    if (bestObject == null) {
                        Log.v("SkiCamera", "No objects at all")
                        onZoomResult(SharedRect(0.0, 0.0, 1.0, 1.0), 1.0, "None", "Rot: $rotation", null)
                        return@addOnSuccessListener
                    }

                    val box = bestObject.boundingBox
                    val label = if (person != null) "Person" else "Unknown (${labels.ifEmpty { "n/a" }})"
                    
                    // InputImage.width/height are already adjusted for rotation!
                    val w = image.width.toDouble()
                    val h = image.height.toDouble()

                    val normalizedRect = SharedRect(
                        left = box.left.toDouble() / w,
                        top = box.top.toDouble() / h,
                        right = box.right.toDouble() / w,
                        bottom = box.bottom.toDouble() / h
                    )

                    Log.i("SkiCamera", "RAW Box: $box, Img: ${w}x${h}, Rot: $rotation")
                    Log.i("SkiCamera", "NORM Rect: $normalizedRect")

                    val dt = 1.0 / 30.0 
                    val cropRect = autoZoomManager.update(normalizedRect, dt)
                    
                    val metadata = "Rot: $rotation / Res: ${w.toInt()}x${h.toInt()}"
                    onZoomResult(cropRect, normalizedRect.height, label, metadata, normalizedRect, autoZoomManager.isZooming)
                }
                .addOnFailureListener { e ->
                    Log.e("SkiCamera", "Detection failed", e)
                }
                .addOnCompleteListener {
                    imageProxy.close()
                }
        } else {
            imageProxy.close()
        }
    }
}
