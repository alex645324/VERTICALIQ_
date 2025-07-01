class BuildingProfile {
  final String buildingId;
  final String address;
  final double heuristicDwellTime;
  double? liveAvgDwellTime;
  double blendedDwellTime;
  int visitCount;

  BuildingProfile({
    required this.buildingId,
    required this.address,
    required this.heuristicDwellTime,
    this.liveAvgDwellTime,
    required this.blendedDwellTime,
    this.visitCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'buildingId': buildingId,
      'address': address,
      'heuristicDwellTime': heuristicDwellTime,
      'liveAvgDwellTime': liveAvgDwellTime,
      'blendedDwellTime': blendedDwellTime,
      'visitCount': visitCount,
    };
  }

  factory BuildingProfile.fromMap(Map<String, dynamic> map) {
    return BuildingProfile(
      buildingId: map['buildingId'],
      address: map['address'],
      heuristicDwellTime: (map['heuristicDwellTime'] as num).toDouble(),
      liveAvgDwellTime: map['liveAvgDwellTime'] != null 
          ? (map['liveAvgDwellTime'] as num).toDouble() 
          : null,
      blendedDwellTime: (map['blendedDwellTime'] as num).toDouble(),
      visitCount: map['visitCount'] ?? 0,
    );
  }
} 