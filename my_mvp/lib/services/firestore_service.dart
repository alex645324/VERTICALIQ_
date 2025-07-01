import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/building_profile.dart';
import '../models/session.dart';
import 'dwell_time_calculator.dart';

class FirestoreService {
  final FirebaseFirestore firestore;
  final DwellTimeCalculator dwellTimeCalculator;

  FirestoreService({
    FirebaseFirestore? firestore,
    DwellTimeCalculator? calculator,
  }) : firestore = firestore ?? FirebaseFirestore.instance,
       dwellTimeCalculator = calculator ?? DwellTimeCalculatorFactory.createCalculator();

  FirestoreService.withFirestore(this.firestore) 
      : dwellTimeCalculator = DwellTimeCalculatorFactory.createCalculator();

  /// Calculates the blended dwell time using confidence-based weighting
  /// visitCount: number of visits recorded
  /// heuristicTime: initial estimate (240s)
  /// liveAverage: actual average from recorded visits
  double calculateBlendedDwellTime(int visitCount, double heuristicTime, double liveAverage) {
    // k factor determines how quickly we transition from heuristic to live data
    // higher k = slower transition
    const double k = 10.0;
    
    // Calculate confidence (0 to 1) based on visit count
    final confidence = visitCount / (visitCount + k);
    
    // Blend between heuristic and live average based on confidence
    return heuristicTime * (1 - confidence) + liveAverage * confidence;
  }

  // Initial seed data
  Future<void> seedInitialData() async {
    // Seed pilot buildings
    await firestore.doc('config/pilotBuildings').set({
      'buildings': [
        'test-building-1',
        'test-building-2',
        'test-building-3',
      ]
    });

    // Seed baseline config
    await firestore.doc('config/baseline').set({
      'dwellTimeSeconds': 300.0,
      'blendingThreshold': 10,
    });

    // Seed building profiles
    final buildings = [
      BuildingProfile(
        buildingId: 'test-building-1',
        address: '123 Test St, NYC',
        heuristicDwellTime: 240.0,
        blendedDwellTime: 240.0,
      ),
      BuildingProfile(
        buildingId: 'test-building-2',
        address: '456 Test Ave, NYC',
        heuristicDwellTime: 180.0,
        blendedDwellTime: 180.0,
      ),
      BuildingProfile(
        buildingId: 'test-building-3',
        address: '789 Test Blvd, NYC',
        heuristicDwellTime: 300.0,
        blendedDwellTime: 300.0,
      ),
    ];

    // Create building profiles
    for (var building in buildings) {
      await firestore
          .doc('profiles/${building.buildingId}')
          .set(building.toMap());
    }
  }

  // Get building profile
  Future<BuildingProfile?> getBuildingProfile(String buildingId) async {
    final doc = await firestore.doc('profiles/$buildingId').get();
    if (!doc.exists) return null;
    return BuildingProfile.fromMap(doc.data()!);
  }

  // Get all pilot buildings
  Future<List<String>> getPilotBuildings() async {
    final doc = await firestore.doc('config/pilotBuildings').get();
    return List<String>.from(doc.data()?['buildings'] ?? []);
  }

  /// Updates building profile with new session data
  Future<void> _updateBuildingProfile(String buildingId, Session session) async {
    final profileRef = firestore.doc('profiles/$buildingId');
    
    await firestore.runTransaction((transaction) async {
      final profileDoc = await transaction.get(profileRef);
      
      if (!profileDoc.exists) {
        throw Exception('Building profile not found');
      }
      
      final profile = BuildingProfile.fromMap(profileDoc.data()!);
      
      // Update visit count and recalculate live average
      final newVisitCount = profile.visitCount + 1;
      final currentLiveAvg = profile.liveAvgDwellTime ?? profile.heuristicDwellTime;
      final newLiveAvg = ((currentLiveAvg * profile.visitCount) + session.dwellSeconds) / newVisitCount;
      
      // Calculate new blended time using the configured calculator
      final newBlendedTime = dwellTimeCalculator.calculateBlendedDwellTime(
        newVisitCount,
        profile.heuristicDwellTime,
        newLiveAvg
      );
      
      transaction.update(profileRef, {
        'visitCount': newVisitCount,
        'liveAvgDwellTime': newLiveAvg,
        'blendedDwellTime': newBlendedTime,
      });
    });
  }

  // Create a new session and update building profile
  Future<void> createSession(Session session) async {
    await firestore.runTransaction((transaction) async {
      // First, do all reads
      final profileRef = firestore.doc('profiles/${session.buildingId}');
      final profileDoc = await transaction.get(profileRef);
      
      if (!profileDoc.exists) {
        throw Exception('Building profile not found');
      }

      final profile = BuildingProfile.fromMap(profileDoc.data()!);

      // Calculate new metrics
      final newVisitCount = profile.visitCount + 1;
      final totalDwellSeconds = (profile.liveAvgDwellTime ?? 0) * profile.visitCount + session.dwellSeconds;
      final newLiveAvgDwellTime = totalDwellSeconds / newVisitCount;

      // Calculate new blended time using confidence-based approach
      final newBlendedDwellTime = calculateBlendedDwellTime(
        newVisitCount,
        profile.heuristicDwellTime,
        newLiveAvgDwellTime
      );

      // Now do all writes
      final sessionRef = firestore.doc('sessions/${session.sessionId}');
      transaction.set(sessionRef, session.toMap());
      
      transaction.update(profileRef, {
        'visitCount': newVisitCount,
        'liveAvgDwellTime': newLiveAvgDwellTime,
        'blendedDwellTime': newBlendedDwellTime,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  // Get all sessions for a building
  Future<List<Session>> getBuildingSessions(String buildingId) async {
    final querySnapshot = await firestore
        .collection('sessions')
        .where('buildingId', isEqualTo: buildingId)
        .orderBy('startTime', descending: true)
        .get();

    return querySnapshot.docs
        .map((doc) => Session.fromMap(doc.data()))
        .toList();
  }

  // Get recent sessions for testing
  Future<List<Session>> getRecentSessions({int limit = 10}) async {
    final querySnapshot = await firestore
        .collection('sessions')
        .orderBy('startTime', descending: true)
        .limit(limit)
        .get();

    return querySnapshot.docs
        .map((doc) => Session.fromMap(doc.data()))
        .toList();
  }

  // Get baseline config
  Future<Map<String, dynamic>> getBaselineConfig() async {
    final doc = await firestore.doc('config/baseline').get();
    return doc.data() ?? {
      'dwellTimeSeconds': 300.0,
      'blendingThreshold': 10,
    };
  }
} 