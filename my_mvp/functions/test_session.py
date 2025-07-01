import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta
import random
import os
import time
import math

# Initialize Firebase Admin with credentials
cred = credentials.Certificate(os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json'))
firebase_admin.initialize_app(cred)

# Create a Firestore client
db = firestore.client()

# Create sample accelerometer data (simulating walking and stopping)
def generate_accelerometer_data():
    data = []
    # Generate 60 seconds of data at 1Hz
    for i in range(60):
        if 20 <= i <= 30:  # Simulate movement between 20-30 seconds
            # Add some random movement
            data.append({
                'x': random.uniform(-2.0, 2.0),
                'y': random.uniform(-2.0, 2.0),
                'z': random.uniform(9.0, 11.0),  # Mostly gravity + movement
                'timestamp': i
            })
        else:
            # Relatively still
            data.append({
                'x': random.uniform(-0.1, 0.1),
                'y': random.uniform(-0.1, 0.1),
                'z': random.uniform(9.8, 9.9),  # Mostly just gravity
                'timestamp': i
            })
    return data

# Create sample barometer data (simulating floor changes)
def generate_barometer_data():
    data = []
    base_pressure = 1013.25  # Standard atmospheric pressure in hPa
    
    # Generate 60 seconds of data at 1Hz
    for i in range(60):
        if 20 <= i <= 25:  # Simulate going up one floor
            pressure = base_pressure - (i - 20) * 0.3
        elif 25 < i <= 30:  # Stabilize at new floor
            pressure = base_pressure - 1.5
        else:
            pressure = base_pressure + random.uniform(-0.1, 0.1)
            
        data.append({
            'pressure': pressure,
            'timestamp': i
        })
    return data

# Create a test session
def create_test_session():
    # Create sample sensor data
    accelerometer_data = []
    barometer_data = []
    
    # Current time for timestamps
    now = datetime.now()
    start_time = now - timedelta(minutes=1)  # Session started 1 minute ago
    
    # Generate 30 seconds of accelerometer data (1 reading per second)
    for i in range(30):
        # Add some random movement
        accelerometer_data.append({
            'x': random.uniform(-0.5, 0.5),
            'y': random.uniform(-0.5, 0.5),
            'z': random.uniform(9.5, 10.5),  # Mostly gravity
            'timestamp': time.time() + i
        })
        
        # Add some random pressure data
        barometer_data.append({
            'pressure': 101325 + random.uniform(-10, 10),  # Around 1 atm
            'timestamp': time.time() + i
        })
    
    # Create test session document
    session_data = {
        'buildingId': 'test_building_123',
        'userId': 'test_user_456',
        'userType': 'friend',
        'startTime': start_time,
        'endTime': now,
        'dwellSeconds': 60,
        'accelerometerData': accelerometer_data,
        'barometerData': barometer_data,
        'createdAt': firestore.SERVER_TIMESTAMP
    }
    
    # Add to Firestore
    doc_ref = db.collection('sessions').document()
    doc_ref.set(session_data)
    
    print(f'Created test session with ID: {doc_ref.id}')
    print('Test session created successfully!')
    print('The cloud function should process this automatically.')
    print('Check the Firebase Console logs for processing details.')

if __name__ == '__main__':
    create_test_session() 