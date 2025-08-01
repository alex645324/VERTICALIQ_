# VMI Driver App

## Problem

Delivery and fleet operators need reliable, continuous on-shift sensor data (location + motion) from drivers. Manual tracking is inconsistent, background collection drops off, and lost uploads break analysis.

## What It Does

- Automatically tracks accelerometer (~10Hz) and GPS (30–60s) during scheduled shifts.
- Runs in the background on iOS/Android with automatic start/stop based on driver schedule.
- Buffers and uploads data in chunks to Firebase Firestore with retry/fallback on failure.
- Assigns unique session IDs per shift, preserving full shift history.
- Provides a minimal UI for drivers to set and manage their shift times.

## How to Use

### 1. Requirements
- Flutter SDK (>=3.0.0)
- Firebase project with Firestore enabled
- iOS/Android dev environment (Xcode / Android SDK)

### 2. Setup

#### Firebase
- Add Firebase config files:
  - iOS: `GoogleService-Info.plist`
  - Android: `google-services.json`
- Enable Firestore in your Firebase console.

#### Permissions
Grant the app:
- Location access (foreground/background)
- Motion/sensor access (iOS: Motion & Fitness)
- Background execution capabilities

### 3. Install & Run
```bash
flutter pub get
flutter run
