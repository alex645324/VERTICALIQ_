from typing import Dict
from pluto_service import PlutoService

class BuildingProfileService:
    """Service for managing building profiles with PLUTO integration."""
    
    def __init__(self):
        """Initialize the building profile service."""
        self.pluto_service = PlutoService()
    
    def create_building_profile(self, building_id: str, address: str, zip_code: str) -> Dict:
        """Create a new building profile with smart baseline from PLUTO.
        
        Args:
            building_id: Unique identifier for the building
            address: Street address
            zip_code: ZIP code
            
        Returns:
            Dict containing the building profile data
        """
        # Get smart baseline from PLUTO (falls back to 240.0 if unavailable)
        pluto_baseline = self.pluto_service.get_pluto_baseline(address, zip_code)
        
        # Create profile with smart baseline
        profile = {
            "buildingId": building_id,
            "address": address,
            "zipCode": zip_code,
            "heuristicDwellTime": pluto_baseline,  # Smart baseline from PLUTO
            "visitCount": 0,
            "totalDwellTime": 0.0,
            "averageDwellTime": 0.0,
            "lastUpdated": None
        }
        
        return profile
    
    def update_profile_stats(self, profile: Dict, dwell_time: float) -> Dict:
        """Update profile statistics with a new dwell time measurement.
        
        Args:
            profile: Existing building profile
            dwell_time: New dwell time measurement in seconds
            
        Returns:
            Updated building profile
        """
        # Increment visit count
        profile["visitCount"] += 1
        
        # Update total and average
        profile["totalDwellTime"] += dwell_time
        profile["averageDwellTime"] = profile["totalDwellTime"] / profile["visitCount"]
        
        # Calculate confidence (k=10 for smooth transition)
        k = 10
        confidence = profile["visitCount"] / (profile["visitCount"] + k)
        
        # Blend between heuristic and live average
        heuristic = profile["heuristicDwellTime"]
        live_avg = profile["averageDwellTime"]
        
        # Final dwell time is weighted average
        profile["currentDwellTime"] = (heuristic * (1 - confidence)) + (live_avg * confidence)
        
        return profile 