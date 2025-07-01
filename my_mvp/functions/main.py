# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

from firebase_functions import firestore_fn
from firebase_admin import initialize_app, firestore
import firebase_admin
import math
from typing import Dict, Any, Optional, Tuple
from datetime import datetime

# Initialize Firebase Admin
initialize_app()

def validate_session(session: Dict[str, Any]) -> Tuple[bool, Optional[str]]:
    """Validates the session data for required fields and reasonable values."""
    
    # Check required fields
    required_fields = ['buildingId', 'startTime', 'endTime', 'userId', 'userType']
    for field in required_fields:
        if field not in session:
            return False, f"Missing required field: {field}"
    
    # Validate userType
    valid_user_types = ['friend', 'carrier', 'admin']
    if session['userType'] not in valid_user_types:
        return False, f"Invalid userType. Must be one of: {', '.join(valid_user_types)}"
    
    # Check dwell time is reasonable (between 10 seconds and 2 hours)
    dwell_seconds = session.get('dwellSeconds', 0)
    if dwell_seconds < 10 or dwell_seconds > 7200:
        return False, "Unrealistic dwell time"
    
    # Skip timestamp validation for server timestamps
    if session['startTime'] == firestore.SERVER_TIMESTAMP or session['endTime'] == firestore.SERVER_TIMESTAMP:
        return True, None
    
    # Check start time is before end time
    if session['startTime'] >= session['endTime']:
        return False, "Invalid time sequence"
    
    return True, None

def process_accelerometer_data(data: list) -> Dict[str, Any]:
    """Process accelerometer data to detect movement patterns."""
    if not data:
        return {"movementDetected": False, "confidence": 0}
    
    movement_count = 0
    total_readings = len(data)
    
    for i in range(1, len(data)):
        prev = data[i-1]
        curr = data[i]
        
        # Calculate acceleration magnitude change
        prev_mag = math.sqrt(prev['x']**2 + prev['y']**2 + prev['z']**2)
        curr_mag = math.sqrt(curr['x']**2 + curr['y']**2 + curr['z']**2)
        
        # If significant change, count as movement
        if abs(curr_mag - prev_mag) > 2.0:
            movement_count += 1
    
    movement_ratio = movement_count / total_readings
    return {
        "movementDetected": movement_ratio > 0.1,
        "confidence": movement_ratio,
        "totalReadings": total_readings
    }

def process_barometer_data(data: list) -> Dict[str, Any]:
    """Process barometer readings to detect floor changes."""
    if not data:
        return {"floorChanges": 0, "confidence": 0}
    
    floor_changes = 0
    pressure_threshold = 12.0  # Pascal threshold for floor change
    
    for i in range(1, len(data)):
        pressure_diff = abs(data[i]['pressure'] - data[i-1]['pressure'])
        if pressure_diff > pressure_threshold:
            floor_changes += 1
    
    return {
        "floorChanges": floor_changes,
        "confidence": 0.8 if len(data) > 10 else 0.4,
        "totalReadings": len(data)
    }

def calculate_refined_dwell_time(base_dwell_time: float, movement_data: Dict[str, Any], floor_data: Dict[str, Any]) -> float:
    """Calculate refined dwell time using sensor data."""
    adjusted_time = base_dwell_time
    
    # If significant movement detected, might indicate walking between floors
    if movement_data["movementDetected"] and movement_data["confidence"] > 0.3:
        # Add time for movement between floors (estimated 30s per floor change)
        adjusted_time += floor_data["floorChanges"] * 30
    
    # Ensure reasonable bounds
    return max(10, min(adjusted_time, 7200))

def calculate_confidence_based_blending(visit_count: int, heuristic_time: float, live_avg: Optional[float]) -> float:
    """Calculate the confidence-based blend between heuristic and live data."""
    if visit_count == 0 or live_avg is None:
        return heuristic_time
    
    k = 10.0  # Confidence parameter
    confidence = visit_count / (visit_count + k)
    
    blended = (heuristic_time * (1 - confidence)) + (live_avg * confidence)
    print(f"🧮 Blending: {visit_count} visits, {confidence*100:.1f}% confidence → {blended:.1f}s")
    
    return blended

@firestore.transactional
def update_building_profile_transaction(transaction, db, building_id: str, session: Dict[str, Any], processed_dwell_time: float):
    """Update building profile with new session data using a transaction."""
    profile_ref = db.collection('profiles').document(building_id)
    profile_doc = profile_ref.get(transaction=transaction)
    
    if not profile_doc.exists:
        # Create new profile if doesn't exist
        profile = {
            'buildingId': building_id,
            'address': session.get('address', 'Unknown Address'),
            'heuristicDwellTime': 240.0,  # 4 minutes default
            'liveAvgDwellTime': None,
            'blendedDwellTime': 240.0,
            'visitCount': 0,
            'totalDwellSeconds': 0,
            'createdAt': firestore.SERVER_TIMESTAMP,
            'lastUpdated': firestore.SERVER_TIMESTAMP
        }
    else:
        profile = profile_doc.to_dict()
    
    # Update visit statistics
    new_visit_count = profile['visitCount'] + 1
    new_total_dwell_seconds = profile.get('totalDwellSeconds', 0) + processed_dwell_time
    new_live_avg_dwell_time = new_total_dwell_seconds / new_visit_count
    
    # Calculate blended dwell time
    new_blended_dwell_time = calculate_confidence_based_blending(
        new_visit_count,
        profile['heuristicDwellTime'],
        new_live_avg_dwell_time
    )
    
    # Update profile
    profile.update({
        'visitCount': new_visit_count,
        'totalDwellSeconds': new_total_dwell_seconds,
        'liveAvgDwellTime': new_live_avg_dwell_time,
        'blendedDwellTime': new_blended_dwell_time,
        'lastUpdated': firestore.SERVER_TIMESTAMP
    })
    
    transaction.set(profile_ref, profile, merge=True)
    print(f"📊 Updated profile for {building_id}: {new_visit_count} visits, {new_blended_dwell_time:.1f}s avg")

@firestore.transactional
def update_user_stats_transaction(transaction, db, user_id: str, session_data: Dict[str, Any], processed_dwell_time: float):
    """Update user statistics with new session data using a transaction."""
    user_ref = db.collection('users').document(user_id)
    user_doc = user_ref.get(transaction=transaction)
    
    if not user_doc.exists:
        # Create new user stats if doesn't exist
        user_stats = {
            'userId': user_id,
            'userType': session_data['userType'],
            'totalSessions': 1,
            'totalDwellSeconds': processed_dwell_time,
            'avgDwellTime': processed_dwell_time,
            'firstSessionAt': firestore.SERVER_TIMESTAMP,
            'lastSessionAt': firestore.SERVER_TIMESTAMP,
            'createdAt': firestore.SERVER_TIMESTAMP,
            'lastUpdated': firestore.SERVER_TIMESTAMP
        }
    else:
        user_stats = user_doc.to_dict()
        # Update existing user stats
        total_sessions = user_stats['totalSessions'] + 1
        total_dwell_seconds = user_stats['totalDwellSeconds'] + processed_dwell_time
        
        user_stats.update({
            'totalSessions': total_sessions,
            'totalDwellSeconds': total_dwell_seconds,
            'avgDwellTime': total_dwell_seconds / total_sessions,
            'lastSessionAt': firestore.SERVER_TIMESTAMP,
            'lastUpdated': firestore.SERVER_TIMESTAMP
        })
    
    transaction.set(user_ref, user_stats, merge=True)
    print(f"👤 Updated stats for user {user_id}: {user_stats['totalSessions']} sessions, {user_stats['avgDwellTime']:.1f}s avg")

@firestore_fn.on_document_created(document="sessions/{sessionId}")
def on_session_create(event: firestore_fn.Event[firestore_fn.DocumentSnapshot]) -> None:
    """Process new sessions when they are created."""
    try:
        print('🔥 New session created! Starting processing...')
        
        session = event.data.to_dict()
        if not session:
            print("❌ Error: Session data is empty")
            return
            
        session_id = event.data.reference.id
        db = firestore.client()
        
        # Step 1: Validate the session data
        is_valid, error_reason = validate_session(session)
        if not is_valid:
            print(f"❌ Invalid session {session_id}: {error_reason}")
            db.collection('sessions').document(session_id).set({
                'processingStatus': 'invalid',
                'invalidReason': error_reason,
                'processedAt': firestore.SERVER_TIMESTAMP
            }, merge=True)
            return
        
        # Step 2: Process sensor data if available
        processed_dwell_time = session['dwellSeconds']
        if session.get('accelerometerData') or session.get('barometerData'):
            movement_data = process_accelerometer_data(session.get('accelerometerData', []))
            floor_data = process_barometer_data(session.get('barometerData', []))
            processed_dwell_time = calculate_refined_dwell_time(
                session['dwellSeconds'],
                movement_data,
                floor_data
            )
            print(f"📊 Refined dwell time: {session['dwellSeconds']}s → {processed_dwell_time}s")
        
        # Step 3: Update the session with processed data
        db.collection('sessions').document(session_id).set({
            'processedDwellTime': processed_dwell_time,
            'processedAt': firestore.SERVER_TIMESTAMP,
            'processingStatus': 'completed'
        }, merge=True)
        
        # Step 4: Update building profile using transaction
        transaction = db.transaction()
        update_building_profile_transaction(transaction, db, session['buildingId'], session, processed_dwell_time)
        
        # Step 5: Update user statistics using transaction
        transaction = db.transaction()
        update_user_stats_transaction(transaction, db, session['userId'], session, processed_dwell_time)
        
        print(f"✅ Successfully processed session {session_id}")
        
    except Exception as e:
        print(f"❌ Error processing session {event.data.reference.id}:", str(e))
        db = firestore.client()
        db.collection('sessions').document(event.data.reference.id).set({
            'processingStatus': 'error',
            'errorMessage': str(e),
            'processedAt': firestore.SERVER_TIMESTAMP
        }, merge=True)