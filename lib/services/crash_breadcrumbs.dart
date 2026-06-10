import 'dart:io';

/// Persists capture-pipeline progress markers so that, after a native crash
/// (which Dart cannot intercept), the next launch can report the last step
/// that completed and pinpoint where the process died.
class CrashBreadcrumbs {
  static const _fileName = 'capture_breadcrumbs.txt';

  static File get _file => File('${Directory.systemTemp.path}/$_fileName');

  /// Records that the pipeline reached [step]. Overwrites the previous mark.
  static Future<void> mark(String step) async {
    try {
      await _file.writeAsString(step, flush: true);
    } catch (_) {}
  }

  /// Removes the marker — call when a capture completes without crashing.
  static Future<void> clear() async {
    try {
      if (_file.existsSync()) await _file.delete();
    } catch (_) {}
  }

  /// The last step recorded by a previous run, or null when the previous
  /// capture completed cleanly (or no capture was attempted).
  static Future<String?> readPrevious() async {
    try {
      if (_file.existsSync()) {
        final value = (await _file.readAsString()).trim();
        return value.isEmpty ? null : value;
      }
    } catch (_) {}
    return null;
  }
}
