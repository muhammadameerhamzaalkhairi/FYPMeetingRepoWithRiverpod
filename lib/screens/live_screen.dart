import 'package:livemeet/utils/app_error.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/providers/meeting_providers.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/utils/time_utils.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:livemeet/widgets/LiveDetailMeetingCard.dart';
import 'package:livemeet/widgets/TextBox.dart';
import 'package:livemeet/widgets/attendance_dialog.dart';
import 'package:livemeet/widgets/confirm_dialog.dart';
import 'package:livemeet/widgets/filter.dart';

enum _GroupAction { start, end, pause, resume, attendance }

class LiveScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  final ValueChanged<bool> onBusyChanged;

  const LiveScreen({
    super.key,
    required this.onNavigate,
    required this.onBusyChanged,
  });

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  static const sortRank = {
    'running': 0,
    'paused': 1,
    'upcoming': 2,
    'done': 3,
    'skipped': 4,
  };
  static const filters = ['All', 'Running', 'Upcoming', 'Paused', 'Done'];
  final search = TextEditingController();
  final _dataKey = Object();
  late final ActiveMeetingController _controller;
  MeetingLoadState<ActiveMeetingData> get _data =>
      ref.read(activeMeetingProvider(_dataKey));
  bool get isLoading => _data.isLoading;
  bool get busy => _data.busy;
  String get errorMessage => _data.errorMessage;
  Meeting? get meeting => _data.data.meeting;
  Map<int, List<Map<String, dynamic>>> get groups => _data.data.groups;
  int selectedFilter = 0;
  int? selectedGroup;
  int? expandedGroup;
  late final Timer ticker;

  // Responsive: true on small phones (width < 360 px).
  bool get narrow => MediaQuery.sizeOf(context).width < 360;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(activeMeetingProvider(_dataKey).notifier);
    search.addListener(searchChanged);
    Future.microtask(() {
      if (mounted) loadMeeting(selectRunningGroup: true);
    });
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && meeting?.status == 'running' && hasRunningGroup) {
        setState(() {});
      }
    });
  }

  void searchChanged() => setState(() {});

  @override
  void dispose() {
    _controller.cancelLoads();
    ticker.cancel();
    search.removeListener(searchChanged);
    search.dispose();
    super.dispose();
  }

  // silent = refresh the data without the loading spinner, so open cards and
  // their timers are not rebuilt from scratch (used after saving attendance).
  // Attendance refreshes keep cards mounted and retain unsaved checkbox drafts.
  Future<void> loadMeeting({
    bool selectRunningGroup = false,
    bool silent = false,
  }) async {
    final previousId = meeting?.id;
    final loaded = await _controller.load(silent: silent);
    if (!mounted || !loaded) return;
    setState(() {
      if (previousId != meeting?.id) {
        selectedGroup = null;
        expandedGroup = null;
      }
      if (selectRunningGroup) {
        selectedGroup = groups.entries
            .where((entry) => entry.value.first['status'] == 'running')
            .map((entry) => entry.key)
            .firstOrNull;
      }
      if (!groups.containsKey(selectedGroup)) selectedGroup = null;
      if (!groups.containsKey(expandedGroup)) expandedGroup = null;
    });
  }

  Future<void> refreshMeeting() async {
    if (busy || isLoading) return;
    await loadMeeting();
  }

  bool get hasRunningGroup =>
      groups.values.any((rows) => rows.first['status'] == 'running');

  bool get ready => !busy && !isLoading && errorMessage.isEmpty;

  // Group actions need the whole meeting to be running (not paused).
  bool get meetingRunning => meeting?.status == 'running';

  // Start only for upcoming groups when no group is running.
  // Paused groups do not block starting another group.
  bool canStart(Map<String, dynamic> row) =>
      ready &&
      meetingRunning &&
      row['status'] == 'upcoming' &&
      !hasRunningGroup;

  // End works for a running OR paused group.
  bool canEnd(Map<String, dynamic> row) =>
      ready &&
      meetingRunning &&
      (row['status'] == 'running' || row['status'] == 'paused');

  // Pause: only a running group. Resume: only a paused group, and only
  // while no other group is running.
  bool canPauseResume(Map<String, dynamic> row) =>
      ready &&
      meetingRunning &&
      switch (row['status']) {
        'running' => true,
        'paused' => !hasRunningGroup,
        _ => false,
      };

  // Attendance can be edited (tick AND untick) for every group that has
  // started: running, paused or done. It never touches timers, and it also
  // works while the whole meeting is paused.
  bool canEditAttendance(Map<String, dynamic> row) =>
      ready &&
      meeting?.isActive == true &&
      (row['status'] == 'running' ||
          row['status'] == 'paused' ||
          row['status'] == 'done');

  String? groupTimer(Map<String, dynamic> row) {
    final startedAt = row['started_at'] as String?;
    if (startedAt == null) return null;
    final pausedSeconds = (row['paused_seconds'] as num?)?.toInt() ?? 0;
    switch (row['status']) {
      case 'running':
        return formatClock(
          elapsedSec(
            now: ref.read(serverClockProvider.notifier).now(),
            startedAt: DateTime.parse(startedAt),
            pausedSeconds: pausedSeconds,
            frozenAt: meeting?.pausedAt,
          ),
        );
      case 'paused':
        // A paused group shows its saved time, frozen.
        final saved = (row['duration_sec'] as num?)?.toInt();
        if (saved != null) return formatClock(saved);
        final pausedAt = row['paused_at'] as String?;
        return formatClock(
          elapsedSec(
            now: ref.read(serverClockProvider.notifier).now(),
            startedAt: DateTime.parse(startedAt),
            pausedSeconds: pausedSeconds,
            frozenAt: pausedAt == null ? null : DateTime.parse(pausedAt),
          ),
        );
      default:
        return null;
    }
  }

  // [regs] is used only by the attendance action: the FULL list of students
  // that should be present (may be empty = everyone absent).
  Future<void> changeGroup(
    int number,
    _GroupAction action, {
    List<String> regs = const [],
  }) async {
    final active = meeting;
    final rows = groups[number];
    final row = rows?.first;
    if (active == null || rows == null || row == null) return;
    final allowed = switch (action) {
      _GroupAction.start => canStart(row),
      _GroupAction.end => canEnd(row),
      _GroupAction.pause || _GroupAction.resume => canPauseResume(row),
      _GroupAction.attendance => canEditAttendance(row),
    };
    if (!allowed) return;
    _controller.setBusy(true);
    try {
      List<String>? present;
      if (action == _GroupAction.start) {
        // Replaces the plain confirm: operator checks who is present.
        present = await showAttendanceDialog(
          context,
          number: number,
          project: row['project'] as String,
          students: rows,
        );
        if (!mounted) return;
        if (present == null) return;
      } else if (action == _GroupAction.end) {
        final confirmed = await showConfirmDialog(
          context,
          title: 'End group $number?',
          message: 'Elapsed time: ${groupTimer(row) ?? '—'}',
        );
        if (!mounted) return;
        if (!confirmed) return;
      }
      widget.onBusyChanged(true);
      var changed = 0;
      switch (action) {
        case _GroupAction.start:
          await ref
              .read(meetingServiceProvider)
              .startGroup(active.id, number, present: present);
        case _GroupAction.end:
          await ref.read(meetingServiceProvider).endGroup(active.id, number);
        case _GroupAction.pause:
          await ref.read(meetingServiceProvider).pauseGroup(active.id, number);
        case _GroupAction.resume:
          await ref.read(meetingServiceProvider).resumeGroup(active.id, number);
        case _GroupAction.attendance:
          changed = await ref
              .read(meetingServiceProvider)
              .setAttendance(active.id, number, regs);
      }
      if (!mounted) return;
      if (action == _GroupAction.start || action == _GroupAction.resume) {
        setState(() => selectedGroup = number);
      }
      if (action == _GroupAction.attendance) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changed > 0
                  ? 'Attendance saved ($changed changed)'
                  : 'Attendance already up to date',
            ),
          ),
        );
      }
      await loadMeeting(silent: action == _GroupAction.attendance);
      if (!mounted) return;
    } catch (e, stack) {
      final message = AppError.handle(
        e,
        stack,
        action: action == _GroupAction.attendance
            ? ErrorAction.attendance
            : ErrorAction.group,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await loadMeeting();
      if (!mounted) return;
    } finally {
      widget.onBusyChanged(false);
      if (mounted) _controller.setBusy(false);
    }
  }

  List<int> get visibleGroups {
    final words = search.text
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final visible = groups.keys.where((number) {
      final rows = groups[number]!;
      final row = rows.first;
      if (selectedFilter != 0 &&
          row['status'] != filters[selectedFilter].toLowerCase()) {
        return false;
      }
      final fields = [
        row['project'],
        row['supervisor'],
        ...rows.expand(
          (student) => [
            student['student_name'],
            student['reg_no'],
            student['tech'],
          ],
        ),
      ].map((value) => (value ?? '').toString().toLowerCase()).toList();
      return words.every((word) {
        if (RegExp(r'^\d+$').hasMatch(word)) {
          if (word.length <= 3) return int.tryParse(word) == number;
          return fields.any((field) => field.contains(word));
        }
        return [
          'group $number',
          row['status'].toString().toLowerCase(),
          ...fields,
        ].any((field) => field.contains(word));
      });
    }).toList();
    visible.sort((a, b) {
      final rank = (sortRank[groups[a]!.first['status']] ?? 5).compareTo(
        sortRank[groups[b]!.first['status']] ?? 5,
      );
      return rank != 0 ? rank : a.compareTo(b);
    });
    return visible;
  }

  Widget groupList() {
    final visible = visibleGroups;
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: refreshMeeting,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount:
              isLoading ||
                  errorMessage.isNotEmpty ||
                  meeting == null ||
                  visible.isEmpty
              ? 1
              : visible.length,
          itemBuilder: (context, index) {
            if (isLoading ||
                errorMessage.isNotEmpty ||
                meeting == null ||
                visible.isEmpty) {
              return ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: isLoading
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomText(
                              text: errorMessage.isNotEmpty
                                  ? errorMessage
                                  : meeting == null
                                  ? 'No meeting is running'
                                  : 'No groups match your search or filter.',
                              textAlign: TextAlign.center,
                              color: errorMessage.isNotEmpty
                                  ? Colors.red
                                  : null,
                            ),

                            if (errorMessage.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Button(text: 'Retry', onTap: loadMeeting),
                            ],

                            if (errorMessage.isEmpty && meeting == null) ...[
                              const SizedBox(height: 10),
                              const CustomText(
                                text: 'Start a meeting from the Meetings tab.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              Button(
                                text: 'Go to Meetings',
                                onTap: () => widget.onNavigate(kMeetings),
                              ),
                            ],
                          ],
                        ),
                ),
              );
            }
            final number = visible[index];
            final rows = groups[number]!;
            final row = rows.first;
            final status = row['status'] as String;
            return Livedetailmeetingcard(
              key: ValueKey('${meeting!.id}:$number'),
              number: number,
              title: row['project'] as String,
              status: '${status[0].toUpperCase()}${status.substring(1)}',
              supervisor: row['supervisor'] as String,
              time: formatTime(
                DateTime.parse('2000-01-01T${row['meeting_time']}'),
              ),
              students: rows,
              timerText: groupTimer(row),
              totalText: status == 'done' && row['duration_sec'] != null
                  ? formatTotal((row['duration_sec'] as num).toInt())
                  : null,
              isExpanded: expandedGroup == number,
              isSelected: selectedGroup == number,
              onExpand: () => setState(
                () => expandedGroup = expandedGroup == number ? null : number,
              ),
              onTap: () => setState(
                () => selectedGroup = selectedGroup == number ? null : number,
              ),
              canStart: canStart(row),
              canEnd: canEnd(row),
              canPauseResume: canPauseResume(row),
              canEditAttendance: canEditAttendance(row),
              onStart: () => changeGroup(number, _GroupAction.start),
              onEnd: () => changeGroup(number, _GroupAction.end),
              onPauseResume: () => changeGroup(
                number,
                status == 'paused' ? _GroupAction.resume : _GroupAction.pause,
              ),
              onSaveAttendance: (regs) =>
                  changeGroup(number, _GroupAction.attendance, regs: regs),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activeMeetingProvider(_dataKey));
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          narrow ? 14 : 18,
          60,
          narrow ? 14 : 18,
          18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!keyboardVisible) ...[
              CustomText(
                text: formatDate(meeting?.meetingDate ?? DateTime.now()),
              ),
              CustomText(
                text: 'Live',
                fontSize: narrow ? 30 : 38,
                fontWeight: FontWeight.w900,
              ),
            ],
            if (meeting?.status == 'paused')
              const CustomText(text: 'Meeting is paused'),
            const SizedBox(height: 10),
            TextBox(controller: search, hintText: 'Search'),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: narrow ? 6 : 10,
                children: [
                  for (var index = 0; index < filters.length; index++)
                    Filter(
                      text: filters[index],
                      isSelected: selectedFilter == index,
                      onTap: () => setState(() => selectedFilter = index),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: groupList()),
          ],
        ),
      ),
    );
  }
}
