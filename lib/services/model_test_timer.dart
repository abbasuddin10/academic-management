import 'dart:async';

import 'package:flutter/foundation.dart';

/// Countdown driven by an absolute server-derived deadline rather than by
/// decrementing a counter. Backgrounding the app, throttled ticks, or device
/// clock changes therefore never accumulate drift: every tick recomputes from
/// the wall clock.
class ModelTestTimer extends ChangeNotifier {
  ModelTestTimer(this.deadline) {
    start();
  }

  final DateTime deadline;
  Timer? _tick;
  bool _fired = false;
  bool _disposed = false;

  Duration get remaining {
    final diff = deadline.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get isExpired => remaining <= Duration.zero;

  /// True exactly once, on the tick when the deadline first passes.
  bool get consumeExpiry {
    if (_fired) return false;
    if (!isExpired) return false;
    _fired = true;
    return true;
  }

  void start() {
    if (_tick != null || _disposed) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      notifyListeners();
    });
  }

  void stop() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

String formatDuration(Duration duration) {
  final total = duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
