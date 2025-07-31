import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

import 'storage_service.dart';

class BackgroundService {
  // ─── Singleton ──────────────────────────────────────────────────────────────
  static final _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  // ─── Firestore instance ──────────────────────────────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Streams & Timers ───────────────────────────────────────────────────────
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _gpsTimer;
  Timer? _uploadTimer;

  // ─── Session State ──────────────────────────────────────────────────────────
  DateTime? _currentSessionStart;
  String? _currentSessionId;
  final List<Map<String, dynamic>> _accelBuffer = [];
  final List<Map<String, dynamic>> _gpsBuffer = [];

  // ─── Storage Service Instance ───────────────────────────────────────────────
  final StorageService _storage = StorageService();

  // ─── iOS Background State ───────────────────────────────────────────────────
  bool _isInBackground = false;
  DateTime? _backgroundStartTime;

  // ────────────────────────────────────────────────────────────────────────────
  // Permission Handling
  // ────────────────────────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    debugPrint('BackgroundService: Requesting permissions');
    
    // Location permission
    LocationPermission locationPermission = await Geolocator.checkPermission();
    if (locationPermission == LocationPermission.denied) {
      locationPermission = await Geolocator.requestPermission();
    }
    
    if (locationPermission == LocationPermission.deniedForever) {
      debugPrint('BackgroundService: Location permission denied forever');
      return false;
    }

    // iOS-specific: Motion & Fitness permission for sensors
    if (Platform.isIOS) {
      final motionStatus = await Permission.sensors.request();
      if (!motionStatus.isGranted) {
        debugPrint('BackgroundService: Motion permission not granted');
      }
    }

    debugPrint('BackgroundService: Permissions requested successfully');
    return true;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────────────────

  /// Call every second from main.dart to auto‑start/stop based on schedule
  void checkSchedule() {
    debugPrint('BackgroundService: checkSchedule called');
    final nowTOD = TimeOfDay.fromDateTime(DateTime.now());
    final start = _storage.shiftStartTOD;
    final end = _storage.shiftEndTOD;
    debugPrint('BackgroundService: nowTOD = $nowTOD, start = $start, end = $end');

    final inShift = _isInShiftTime(nowTOD, start, end);

    if (inShift && _accelSub == null) {
      startCollection();
    } else if (!inShift && _accelSub != null) {
      stopCollection();
    }
  }

  bool _isInShiftTime(TimeOfDay now, TimeOfDay? start, TimeOfDay? end) {
    if (start == null || end == null) return false;
    
    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    
    // Handle overnight shifts (e.g., 22:00 to 06:00)
    if (startMinutes > endMinutes) {
      return nowMinutes >= startMinutes || nowMinutes < endMinutes;
    } else {
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // iOS Background Handling
  // ────────────────────────────────────────────────────────────────────────────

  void handleAppBackground() {
    debugPrint('BackgroundService: App went to background');
    _isInBackground = true;
    _backgroundStartTime = DateTime.now();
    
    if (Platform.isIOS && _accelSub != null) {
      // On iOS, we have limited background execution time (~30 seconds)
      // Upload data immediately when going to background
      Timer(const Duration(seconds: 5), () {
        debugPrint('BackgroundService: Background time limit approaching, uploading data');
        _uploadBufferedData();
      });
    }
  }

  void handleAppForeground() {
    debugPrint('BackgroundService: App returned to foreground');
    _isInBackground = false;
    
    // Check if we need to restart collection
    if (_backgroundStartTime != null) {
      final backgroundDuration = DateTime.now().difference(_backgroundStartTime!);
      debugPrint('BackgroundService: Was in background for ${backgroundDuration.inMinutes} minutes');
      
      // If we were collecting before and still in shift time, ensure collection is running
      checkSchedule();
    }
  }

  void handleAppTermination() {
    debugPrint('BackgroundService: App terminating');
    if (_accelSub != null) {
      _uploadBufferedData();
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Collection Control
  // ────────────────────────────────────────────────────────────────────────────

  void startCollection() async {
    debugPrint('BackgroundService: startCollection called');
    _currentSessionStart = DateTime.now().toUtc();
    _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}_${_storage.deviceId}';
    debugPrint('🔔 [BackgroundService] START at $_currentSessionStart');

    // Request permissions before starting
    final hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      debugPrint('BackgroundService: Insufficient permissions, cannot start collection');
      return;
    }

    // Create session document in Firestore
    await _createSessionDocument();

    // Accelerometer (~10 Hz default) - Note: Barometer not available in sensors_plus 4.0.2
    try {
      _accelSub = accelerometerEventStream().listen(
        (AccelerometerEvent e) {
          debugPrint('BackgroundService: Accelerometer event: x=${e.x}, y=${e.y}, z=${e.z}');
          _accelBuffer.add({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'x': e.x,
            'y': e.y,
            'z': e.z,
            'created_at': FieldValue.serverTimestamp(),
          });
        },
        onError: (error) {
          debugPrint('BackgroundService: Accelerometer error: $error');
        },
      );
    } catch (e) {
      debugPrint('BackgroundService: Failed to start accelerometer: $e');
    }

    // GPS timing adjusted for iOS
    final gpsInterval = Platform.isIOS ? const Duration(seconds: 60) : const Duration(seconds: 30);
    _gpsTimer = Timer.periodic(gpsInterval, (_) async {
      debugPrint('BackgroundService: GPS timer triggered');
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
        debugPrint('BackgroundService: GPS position: lat=${pos.latitude}, lon=${pos.longitude}');
        _gpsBuffer.add({
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'lat': pos.latitude,
          'lon': pos.longitude,
          'alt': pos.altitude,
          'accuracy': pos.accuracy,
          'created_at': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('BackgroundService: GPS error: $e');
      }
    });

    // Schedule periodic uploads (every 5 minutes)
    _schedulePeriodicUploads();
    debugPrint('BackgroundService: Collection started successfully');
  }

  Future<void> stopCollection() async {
    debugPrint('BackgroundService: stopCollection called');
    debugPrint('🔕 [BackgroundService] STOP at ${DateTime.now().toUtc()}');

    _accelSub?.cancel();
    _accelSub = null;
    _gpsTimer?.cancel();
    _gpsTimer = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;

    try {
      await _uploadBufferedData();
      await _updateSessionEndTime();
      debugPrint('BackgroundService: Final data uploaded and session closed');
    } catch (e) {
      debugPrint('❌ Final upload failed: $e');
    }

    _currentSessionStart = null;
    _currentSessionId = null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Firestore Operations
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _createSessionDocument() async {
    if (_currentSessionId == null) return;

    try {
      await _firestore.collection('sessions').doc(_currentSessionId).set({
        'session_id': _currentSessionId,
        'device_id': _storage.deviceId,
        'platform': Platform.operatingSystem,
        'start_time': _currentSessionStart!.toIso8601String(),
        'end_time': null, // Will be updated when session ends
        'shift_start': _storage.shiftStart,
        'shift_end': _storage.shiftEnd,
        'status': 'active',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('BackgroundService: Session document created: $_currentSessionId');
    } catch (e) {
      debugPrint('BackgroundService: Failed to create session document: $e');
    }
  }

  Future<void> _updateSessionEndTime() async {
    if (_currentSessionId == null) return;

    try {
      await _firestore.collection('sessions').doc(_currentSessionId).update({
        'end_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'completed',
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('BackgroundService: Session document updated with end time');
    } catch (e) {
      debugPrint('BackgroundService: Failed to update session end time: $e');
    }
  }

  /// Upload buffered sensor data to Firestore
  Future<void> _uploadBufferedData() async {
    if (_currentSessionId == null) return;
    
    debugPrint('BackgroundService: _uploadBufferedData called');
    if (_accelBuffer.isEmpty && _gpsBuffer.isEmpty) {
      debugPrint('BackgroundService: All buffers empty, nothing to upload');
      return;
    }

    debugPrint('📤 [BackgroundService] Uploading buffers at ${DateTime.now().toUtc()}');

    try {
      final batch = _firestore.batch();
      final now = DateTime.now();
      final chunkId = 'chunk_${now.millisecondsSinceEpoch}';

      // Create a data chunk document
      final chunkRef = _firestore
          .collection('sessions')
          .doc(_currentSessionId)
          .collection('data_chunks')
          .doc(chunkId);

      batch.set(chunkRef, {
        'chunk_id': chunkId,
        'session_id': _currentSessionId,
        'device_id': _storage.deviceId,
        'chunk_start_time': now.toUtc().toIso8601String(),
        'background_session': _isInBackground,
        'data_counts': {
          'accelerometer': _accelBuffer.length,
          'gps': _gpsBuffer.length,
        },
        'sensor_data': {
          'accelerometer': List.from(_accelBuffer),
          'gps': List.from(_gpsBuffer),
        },
        'created_at': FieldValue.serverTimestamp(),
      });

      // Commit the batch
      await batch.commit();

      debugPrint('✅ Uploaded data chunk: $chunkId');

      // Clear buffers after successful upload
      _accelBuffer.clear();
      _gpsBuffer.clear();
      debugPrint('BackgroundService: Buffers cleared after successful upload');

      // Update session with last activity
      await _firestore.collection('sessions').doc(_currentSessionId).update({
        'last_data_upload': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

    } catch (e) {
      debugPrint('BackgroundService: Error uploading to Firestore: $e');
      
      // Keep data in buffers for retry
      // Optionally: Save to local storage as backup
      await _saveToLocalBackup();
    }
  }

  /// Save data to local file as backup if Firestore upload fails
  Future<void> _saveToLocalBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$fileName');

      final backupData = {
        'session_id': _currentSessionId,
        'device_id': _storage.deviceId,
        'backup_time': DateTime.now().toUtc().toIso8601String(),
        'sensor_data': {
          'accelerometer': List.from(_accelBuffer),
          'gps': List.from(_gpsBuffer),
        },
      };

      await file.writeAsString(jsonEncode(backupData));
      debugPrint('BackgroundService: Data saved to local backup: $fileName');
    } catch (e) {
      debugPrint('BackgroundService: Failed to save local backup: $e');
    }
  }

  /// Schedule periodic uploads every 5 minutes
  void _schedulePeriodicUploads() {
    debugPrint('BackgroundService: _schedulePeriodicUploads called');
    
    // Upload more frequently on iOS due to background limitations
    final uploadInterval = Platform.isIOS ? 
        const Duration(minutes: 3) : 
        const Duration(minutes: 5);
    
    _uploadTimer = Timer.periodic(uploadInterval, (_) {
      debugPrint('BackgroundService: Periodic upload timer triggered');
      if (_accelSub != null && 
          (_accelBuffer.isNotEmpty || _gpsBuffer.isNotEmpty)) {
        _uploadBufferedData();
      }
    });
  }
}