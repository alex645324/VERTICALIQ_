import 'package:cloud_firestore/cloud_firestore.dart';

class Session {
  final String sessionId;
  final String buildingId;
  final DateTime startTime;
  final DateTime endTime;
  final int dwellSeconds;
  final String floorCategory; // "bottom", "middle", "top"
  final String userType; // "friend", "carrier"
  final String userId;

  Session({
    required this.sessionId,
    required this.buildingId,
    required this.startTime,
    required this.endTime,
    required this.dwellSeconds,
    required this.floorCategory,
    required this.userType,
    required this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'buildingId': buildingId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'dwellSeconds': dwellSeconds,
      'floorCategory': floorCategory,
      'userType': userType,
      'userId': userId,
    };
  }

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      sessionId: map['sessionId'],
      buildingId: map['buildingId'],
      startTime: (map['startTime'] as Timestamp).toDate(),
      endTime: (map['endTime'] as Timestamp).toDate(),
      dwellSeconds: map['dwellSeconds'],
      floorCategory: map['floorCategory'],
      userType: map['userType'],
      userId: map['userId'],
    );
  }

  // Helper method to calculate dwell time from start and end times
  static int calculateDwellSeconds(DateTime start, DateTime end) {
    return end.difference(start).inSeconds;
  }
} 