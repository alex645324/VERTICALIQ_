import pytest
from unittest.mock import Mock, patch
from building_profile import BuildingProfileService

@pytest.fixture
def building_service():
    """Create a BuildingProfileService instance."""
    return BuildingProfileService()

@patch('pluto_service.PlutoService.get_pluto_baseline')
def test_create_building_profile_with_pluto(mock_get_baseline, building_service):
    """Test building profile creation with PLUTO baseline."""
    # Mock PLUTO baseline
    mock_get_baseline.return_value = 300.0  # Large residential building
    
    profile = building_service.create_building_profile(
        "test-building-1",
        "350 5th Avenue",
        "10118"
    )
    
    assert profile["buildingId"] == "test-building-1"
    assert profile["address"] == "350 5th Avenue"
    assert profile["zipCode"] == "10118"
    assert profile["heuristicDwellTime"] == 300.0
    assert profile["visitCount"] == 0
    assert profile["totalDwellTime"] == 0.0
    assert profile["averageDwellTime"] == 0.0
    assert profile["lastUpdated"] is None

def test_update_profile_stats(building_service):
    """Test profile statistics update with confidence-based blending."""
    # Create initial profile with 240s baseline
    profile = {
        "buildingId": "test-building-2",
        "address": "123 Test St",
        "zipCode": "10001",
        "heuristicDwellTime": 240.0,
        "visitCount": 0,
        "totalDwellTime": 0.0,
        "averageDwellTime": 0.0,
        "lastUpdated": None
    }
    
    # Test first visit (low confidence)
    updated = building_service.update_profile_stats(profile, 180.0)
    assert updated["visitCount"] == 1
    assert updated["totalDwellTime"] == 180.0
    assert updated["averageDwellTime"] == 180.0
    # With k=10, confidence should be 1/11 ≈ 0.091
    # Blended time = 240 * (1 - 0.091) + 180 * 0.091 ≈ 234.6
    assert abs(updated["currentDwellTime"] - 234.6) < 0.1
    
    # Test after 10 visits (medium confidence)
    for _ in range(9):
        profile = building_service.update_profile_stats(profile, 180.0)
    
    assert profile["visitCount"] == 10
    assert abs(profile["averageDwellTime"] - 180.0) < 0.1
    # With k=10, confidence should be 10/20 = 0.5
    # Blended time = 240 * 0.5 + 180 * 0.5 = 210
    assert abs(profile["currentDwellTime"] - 210.0) < 0.1
    
    # Test after 50 visits (high confidence)
    for _ in range(40):
        profile = building_service.update_profile_stats(profile, 180.0)
    
    assert profile["visitCount"] == 50
    assert abs(profile["averageDwellTime"] - 180.0) < 0.1
    # With k=10, confidence should be 50/60 ≈ 0.833
    # Blended time = 240 * (1 - 0.833) + 180 * 0.833 ≈ 190
    assert abs(profile["currentDwellTime"] - 190.0) < 0.1

@patch('pluto_service.PlutoService.get_pluto_baseline')
def test_create_building_profile_pluto_error(mock_get_baseline, building_service):
    """Test building profile creation when PLUTO fails."""
    # Mock PLUTO error/default
    mock_get_baseline.return_value = 240.0  # Default fallback
    
    profile = building_service.create_building_profile(
        "test-building-3",
        "Invalid Address",
        "12345"  # Invalid ZIP
    )
    
    assert profile["heuristicDwellTime"] == 240.0  # Should use default 