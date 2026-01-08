# Implementation Plan - AutoZoom Integration for LockedCameraCaptureExtensionDemo

This plan describes how to integrate the AutoZoom capability from `SkiCameraIOS` into the `LockedCameraCaptureExtensionDemo`.

## User Review Required

> [!IMPORTANT]
> **Xcode Target Membership**: 
> After creating the new files (`AutoZoomManager.swift`, `SkierAnalyzer.swift`) via this agent, you **MUST** manually ensure they are added to the `LockedExtension` target in your Xcode project. 
> This agent can write the files to disk, but it cannot modify `project.pbxproj` integration directly.
> If these files are missing from the target, the extension will fail to build.

## Proposed Changes

We will introduce the AutoZoom logic into the demo app's camera pipeline.

### Camera / Logic

We will port the core algorithms.

#### [NEW] [AutoZoomManager.swift](file:///Users/vincentchoi/development/SkiCamera/LockedCameraCaptureExtensionDemo/LockedCameraCaptureExtensionDemo/Camera/Logic/AutoZoomManager.swift)
- **Source**: `SkiCameraIOS/.../Logic/AutoZoomManager.swift`
- **Purpose**: logic for calculating smooth zoom and pan based on subject rect.
- **Changes**: Copy as-is.

#### [NEW] [SkierAnalyzer.swift](file:///Users/vincentchoi/development/SkiCamera/LockedCameraCaptureExtensionDemo/LockedCameraCaptureExtensionDemo/Camera/Logic/SkierAnalyzer.swift)
- **Source**: `SkiCameraIOS/.../Camera/SkierAnalyzer.swift`
- **Purpose**: Uses Vision to detect skier (human) in pixel buffers.
- **Changes**: Copy as-is.

### Camera / ViewModel

We will wire the logic into the binding layer.

#### [MODIFY] [MainViewModel.swift](file:///Users/vincentchoi/development/SkiCamera/LockedCameraCaptureExtensionDemo/LockedCameraCaptureExtensionDemo/Camera/ViewModel/MainViewModel.swift)
- **Store Device Reference**: Add `private var videoDevice: AVCaptureDevice?` to hold the active camera.
- **Capture Device**: In `setupCameraSession`, save the `device` to `self.videoDevice`.
- **Inject Device**: After setup, pass `self.videoDevice` to `camPreviewViewModel`.
- **(Optional) Zoom Interface**: Alternatively, handle zoom here if preferred, but direct device access in PreviewModel is simpler for high-frequency loop.

#### [MODIFY] [CamPreviewViewModel.swift](file:///Users/vincentchoi/development/SkiCamera/LockedCameraCaptureExtensionDemo/LockedCameraCaptureExtensionDemo/Camera/ViewModel/CamPreviewViewModel.swift)
- **Properties**: Add `private let analyzer = SkierAnalyzer()` and `private let autoZoomManager = AutoZoomManager()`.
- **Device Access**: Add `var videoDevice: AVCaptureDevice?`.
- **Analysis Loop**: In `captureOutput(_:didOutput:from:)`:
    1. Extract `pixelBuffer`.
    2. Call `analyzer.analyze`.
    3. On result, update `autoZoomManager`.
    4. Calculate `targetZoom = 1.0 / max(0.01, cropRect.width)`.
    5. Apply `targetZoom` to `videoDevice.videoZoomFactor` (ensure thread safety/locking).

## Verification Plan

### Automated Tests
- None. (Visual feature).

### Manual Verification
1.  **Build**: Open Xcode and add the new `Logic` folder/files to the `LockedExtension` target.
2.  **Run**: Launch the **Locked Camera Extension** (via Lock Screen or standard debug run if possible).
3.  **Test**: Point camera at a person (or picture of a person).
4.  **Observe**: Verify that the camera automatically zooms in to frame the person.
5.  **Performance**: Ensure the preview remains smooth (60fps) and no stuttering occurs due to Vision processing.
