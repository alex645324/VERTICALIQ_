// lib/services/storage_service.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class StorageService extends ChangeNotifier {
  static late SharedPreferences _prefs;

  // Keys for SharedPreferences
  static const String _kShiftStartKey = 'shift_start';
  static const String _kShiftEndKey = 'shift_end';
  static const String _kDeviceIdKey = 'device_id';

  /// Call this once at app startup
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get the saved shift start time as a string "HH:mm", or null if none
  String? get shiftStart => _prefs.getString(_kShiftStartKey);

  /// Get the saved shift end time as a string "HH:mm", or null if none
  String? get shiftEnd => _prefs.getString(_kShiftEndKey);

  /// Get shift start as TimeOfDay for easier comparison
  TimeOfDay? get shiftStartTOD {
    final start = shiftStart;
    print('StorageService: shiftStartTOD getter called, value = $start');
    if (start == null) return null;
    final parts = start.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Get shift end as TimeOfDay for easier comparison
  TimeOfDay? get shiftEndTOD {
    final end = shiftEnd;
    print('StorageService: shiftEndTOD getter called, value = $end');
    if (end == null) return null;
    final parts = end.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Get or generate device ID
  String get deviceId {
    String? id = _prefs.getString(_kDeviceIdKey);
    if (id == null) {
      print('StorageService: Generating new deviceId');
      // Generate a simple device ID
      id = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
      _prefs.setString(_kDeviceIdKey, id);
    }
    print('StorageService: deviceId getter called, value = $id');
    return id;
  }

  /// Save a new shift start time ("HH:mm")
  Future<void> setShiftStart(String time) async {
    print('StorageService: setShiftStart called with $time');
    await _prefs.setString(_kShiftStartKey, time);
    notifyListeners();
  }

  /// Save a new shift end time ("HH:mm")
  Future<void> setShiftEnd(String time) async {
    print('StorageService: setShiftEnd called with $time');
    await _prefs.setString(_kShiftEndKey, time);
    notifyListeners();
  }

  /// Clear both shift start and end
  Future<void> clearSchedule() async {
    print('StorageService: clearSchedule called');
    await _prefs.remove(_kShiftStartKey);
    await _prefs.remove(_kShiftEndKey);
    notifyListeners();
  }
}