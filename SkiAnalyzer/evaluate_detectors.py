import cv2
from detectors import YOLOv8Detector, EfficientDetD0Detector, MobileNetSSDDetector

VIDEO_PATH = '/Users/vincentchoi/development/SkiCamera/ambles_parallel_demo_20260107.mp4'

# Initialize detectors (YOLOv8 will download model if needed)
yolo = YOLOv8Detector()
# Placeholders – will raise NotImplementedError if instantiated
try:
    efficient = EfficientDetD0Detector()
except NotImplementedError:
    efficient = None
try:
    mobilenet = MobileNetSSDDetector('path/to/prototxt', 'path/to/caffemodel')
except NotImplementedError:
    mobilenet = None

# Helper to evaluate a detector
def evaluate(detector, name):
    cap = cv2.VideoCapture(VIDEO_PATH)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    detected = 0
    frame_idx = 0
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        if detector:
            rect = detector.detect(frame)
            if rect is not None:
                detected += 1
        frame_idx += 1
    cap.release()
    rate = detected / total * 100 if total > 0 else 0
    print(f"{name}: Detected {detected}/{total} frames ({rate:.2f}% detection rate)")

# Run evaluations
evaluate(yolo, 'YOLOv8 (yolov8n)')
if efficient:
    evaluate(efficient, 'EfficientDet D0')
else:
    print('EfficientDet D0: Not implemented – detection rate 0%')
if mobilenet:
    evaluate(mobilenet, 'MobileNet SSD')
else:
    print('MobileNet SSD: Not implemented – detection rate 0%')
