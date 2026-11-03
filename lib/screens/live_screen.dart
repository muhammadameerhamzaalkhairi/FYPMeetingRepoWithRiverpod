import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/services/meeting_service.dart';
import 'package:livemeet/utils/time_utils.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:livemeet/widgets/LiveDetailMeetingCard.dart';
import 'package:livemeet/widgets/TextBox.dart';
import 'package:livemeet/widgets/confirm_dialog.dart';
import 'package:livemeet/widgets/filter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _GroupAction { start, end, pauseResume }

class LiveScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  final ValueChanged<bool> onBusyChanged;

  const LiveScreen({
    super.key,
    required this.onNavigate,
    required this.onBusyChanged,
  });

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  static const sortRank = {
    'running': 0,
    'upcoming': 1,
    'done': 2,
    'skipped': 3,
  };
  static const filters = ['All', 'Running', 'Upcoming', 'Done'];
  final search = TextEditingController();
  Meeting? meeting;
  Map<int, List<Map<String, dynamic>>> groups = {};
  int selectedFilter = 0;
  int? selectedGroup;
  int? expandedGroup;
  bool isLoading = false;
  bool busy = false;
  String errorMessage = '';
  late final Timer ticker;

  // Responsive: true on small phones (width < 360 px).
  bool get narrow => MediaQuery.sizeOf(context).width < 360;

  @override
  void initState() {
    super.initState();
    search.addListener(searchChanged);
    loadMeeting(selectRunningGroup: true);
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && meeting?.status == 'running' && hasRunningGroup) {
        setState(() {});
      }
    });
  }

  void searchChanged() => setState(() {});

  @override
  void dispose() {
    ticker.cancel();
    search.removeListener(searchChanged);
    search.dispose();
    super.dispose();
  }

  Future<void> loadMeeting({bool selectRunningGroup = false}) async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    try {
      await syncServerClock();
      if (!mounted) return;
      final active = await MeetingService.fetchActiveMeeting();
      if (!mounted) return;
      final Map<int, List<Map<String, dynamic>>> loaded = {};
      if (active != null) {
        final rows = await MeetingService.fetchRows(active.id);
        if (!mounted) return;
        for (final row in rows) {
          final number = (row['group_no'] as num).toInt();
          loaded.putIfAbsent(number, () => []).add(row);
        }
      }
      setState(() {
        if (meeting?.id != active?.id) {
          selectedGroup = null;
          expandedGroup = null;
        }
        meeting = active;
        groups = loaded;
        if (selectRunningGroup) {
          selectedGroup = groups.entries
              .where((entry) => entry.value.first['status'] == 'running')
              .map((entry) => entry.key)
              .firstOrNull;
        }
        if (!groups.containsKey(selectedGroup)) selectedGroup = null;
        if (!groups.containsKey(expandedGroup)) expandedGroup = null;
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

  Future<void> refreshMeeting() async {
    if (busy || isLoading) return;
    await loadMeeting();
  }

  bool get hasRunningGroup =>
      groups.values.any((rows) => rows.first['status'] == 'running');

  bool canStart(Map<String, dynamic> row) =>
      !busy &&
      !isLoading &&
      errorMessage.isEmpty &&
      meeting?.status == 'running' &&
      row['status'] == 'upcoming' &&
      !hasRunningGroup;

  bool canEnd(Map<String, dynamic> row) =>
      !busy &&
      !isLoading &&
      errorMessage.isEmpty &&
      meeting?.status == 'running' &&
      row['status'] == 'running';

  bool canPauseResume(Map<String, dynamic> row) =>
      !busy &&
      !isLoading &&
      errorMessage.isEmpty &&
      meeting?.isActive == true &&
      row['status'] == 'running';

  String? groupTimer(Map<String, dynamic> row) {
    if (row['status'] != 'running' || row['started_at'] == null) return null;
    return formatClock(
      elapsedSec(
        startedAt: DateTime.parse(row['started_at'] as String),
        pausedSeconds: (row['paused_seconds'] as num?)?.toInt() ?? 0,
        frozenAt: meeting?.pausedAt,
      ),
    );
  }

  Future<void> changeGroup(int number, _GroupAction action) async {
    final active = meeting;
    final row = groups[number]?.first;
    if (active == null || row == null) return;
    final allowed = switch (action) {
      _GroupAction.start => canStart(row),
      _GroupAction.end => canEnd(row),
      _GroupAction.pauseResume => canPauseResume(row),
    };
    if (!allowed) return;
    setState(() => busy = true);
    try {
      if (action != _GroupAction.pauseResume) {
        final confirmed = await showConfirmDialog(
          context,
          title:
              '${action == _GroupAction.start ? 'Start' : 'End'} group $number?',
          message: action == _GroupAction.start
              ? row['project'] as String
              : 'Elapsed time: ${groupTimer(row) ?? '—'}',
        );
        if (!mounted) return;
        if (!confirmed) return;
      }
      widget.onBusyChanged(true);
      switch (action) {
        case _GroupAction.start:
          await MeetingService.startGroup(active.id, number);
        case _GroupAction.end:
          await MeetingService.endGroup(active.id, number);
        case _GroupAction.pauseResume:
          if (active.status == 'paused') {
            await MeetingService.resumeMeeting(active.id);
          } else {
            await MeetingService.pauseMeeting(active.id);
          }
      }
      if (!mounted) return;
      if (action == _GroupAction.start) setState(() => selectedGroup = number);
      await loadMeeting();
      if (!mounted) return;
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      await loadMeeting();
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Group action failed: $e')));
      await loadMeeting();
      if (!mounted) return;
    } finally {
      widget.onBusyChanged(false);
      if (mounted) setState(() => busy = false);
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
      final rank = (sortRank[groups[a]!.first['status']] ?? 4).compareTo(
        sortRank[groups[b]!.first['status']] ?? 4,
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
              isPaused: meeting!.status == 'paused',
              onStart: () => changeGroup(number, _GroupAction.start),
              onEnd: () => changeGroup(number, _GroupAction.end),
              onPauseResume: () =>
                  changeGroup(number, _GroupAction.pauseResume),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(narrow ? 14 : 18, 60, narrow ? 14 : 18, 18),
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