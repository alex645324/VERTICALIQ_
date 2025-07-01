import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import '../lib/services/firestore_service.dart';
import '../lib/services/dwell_time_calculator.dart';
import '../lib/models/session.dart';
import '../lib/models/building_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  late FirestoreService firestoreService;
  final testBuildingId = 'test-building-1';

  setUp(() {
    final fakeFirestore = FakeFirebaseFirestore();
    firestoreService = FirestoreService(
      firestore: fakeFirestore,
      calculator: const ConfidenceBasedCalculator(),
    );
  });
  
  group('Session Processing Tests', () {
    test('Create session and verify initial confidence-based blending', () async {
      // 1. First, ensure we have a test building profile
      final initialProfile = BuildingProfile(
        buildingId: testBuildingId,
        address: '123 Test St, NYC',
        heuristicDwellTime: 240.0,
        blendedDwellTime: 240.0,
        visitCount: 0,
      );
      
      await firestoreService.firestore
          .doc('profiles/$testBuildingId')
          .set(initialProfile.toMap());

      // 2. Create a test session with 180 seconds dwell time
      final testSession = Session(
        sessionId: 'test-session-${DateTime.now().millisecondsSinceEpoch}',
        buildingId: testBuildingId,
        startTime: DateTime.now().subtract(Duration(minutes: 3)),
        endTime: DateTime.now(),
        dwellSeconds: 180, // 3 minutes
        floorCategory: 'middle',
        userType: 'friend',
        userId: 'test-user-1',
      );

      // 3. Process the session
      await firestoreService.createSession(testSession);

      // 4. Verify the building profile was updated
      final updatedProfileDoc = await firestoreService.firestore
          .doc('profiles/$testBuildingId')
          .get();
      
      final updatedProfile = BuildingProfile.fromMap(updatedProfileDoc.data()!);

      // 5. Assert the changes
      expect(updatedProfile.visitCount, equals(1));
      expect(updatedProfile.liveAvgDwellTime, equals(180.0));
      
      // With 1 visit and k=10, confidence = 1/(1+10) ≈ 0.091
      // blendedTime = 240 * 0.909 + 180 * 0.091 ≈ 234.5
      expect(updatedProfile.blendedDwellTime, closeTo(234.5, 0.1));
    });

    test('Verify progressive confidence-based blending', () async {
      // 1. Reset the test building profile
      final initialProfile = BuildingProfile(
        buildingId: testBuildingId,
        address: '123 Test St, NYC',
        heuristicDwellTime: 240.0,
        blendedDwellTime: 240.0,
        visitCount: 0,
      );
      
      await firestoreService.firestore
          .doc('profiles/$testBuildingId')
          .set(initialProfile.toMap());

      // 2. Create and process 20 sessions (180 seconds each)
      for (var i = 0; i < 20; i++) {
        final session = Session(
          sessionId: 'test-session-${DateTime.now().millisecondsSinceEpoch}-$i',
          buildingId: testBuildingId,
          startTime: DateTime.now().subtract(Duration(minutes: 3)),
          endTime: DateTime.now(),
          dwellSeconds: 180,
          floorCategory: 'middle',
          userType: 'friend',
          userId: 'test-user-1',
        );

        await firestoreService.createSession(session);
        await Future.delayed(Duration(milliseconds: 100));
      }

      // 3. Verify the final state
      final finalProfileDoc = await firestoreService.firestore
          .doc('profiles/$testBuildingId')
          .get();
      
      final finalProfile = BuildingProfile.fromMap(finalProfileDoc.data()!);

      // 4. Assert the changes
      expect(finalProfile.visitCount, equals(20));
      expect(finalProfile.liveAvgDwellTime, equals(180.0));
      
      // With 20 visits and k=10, confidence = 20/(20+10) ≈ 0.667
      // blendedTime = 240 * 0.333 + 180 * 0.667 ≈ 200.0
      expect(finalProfile.blendedDwellTime, closeTo(200.0, 0.1));
    });

    test('Verify different calculator strategies', () {
      final confidenceCalc = ConfidenceBasedCalculator(kFactor: 10.0);
      final thresholdCalc = ThresholdBasedCalculator(threshold: 10);
      
      // Test confidence-based calculator
      expect(confidenceCalc.calculateBlendedDwellTime(1, 240.0, 180.0), closeTo(234.5, 0.1));
      expect(confidenceCalc.calculateBlendedDwellTime(50, 240.0, 180.0), closeTo(190.0, 0.1));
      
      // Test threshold-based calculator
      expect(thresholdCalc.calculateBlendedDwellTime(5, 240.0, 180.0), equals(240.0));
      expect(thresholdCalc.calculateBlendedDwellTime(15, 240.0, 180.0), equals(180.0));
    });

    test('Verify blending math directly', () {
      // Create a service instance just to access the protected method
      final service = FirestoreService.withFirestore(FakeFirebaseFirestore());

      // Test different visit counts against 240s heuristic and 180s live average
      final results = {
        1: service.calculateBlendedDwellTime(1, 240.0, 180.0),   // Low confidence
        5: service.calculateBlendedDwellTime(5, 240.0, 180.0),   // Some confidence
        10: service.calculateBlendedDwellTime(10, 240.0, 180.0), // Medium confidence
        50: service.calculateBlendedDwellTime(50, 240.0, 180.0), // High confidence
      };

      // Verify progression
      expect(results[1]!, closeTo(234.5, 0.1));  // confidence = 1/11 ≈ 0.091
      expect(results[5]!, closeTo(220.0, 0.1));  // confidence = 5/15 ≈ 0.333
      expect(results[10]!, closeTo(210.0, 0.1)); // confidence = 10/20 = 0.5
      expect(results[50]!, closeTo(190.0, 0.1)); // confidence = 50/60 ≈ 0.833
      
      // Verify ordering
      expect(results[1]!, greaterThan(results[5]!));
      expect(results[5]!, greaterThan(results[10]!));
      expect(results[10]!, greaterThan(results[50]!));
    });

    test('Verify session retrieval', () async {
      // Test getting recent sessions
      final recentSessions = await firestoreService.getRecentSessions(limit: 5);
      expect(recentSessions.length, lessThanOrEqualTo(5));

      // Test getting building sessions
      final buildingSessions = await firestoreService.getBuildingSessions(testBuildingId);
      expect(buildingSessions.every((s) => s.buildingId == testBuildingId), isTrue);
    });
  });
} 