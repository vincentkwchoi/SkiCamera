import math

class Rect:
    def __init__(self, left, top, right, bottom):
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom

    @property
    def width(self):
        return self.right - self.left

    @property
    def height(self):
        return self.bottom - self.top

    @property
    def center_x(self):
        return (self.left + self.right) / 2.0

    @property
    def center_y(self):
        return (self.top + self.bottom) / 2.0

    @staticmethod
    def from_center_and_scale(cx, cy, scale):
        half = scale / 2.0
        return Rect(cx - half, cy - half, cx + half, cy + half)

    def __repr__(self):
        return f"Rect(l={self.left:.3f}, t={self.top:.3f}, r={self.right:.3f}, b={self.bottom:.3f})"


class PIDController:
    def __init__(self, kp, kd):
        self.kp = kp
        self.kd = kd
        self.last_error = 0.0

    def update(self, error, dt):
        if dt <= 0:
            return 0.0
        derivative = (error - self.last_error) / dt
        self.last_error = error
        return (self.kp * error) + (self.kd * derivative)


class SmoothingFilter:
    def __init__(self, alpha):
        self.alpha = alpha
        self.value = None

    def filter(self, input_val):
        if self.value is None:
            self.value = input_val
            return input_val
        
        # Exponential Moving Average
        new_value = (self.alpha * input_val) + ((1.0 - self.alpha) * self.value)
        self.value = new_value
        return new_value

    def reset(self):
        self.value = None


class AutoZoomManager:
    def __init__(self):
        # Components
        self.height_smoother = SmoothingFilter(alpha=0.2)
        self.center_x_smoother = SmoothingFilter(alpha=0.2)
        self.center_y_smoother = SmoothingFilter(alpha=0.2)

        # "Sticky Framing" Intent Detectors
        self.target_framing_x_intent = SmoothingFilter(alpha=0.05)
        self.target_framing_y_intent = SmoothingFilter(alpha=0.05)

        self.pan_x_pid = PIDController(kp=1.0, kd=0.5)
        self.pan_y_pid = PIDController(kp=1.0, kd=0.5)

        # State
        self.current_zoom_scale = 1.0  # 1.0 = Full Frame
        self.current_crop_center_x = 0.5
        self.current_crop_center_y = 0.5

        # Configuration
        self.target_subject_height_ratio = 0.15 # Reduced from 0.25 to 0.15 to reduce zoom level
        self.max_zoom_speed = 5.0
        self.max_pan_speed = 5.0

    def update(self, skier_rect, dt):
        if dt <= 0:
            return Rect.from_center_and_scale(self.current_crop_center_x, self.current_crop_center_y, self.current_zoom_scale)

        # 1. Smooth Input
        smoothed_height = self.height_smoother.filter(skier_rect.height)
        smoothed_center_x = self.center_x_smoother.filter(skier_rect.center_x)
        smoothed_center_y = self.center_y_smoother.filter(skier_rect.center_y)

        # 2. Sticky Framing Intent
        target_pan_x = self.target_framing_x_intent.filter(smoothed_center_x)
        target_pan_y = self.target_framing_y_intent.filter(smoothed_center_y)

        # 3. Zoom Logic
        # iOS Vision receives the ZOOMED buffer. So 'smoothedHeight' IS the height in crop.
        # We do NOT need to divide by currentZoomScale.
        # let currentSkierHeightInCrop = smoothedHeight / currentZoomScale
        current_skier_height_in_crop = smoothed_height
        zoom_error = self.target_subject_height_ratio - current_skier_height_in_crop

        # Gain
        k_zoom = 10.0

        # Error > 0 (Too small/far) -> Decrease Scale (Zoom In)
        scale_change = -zoom_error * k_zoom * dt
        self.current_zoom_scale += scale_change

        # Clamp Scale (0.1 = 10x Zoom, 1.0 = 1x Zoom)
        self.current_zoom_scale = max(0.05, min(1.0, self.current_zoom_scale))

        # 4. Pan Logic (Proportional Panning)
        # Direct Mapping: Crop Center = Skier Center (Smoothed)
        # This bypasses the PID controller for immediate "proportional" tracking,
        # ensuring the subject's relative position in crop matches full frame.
        self.current_crop_center_x = smoothed_center_x
        self.current_crop_center_y = smoothed_center_y

        # Note: We skip the PID update for panning as requested.
        # pan_x_vel = ...
        # pan_y_vel = ...

        # Clamp Center
        half_scale = self.current_zoom_scale / 2.0
        min_center = half_scale
        max_center = 1.0 - half_scale

        self.current_crop_center_x = self._clamp(self.current_crop_center_x, min_center, max_center)
        self.current_crop_center_y = self._clamp(self.current_crop_center_y, min_center, max_center)

        return Rect.from_center_and_scale(self.current_crop_center_x, self.current_crop_center_y, self.current_zoom_scale)

    def _clamp(self, val, min_val, max_val):
        return max(min_val, min(max_val, val))
