from pluto_service import PlutoService

def test_real_addresses():
    """Test PLUTO service with real Manhattan addresses."""
    pluto = PlutoService()
    
    # Test cases: (address, zip_code, description)
    test_cases = [
        # Residential buildings
        ("15 Central Park West", "10023", "Luxury residential"),
        ("432 Park Avenue", "10022", "Super tall residential"),
        ("200 East 62nd Street", "10065", "Mid-size residential"),
        ("45 Christopher Street", "10014", "Small residential"),
        
        # Commercial buildings
        ("350 Fifth Avenue", "10118", "Empire State Building"),
        ("30 Rockefeller Plaza", "10112", "Large office building"),
        ("200 Vesey Street", "10281", "Brookfield Place"),
        
        # Mixed use buildings
        ("10 Hudson Yards", "10001", "Mixed use development"),
        ("230 Fifth Avenue", "10001", "Mixed retail/office"),
        
        # Storage/Industrial
        ("250 Williams Street", "10038", "Storage facility"),
        ("601 West 26th Street", "10001", "Starrett-Lehigh Building"),
    ]
    
    print("\nTesting real Manhattan addresses:")
    print("=" * 60)
    
    for address, zip_code, description in test_cases:
        dwell_time = pluto.get_pluto_baseline(address, zip_code)
        print(f"\n{description}")
        print(f"Address: {address}, {zip_code}")
        print(f"Estimated dwell time: {dwell_time:.1f} seconds ({dwell_time/60:.1f} minutes)")
    
    print("\nDone!")

if __name__ == "__main__":
    test_real_addresses() 