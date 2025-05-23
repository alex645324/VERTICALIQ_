import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'storage_service.dart';

class BackgroundService {
  // ─── Singleton ──────────────────────────────────────────────────────────────
  static final _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  // ─── Streams & Timers ───────────────────────────────────────────────────────
  StreamSubscription<BarometerEvent>? _baroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _gpsTimer;
  Timer? _hourlyChunkTimer;

  // ─── Session State ──────────────────────────────────────────────────────────
  DateTime? _currentSessionStart;
  final List<Map<String, dynamic>> _baroBuffer = [];
  final List<Map<String, dynamic>> _accelBuffer = [];
  final List<Map<String, dynamic>> _gpsBuffer = [];

  // ─── Storage Service Instance ───────────────────────────────────────────────
  final StorageService _storage = StorageService();

  // ────────────────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────────────────

  /// Call every second from main.dart to auto‑start/stop based on schedule
  void checkSchedule() {
    print('BackgroundService: checkSchedule called');
    final nowTOD = TimeOfDay.fromDateTime(DateTime.now());
    final start = _storage.shiftStartTOD;
    final end = _storage.shiftEndTOD;
    print('BackgroundService: nowTOD = [32m$nowTOD[0m, start = $start, end = $end');

    final inShift = start != null &&
        end != null &&
        (nowTOD.hour > start.hour ||
         (nowTOD.hour == start.hour && nowTOD.minute >= start.minute)) &&
        (nowTOD.hour < end.hour ||
         (nowTOD.hour == end.hour && nowTOD.minute < end.minute));

    if (inShift && _baroSub == null) {
      startCollection();
    } else if (!inShift && _baroSub != null) {
      stopCollection();
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Collection Control
  // ────────────────────────────────────────────────────────────────────────────

  void startCollection() async {
    print('BackgroundService: startCollection called');
    _currentSessionStart = DateTime.now().toUtc();
    debugPrint('🔔 [BackgroundService] START at $_currentSessionStart');

    // Barometer (~1 Hz)
    _baroSub = barometerEventStream().listen((e) {
      print('BackgroundService: Barometer event: pressure = [34m${e.pressure}[0m');
      _baroBuffer.add({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'pressure_hpa': e.pressure,
      });
    });

    // Accelerometer (~10 Hz default)
    _accelSub = accelerometerEventStream().listen((e) {
      print('BackgroundService: Accelerometer event: x=${e.x}, y=${e.y}, z=${e.z}');
      _accelBuffer.add({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'x': e.x,
        'y': e.y,
        'z': e.z,
      });
    });

    // Ensure location permission—request once
    await Geolocator.requestPermission();
    print('BackgroundService: Location permission requested');

    // GPS every 30 s
    _gpsTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      print('BackgroundService: GPS timer triggered');
      try {
        final pos = await Geolocator.getCurrentPosition();
        print('BackgroundService: GPS position: lat=${pos.latitude}, lon=${pos.longitude}, alt=${pos.altitude}, accuracy=${pos.accuracy}');
        _gpsBuffer.add({
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'lat': pos.latitude,
          'lon': pos.longitude,
          'alt': pos.altitude,
          'accuracy': pos.accuracy,
        });
      } catch (e) {
        debugPrint('GPS error: $e');
        print('BackgroundService: GPS error: $e');
      }
    });

    // Schedule first hourly flush
    _scheduleNextChunk();
    print('BackgroundService: Scheduled next chunk');
  }

  Future<void> stopCollection() async {
    print('BackgroundService: stopCollection called');
    debugPrint('🔕 [BackgroundService] STOP at [31m${DateTime.now().toUtc()}[0m');

    _baroSub?.cancel();
    _baroSub = null;
    _accelSub?.cancel();
    _accelSub = null;
    _gpsTimer?.cancel();
    _gpsTimer = null;
    _hourlyChunkTimer?.cancel();
    _hourlyChunkTimer = null;

    try {
      await _flushBuffers();
      print('BackgroundService: Buffers flushed on stop');
    } catch (e) {
      debugPrint('❌ Flush on stop failed: $e');
      print('BackgroundService: Flush on stop failed: $e');
    }

    _currentSessionStart = null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Internal Helpers
  // ────────────────────────────────────────────────────────────────────────────

  /// Flushes current buffers → JSON file → Firebase Storage
  Future<void> _flushBuffers() async {
    print('BackgroundService: _flushBuffers called');
    if (_baroBuffer.isEmpty && _accelBuffer.isEmpty && _gpsBuffer.isEmpty) {
      print('BackgroundService: All buffers empty, nothing to flush');
      return;
    }

    debugPrint('✂️ [BackgroundService] Flushing buffers at ${DateTime.now().toUtc()}');

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'session_${DateTime.now().toIso8601String()}.json';
    final file = File('${dir.path}/$fileName');

    final jsonPayload = {
      'session_id': 'UUID-${DateTime.now().millisecondsSinceEpoch}',
      'start_time': _currentSessionStart?.toIso8601String() ??
          DateTime.now().toUtc().toIso8601String(),
      'end_time': DateTime.now().toUtc().toIso8601String(),
      'device_id': _storage.deviceId,
      'manual_override': false,
      'sensor_data': {
        'barometer': _baroBuffer,
        'accelerometer': _accelBuffer,
        'gps': _gpsBuffer,
      },
    };

    await file.writeAsString(jsonEncode(jsonPayload));
    print('BackgroundService: Wrote JSON to file $fileName');

    // Upload
    try {
      final ref = FirebaseStorage.instance.ref('sessions/$fileName');
      await ref.putFile(file);
      debugPrint('✅ Uploaded $fileName');
      print('BackgroundService: Uploaded $fileName to Firebase');
      await file.delete();
      print('BackgroundService: Deleted local file $fileName after upload');
    } catch (e) {
      debugPrint('❌ Upload failed for $fileName: $e');
      print('BackgroundService: Upload failed for $fileName: $e');
      // keep local file for retry
    }

    // Clear memory
    _baroBuffer.clear();
    _accelBuffer.clear();
    _gpsBuffer.clear();
    print('BackgroundService: Buffers cleared');
  }

  /// Schedules flush exactly at the top of next hour
  void _scheduleNextChunk() {
    print('BackgroundService: _scheduleNextChunk called');
    final now = DateTime.now();
    final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
    final delay = nextHour.difference(now);
    print('BackgroundService: Scheduling next chunk in ${delay.inSeconds} seconds');
    _hourlyChunkTimer = Timer(delay, () {
      print('BackgroundService: Hourly chunk timer triggered');
      if (_baroSub != null) {
        _flushBuffers();
        _scheduleNextChunk(); // keep rolling
      }
    });
  }
}



// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:sensors_plus/sensors_plus.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'storage_service.dart';

// class BackgroundService {
//   static final _instance = BackgroundService._internal();
//   factory BackgroundService() => _instance;
//   BackgroundService._internal();

//   StreamSubscription<BarometerEvent>? _baroSub;
//   StreamSubscription<AccelerometerEvent>? _accelSub;
//   Timer? _gpsTimer;
//   Timer? _hourlyChunkTimer;
//   DateTime? _currentSessionStart;

//   final List<Map<String, dynamic>> _baroBuffer = [];
//   final List<Map<String, dynamic>> _accelBuffer = [];
//   final List<Map<String, dynamic>> _gpsBuffer = [];

//   /// Writes buffered data to a JSON file, uploads to Firebase Storage, and clears buffers
//   Future<void> _flushBuffers() async {
//     final dir = await getApplicationDocumentsDirectory();
//     final fileName = 'session_${DateTime.now().toIso8601String()}.json';
//     final file = File('${dir.path}/$fileName');

//     final content = jsonEncode({
//       'session_id': 'UUID-${DateTime.now().millisecondsSinceEpoch}',
//       'start_time': _currentSessionStart?.toIso8601String()?? DateTime.now().toUtc().toIso8601String(),
//       'end_time': DateTime.now().toUtc().toIso8601String(),
//       'device_id': StorageService().deviceId,
//       'manual_override': false,
//       'sensor_data': {
//         'barometer': _baroBuffer,
//         'accelerometer': _accelBuffer,
//         'gps': _gpsBuffer,
//       },
//     });
//     await file.writeAsString(content);

//     // UPLOAD TO FIREBASE STORAGE
//     try {
//       final storageRef = FirebaseStorage.instance
//           .ref()
//           .child('sessions')
//           .child(fileName);
//       await storageRef.putFile(file);
//       // On success, delete local file
//       await file.delete();
//     } catch (e) {
//       // If upload fails, you can log or retry later
//       debugPrint('Upload failed for $fileName: $e');
//     }

//     // Clear in-memory buffers
//     _baroBuffer.clear();
//     _accelBuffer.clear();
//     _gpsBuffer.clear();
//   }

//   /// Starts listening to sensors and GPS
//   void start() {
//     //mark session start 
//     _currentSessionStart = DateTime.now().toUtc();
//     debugPrint('🔔 [BackgroundService] START at $_currentSessionStart');
 
//     // Barometer at ~1Hz
//     _baroSub = SensorsPlus.barometerEvents.listen((event) {
//       _baroBuffer.add({
//         'timestamp': DateTime.now().millisecondsSinceEpoch,
//         'pressure_hpa': event.pressure,
//       });
//     });

//     // Accelerometer at device default (~10Hz)
//     _accelSub = SensorsPlus.accelerometerEvents.listen((event) {
//       _accelBuffer.add({
//         'timestamp': DateTime.now().millisecondsSinceEpoch,
//         'x': event.x,
//         'y': event.y,
//         'z': event.z,
//       });
//     });

//     // GPS every 30 seconds
//     _gpsTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
//       final pos = await Geolocator.getCurrentPosition();
//       _gpsBuffer.add({
//         'timestamp': DateTime.now().millisecondsSinceEpoch,
//         'lat': pos.latitude,
//         'lon': pos.longitude,
//         'alt': pos.altitude,
//         'accuracy': pos.accuracy,
//       });
//     });

//     // Schedule first hourly chunk
//     _scheduleNextChunk();
//   }

//   /// Stops all sensor and GPS subscriptions and writes remaining data
//   Future<void> stop() async {
//     _baroSub?.cancel();
//     _baroSub = null;
//     _accelSub?.cancel();
//     _accelSub = null;
//     _gpsTimer?.cancel();
//     _gpsTimer = null;
//     _hourlyChunkTimer?.cancel();
//     _hourlyChunkTimer = null;
//     await _flushBuffers();
//   }
  

//   /// Checks the saved shift schedule and toggles start/stop
//   void checkSchedule() {
//     final now = TimeOfDay.fromDateTime(DateTime.now());
//     final start = StorageService().shiftStartTOD;
//     final end = StorageService().shiftEndTOD;
//     final inShift = start != null && end != null &&
//         (now.hour > start.hour || (now.hour == start.hour && now.minute >= start.minute)) &&
//         (now.hour < end.hour || (now.hour == end.hour && now.minute < end.minute));

//     if (inShift && _baroSub == null) {
//       start();
//     } else if (!inShift && _baroSub != null) {
//       stop();
//     }
//   }

//   /// Calculates delay until next full hour, then schedules a chunk
//   void _scheduleNextChunk() {
//     final now = DateTime.now();
//     final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
//     final delay = nextHour.difference(now);

//     _hourlyChunkTimer = Timer(delay, () {
//       if (_baroSub != null) {
//         _flushBuffers();
//         _scheduleNextChunk();
//       }
//     });
//   }
// }
