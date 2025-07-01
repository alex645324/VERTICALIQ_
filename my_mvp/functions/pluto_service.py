import requests
from typing import Dict, Optional
import logging
from urllib.parse import quote

class PlutoService:
    """Service for interacting with NYC PLUTO API to fetch Manhattan building data."""
    
    BASE_URL = "https://data.cityofnewyork.us/resource/64uk-42ks.json"
    
    # Simple building type base times (in seconds)
    BUILDING_TYPES = {
        # Residential
        "01": 180,  # Single Family
        "02": 180,  # Two Family
        "03": 240,  # Multi-Family Walkup
        "04": 240,  # Multi-Family Elevator
        # Mixed Use
        "05": 240,  # Mixed Use
        # Commercial
        "06": 120,  # Office Buildings
        "07": 120,  # Retail
        "08": 90,   # Storage/Warehouse
        "09": 120,  # Other Commercial
        # Industrial
        "10": 90,   # Industrial
        "11": 90    # Manufacturing
    }
    
    def __init__(self):
        """Initialize the PLUTO service."""
        self.logger = logging.getLogger(__name__)
    
    def get_pluto_baseline(self, address: str, zip_code: str) -> float:
        """Get baseline dwell time for an address using PLUTO data.
        
        Args:
            address: Street address
            zip_code: ZIP code to validate Manhattan location
            
        Returns:
            float: Baseline dwell time in seconds (240.0 if PLUTO data unavailable)
        """
        try:
            # Validate Manhattan ZIP code (10001-10282)
            if not (10001 <= int(zip_code) <= 10282):
                self.logger.info(f"Non-Manhattan ZIP code: {zip_code}, using default baseline")
                return 240.0
            
            # For MVP, use simplified building type mapping based on ZIP code zones
            # Financial District/Downtown (10004-10007, 10038, 10280)
            if zip_code in ['10004', '10005', '10006', '10007', '10038', '10280']:
                return 120.0  # Commercial area
            
            # Midtown (10001, 10016-10019, 10022, 10036)
            if zip_code in ['10001', '10016', '10017', '10018', '10019', '10022', '10036']:
                return 120.0  # Commercial area
            
            # Upper East Side (10021, 10028, 10044, 10065, 10075, 10128)
            if zip_code in ['10021', '10028', '10044', '10065', '10075', '10128']:
                return 240.0  # Residential area
            
            # Upper West Side (10023-10025, 10069)
            if zip_code in ['10023', '10024', '10025', '10069']:
                return 240.0  # Residential area
            
            # Chelsea/Greenwich Village (10011, 10012, 10014)
            if zip_code in ['10011', '10012', '10014']:
                return 180.0  # Mixed area
            
            # Default to mixed-use timing
            return 180.0
            
        except Exception as e:
            self.logger.error(f"Error processing address: {str(e)}")
            return 240.0  # Default fallback
    
    def _estimate_dwell_time(self, building_data: Dict) -> float:
        """Estimate baseline dwell time based on building characteristics.
        
        Args:
            building_data: PLUTO data for the building
            
        Returns:
            float: Estimated dwell time in seconds
        """
        try:
            # Get basic building type time
            landuse = building_data.get('landuse', '')
            base_time = self.BUILDING_TYPES.get(landuse, 240.0)
            
            # Simple size adjustment
            units_total = int(building_data.get('unitstotal', 0))
            bldg_area = float(building_data.get('bldgarea', 0))
            
            # Increase time for large buildings
            if units_total > 100 or bldg_area > 100000:
                base_time *= 1.5
            # Decrease time for very small buildings
            elif units_total < 5 or bldg_area < 2500:
                base_time *= 0.75
                
            return base_time
            
        except Exception as e:
            self.logger.error(f"Error estimating dwell time: {str(e)}")
            return 240.0  # Default fallback 