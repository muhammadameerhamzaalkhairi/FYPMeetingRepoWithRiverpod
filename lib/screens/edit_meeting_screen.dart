import 'package:flutter/material.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/services/meeting_service.dart';
import 'package:livemeet/utils/time_utils.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:livemeet/widgets/TextBox.dart';
import 'package:livemeet/widgets/confirm_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------- helpers ----------
int _toMin(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String _hhmm(int m) {
  m = m % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String _label(int m) {
  m = m % 1440;
  return formatTime(DateTime(2000, 1, 1, m ~/ 60, m % 60));
}

// ---------- local models ----------
class _Student {
  String name, reg, tech;
  _Student(this.name, this.reg, this.tech);
  _Student copy() => _Student(name, reg, tech);
}

int _nextUid = 0;

class _Group {
  final int uid;
  String project, supervisor;
  List<_Student> students;

  _Group({
    int? uid,
    required this.project,
    required this.supervisor,
    required this.students,
  }) : uid = uid ?? _nextUid++;

  _Group copy() => _Group(
    uid: uid,
    project: project,
    supervisor: supervisor,
    students: students.map((s) => s.copy()).toList(),
  );
}

class _Snap {
  final List<_Group> groups;
  final List<int> slots;
  _Snap(this.groups, this.slots);
}

// ---------- screen ----------
class EditMeetingScreen extends StatefulWidget {
  final Meeting meeting;
  const EditMeetingScreen({super.key, required this.meeting});

  @override
  State<EditMeetingScreen> createState() => _EditMeetingScreenState();
}

class _EditMeetingScreenState extends State<EditMeetingScreen> {
  final search = TextEditingController();
  List<_Group> groups = [];
  List<int> slots = []; // time (minutes) for each position
  int gap = 15;
  final List<_Snap> undoStack = [];
  final List<_Snap> redoStack = [];
  int? expanded; // uid of the expanded group
  bool isLoading = true;
  bool busy = false;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() {}));
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    try {
      final rows = await MeetingService.fetchRows(widget.meeting.id);
      if (!mounted) return;
      final map = <int, _Group>{};
      final times = <int, int>{};
      for (final r in rows) {
        final no = (r['group_no'] as num).toInt();
        final g = map.putIfAbsent(no, () {
          times[no] = _toMin(r['meeting_time'] as String);
          return _Group(
            project: (r['project'] ?? '').toString(),
            supervisor: (r['supervisor'] ?? '').toString(),
            students: [],
          );
        });
        g.students.add(
          _Student(
            (r['student_name'] ?? '').toString(),
            (r['reg_no'] ?? '').toString(),
            (r['tech'] ?? '').toString(),
          ),
        );
      }
      final order = map.keys.toList()..sort();
      setState(() {
        groups = [for (final k in order) map[k]!];
        slots = [for (final k in order) times[k]!];
        // Gap is detected once, from the first two meetings.
        gap = slots.length >= 2 && slots[1] - slots[0] > 0
            ? slots[1] - slots[0]
            : 15;
        undoStack.clear();
        redoStack.clear();
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = 'Unable to load groups: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ---------- undo / redo ----------
  _Snap snapshot() =>
      _Snap(groups.map((g) => g.copy()).toList(), List.of(slots));

  void restore(_Snap s) {
    groups = s.groups.map((g) => g.copy()).toList();
    slots = List.of(s.slots);
  }

  void pushHistory() {
    undoStack.add(snapshot());
    redoStack.clear();
  }

  void undo() {
    if (undoStack.isEmpty || busy) return;
    setState(() {
      redoStack.add(snapshot());
      restore(undoStack.removeLast());
    });
  }

  void redo() {
    if (redoStack.isEmpty || busy) return;
    setState(() {
      undoStack.add(snapshot());
      restore(redoStack.removeLast());
    });
  }

  // ---------- actions ----------
  void onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    setState(() {
      pushHistory();
      groups.insert(newIndex, groups.removeAt(oldIndex));
      // slots stay in place, so numbers AND times follow the new position
    });
  }

  Set<String> regsExcept(int? uid) => {
    for (final g in groups)
      if (g.uid != uid)
        for (final s in g.students) s.reg.trim().toLowerCase(),
  };

  Future<_Group?> openEditor(_Group? group) {
    return showModalBottomSheet<_Group>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) =>
          _GroupEditor(group: group, takenRegs: regsExcept(group?.uid)),
    );
  }

  Future<void> editGroup(int index) async {
    if (busy) return;
    final result = await openEditor(groups[index]);
    if (result == null || !mounted) return;
    setState(() {
      pushHistory();
      groups[index] = result;
    });
  }

  Future<void> addGroup() async {
    if (busy) return;
    final result = await openEditor(null);
    if (result == null || !mounted) return;
    setState(() {
      pushHistory();
      groups.add(result);
      slots.add(slots.isEmpty ? 9 * 60 : slots.last + gap);
      expanded = result.uid;
    });
  }

  Future<void> deleteGroup(int index) async {
    if (busy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete group ${index + 1}?',
      message: groups[index].project,
      confirmText: 'Delete',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      pushHistory();
      groups.removeAt(index);
      slots.removeLast(); // later groups move up into earlier time slots
    });
  }

  void snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> save() async {
    if (busy || undoStack.isEmpty) return;
    if (groups.isEmpty) {
      snack('Add at least one group');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < groups.length; i++) {
        for (final s in groups[i].students) {
          rows.add({
            'group_no': i + 1,
            'meeting_time': _hhmm(slots[i]),
            'project': groups[i].project,
            'supervisor': groups[i].supervisor,
            'reg_no': s.reg,
            'student_name': s.name,
            'tech': s.tech,
          });
        }
      }
      await MeetingService.saveSchedule(widget.meeting.id, rows);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Meeting updated')));
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) snack(e.message);
    } catch (e) {
      if (mounted) snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteMeeting() async {
    if (busy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete meeting?',
      message:
          '${widget.meeting.title}\n${formatDate(widget.meeting.meetingDate)}\n\nThis permanently deletes the meeting and all its groups.',
      confirmText: 'Delete',
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await MeetingService.deleteMeeting(widget.meeting.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Meeting deleted')));
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) snack(e.message);
    } catch (e) {
      if (mounted) snack('Delete failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------- UI ----------
  bool matches(int index, List<String> words) {
    final g = groups[index];
    final fields = [
      'group ${index + 1}',
      g.project,
      g.supervisor,
      for (final s in g.students) ...[s.name, s.reg, s.tech],
    ].map((e) => e.toLowerCase()).toList();
    return words.every((w) {
      if (RegExp(r'^\d+$').hasMatch(w) && w.length <= 3) {
        return int.tryParse(w) == index + 1;
      }
      return fields.any((f) => f.contains(w));
    });
  }

  Widget groupCard(int index, {required bool draggable}) {
    final g = groups[index];
    final isOpen = expanded == g.uid;
    return Container(
      key: ValueKey(g.uid),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (draggable)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.drag_indicator_rounded),
                  ),
                ),
              CustomText(
                text: '${index + 1}',
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => expanded = isOpen ? null : g.uid),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(
                        text: g.project,
                        height: 1,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      const SizedBox(height: 5),
                      CustomText(
                        text: '${g.supervisor} - ${_label(slots[index])}',
                        fontSize: 12,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit group',
                onPressed: busy ? null : () => editGroup(index),
                icon: const Icon(Icons.edit_outlined),
                color: Colors.black,
              ),
              IconButton(
                onPressed: () => setState(() => expanded = isOpen ? null : g.uid),
                icon: Icon(
                  isOpen
                      ? Icons.arrow_drop_up_rounded
                      : Icons.arrow_drop_down_rounded,
                ),
                color: Colors.black,
              ),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 10),
            for (final s in g.students)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CustomText(
                            text: s.name,
                            fontWeight: FontWeight.bold,
                          ),
                          CustomText(text: s.reg, fontSize: 12),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD6E6F7),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: CustomText(text: s.tech, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : () => deleteGroup(index),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete group'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget body() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomText(
              text: errorMessage,
              color: Colors.red,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Button(text: 'Retry', onTap: load),
          ],
        ),
      );
    }
    if (groups.isEmpty) {
      return const Center(
        child: CustomText(
          text: 'No groups. Tap + to add one.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final words = search.text
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isNotEmpty) {
      final visible = [
        for (var i = 0; i < groups.length; i++)
          if (matches(i, words)) i,
      ];
      if (visible.isEmpty) {
        return const Center(
          child: CustomText(text: 'No groups match your search.'),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: visible.length,
        itemBuilder: (_, i) => groupCard(visible[i], draggable: false),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: groups.length,
      onReorder: onReorder,
      proxyDecorator: (child, _, _) =>
          Material(color: Colors.transparent, child: child),
      itemBuilder: (_, i) => groupCard(i, draggable: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final canEdit = !isLoading && errorMessage.isEmpty;
    return PopScope(
      canPop: undoStack.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showConfirmDialog(
          context,
          title: 'Discard changes?',
          message: 'Your unsaved changes will be lost.',
          confirmText: 'Discard',
        );
        if (discard && mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        floatingActionButton: canEdit
            ? FloatingActionButton(
                onPressed: busy ? null : addGroup,
                backgroundColor: const Color(0xFF111111),
                foregroundColor: const Color(0xFFDDF35C),
                shape: const CircleBorder(),
                child: const Icon(Icons.add),
              )
            : null,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Button(
              text: busy ? 'Saving...' : 'Save changes',
              enabled: canEdit && undoStack.isNotEmpty && !busy,
              onTap: save,
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(18, 60, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: busy ? null : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    color: const Color(0xFF111111),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Undo',
                    onPressed: undoStack.isEmpty || busy ? null : undo,
                    icon: const Icon(Icons.undo_rounded),
                    color: const Color(0xFF111111),
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    onPressed: redoStack.isEmpty || busy ? null : redo,
                    icon: const Icon(Icons.redo_rounded),
                    color: const Color(0xFF111111),
                  ),
                  IconButton(
                    tooltip: 'Delete meeting',
                    onPressed: busy ? null : deleteMeeting,
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: Colors.red,
                  ),
                ],
              ),
              if (!keyboardVisible) ...[
                CustomText(text: formatDate(widget.meeting.meetingDate)),
                const CustomText(
                  text: 'Edit meeting',
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),
                CustomText(
                  text: widget.meeting.title,
                  fontWeight: FontWeight.bold,
                ),
              ],
              const SizedBox(height: 10),
              TextBox(controller: search, hintText: 'Search'),
              if (search.text.trim().isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 6),
                  child: CustomText(
                    text: 'Clear search to drag and reorder',
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(child: body()),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- add / edit bottom sheet ----------
class _StudentCtrl {
  final TextEditingController name, reg, tech;
  _StudentCtrl([_Student? s])
    : name = TextEditingController(text: s?.name ?? ''),
      reg = TextEditingController(text: s?.reg ?? ''),
      tech = TextEditingController(text: s?.tech ?? '');

  void dispose() {
    name.dispose();
    reg.dispose();
    tech.dispose();
  }
}

class _GroupEditor extends StatefulWidget {
  final _Group? group;
  final Set<String> takenRegs;
  const _GroupEditor({required this.group, required this.takenRegs});

  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController project;
  late final TextEditingController supervisor;
  final List<_StudentCtrl> students = [];
  String error = '';

  @override
  void initState() {
    super.initState();
    project = TextEditingController(text: widget.group?.project ?? '');
    supervisor = TextEditingController(text: widget.group?.supervisor ?? '');
    final existing = widget.group?.students ?? [];
    if (existing.isEmpty) {
      students.add(_StudentCtrl());
    } else {
      students.addAll(existing.map(_StudentCtrl.new));
    }
  }

  @override
  void dispose() {
    project.dispose();
    supervisor.dispose();
    for (final s in students) {
      s.dispose();
    }
    super.dispose();
  }

  String? required(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;

  void submit() {
    if (!formKey.currentState!.validate()) return;
    final seen = <String>{};
    for (final s in students) {
      final reg = s.reg.text.trim().toLowerCase();
      if (!seen.add(reg) || widget.takenRegs.contains(reg)) {
        setState(() => error = 'Reg # ${s.reg.text.trim()} is already used in this meeting.');
        return;
      }
    }
    Navigator.pop(
      context,
      _Group(
        uid: widget.group?.uid,
        project: project.text.trim(),
        supervisor: supervisor.text.trim(),
        students: [
          for (final s in students)
            _Student(s.name.text.trim(), s.reg.text.trim(), s.tech.text.trim()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(
                text: widget.group == null ? 'New group' : 'Edit group',
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
              const SizedBox(height: 15),
              TextBox(
                hintText: 'Project name',
                controller: project,
                validator: required,
              ),
              const SizedBox(height: 10),
              TextBox(
                hintText: 'Supervisor',
                controller: supervisor,
                validator: required,
              ),
              const SizedBox(height: 15),
              const CustomText(
                text: 'Students',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < students.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CustomText(
                              text: 'Student ${i + 1}',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (students.length > 1)
                            IconButton(
                              tooltip: 'Remove student',
                              onPressed: () => setState(() {
                                students.removeAt(i).dispose();
                              }),
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                      TextBox(
                        hintText: 'Student name',
                        controller: students[i].name,
                        validator: required,
                      ),
                      const SizedBox(height: 8),
                      TextBox(
                        hintText: 'Reg #',
                        controller: students[i].reg,
                        validator: required,
                      ),
                      const SizedBox(height: 8),
                      TextBox(
                        hintText: 'Technology',
                        controller: students[i].tech,
                      ),
                    ],
                  ),
                ),
              Button(
                text: 'Add student',
                height: 44,
                fontSize: 14,
                color: Colors.white,
                onTap: () => setState(() => students.add(_StudentCtrl())),
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 10),
                CustomText(text: error, color: Colors.red),
              ],
              const SizedBox(height: 15),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: Button(
                      text: 'Close',
                      height: 50,
                      fontSize: 15,
                      color: Colors.white,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Button(
                      text: widget.group == null ? 'Add' : 'Save',
                      height: 50,
                      fontSize: 15,
                      onTap: submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}