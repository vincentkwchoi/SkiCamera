import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_tasks
from mediapipe.tasks.python import vision

from auto_zoom_manager import AutoZoomManager, Rect
from detectors import YOLOv8Detector

class VideoProcessor:
    def __init__(self, input_path, output_path, enable_skeleton=False):
        self.input_path = input_path
        self.output_path = output_path
        self.enable_skeleton = enable_skeleton
        self.auto_zoom = AutoZoomManager()
        self.auto_zoom = AutoZoomManager()
        self.auto_zoom = AutoZoomManager()
        self.yolo = YOLOv8Detector()
        self.target_track_id = None

        self.landmarker = None
        if self.enable_skeleton:
            # Initialize MediaPipe Pose Landmarker
            model_path = 'pose_landmarker_full.task'
            base_options = mp_tasks.BaseOptions(model_asset_path=model_path)
            options = vision.PoseLandmarkerOptions(
                base_options=base_options,
                running_mode=vision.RunningMode.IMAGE,
                output_segmentation_masks=False
            )
            self.landmarker = vision.PoseLandmarker.create_from_options(options)

    def draw_landmarks(self, image, detection_result):
        pose_landmarks_list = detection_result.pose_landmarks
        if not pose_landmarks_list:
            return
        
        # Connections for the body (subset of full 33 landmarks)
        # 11-12 (shoulders), 11-13 (left arm), 13-15 (left forearm)
        # 12-14 (right arm), 14-16 (right forearm)
        # 11-23 (left torso), 12-24 (right torso), 23-24 (waist)
        # 23-25 (left thigh), 24-26 (right thigh)
        # 25-27 (left leg), 26-28 (right leg)
        connections = [
            (11, 12), (11, 13), (13, 15),
            (12, 14), (14, 16),
            (11, 23), (12, 24), (23, 24),
            (23, 25), (24, 26),
            (25, 27), (26, 28)
        ]

        for landmarks in pose_landmarks_list:
            # Draw lines
            h, w = image.shape[:2]
            for start_idx, end_idx in connections:
                if start_idx >= len(landmarks) or end_idx >= len(landmarks):
                    continue
                start = landmarks[start_idx]
                end = landmarks[end_idx]
                cv2.line(image, (int(start.x * w), int(start.y * h)),(int(end.x * w), int(end.y * h)), (255, 255, 0), 2)
            
            # Draw points
            for idx, landmark in enumerate(landmarks):
                # Draw only relevant landmarks to reduce clutter
                if idx in [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]:
                     cv2.circle(image, (int(landmark.x * w), int(landmark.y * h)), 4, (0, 255, 0), -1)

    def process(self):
        print(f"Opening video: {self.input_path}")
        cap = cv2.VideoCapture(self.input_path)
        if not cap.isOpened():
            print("Error opening video.")
            return

        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

        target_width = width
        target_height = height
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(self.output_path, fourcc, fps, (target_width, target_height))

        frame_idx = 0
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            # 1. Detect skier using YOLOv8
            # Pass target_track_id for ByteTrack ID matching
            detected_rect, track_id = self.yolo.detect(frame, target_track_id=self.target_track_id)
            
            # Update tracking state
            if track_id is not None:
                # If we found a track (either re-acquired or new), latch onto it
                # Logic: If we didn't have a target, this is the new one (closest to center).
                # If we had a target and found it, great.
                # If we had a target and lost it, detect() might return None or a new closest track.
                # Here we strictly follow what detect() returns.
                self.target_track_id = track_id

            # Draw detection (green) if present
            if detected_rect:
                p_left = int(detected_rect.left * width)
                p_top = int(detected_rect.top * height)
                p_right = int(detected_rect.right * width)
                p_bottom = int(detected_rect.bottom * height)
                cv2.rectangle(frame, (p_left, p_top), (p_right, p_bottom), (0, 255, 0), 2)

            # 2. AutoZoom logic
            dt = 1.0 / fps if fps > 0 else 1.0 / 30.0
            current_zoom = self.auto_zoom.current_zoom_scale
            scaled_input_rect = None
            if detected_rect:
                cx = self.auto_zoom.current_crop_center_x
                cy = self.auto_zoom.current_crop_center_y
                scale = current_zoom
                crop_l = cx - scale / 2
                crop_t = cy - scale / 2
                l_new = (detected_rect.left - crop_l) / scale
                t_new = (detected_rect.top - crop_t) / scale
                r_new = (detected_rect.right - crop_l) / scale
                b_new = (detected_rect.bottom - crop_t) / scale
                scaled_input_rect = Rect(l_new, t_new, r_new, b_new)
                crop_rect_norm = self.auto_zoom.update(scaled_input_rect, dt)
            else:
                # Freeze when no detection
                crop_rect_norm = self.auto_zoom.update(Rect(0, 0, 0, 0), 0)

            # 3. Render cropped region
            c_left = int(crop_rect_norm.left * width)
            c_top = int(crop_rect_norm.top * height)
            c_right = int(crop_rect_norm.right * width)
            c_bottom = int(crop_rect_norm.bottom * height)
            c_left = max(0, c_left)
            c_top = max(0, c_top)
            c_right = min(width, c_right)
            c_bottom = min(height, c_bottom)
            if c_right <= c_left:
                c_right = c_left + 1
            if c_bottom <= c_top:
                c_bottom = c_top + 1
            
            crop_img = frame[c_top:c_bottom, c_left:c_right]
            
            if crop_img.size != 0:
                 if self.enable_skeleton and self.landmarker:
                     # 4. Run MediaPipe Pose on the zoomed (cropped) image
                     mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(crop_img, cv2.COLOR_BGR2RGB))
                     detection_result = self.landmarker.detect(mp_image)
                     self.draw_landmarks(crop_img, detection_result)
                 
                 resized = cv2.resize(crop_img, (target_width, target_height))
            else:
                 resized = cv2.resize(frame, (target_width, target_height))

            # Debug overlay
            h_orig = detected_rect.height if detected_rect else 0.0
            h_crop = scaled_input_rect.height if scaled_input_rect else 0.0
            zoom_lvl = 1.0 / self.auto_zoom.current_zoom_scale
            algo_str = "YOLO+MP" if self.enable_skeleton else "YOLOv8"
            tid_str = f"ID:{self.target_track_id}" if self.target_track_id is not None else "No ID"
            debug_text = f"{algo_str} | {tid_str} | Orig H: {h_orig:.3f} | Crop H: {h_crop:.3f} (Target: {self.auto_zoom.target_subject_height_ratio}) | Zoom: {zoom_lvl:.2f}x"
            cv2.rectangle(resized, (10, 10), (900, 60), (0, 0, 0), -1)
            cv2.putText(resized, debug_text, (20, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 255), 2)
            print(f"Frame {frame_idx}: {debug_text}")

            out.write(resized)
            frame_idx += 1
            if frame_idx % 30 == 0:
                pass

        cap.release()
        out.release()
        print("Done!")
