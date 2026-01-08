# Mission: Ski Video Analyzer (AutoZoom)

## Objective
Create a Python program to post-process a raw ski video into a stabilized, auto-zoomed output video.

## Inputs
- **Source Video**: `ambles_parallel_demo_20260107.mp4` (High resolution, wide angle).

## Outputs
- **Processed Video**: `ambles_parallel_demo_20260107_processed.mp4`.
    - Resolution: Ideally 1080p or 4K crop.
    - Content: Dynamically zoomed and panned to follow the subject (skier).

## Requirements

### 1. Subject Detection (YOLOv8 + Optional MediaPipe)
- **Primary**: **YOLOv8** (Ultralytics) for robust skier detection (bounding box).
- **Secondary (Optional)**: **MediaPipe Pose** for detailed skeletal overlay on the zoomed subject.
- **Why**: YOLOv8 provides higher reliability for small/distant subjects compared to MediaPipe/Vision. MediaPipe is used for visualization when the subject is large enough.

### 2. AutoZoom Logic (Python Port)
- Port the logic from `AutoZoomManager.kt` to Python.
- **PID Control**: 
    - **Zoom**: Uses gain-based control to adjust scale based on subject height ratio.
    - **Pan**: Uses **Proportional Panning** (PID Bypassed).
- **Smoothing**: Implement Exponential Smoothing for inputs.
- **Logic**: 
    - Smooth the detected center/height.
    - **Proportional Panning**: The crop center directly tracks the smoothed subject center. This ensures the subject's relative position in the zoomed frame matches their position in the full frame (e.g., if skier is at 90% width in full view, they appear at 90% width in zoomed view).
    - **Auto-Zoom**: Adjust zoom scale to maintain target subject height (0.15).

### 3. Video Processing (OpenCV)
- **Read**: Use `cv2.VideoCapture` to read the input video frame-by-frame.
- **Render**: 
    - **Overlay**: 
        - Draw **Green Bounding Box** (YOLOv8).
        - Optionally draw **Skeleton** (MediaPipe) if enabled (`--skeleton`).
    - **Crop**: Calculate the crop rectangle based on the AutoZoom state.
    - **Resize**: Crop and resize to target resolution (1080p).
- **Write**: Use `cv2.VideoWriter` to save the processed frames to a new `.mp4` file.

## Technology Stack
- **Language**: Python 3
- **Libraries**:
    - `mediapipe` (AI Detection)
    - `opencv-python` (Video I/O, Image Ops)
    - `numpy` (Math)

## Step-by-Step Plan
1.  **Environment**: Install `opencv-python`, `mediapipe`.
2.  **Detection Script**: Validate MediaPipe Pose on the video.
3.  **Logic Port**: Translate `AutoZoomManager` class (PID, Smoothing) to Python.
4.  **Pipeline**: Create `process_video.py` combining Read -> Detect -> Zoom -> Render -> Write.
