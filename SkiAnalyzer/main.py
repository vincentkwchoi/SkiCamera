import os
from video_processor import VideoProcessor

def main():
    # Define paths
    # Assuming running from SkiAnalyzer directory or project root
    # Let's use absolute paths or relative to this script for safety
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    
    import argparse
    parser = argparse.ArgumentParser(description='Ski Video Analyzer')
    parser.add_argument('input', nargs='?', help='Path to input video file')
    parser.add_argument('--output', help='Path to output video file')
    parser.add_argument('--skeleton', action='store_true', help='Enable MediaPipe skeleton overlay on zoomed subject')
    args = parser.parse_args()

    # Determine input path
    if args.input:
        input_video = os.path.abspath(args.input)
    else:
        # Default hardcoded path
        input_video = os.path.join(project_root, "ambles_parallel_demo_20260107.mp4")

    # Determine output path
    if args.output:
        output_video = os.path.abspath(args.output)
    else:
        # Default based on input name
        base, ext = os.path.splitext(input_video)
        output_video = f"{base}_processed{ext}"
    
    if not os.path.exists(input_video):
        print(f"Error: Input video not found at {input_video}")
        return

    print(f"Input: {input_video}")
    print(f"Output: {output_video}")
    print(f"Skeleton Overlay: {'Enabled' if args.skeleton else 'Disabled'}")
    
    processor = VideoProcessor(input_video, output_video, enable_skeleton=args.skeleton)
    processor.process()

if __name__ == "__main__":
    main()
