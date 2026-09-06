import 'dart:convert';

class HistoryEntry {
  final int timestamp;
  final String description;
  final Map<String, dynamic> projectSnapshot;

  HistoryEntry({
    required this.timestamp,
    this.description = '',
    required this.projectSnapshot,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'description': description,
        'projectSnapshot': projectSnapshot,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        timestamp: json['timestamp'] as int,
        description: json['description'] as String? ?? '',
        projectSnapshot: json['projectSnapshot'] as Map<String, dynamic>,
      );
}

class HistoryService {
  final List<HistoryEntry> _undoStack = [];
  final List<HistoryEntry> _redoStack = [];
  static const int _maxHistory = 100;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  List<HistoryEntry> get allEntries => [..._undoStack];

  void pushEntry(HistoryEntry entry) {
    // Deduplicate: identical consecutive snapshots (same project state,
    // e.g. duplicate pushes during one gesture) waste memory and make undo
    // feel broken (undoing appears to do nothing). Skip exact repeats.
    if (_undoStack.isNotEmpty &&
        identical(_undoStack.last.projectSnapshot, entry.projectSnapshot)) {
      return;
    }
    _undoStack.add(entry);
    _redoStack.clear();
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
  }

  Map<String, dynamic>? undo() {
    if (_undoStack.isEmpty) return null;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    return entry.projectSnapshot;
  }

  Map<String, dynamic>? redo() {
    if (_redoStack.isEmpty) return null;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    return entry.projectSnapshot;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }

  List<Map<String, dynamic>> toJson() =>
      _undoStack.map((e) => e.toJson()).toList();

  void loadFromJson(List<dynamic> json) {
    _undoStack.clear();
    _redoStack.clear();
    for (final item in json) {
      _undoStack.add(HistoryEntry.fromJson(item as Map<String, dynamic>));
    }
  }

  String toJsonString() => jsonEncode(toJson());
}
