# SkiCam - Mission

## Objective
Create a suite of native mobile applications (Android & iOS) designed specifically for ski coaches, instructors, and serious skiers to record and analyze performance on the slopes. The platform uses a hybrid architecture with shared Kotlin Multiplatform (KMP) logic to ensure consistent AI behavior across devices.

## Core Philosophy
**"Glove-On" Usability**: The entire user experience is designed for extreme environments. Operation must be possible without taking off thick ski gloves or interacting with complex touch menus.

## Key Features

### 1. Hands-Free Recording (Auto-Start)
- **Goal**: Zero friction from pocket to recording.
- **Action**: Recording starts automatically **3 seconds** after the app is launched.
- **Triggers**: 
    - **iOS**: Launch via Action Button or Lock Screen Shortcut.
    - **Android**: Launch via Double-Press Power/Side Key.

### 2. AI Auto-Zoom & Tracking
- **Feature**: Autonomous subject framing using on-device ML (ML Kit).
- **Core Logic**: Shared KMP `AutoZoomManager` utilizing PID controllers to keep the skier perfectly framed.
- **Goal**: Allow the coach to point the phone in the general direction of the skier while the AI handles precise zoom and framing.

### 3. Physical Controls (Glove-Friendly)
- **Volume Buttons**: Manual zoom override (In/Out).
- **Power Button**: Lock screen detection to automatically finalize and save the video.
- **Tactile Feedback**: Reliable operation in the cold where touch screens fail.

## Target Audience
- Ski Coaches & Instructors
- Professional Athlete Video Technicians
- Serious Skiers analyzing technique
