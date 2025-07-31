VMI Driver App

A new Flutter project.
A Flutter-based mobile application designed for collecting sensor data from delivery drivers during their scheduled shifts. This app automatically tracks accelerometer and GPS data when drivers are on duty and uploads the information to Firebase Firestore for analysis.

## Getting Started
## 🚀 Project Overview

This project is a starting point for a Flutter application.
The VMI Driver App is a sophisticated data collection system that:

A few resources to get you started if this is your first Flutter project:
- **Automatically tracks sensor data** during scheduled shift times
- **Collects accelerometer data** at ~10Hz for movement analysis
- **Records GPS location** every 30-60 seconds for route tracking
- **Uploads data to Firebase Firestore** in real-time chunks
- **Handles background execution** on both iOS and Android
- **Provides a simple shift scheduling interface** for drivers

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)
## 🏗️ Architecture

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
### Core Components

1. **Main App (`main.dart`)**
   - Initializes Firebase and background services
   - Handles app lifecycle states
   - Manages periodic schedule checking

2. **Shift Schedule Screen (`shift_schedule_screen.dart`)**
   - Simple UI for setting shift start/end times
   - Time picker interface for easy scheduling
   - Save/clear functionality for shift management

3. **Background Service (`background_service.dart`)**
   - Core data collection engine
   - Manages sensor streams and GPS polling
   - Handles data buffering and uploads
   - Platform-specific background execution

4. **Storage Service (`storage_service.dart`)**
   - Local data persistence using SharedPreferences
   - Device ID generation and management
   - Shift schedule storage

### Data Flow

```
Driver Sets Schedule → App Checks Time → Start/Stop Collection → Buffer Data → Upload to Firestore
```

## 📱 Features

### Automatic Data Collection
- **Accelerometer**: Continuous 3-axis movement data (~10Hz)
- **GPS**: Location tracking every 30-60 seconds
- **Session Management**: Unique session IDs for each shift
- **Background Execution**: Continues collecting when app is minimized

### Smart Scheduling
- **Time-based activation**: Only collects during scheduled shifts
- **Overnight shift support**: Handles shifts spanning midnight
- **Automatic start/stop**: No manual intervention required

### Data Management
- **Real-time uploads**: Data sent to Firebase every 3-5 minutes
- **Local backup**: Failed uploads saved to device storage
- **Session tracking**: Complete shift history in Firestore
- **Device identification**: Unique device IDs for data attribution

### Platform Optimization
- **iOS**: Limited background execution with optimized uploads
- **Android**: Full background service support
- **Cross-platform**: Consistent behavior across devices

## 🛠️ Technical Stack

### Flutter Dependencies
- **`sensors_plus`**: Accelerometer data collection
- **`geolocator`**: GPS location services
- **`firebase_core` & `cloud_firestore`**: Cloud data storage
- **`flutter_background`**: Background execution management
- **`permission_handler`**: Device permission management
- **`provider`**: State management
- **`shared_preferences`**: Local data storage

### Firebase Structure
```
sessions/
  ├── {session_id}/
  │   ├── session metadata (start/end times, device info)
  │   └── data_chunks/
  │       └── {chunk_id}/
  │           ├── accelerometer data (x, y, z, timestamp)
  │           └── gps data (lat, lon, alt, accuracy)
```

## 🔧 Setup & Installation

### Prerequisites
- Flutter SDK (>=3.0.0)
- Firebase project with Firestore enabled
- iOS/Android development environment

### Configuration
1. **Firebase Setup**
   - Add `GoogleService-Info.plist` to iOS project
   - Configure Firebase project for your app

2. **Permissions**
   - Location permissions for GPS tracking
   - Motion/Fitness permissions for iOS sensors
   - Background execution permissions

3. **Build & Run**
   ```bash
   flutter pub get
   flutter run
   ```

## 📊 Data Collection Details

### Accelerometer Data
- **Frequency**: ~10Hz (device-dependent)
- **Format**: 3-axis acceleration (x, y, z)
- **Units**: m/s²
- **Buffer**: In-memory with periodic uploads

### GPS Data
- **Frequency**: 30 seconds (Android) / 60 seconds (iOS)
- **Accuracy**: Medium accuracy for battery optimization
- **Data**: Latitude, longitude, altitude, accuracy
- **Timeout**: 10-second location request timeout

### Upload Strategy
- **Chunk Size**: 3-5 minutes of data
- **Background Uploads**: Immediate upload when app goes to background
- **Retry Logic**: Failed uploads saved locally for retry
- **Session Management**: Complete session lifecycle tracking

## 🎯 Use Cases

This app is designed for:
- **Delivery companies** tracking driver behavior
- **Fleet management** systems requiring movement data
- **Safety analysis** of driving patterns
- **Route optimization** based on actual travel data
- **Compliance monitoring** for regulated industries

## 🔒 Privacy & Security

- **Local storage**: Sensitive data stored locally when possible
- **Permission-based**: Only collects data with explicit user consent
- **Session isolation**: Data tied to specific shift sessions
- **Device identification**: Anonymous device IDs for data attribution

## 🚧 Platform Limitations

### iOS
- Limited background execution time (~30 seconds)
- More frequent uploads required
- Motion/Fitness permission required for sensors

### Android
- Full background service support
- More reliable long-term data collection
- Better battery optimization options

## 📈 Future Enhancements

Potential improvements for the next iteration:
- **Real-time analytics dashboard**
- **Driver behavior scoring**
- **Route deviation alerts**
- **Battery optimization improvements**
- **Offline data synchronization**
- **Multi-shift scheduling**
- **Driver identification system**

## 🤝 Contributing

This project is designed as a vertical MVP for sensor data collection. The codebase is structured for easy extension and modification based on specific business requirements.
