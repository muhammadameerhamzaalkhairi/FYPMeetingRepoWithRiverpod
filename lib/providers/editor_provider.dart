import 'package:livemeet/utils/app_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/models/meeting_draft.dart';
import 'package:livemeet/providers/app_providers.dart';

final groupClipboardProvider = NotifierProvider<GroupClipboard, DraftGroup?>(
  GroupClipboard.new,
);

class GroupClipboard extends Notifier<DraftGroup?> {
  @override
  DraftGroup? build() => null;
  void copy(DraftGroup group) => state = group.copy();
}

class EditorState {
  final List<DraftGroup> groups;
  final List<LockedGroup> locked;
  final List<int> slots;
  final int gap;
  final List<DraftSnapshot> undoStack, redoStack;
  final bool isLoading, busy;
  final String errorMessage;
  EditorState({
    List<DraftGroup> groups = const [],
    List<LockedGroup> locked = const [],
    List<int> slots = const [],
    this.gap = 15,
    List<DraftSnapshot> undoStack = const [],
    List<DraftSnapshot> redoStack = const [],
    this.isLoading = true,
    this.busy = false,
    this.errorMessage = '',
  }) : groups = List.unmodifiable(groups),
       locked = List.unmodifiable(locked),
       slots = List.unmodifiable(slots),
       undoStack = List.unmodifiable(undoStack),
       redoStack = List.unmodifiable(redoStack);
  EditorState copyWith({
    List<DraftGroup>? groups,
    List<LockedGroup>? locked,
    List<int>? slots,
    int? gap,
    List<DraftSnapshot>? undoStack,
    List<DraftSnapshot>? redoStack,
    bool? isLoading,
    bool? busy,
    String? errorMessage,
  }) => EditorState(
    groups: groups ?? this.groups,
    locked: locked ?? this.locked,
    slots: slots ?? this.slots,
    gap: gap ?? this.gap,
    undoStack: undoStack ?? this.undoStack,
    redoStack: redoStack ?? this.redoStack,
    isLoading: isLoading ?? this.isLoading,
    busy: busy ?? this.busy,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

final editorProvider = NotifierProvider.autoDispose
    .family<EditorController, EditorState, Object>(EditorController.new);

class EditorController extends Notifier<EditorState> {
  EditorController(this.owner);
  final Object owner;
  int _request = 0;
  bool _closed = false;
  @override
  EditorState build() {
    ref.onDispose(cancelLoads);
    return EditorState();
  }

  void cancelLoads() {
    _closed = true;
    _request++;
  }

  bool _current(int request) => !_closed && ref.mounted && request == _request;
  void setBusy(bool value) => state = state.copyWith(busy: value);

  Future<void> load(int meetingId) async {
    final request = ++_request;
    final service = ref.read(meetingServiceProvider);
    state = state.copyWith(isLoading: true, errorMessage: '');
    try {
      final rows = await service.fetchRows(meetingId);
      if (!_current(request)) return;
      // Build privately, then publish immutable groups. Mixed row states follow
      // the original split into editable and locked groups.
      final editable = <int, List<Map<String, dynamic>>>{};
      final progressed = <int, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final number = (row['group_no'] as num).toInt();
        final target = (row['status'] ?? 'upcoming').toString() == 'upcoming'
            ? editable
            : progressed;
        target.putIfAbsent(number, () => []).add(row);
      }
      int minutes(String time) {
        final parts = time.split(':');
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }

      List<DraftStudent> students(List<Map<String, dynamic>> rows) => [
        for (final r in rows)
          DraftStudent(
            (r['student_name'] ?? '').toString(),
            (r['reg_no'] ?? '').toString(),
            (r['tech'] ?? '').toString(),
          ),
      ];
      final order = editable.keys.toList()..sort();
      // Allocate IDs in database row order, as before sorting the editable list.
      final groups = {
        for (final entry in editable.entries)
          entry.key: DraftGroup(
            project: (entry.value.first['project'] ?? '').toString(),
            supervisor: (entry.value.first['supervisor'] ?? '').toString(),
            students: students(entry.value),
          ),
      };
      final locks = [
        for (final entry in progressed.entries)
          LockedGroup(
            no: entry.key,
            time: minutes(entry.value.first['meeting_time'] as String),
            status: (entry.value.first['status'] ?? 'upcoming').toString(),
            project: (entry.value.first['project'] ?? '').toString(),
            supervisor: (entry.value.first['supervisor'] ?? '').toString(),
            students: students(entry.value),
          ),
      ]..sort((a, b) => a.no.compareTo(b.no));
      final times = {
        for (final entry in editable.entries)
          entry.key: minutes(entry.value.first['meeting_time'] as String),
      };
      final allTimes = {...times, for (final l in locks) l.no: l.time};
      final allOrder = allTimes.keys.toList()..sort();
      state = state.copyWith(
        groups: [for (final k in order) groups[k]!],
        locked: locks,
        slots: [for (final k in order) times[k]!],
        gap:
            allOrder.length >= 2 &&
                allTimes[allOrder[1]]! - allTimes[allOrder[0]]! > 0
            ? allTimes[allOrder[1]]! - allTimes[allOrder[0]]!
            : 15,
        undoStack: [],
        redoStack: [],
      );
    } catch (e, stack) {
      final message = AppError.handle(e, stack, action: ErrorAction.loadGroups);
      if (_current(request)) {
        state = state.copyWith(errorMessage: message);
      }
    } finally {
      if (_current(request)) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  DraftSnapshot _snapshot() => DraftSnapshot(state.groups, state.slots);
  void _change(List<DraftGroup> groups, List<int> slots) {
    state = state.copyWith(
      groups: groups,
      slots: slots,
      undoStack: [...state.undoStack, _snapshot()],
      redoStack: [],
    );
  }

  void undo() {
    if (state.undoStack.isEmpty || state.busy) return;
    final previous = state.undoStack.last;
    state = state.copyWith(
      groups: previous.groups.map((g) => g.copy()).toList(),
      slots: previous.slots,
      undoStack: state.undoStack.sublist(0, state.undoStack.length - 1),
      redoStack: [...state.redoStack, _snapshot()],
    );
  }

  void redo() {
    if (state.redoStack.isEmpty || state.busy) return;
    final next = state.redoStack.last;
    state = state.copyWith(
      groups: next.groups.map((g) => g.copy()).toList(),
      slots: next.slots,
      redoStack: state.redoStack.sublist(0, state.redoStack.length - 1),
      undoStack: [...state.undoStack, _snapshot()],
    );
  }

  int numberOf(int index) {
    final taken = {for (final l in state.locked) l.no};
    var found = 0, candidate = 0;
    while (true) {
      candidate++;
      if (taken.contains(candidate)) continue;
      if (found == index) return candidate;
      found++;
    }
  }

  Set<String> regsExcept(int? uid) => {
    for (final g in state.groups)
      if (g.uid != uid)
        for (final s in g.students) s.reg.trim().toLowerCase(),
    for (final l in state.locked)
      for (final s in l.students) s.reg.trim().toLowerCase(),
  };
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    final groups = [...state.groups];
    groups.insert(newIndex, groups.removeAt(oldIndex));
    _change(groups, state.slots);
  }

  void replaceGroup(int index, DraftGroup group) {
    final groups = [...state.groups];
    groups[index] = group;
    _change(groups, state.slots);
  }

  int _nextSlot(List<int> slots) {
    final last = slots.isNotEmpty
        ? slots.last
        : state.locked.isNotEmpty
        ? state.locked.fold<int>(0, (a, l) => l.time > a ? l.time : a)
        : null;
    return last == null ? 9 * 60 : last + state.gap;
  }

  void addGroup(DraftGroup group) => _change(
    [...state.groups, group],
    [...state.slots, _nextSlot(state.slots)],
  );
  void deleteGroup(int index) {
    final groups = [...state.groups]..removeAt(index);
    final slots = [...state.slots]..removeLast();
    _change(groups, slots);
  }

  void copyGroup(int index) =>
      ref.read(groupClipboardProvider.notifier).copy(state.groups[index]);
  String _uniqueReg(String reg, Set<String> taken) {
    final base = reg.trim();
    if (!taken.contains(base.toLowerCase())) return base;
    var candidate = '$base-copy', n = 2;
    while (taken.contains(candidate.toLowerCase())) {
      candidate = '$base-copy$n';
      n++;
    }
    return candidate;
  }

  ({DraftGroup group, bool renamed})? paste() {
    final source = ref.read(groupClipboardProvider);
    if (source == null || state.busy) return null;
    final taken = regsExcept(null);
    var renamed = false;
    final students = <DraftStudent>[];
    for (final s in source.students) {
      final reg = _uniqueReg(s.reg, taken);
      if (reg != s.reg.trim()) renamed = true;
      taken.add(reg.toLowerCase());
      students.add(DraftStudent(s.name, reg, s.tech));
    }
    final group = DraftGroup(
      project: source.project,
      supervisor: source.supervisor,
      students: students,
    );
    addGroup(group);
    return (group: group, renamed: renamed);
  }
}
