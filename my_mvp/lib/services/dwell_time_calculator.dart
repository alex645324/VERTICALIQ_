/// Abstract class defining the interface for dwell time calculation strategies
abstract class DwellTimeCalculator {
  double calculateBlendedDwellTime(int visitCount, double heuristicTime, double liveAverage);
}

/// Default implementation using confidence-based blending
class ConfidenceBasedCalculator implements DwellTimeCalculator {
  final double kFactor;

  /// Creates a confidence-based calculator with the specified k-factor
  /// Higher k = slower transition from heuristic to live data
  const ConfidenceBasedCalculator({this.kFactor = 10.0});

  @override
  double calculateBlendedDwellTime(int visitCount, double heuristicTime, double liveAverage) {
    // Calculate confidence (0 to 1) based on visit count
    final confidence = visitCount / (visitCount + kFactor);
    
    // Blend between heuristic and live average based on confidence
    return heuristicTime * (1 - confidence) + liveAverage * confidence;
  }
}

/// Simple threshold-based calculator that switches at a specific visit count
class ThresholdBasedCalculator implements DwellTimeCalculator {
  final int threshold;

  const ThresholdBasedCalculator({this.threshold = 10});

  @override
  double calculateBlendedDwellTime(int visitCount, double heuristicTime, double liveAverage) {
    return visitCount >= threshold ? liveAverage : heuristicTime;
  }
}

/// Factory for creating different types of dwell time calculators
class DwellTimeCalculatorFactory {
  static DwellTimeCalculator createCalculator({String type = 'confidence'}) {
    switch (type.toLowerCase()) {
      case 'threshold':
        return const ThresholdBasedCalculator();
      case 'confidence':
      default:
        return const ConfidenceBasedCalculator();
    }
  }
} 