import mediapipe as mp
try:
    from mediapipe.python import solutions
    print("Explicit import succeeded.")
    print(f"Solutions: {solutions}")
    print(f"Pose: {solutions.pose}")
except ImportError as e:
    print(f"Explicit import failed: {e}")

print("Checking tasks...")
if hasattr(mp, 'tasks'):
    print(f"Tasks module found: {mp.tasks}")
