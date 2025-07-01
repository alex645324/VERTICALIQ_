from firebase_admin import initialize_app, firestore, credentials
import firebase_admin
import json

# Initialize Firebase Admin with credentials
cred = credentials.Certificate('serviceAccountKey.json')
initialize_app(cred)

# Get Firestore client
db = firestore.client()

def create_indexes():
    print('🔍 Creating Firestore indexes...')
    
    # Define the indexes we need
    indexes = {
        'sessions': [
            {
                'collectionId': 'sessions',
                'fields': [
                    {'fieldPath': 'userId', 'order': 'ASCENDING'},
                    {'fieldPath': 'startTime', 'order': 'DESCENDING'}
                ]
            },
            {
                'collectionId': 'sessions',
                'fields': [
                    {'fieldPath': 'buildingId', 'order': 'ASCENDING'},
                    {'fieldPath': 'startTime', 'order': 'DESCENDING'}
                ]
            }
        ]
    }
    
    print('\n📝 Required indexes:')
    print('1. sessions(userId: ASC, startTime: DESC)')
    print('2. sessions(buildingId: ASC, startTime: DESC)')
    
    print('\n⚠️ Note: Indexes must be created manually in the Firebase Console.')
    print('Follow these steps:')
    print('1. Go to Firebase Console → Firestore Database → Indexes tab')
    print('2. Click "Add Index"')
    print('3. Create each index with the fields shown above')
    print('4. Wait for indexes to build (may take a few minutes)')
    
    # Save indexes definition to a file for reference
    with open('firestore.indexes.json', 'w') as f:
        json.dump({'indexes': indexes['sessions']}, f, indent=2)
    print('\n✅ Created firestore.indexes.json for reference')

if __name__ == '__main__':
    create_indexes() 