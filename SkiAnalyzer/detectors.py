import cv2
import numpy as np
from auto_zoom_manager import Rect

# ---------- YOLOv8 Detector ----------
class YOLOv8Detector:
    def __init__(self, model_name='yolov8n.pt'):
        from ultralytics import YOLO
        # This will download the model if not present
        self.model = YOLO(model_name)
        # YOLO expects BGR images; we will pass frames directly
        self.confidence_threshold = 0.3

    def detect(self, frame, target_track_id=None):
        # Run tracking (persist=True is essential for ByteTrack)
        results = self.model.track(frame, persist=True, tracker="bytetrack.yaml", verbose=False)[0]
        
        # Parse detections: boxes, cls, id
        # We need to handle cases where no tracks are found
        if results.boxes is None or len(results.boxes) == 0:
            return None, None
            
        # Filter for class 0 (person)
        # boxes.id might be None if tracking not initialized or no tracks confirmed
        candidates = []
        for i, box in enumerate(results.boxes):
             if int(box.cls) == 0 and box.conf.item() >= self.confidence_threshold:
                 # Check if track id exists
                 tid = int(box.id.item()) if box.id is not None else None
                 candidates.append((box, tid))
        
        if not candidates:
            return None, None
            
        h, w = frame.shape[:2]
        
        # Selection Logic
        selected = None
        
        if target_track_id is not None:
             # 1. Try to find the specific track ID
             for box, tid in candidates:
                 if tid == target_track_id:
                     selected = (box, tid)
                     break
        
        if selected is None:
             # 2. Fallback: Find closest to center (Initial acquisition or recovery)
             # Note: If target_track_id was set but not found, we effectively 'lost' and re-acquire
             # or we could return None, None to indicate loss.
             # Let's return best candidate (closest to center) and let the caller decide if it wants to switch.
             # Actually, for "Recovery", simpler is picking closest to center.
             centre_x, centre_y = w / 2, h / 2
             best_dist = float('inf')
             
             for box, tid in candidates:
                 x1, y1, x2, y2 = box.xyxy[0].tolist()
                 cx = (x1 + x2) / 2
                 cy = (y1 + y2) / 2
                 dist = (cx - centre_x) ** 2 + (cy - centre_y) ** 2
                 if dist < best_dist:
                     best_dist = dist
                     selected = (box, tid)

        if selected is None:
            return None, None

        box, tid = selected
        x1, y1, x2, y2 = box.xyxy[0].tolist()
        
        # Convert to normalized Rect (top‑left origin)
        left = x1 / w
        top = y1 / h
        right = x2 / w
        bottom = y2 / h
        return Rect(left, top, right, bottom), tid

# ---------- EfficientDet D0 placeholder ----------
class EfficientDetD0Detector:
    def __init__(self):
        # Placeholder – real implementation would load a TFLite model
        raise NotImplementedError('EfficientDet D0 detector not implemented yet')
    def detect(self, frame):
        return None

# ---------- MobileNet SSD placeholder ----------
class MobileNetSSDDetector:
    def __init__(self, prototxt_url=None, model_url=None):
        import os, urllib.request
        # Default URLs for Caffe model
        if prototxt_url is None:
            prototxt_url = 'https://raw.githubusercontent.com/chuanqi305/MobileNet-SSD/master/MobileNetSSD_deploy.prototxt'
        if model_url is None:
            model_url = 'https://raw.githubusercontent.com/chuanqi305/MobileNet-SSD/master/MobileNetSSD_deploy.caffemodel'
        self.prototxt_path = os.path.join(os.path.expanduser('~'), '.cache', 'MobileNetSSD_deploy.prototxt')
        self.model_path = os.path.join(os.path.expanduser('~'), '.cache', 'MobileNetSSD_deploy.caffemodel')
        os.makedirs(os.path.dirname(self.prototxt_path), exist_ok=True)
        # Download if missing
        if not os.path.isfile(self.prototxt_path):
            print('Downloading MobileNetSSD prototxt...')
            urllib.request.urlretrieve(prototxt_url, self.prototxt_path)
        if not os.path.isfile(self.model_path):
            print('Downloading MobileNetSSD caffemodel...')
            urllib.request.urlretrieve(model_url, self.model_path)
        # Load the network
        self.net = cv2.dnn.readNetFromCaffe(self.prototxt_path, self.model_path)
        self.confidence_threshold = 0.3
        # Class ID for "person" in this model is 15
        self.person_class_id = 15

    def detect(self, frame):
        (h, w) = frame.shape[:2]
        blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 0.007843, (300, 300), 127.5)
        self.net.setInput(blob)
        detections = self.net.forward()
        best = None
        best_dist = float('inf')
        for i in range(detections.shape[2]):
            confidence = float(detections[0, 0, i, 2])
            if confidence > self.confidence_threshold:
                class_id = int(detections[0, 0, i, 1])
                if class_id == self.person_class_id:
                    box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
                    (x1, y1, x2, y2) = box.astype('int')
                    cx = (x1 + x2) / 2
                    cy = (y1 + y2) / 2
                    dist = (cx - w/2)**2 + (cy - h/2)**2
                    if dist < best_dist:
                        best_dist = dist
                        best = (x1, y1, x2, y2)
        if best is None:
            return None
        x1, y1, x2, y2 = best
        # Normalized Rect (top‑left origin)
        left = x1 / w
        top = y1 / h
        right = x2 / w
        bottom = y2 / h
        return Rect(left, top, right, bottom)

