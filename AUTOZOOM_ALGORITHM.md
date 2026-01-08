# Auto-Zoom Algorithm: Critically Damped PID Controller

> [!NOTE]
> This algorithm is implemented as a **Cross-Platform Shared Module** using Kotlin Multiplatform (KMP). The core logic in `native/shared` is consumed by both the Native Android and Native iOS applications to ensure identical framing behavior across devices.

## 1. Core Concept
To create a smooth auto-zoom for a skier without overshoot, we utilize a **Critically Damped PID Controller**. This approach treats the zoom level as a physical system with "mass" and "friction," ensuring the lens arrives at the target zoom level quickly but stops precisely on target.

Critical damping ($\zeta = 1$) is the specific tuning where a system returns to its target in the shortest possible time without crossing (overshooting) it.

**The "Error"**: The difference between the **Target Zoom** (the zoom level where the skier occupies a specific % of the frame) and the **Current Zoom**.

## 2. Algorithm Strategy

The algorithm runs in a loop (e.g., 30 or 60 Hz) following these three phases:

### Phase A: Subject Detection (The Input)
1.  **Detection**: Use a real-time object detector (e.g., YOLOv8-Nano, MediaPipe) to obtain the skier's bounding box.
2.  **Current Scale ($S_{current}$)**:
    $$ S_{current} = \frac{\text{Height of Skier Bounding Box}}{\text{Total Frame Height}} $$
3.  **Target Scale ($S_{target}$)**: Define the desired proportion of the frame the skier should fill (e.g., 0.4 or 40%).

### Phase B: The Control Logic (The Brain)
We use a **PD Controller (Proportional-Derivative)** tuned for critical damping. The Integral (I) term is skipped to avoid overshoot in fast-moving scenarios.

**Formula for Zoom Velocity ($v$)**:
$$ v(t) = K_p \cdot \text{Error} + K_d \cdot \frac{d(\text{Error})}{dt} $$

**Tuning for Critical Damping**:
$$ K_d = 2\sqrt{K_p} $$

*   **$K_p$ (Proportional)**: Determines reactiveness. Start low.
*   **$K_d$ (Derivative)**: Acts as the "brake." By setting $K_d = 2\sqrt{K_p}$, the zoom slows down perfectly as it approaches the target.

### Phase C: Logarithmic Scaling (The Output)
Human perception of zoom is logarithmic, not linear (1x to 2x feels the same as 4x to 8x).

*   **Rule**: Apply the control algorithm to the **log** of the zoom level. This prevents the "rushing" feeling when zooming in from far away and ensures visual consistency.

## 3. Implementation Steps

| Component | Recommendation | Why? |
| :--- | :--- | :--- |
| **Tracker** | ByteTrack or Kalman Filter | Skiers move fast; prediction is needed if they are briefly obscured (e.g., snow spray). |
| **Smoothing** | Exponential Moving Average (EMA) | Raw bounding box data is jittery. Smooth the input before feeding it to the PID. |
| **Constraint** | Rate Limiter | Limit the max "Zoom Speed" to avoid motion sickness. |

## 4. Execution Flow
1.  **Detect**: Get skier bounding box height.
2.  **Smooth**: Apply 3-5 frame moving average to the height value.
3.  **Calculate Error**: Diff between smoothed height and desired height (e.g., 400 pixels).
4.  **Compute Scale Change**: Use the critically damped formula ($K_d = 2\sqrt{K_p}$).
5.  **Update Zoom**: Apply change using logarithmic scaling.

## 5. System Architecture

The complete module pipeline consists of these four distinct blocks:

```mermaid
graph LR
    A("Camera Input") --> B("Tracker")
    B -->|"Raw Box"| C("Smoothing")
    C -->|"Smoothed Size"| D("PID Controller")
    D -->|"Velocity Command"| E("Constraint")
    E -->|"Safe Zoom Level"| F("Hardware Lens")

    subgraph "1. Perception"
    B
    C
    end

    subgraph "2. Control"
    D
    end

    subgraph "3. Safety"
    E
    end
```

### Component I/O Specifications

| Component | Input Parameters | Output Parameters | purpose |
| :--- | :--- | :--- | :--- |
| **1. Tracker** | • Video Frame `(ImageBuffer)`<br>• Previous State `(List<Track>)` | • Bounding Box `Rect(x, y, w, h)`<br>• Confidence Score `(float)` | Detects skier and maintains ID across frames. |
| **2. Smoothing** | • Raw Box Height `h_raw` (px)<br>• Alpha `α` (0.1 - 0.3)<br>• **Previous Smoothed Height** `h_prev` | • Smoothed Height `h_smooth` (px) | Reduces high-frequency jitter from detection noise. |
| **3. PID Controller** | • Target Height `h_target` (px)<br>• Smoothed Height `h_smooth` (px)<br>• Delta Time `dt` (sec) | • Zoom Velocity `v_zoom` (factor/sec) | Calculates how fast to change zoom to minimize error. |
| **4. Constraint** | • Raw Velocity `v_zoom`<br>• Max Speed Limit `v_max` | • Safe Velocity `v_final` | Prevents nausea by clamping extreme zoom speeds. |

#### Data Structure Definitions
*   **Track Object**: Represents one identified skier over time.
    *   `id`: Unique Integer (e.g., #42).
    *   `bbox`: The current position `Rect(x,y,w,h)`.
    *   `kalman_state`: Internal matrix representing velocity/covariance (used to predict where box will be next frame).
    *   `missed_frames`: Counter. If > 30, we delete this track (skier left the mountain).

## 6. Handling Camera Panning (Lateral Movement)
Since the camera operator will pan to follow the skier, we must adjust the algorithm to distinguish **Subject Motion** vs **Camera Motion**.

1.  **Ignore Horizontal Position**: The zoom algorithm should calculate scale based **only on Bounding Box Height**, not width or x-position.
2.  **Pan-Tilt-Zoom (PTZ) Compensation**:
    *   **Problem**: If the camera pans fast, the bounding box might blur or temporarily deform.
    *   **Solution**: The **Smoothing** component handles this.
    *   **Deadband**: We do NOT auto-center the subject. We assume the human operator does the framing. We *only* control the Zoom dimension.
3.  **"Lost Subject" Logic**:
    *   If the skier moves out of frame (due to bad panning), the tracker will loose them.
    *   **Action**: If tracking is lost, **HOLD** current zoom. Do NOT zoom out to search (this looks chaotic in video). Wait for re-acquisition.

## 7. Auto-Pan (Digital Stabilization)
To support "Auto-Pan" where the algorithm respects the operator's framing (e.g., keeping subject on the right vs. center):

### The Concept: "Sticky Framing"
Instead of forcing the subject to `Center (0.5, 0.5)`, we use a **Dynamic Setpoint** based on the operator's habits.

1.  **Calculate Operator Intent**:
    *   Continuously calculate the **Smoothed Subject Position** relative to the Full Sensor Frame.
    *   Use a **Very Slow EMA** (e.g., $\alpha = 0.05$, ~1-2 sec lag) to determine where the operator "wants" the subject to be.
    *   $$ P_{target} = \text{EMA}(P_{current}, \text{slow}) $$
    
2.  **Digital Crop Logic**:
    *   **IF** the operator holds the subject at `90% Right` for >1 second, $P_{target}$ becomes `0.9`.
    *   **IF** the camera shakes and the subject momentarily slips to `0.85`, the Digital Crop shifts to put them back at `0.9`.
    *   **Result**: The video looks "locked on" to the subject at the position the operator chose.

**PID Control for Pan**:
Use the same **Critically Damped PID** to move the Digital Crop window center towards the $P_{target}$.
*   **Error** = $P_{target} - P_{subject\_in\_crop}$

## 8. Calibration & Testing Module
To verify the smooth mechanics without hitting the slopes, we will build a **Real-Time Interactive Simulator**.

### A. Input Simulation (The "Virtual Skier")
*   **Mouse/Slider Control**: Drag a dot around a canvas to represent the Skier's position (`x`, `y`).
*   **Scroll Wheel**: Change the dot size to simulate the skier coming closer or moving away (`w`, `h`).
*   **Noise Generator**: Toggle a button to add random "jitter" to the dot's position/size (simulating sensor noise) to test the Smoothing filter.

### B. Visualization (The "Viewfinder")
*   **Outer Rectangle (Gray)**: Represents the **Full 4K Sensor**.
*   **Green Dot**: The **Virtual Skier** (Input).
*   **Blue Rectangle**: The **Digital Crop (Output)** determined by the PID.
    *   *Goal*: The Blue Box should follow the Green Dot smoothly.

### C. Tuning Inspector
*   **Real-Time Graphs**:
    *   Chart 1: **Zoom Level** (Target vs. Actual).
    *   Chart 2: **Pan Position** (Target vs. Actual).
*   **PID Sliders**:
    *   Adjust `Kp` (Reaction Speed) and `Kd` (Damping/Braking) on the fly.
    *   Toggle `Constraint` on/off to see motion sickness effects.

