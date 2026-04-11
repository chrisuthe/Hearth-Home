import 'dart:math';

/// Two-dimensional Kalman filter for NTP-style time synchronization.
///
/// Tracks [offset, drift] between client and server clocks with a 2x2
/// covariance matrix. Faithfully ported from the C++ Sendspin time-filter:
/// https://github.com/Sendspin/time-filter
///
/// All times are in microseconds (int).
class SendspinClock {
  SendspinClock({
    double processStdDev = 0.01,
    double driftProcessStdDev = 0.0,
    double forgetFactor = 1.001,
    double adaptiveCutoff = 0.75,
    int minSamples = 100,
    double driftSignificanceThreshold = 2.0,
  })  : _processVariance = processStdDev * processStdDev,
        _driftProcessVariance = driftProcessStdDev * driftProcessStdDev,
        _forgetVarianceFactor = forgetFactor * forgetFactor,
        _adaptiveForgettingCutoff = adaptiveCutoff,
        _minSamplesForForgetting = minSamples,
        _driftSignificanceThresholdSquared =
            driftSignificanceThreshold * driftSignificanceThreshold {
    reset();
  }

  // Persisted state
  int _lastUpdate = 0;
  double _offset = 0.0;
  double _drift = 0.0;
  double _offsetCovariance = double.infinity;
  double _offsetDriftCovariance = 0.0;
  double _driftCovariance = 0.0;
  bool _useDrift = false;
  int _count = 0;

  /// Estimated clock offset in microseconds (server - client).
  double get offsetUs => _offset;

  /// Number of time sync samples processed.
  int get sampleCount => _count;

  /// Whether the filter has converged (enough samples for reliable estimate).
  bool get isConverged => _count >= _minSamplesForForgetting;

  // Immutable parameters
  final double _processVariance;
  final double _driftProcessVariance;
  final double _forgetVarianceFactor;
  final double _adaptiveForgettingCutoff;
  final int _minSamplesForForgetting;
  final double _driftSignificanceThresholdSquared;

  /// Processes a new time synchronization measurement.
  ///
  /// [measurement] is the computed offset from NTP-style exchange in µs.
  /// [maxError] is half the round-trip delay in µs.
  /// [timeAdded] is the client timestamp when this measurement was taken in µs.
  void update(int measurement, int maxError, int timeAdded) {
    if (timeAdded <= _lastUpdate) {
      // Skip non-monotonic timestamps
      return;
    }

    final double dt = (timeAdded - _lastUpdate).toDouble();
    final double dtSquared = dt * dt;
    _lastUpdate = timeAdded;

    final double measurementVariance =
        maxError.toDouble() * maxError.toDouble();

    // Phase 1: First measurement establishes offset baseline
    if (_count <= 0) {
      _count++;
      _offset = measurement.toDouble();
      _offsetCovariance = measurementVariance;
      _drift = 0.0;
      return;
    }

    // Phase 2: Second measurement — initial drift from finite differences
    if (_count == 1) {
      _count++;
      _drift = (measurement.toDouble() - _offset) / dt;
      _offset = measurement.toDouble();
      _driftCovariance =
          (_offsetCovariance + measurementVariance) / dtSquared;
      _offsetCovariance = measurementVariance;
      return;
    }

    // Phase 3: Full Kalman predict -> innovate -> adapt -> update

    /*** Prediction Step ***/
    final double predictedOffset = _offset + _drift * dt;

    final double driftProcessVariance = dt * _driftProcessVariance;
    double newDriftCovariance = _driftCovariance + driftProcessVariance;

    double newOffsetDriftCovariance =
        _offsetDriftCovariance + _driftCovariance * dt;

    final double offsetProcessVariance = dt * _processVariance;
    double newOffsetCovariance = _offsetCovariance +
        2 * _offsetDriftCovariance * dt +
        _driftCovariance * dtSquared +
        offsetProcessVariance;

    /*** Innovation and Adaptive Forgetting ***/
    final double residual = measurement.toDouble() - predictedOffset;
    final double maxResidualCutoff =
        maxError.toDouble() * _adaptiveForgettingCutoff;

    if (_count < _minSamplesForForgetting) {
      _count++;
    } else if (residual.abs() > maxResidualCutoff) {
      newDriftCovariance *= _forgetVarianceFactor;
      newOffsetDriftCovariance *= _forgetVarianceFactor;
      newOffsetCovariance *= _forgetVarianceFactor;
    }

    /*** Update Step ***/
    final double uncertainty =
        1.0 / (newOffsetCovariance + measurementVariance);

    final double offsetGain = newOffsetCovariance * uncertainty;
    final double driftGain = newOffsetDriftCovariance * uncertainty;

    _offset = predictedOffset + offsetGain * residual;
    _drift += driftGain * residual;

    _driftCovariance =
        newDriftCovariance - driftGain * newOffsetDriftCovariance;
    _offsetDriftCovariance =
        newOffsetDriftCovariance - driftGain * newOffsetCovariance;
    _offsetCovariance =
        newOffsetCovariance - offsetGain * newOffsetCovariance;

    // Drift significance check (SNR)
    final double driftSquared = _drift * _drift;
    _useDrift =
        driftSquared > _driftSignificanceThresholdSquared * _driftCovariance;
  }

  /// Converts a client timestamp to the equivalent server timestamp.
  int computeServerTime(int clientTime) {
    final double dt = (clientTime - _lastUpdate).toDouble();
    final double effectiveDrift = _useDrift ? _drift : 0.0;
    final int offset = (_offset + effectiveDrift * dt).round();
    return clientTime + offset;
  }

  /// Converts a server timestamp to the equivalent client timestamp.
  int computeClientTime(int serverTime) {
    final double effectiveDrift = _useDrift ? _drift : 0.0;
    return ((serverTime.toDouble() - _offset +
                effectiveDrift * _lastUpdate.toDouble()) /
            (1.0 + effectiveDrift))
        .round();
  }

  /// Resets the filter to its initial uninitialized state.
  void reset() {
    _count = 0;
    _offset = 0.0;
    _drift = 0.0;
    _offsetCovariance = double.infinity;
    _offsetDriftCovariance = 0.0;
    _driftCovariance = 0.0;
    _lastUpdate = 0;
    _useDrift = false;
  }

  /// Returns the estimated standard deviation of the offset in µs.
  int getError() {
    return sqrt(_offsetCovariance).round();
  }
}
