import 'package:livemeet/utils/app_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/models/meeting_draft.dart';
import 'package:livemeet/providers/editor_provider.dart';
import 'package:livemeet/utils/time_utils.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:livemeet/widgets/TextBox.dart';
import 'package:livemeet/widgets/confirm_dialog.dart';

// ---------- helpers ----------
String _hhmm(int m) {
  m = m % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String _label(int m) {
  m = m % 1440;
  return formatTime(DateTime(2000, 1, 1, m ~/ 60, m % 60));
}

// ---------- screen ----------
class EditMeetingScreen extends ConsumerStatefulWidget {
  final Meeting meeting;
  const EditMeetingScreen({super.key, required this.meeting});

  @override
  ConsumerState<EditMeetingScreen> createState() => _EditMeetingScreenState();
}

class _EditMeetingScreenState extends ConsumerState<EditMeetingScreen> {
  final search = TextEditingController();
  final _draftKey = Object();
  late final EditorController _controller;
  EditorState get _draft => ref.read(editorProvider(_draftKey));
  List<DraftGroup> get groups => _draft.groups;
  List<LockedGroup> get locked => _draft.locked;
  List<int> get slots => _draft.slots;
  List<DraftSnapshot> get undoStack => _draft.undoStack;
  List<DraftSnapshot> get redoStack => _draft.redoStack;
  DraftGroup? get copied => ref.read(groupClipboardProvider);
  int? expanded;
  final scroll = ScrollController();
  bool get isLoading => _draft.isLoading;
  bool get busy => _draft.busy;
  String get errorMessage => _draft.errorMessage;

  // Responsive: true on small phones (width < 360 px).
  bool get narrow => MediaQuery.sizeOf(context).width < 360;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(editorProvider(_draftKey).notifier);
    search.addListener(() => setState(() {}));
    Future.microtask(() {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    _controller.cancelLoads();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() => _controller.load(widget.meeting.id);
  int numberOf(int index) => _controller.numberOf(index);
  void undo() => _controller.undo();
  void redo() => _controller.redo();
  void onReorder(int oldIndex, int newIndex) =>
      _controller.reorder(oldIndex, newIndex);
  Set<String> regsExcept(int? uid) => _controller.regsExcept(uid);

  Future<DraftGroup?> openEditor(DraftGroup? group) {
    return showModalBottomSheet<DraftGroup>(
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
    _controller.replaceGroup(index, result);
  }

  Future<void> addGroup() async {
    if (busy) return;
    final result = await openEditor(null);
    if (result == null || !mounted) return;
    _controller.addGroup(result);
    setState(() => expanded = result.uid);
  }

  void copyGroup(int index) {
    _controller.copyGroup(index);
    snack('Group copied. Tap Paste at the top to add it at the end.');
  }

  void paste() {
    final result = _controller.paste();
    if (result == null) return;
    setState(() => expanded = result.group.uid);
    snack(
      'Pasted as group ${numberOf(groups.length - 1)}'
      '${result.renamed ? '. Reg # were changed to stay unique, edit them before saving.' : ''}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> deleteGroup(int index) async {
    if (busy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete group ${numberOf(index)}?',
      message: groups[index].project,
      confirmText: 'Delete',
    );
    if (!confirmed || !mounted) return;
    _controller.deleteGroup(index);
  }

  void snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // Result of save_meeting_schedule: {updated, added, removed} (student rows).
  String saveSummary(Map<String, dynamic> result) {
    int count(String key) => (result[key] as num?)?.toInt() ?? 0;
    final parts = <String>[
      if (count('updated') > 0) '${count('updated')} student(s) updated',
      if (count('added') > 0) '${count('added')} student(s) added',
      if (count('removed') > 0) '${count('removed')} student(s) removed',
    ];
    return parts.isEmpty ? 'Meeting updated' : parts.join(' · ');
  }

  Future<void> save() async {
    if (busy || undoStack.isEmpty) return;
    if (groups.isEmpty) {
      snack('Add at least one upcoming group');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    _controller.setBusy(true);
    try {
      // Only upcoming groups are sent; locked groups are never touched.
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < groups.length; i++) {
        for (final s in groups[i].students) {
          rows.add({
            'group_no': numberOf(i),
            'meeting_time': _hhmm(slots[i]),
            'project': groups[i].project,
            'supervisor': groups[i].supervisor,
            'reg_no': s.reg,
            'student_name': s.name,
            'tech': s.tech,
          });
        }
      }
      final result = await ref
          .read(meetingServiceProvider)
          .saveSchedule(widget.meeting.id, rows);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(saveSummary(result))));
      Navigator.of(context).pop(true);
    } catch (e, stack) {
      final message = AppError.handle(e, stack, action: ErrorAction.save);
      if (mounted) snack(message);
    } finally {
      if (mounted) _controller.setBusy(false);
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
    _controller.setBusy(true);
    try {
      await ref.read(meetingServiceProvider).deleteMeeting(widget.meeting.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Meeting deleted')));
      Navigator.of(context).pop(true);
    } catch (e, stack) {
      final message = AppError.handle(e, stack, action: ErrorAction.delete);
      if (mounted) snack(message);
    } finally {
      if (mounted) _controller.setBusy(false);
    }
  }

  // ---------- UI ----------
  bool matches(int index, List<String> words) {
    final g = groups[index];
    final fields = [
      'group ${numberOf(index)}',
      g.project,
      g.supervisor,
      for (final s in g.students) ...[s.name, s.reg, s.tech],
    ].map((e) => e.toLowerCase()).toList();
    return words.every((w) {
      if (RegExp(r'^\d+$').hasMatch(w) && w.length <= 3) {
        return int.tryParse(w) == numberOf(index);
      }
      return fields.any((f) => f.contains(w));
    });
  }

  bool matchesLocked(LockedGroup l, List<String> words) {
    final fields = [
      'group ${l.no}',
      l.status,
      l.project,
      l.supervisor,
      for (final s in l.students) ...[s.name, s.reg, s.tech],
    ].map((e) => e.toLowerCase()).toList();
    return words.every((w) {
      if (RegExp(r'^\d+$').hasMatch(w) && w.length <= 3) {
        return int.tryParse(w) == l.no;
      }
      return fields.any((f) => f.contains(w));
    });
  }

  List<Widget> studentTiles(List<DraftStudent> students) => [
    for (final s in students)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(text: s.name, fontWeight: FontWeight.bold),
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
  ];

  Widget lockedCard(LockedGroup l) {
    final isOpen = expanded == l.uid;
    return Container(
      key: ValueKey('locked-${l.no}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(narrow ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Padding(
                padding: EdgeInsets.only(right: narrow ? 4 : 8),
                child: const Icon(Icons.lock_outline_rounded),
              ),
              CustomText(
                text: '${l.no}',
                fontSize: narrow ? 26 : 32,
                fontWeight: FontWeight.bold,
              ),
              SizedBox(width: narrow ? 6 : 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => expanded = isOpen ? null : l.uid),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(
                        text: l.project,
                        height: 1,
                        fontSize: narrow ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 219, 219, 219),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: CustomText(
                              text:
                                  '${l.status[0].toUpperCase()}${l.status.substring(1)}',
                              fontSize: 12,
                            ),
                          ),
                          CustomText(
                            text: '${l.supervisor} - ${_label(l.time)}',
                            fontSize: 12,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => expanded = isOpen ? null : l.uid),
                icon: Icon(
                  isOpen
                      ? Icons.arrow_drop_up_rounded
                      : Icons.arrow_drop_down_rounded,
                ),
                color: Colors.black,
                visualDensity: narrow
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                padding: narrow ? const EdgeInsets.all(4) : null,
                constraints: narrow ? const BoxConstraints() : null,
              ),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 10),
            ...studentTiles(l.students),
          ],
        ],
      ),
    );
  }

  Widget groupCard(int index, {required bool draggable}) {
    final g = groups[index];
    final isOpen = expanded == g.uid;
    return Container(
      key: ValueKey(g.uid),
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(narrow ? 10 : 12),
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
                  child: Padding(
                    padding: EdgeInsets.only(right: narrow ? 4 : 8),
                    child: const Icon(Icons.drag_indicator_rounded),
                  ),
                ),
              CustomText(
                text: '${numberOf(index)}',
                fontSize: narrow ? 26 : 32,
                fontWeight: FontWeight.bold,
              ),
              SizedBox(width: narrow ? 6 : 10),
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
                        fontSize: narrow ? 16 : 18,
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
              PopupMenuButton<String>(
                tooltip: 'Group actions',
                enabled: !busy,
                color: Colors.white,
                icon: const Icon(Icons.more_vert_rounded, color: Colors.black),
                // Responsive: smaller tap area on narrow phones so the
                // title gets more room.
                padding: narrow
                    ? const EdgeInsets.all(4)
                    : const EdgeInsets.all(8),
                onSelected: (value) {
                  switch (value) {
                    case 'copy':
                      copyGroup(index);
                    case 'edit':
                      editGroup(index);
                    case 'delete':
                      deleteGroup(index);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'copy', child: Text('Copy')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
              IconButton(
                onPressed: () =>
                    setState(() => expanded = isOpen ? null : g.uid),
                icon: Icon(
                  isOpen
                      ? Icons.arrow_drop_up_rounded
                      : Icons.arrow_drop_down_rounded,
                ),
                color: Colors.black,
                visualDensity: narrow
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                padding: narrow ? const EdgeInsets.all(4) : null,
                constraints: narrow ? const BoxConstraints() : null,
              ),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 10),
            ...studentTiles(g.students),
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
    if (groups.isEmpty && locked.isEmpty) {
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
      final visibleLocked = [
        for (final l in locked)
          if (matchesLocked(l, words)) l,
      ];
      final visible = [
        for (var i = 0; i < groups.length; i++)
          if (matches(i, words)) i,
      ];
      if (visibleLocked.isEmpty && visible.isEmpty) {
        return const Center(
          child: CustomText(text: 'No groups match your search.'),
        );
      }
      return ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: visibleLocked.length + visible.length,
        itemBuilder: (_, i) => i < visibleLocked.length
            ? lockedCard(visibleLocked[i])
            : groupCard(visible[i - visibleLocked.length], draggable: false),
      );
    }

    return ReorderableListView.builder(
      scrollController: scroll,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 90),
      // Locked groups sit above the list: read-only, never reorderable.
      header: locked.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 6, bottom: 8),
                  child: CustomText(
                    text: 'Started or finished groups are locked',
                    fontSize: 12,
                  ),
                ),
                for (final l in locked) lockedCard(l),
              ],
            ),
      itemCount: groups.length,
      // The controller accepts the original insertion index; the newer
      // callback supplies an index after removal.
      onReorderItem: (oldIndex, newIndex) =>
          onReorder(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
      proxyDecorator: (child, _, _) =>
          Material(color: Colors.transparent, child: child),
      itemBuilder: (_, i) => groupCard(i, draggable: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(editorProvider(_draftKey));
    ref.watch(groupClipboardProvider);
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final canEdit = !isLoading && errorMessage.isEmpty;
    final sidePad = narrow ? 14.0 : 18.0;
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
        if (discard && context.mounted) Navigator.of(context).pop(false);
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
            padding: EdgeInsets.fromLTRB(sidePad, 8, sidePad, 12),
            child: Button(
              text: busy ? 'Saving...' : 'Save changes',
              enabled: canEdit && undoStack.isNotEmpty && !busy,
              onTap: save,
            ),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.fromLTRB(sidePad, 60, sidePad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).maybePop(),
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
                    tooltip: 'Paste group',
                    onPressed: copied == null || busy ? null : paste,
                    icon: const Icon(Icons.content_paste_rounded),
                    color: const Color(0xFF111111),
                  ),
                  // Deleting a whole meeting stays limited to upcoming ones.
                  if (widget.meeting.status == 'upcoming')
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
                CustomText(
                  text: 'Edit meeting',
                  fontSize: narrow ? 30 : 38,
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
  _StudentCtrl([DraftStudent? s])
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
  final DraftGroup? group;
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

  String? requiredField(String? v, String label) =>
      v == null || v.trim().isEmpty ? 'Enter $label.' : null;

  void submit() {
    if (!formKey.currentState!.validate()) return;
    final seen = <String>{};
    for (final s in students) {
      final reg = s.reg.text.trim().toLowerCase();
      if (!seen.add(reg) || widget.takenRegs.contains(reg)) {
        setState(
          () => error =
              'Reg # ${s.reg.text.trim()} is already used in this meeting.',
        );
        return;
      }
    }
    Navigator.pop(
      context,
      DraftGroup(
        uid: widget.group?.uid,
        project: project.text.trim(),
        supervisor: supervisor.text.trim(),
        students: [
          for (final s in students)
            DraftStudent(
              s.name.text.trim(),
              s.reg.text.trim(),
              s.tech.text.trim(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Responsive: tighter padding and heading on narrow phones.
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(narrow ? 14 : 18),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(
                text: widget.group == null ? 'New group' : 'Edit group',
                fontSize: narrow ? 24 : 28,
                fontWeight: FontWeight.w900,
              ),
              const SizedBox(height: 15),
              TextBox(
                hintText: 'Project name',
                controller: project,
                validator: (value) => requiredField(value, 'a project name'),
              ),
              const SizedBox(height: 10),
              TextBox(
                hintText: 'Supervisor',
                controller: supervisor,
                validator: (value) => requiredField(value, 'a supervisor name'),
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
                  padding: EdgeInsets.all(narrow ? 10 : 12),
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
                        validator: (value) =>
                            requiredField(value, 'the student name'),
                      ),
                      const SizedBox(height: 8),
                      TextBox(
                        hintText: 'Reg #',
                        controller: students[i].reg,
                        validator: (value) =>
                            requiredField(value, 'a registration number'),
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
                fontSize: narrow ? 13 : 14,
                color: Colors.white,
                onTap: () => setState(() => students.add(_StudentCtrl())),
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 10),
                CustomText(text: error, color: Colors.red),
              ],
              const SizedBox(height: 15),
              Row(
                spacing: narrow ? 6 : 10,
                children: [
                  Expanded(
                    child: Button(
                      text: 'Close',
                      height: 50,
                      fontSize: narrow ? 14 : 15,
                      color: Colors.white,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Button(
                      text: widget.group == null ? 'Add' : 'Save',
                      height: 50,
                      fontSize: narrow ? 14 : 15,
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
