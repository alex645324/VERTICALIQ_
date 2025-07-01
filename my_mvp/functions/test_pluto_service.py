import pytest
from unittest.mock import Mock, patch
from pluto_service import PlutoService

@pytest.fixture
def pluto_service():
    """Create a PlutoService instance."""
    return PlutoService()

@pytest.fixture
def sample_building_data():
    """Sample PLUTO API response data."""
    return {
        "borough": "1",
        "block": "00847",
        "lot": "0033",
        "landuse": "04",  # Multi-Family Elevator
        "unitsres": "200",
        "unitstotal": "220",
        "bldgarea": "150000",
        "house_number": "350",
        "street_name": "5 AVENUE",
        "zip_code": "10118"
    }

@patch('requests.get')
def test_get_pluto_baseline_success(mock_get, pluto_service, sample_building_data):
    """Test successful baseline time retrieval."""
    # Mock successful API response
    mock_response = Mock()
    mock_response.json.return_value = [sample_building_data]
    mock_get.return_value = mock_response
    
    result = pluto_service.get_pluto_baseline("350 5th Avenue", "10118")
    
    # Base time 240s * 1.5 for large building
    assert result == 360.0
    assert mock_get.called

@patch('requests.get')
def test_get_pluto_baseline_non_manhattan(mock_get, pluto_service):
    """Test fallback for non-Manhattan ZIP codes."""
    result = pluto_service.get_pluto_baseline("123 Main St", "11201")  # Brooklyn ZIP
    
    assert result == 240.0  # Default fallback
    assert not mock_get.called

@patch('requests.get')
def test_get_pluto_baseline_api_error(mock_get, pluto_service):
    """Test fallback when API fails."""
    mock_get.side_effect = Exception("API Error")
    
    result = pluto_service.get_pluto_baseline("350 5th Avenue", "10118")
    
    assert result == 240.0  # Default fallback
    assert mock_get.called

def test_building_type_dwell_times(pluto_service):
    """Test dwell time estimation for different building types."""
    
    # Test single family residential
    single_family = {
        "landuse": "01",
        "unitsres": "1",
        "unitstotal": "1",
        "bldgarea": "2000"
    }
    time = pluto_service._estimate_dwell_time(single_family)
    # Base time 180s * 0.75 for small building
    assert time == 135.0
    
    # Test large office building
    office = {
        "landuse": "06",
        "unitsres": "0",
        "unitstotal": "150",
        "bldgarea": "200000"
    }
    time = pluto_service._estimate_dwell_time(office)
    # Base time 120s * 1.5 for large building
    assert time == 180.0
    
    # Test mixed use building
    mixed = {
        "landuse": "05",
        "unitsres": "50",
        "unitstotal": "60",
        "bldgarea": "50000"
    }
    time = pluto_service._estimate_dwell_time(mixed)
    # Base time 240s (no size adjustment)
    assert time == 240.0
    
    # Test small retail
    retail = {
        "landuse": "07",
        "unitsres": "0",
        "unitstotal": "1",
        "bldgarea": "2000"
    }
    time = pluto_service._estimate_dwell_time(retail)
    # Base time 120s * 0.75 for small building
    assert time == 90.0

def test_size_based_adjustments(pluto_service):
    """Test building size-based time adjustments."""
    
    # Test base building type
    base_building = {
        "landuse": "04",  # Multi-Family Elevator
        "unitsres": "50",
        "unitstotal": "50",
        "bldgarea": "50000"
    }
    base_time = pluto_service._estimate_dwell_time(base_building)
    assert base_time == 240.0  # No adjustment
    
    # Test large building adjustment
    large_building = {
        "landuse": "04",
        "unitsres": "150",
        "unitstotal": "150",
        "bldgarea": "150000"
    }
    large_time = pluto_service._estimate_dwell_time(large_building)
    assert large_time == 360.0  # 1.5x adjustment
    
    # Test small building adjustment
    small_building = {
        "landuse": "04",
        "unitsres": "3",
        "unitstotal": "3",
        "bldgarea": "2000"
    }
    small_time = pluto_service._estimate_dwell_time(small_building)
    assert small_time == 180.0  # 0.75x adjustment

def test_error_handling(pluto_service):
    """Test error handling in dwell time estimation."""
    
    # Test with invalid data
    invalid_data = {
        "landuse": "02",
        "unitsres": "invalid",  # Will cause int conversion error
        "unitstotal": "invalid",
        "bldgarea": "invalid"
    }
    time = pluto_service._estimate_dwell_time(invalid_data)
    assert time == 240.0  # Default fallback 