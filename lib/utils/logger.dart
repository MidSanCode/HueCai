import 'dart:io';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warning, error }

class AppLogger {
  static final AppLogger _instance = AppLogger._();
  factory AppLogger() => _instance;
  AppLogger._();

  final List<_LogEntry> _entries = [];
  File? _logFile;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/huecai_logs');
    if (!await logDir.exists()) await logDir.create(recursive: true);
    final now = DateTime.now();
    _logFile = File('${logDir.path}/huecai_${now.year}${_pad(now.month)}${_pad(now.day)}.log');
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  void debug(String msg) => _log(LogLevel.debug, msg);
  void info(String msg) => _log(LogLevel.info, msg);
  void warning(String msg) => _log(LogLevel.warning, msg);
  void error(String msg) => _log(LogLevel.error, msg);

  void _log(LogLevel level, String msg) {
    final entry = _LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: msg,
    );
    _entries.add(entry);
    _logFile?.writeAsStringSync('${entry.toString()}\n', mode: FileMode.append);
  }

  Future<String> export() async {
    final dir = await getApplicationDocumentsDirectory();
    final exportFile = File('${dir.path}/huecai_logs/export_${DateTime.now().millisecondsSinceEpoch}.log');
    final buffer = StringBuffer();
    for (final entry in _entries) {
      buffer.writeln(entry.toString());
    }
    await exportFile.writeAsString(buffer.toString());
    return exportFile.path;
  }

  String get recentLogs {
    final recent = _entries.length > 200 ? _entries.sublist(_entries.length - 200) : _entries;
    return recent.map((e) => e.toString()).join('\n');
  }
}

class _LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  _LogEntry({required this.timestamp, required this.level, required this.message});

  @override
  String toString() {
    final t = '${timestamp.year}-${_pad(timestamp.month)}-${_pad(timestamp.day)} '
        '${_pad(timestamp.hour)}:${_pad(timestamp.minute)}:${_pad(timestamp.second)}.${_pad(timestamp.millisecond)}';
    return '[$t][${level.name.toUpperCase()}] $message';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
