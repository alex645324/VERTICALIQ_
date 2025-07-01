import os
from firebase_admin import initialize_app, firestore, credentials
import firebase_admin

# Initialize Firebase Admin with credentials
cred = credentials.Certificate('serviceAccountKey.json')
initialize_app(cred)

# Get Firestore client
db = firestore.client()

# Define the configuration settings
config_settings = {
    # Dwell time settings
    'defaultHeuristicDwellTime': 240.0,  # 4 minutes default
    'minDwellTime': 10.0,    # 10 seconds minimum
    'maxDwellTime': 7200.0,  # 2 hours maximum
    
    # Blending algorithm parameters
    'confidenceThreshold': 10.0,  # k-factor for confidence calculation
    'movementThreshold': 2.0,     # acceleration magnitude threshold
    'pressureThreshold': 12.0,    # Pascal threshold for floor changes
    
    # System settings
    'version': '1.0.0',
    'environment': 'production',
    'lastUpdated': firestore.SERVER_TIMESTAMP,
    
    # Processing settings
    'sessionProcessingEnabled': True,
    'sensorDataEnabled': True,
    'debugLoggingEnabled': True,
    
    # Feature flags
    'features': {
        'floorChangeDetection': True,
        'movementAnalysis': True,
        'confidenceBasedBlending': True
    }
}

def setup_config():
    try:
        # Set the configuration document
        config_ref = db.collection('config').document('settings')
        config_ref.set(config_settings)
        print('✅ Successfully created config/settings document')
        
        # Verify the document was created
        doc = config_ref.get()
        if doc.exists:
            print('📄 Configuration document contents:')
            doc_data = doc.to_dict()
            for key, value in doc_data.items():
                if key != 'lastUpdated':  # Skip timestamp as it's server-generated
                    print(f'  {key}: {value}')
        else:
            print('❌ Error: Document was not created')
            
    except Exception as e:
        print(f'❌ Error creating configuration: {str(e)}')

if __name__ == '__main__':
    setup_config() 