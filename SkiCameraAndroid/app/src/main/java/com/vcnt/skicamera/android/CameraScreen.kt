package com.vcnt.skicamera.android

import android.util.Log
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.*
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.vcnt.skicamera.shared.AutoZoomManager
import com.vcnt.skicamera.shared.Rect as SharedRect
import java.util.concurrent.Executors

@Composable
fun CameraScreen(volumeEvent: VolumeEvent?) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val cameraProviderFuture = remember { ProcessCameraProvider.getInstance(context) }
    
    val autoZoomManager = remember { AutoZoomManager() }
    val cameraExecutor = remember { Executors.newSingleThreadExecutor() }
    
    var debugText by remember { mutableStateOf("Initializing...") }
    var cameraControl by remember { mutableStateOf<CameraControl?>(null) }
    var videoCapture by remember { mutableStateOf<VideoCapture<Recorder>?>(null) }
    var currentRecording by remember { mutableStateOf<Recording?>(null) }
    var isRecording by remember { mutableStateOf(false) }
    var detectedRect by remember { mutableStateOf<SharedRect?>(null) }

    // Manual Volume Zoom
    LaunchedEffect(volumeEvent) {
        volumeEvent?.let {
            cameraControl?.let { control ->
                try {
                    val cameraProvider = cameraProviderFuture.get()
                    val camera = cameraProvider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA)
                    val currentZoom = camera.cameraInfo.zoomState.value?.linearZoom ?: 0f
                    val delta = if (it == VolumeEvent.ZoomIn) 0.1f else -0.1f
                    control.setLinearZoom((currentZoom + delta).coerceIn(0f, 1f))
                    Log.d("SkiCamera", "Manual Volume Zoom: $it")
                } catch (e: Exception) {
                    Log.e("SkiCamera", "Manual zoom failed", e)
                }
            }
        }
    }

    // Auto-recording DISABLED for debugging
    /*
    LaunchedEffect(lifecycleOwner) {
        kotlinx.coroutines.delay(3000)
        // ...
    }
    */

    Box(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                Log.d("SkiCamera", "AndroidView factory started")
                val previewView = PreviewView(ctx)
                
                cameraProviderFuture.addListener({
                    val cameraProvider = cameraProviderFuture.get()
                    
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }

                    val imageAnalysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                        .also {
                            // Using main executor for troubleshooting frame flow
                            it.setAnalyzer(ContextCompat.getMainExecutor(ctx), SkierAnalyzer(autoZoomManager) { cropRect, skierHeight, label, metadata, detection, isZooming ->
                                val zoomX = 1.0 / cropRect.width
                                val targetLinearZoom = (zoomX - 1.0) / 4.0 
                                val finalZoom = targetLinearZoom.toFloat().coerceIn(0f, 1f)
                                
                                val status = if (isZooming) "[ZOOMING]" else "[STABLE]"
                                debugText = "$metadata\nLabel: $label\nH: ${"%.2f".format(skierHeight)} - Zoom: ${"%.2f".format(zoomX)}x $status"
                                detectedRect = detection
                                
                                cameraControl?.setLinearZoom(finalZoom)
                            })
                        }

                    val recorder = Recorder.Builder()
                        .setQualitySelector(QualitySelector.from(Quality.SD))
                        .build()
                    val capture = VideoCapture.withOutput(recorder)
                    videoCapture = capture

                    val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

                    try {
                        cameraProvider.unbindAll()
                        Log.d("SkiCamera", "Binding UseCases [Preview, Analysis, Video]...")
                        val camera = cameraProvider.bindToLifecycle(
                            lifecycleOwner, 
                            cameraSelector, 
                            preview, 
                            imageAnalysis, 
                            capture
                        )
                        cameraControl = camera.cameraControl
                        Log.d("SkiCamera", "Binding Successful")
                    } catch (exc: Exception) {
                        Log.e("SkiCamera", "Use case binding failed", exc)
                    }
                }, ContextCompat.getMainExecutor(ctx))
                
                previewView
            }
        )

        // Bounding Box Overlay
        Canvas(modifier = Modifier.fillMaxSize()) {
            detectedRect?.let { rect ->
                drawRect(
                    color = Color.Green,
                    topLeft = androidx.compose.ui.geometry.Offset(
                        x = rect.left.toFloat() * size.width,
                        y = rect.top.toFloat() * size.height
                    ),
                    size = androidx.compose.ui.geometry.Size(
                        width = rect.width.toFloat() * size.width,
                        height = rect.height.toFloat() * size.height
                    ),
                    style = Stroke(width = 4f)
                )
            }
        }

        // Status Overlay
        Text(
            text = if (isRecording) "● RECORDING\n$debugText" else debugText,
            color = if (isRecording) Color.Red else Color.Green,
            modifier = Modifier.align(Alignment.TopCenter)
        )
    }
}
