import 'dart:async';

import 'package:flutter/foundation.dart';

class StartupTimelineEntry {
  final String label;
  final int elapsedMs;
  final int deltaMs;
  final String phase;

  const StartupTimelineEntry({
    required this.label,
    required this.elapsedMs,
    required this.deltaMs,
    required this.phase,
  });
}

class StartupTimeline {
  StartupTimeline._();

  static final StartupTimeline instance = StartupTimeline._();

  static final bool _defaultEnabled = !kReleaseMode;
  static const String _phaseMark = 'mark';
  static const String _phaseStart = 'start';
  static const String _phaseEnd = 'end';
  final Stopwatch _stopwatch = Stopwatch();
  final List<StartupTimelineEntry> _entries = <StartupTimelineEntry>[];
  bool _started = false;
  bool _summaryPrinted = false;
  int _lastElapsedMs = 0;

  bool get isEnabled => _defaultEnabled;

  void start([String label = 'startup:start']) {
    if (!isEnabled || _started) return;
    _stopwatch.start();
    _started = true;
    _append(label, _phaseStart);
  }

  void mark(String label) {
    if (!isEnabled) return;
    _ensureStarted();
    _append(label, _phaseMark);
  }

  Future<T> measureAsync<T>(String label, Future<T> Function() task) async {
    if (!isEnabled) return task();
    _ensureStarted();
    _append('$label:start', _phaseStart);
    try {
      return await task();
    } finally {
      _append('$label:end', _phaseEnd);
    }
  }

  T measureSync<T>(String label, T Function() task) {
    if (!isEnabled) return task();
    _ensureStarted();
    _append('$label:start', _phaseStart);
    try {
      return task();
    } finally {
      _append('$label:end', _phaseEnd);
    }
  }

  void printSummary({String reason = 'startup:summary'}) {
    if (!isEnabled || _summaryPrinted) return;
    _ensureStarted();
    _summaryPrinted = true;
    _append(reason, _phaseMark);

    final buffer = StringBuffer()
      ..writeln('⏱️ [StartupTimeline] Resumo da abertura do app');
    for (final entry in _entries) {
      buffer.writeln(
        ' - ${entry.elapsedMs.toString().padLeft(4)}ms (+${entry.deltaMs.toString().padLeft(4)}ms) '
        '[${entry.phase}] ${entry.label}',
      );
    }
    debugPrint(buffer.toString().trimRight());
  }

  List<StartupTimelineEntry> snapshot() => List.unmodifiable(_entries);

  void _ensureStarted() {
    if (_started) return;
    start();
  }

  void _append(String label, String phase) {
    final elapsedMs = _stopwatch.elapsedMilliseconds;
    final deltaMs = elapsedMs - _lastElapsedMs;
    _entries.add(
      StartupTimelineEntry(
        label: label,
        elapsedMs: elapsedMs,
        deltaMs: deltaMs,
        phase: phase,
      ),
    );
    _lastElapsedMs = elapsedMs;
    debugPrint(
      '⏱️ [StartupTimeline] ${elapsedMs}ms (+${deltaMs}ms) [$phase] $label',
    );
  }
}
