import 'package:livemeet/utils/app_error.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/providers/meeting_providers.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/utils/pdf_export.dart';
import 'package:livemeet/utils/time_utils.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/MeetingCard.dart';
import 'package:livemeet/widgets/confirm_dialog.dart';
import 'package:livemeet/widgets/filter.dart';
import 'package:livemeet/screens/edit_meeting_screen.dart';

enum _MeetingAction { start, pauseResume, end, restart }

class MeetingsScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  final ValueChanged<bool> onBusyChanged;

  const MeetingsScreen({
    super.key,
    required this.onNavigate,
    required this.onBusyChanged,
  });

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen> {
  final _dataKey = Object();
  late final MeetingsController _controller;
  MeetingLoadState<List<Meeting>> get _data =>
      ref.read(meetingsProvider(_dataKey));
  bool get isLoading => _data.isLoading;
  bool get busy => _data.busy;
  String get errorMessage => _data.errorMessage;
  List<Meeting> get meetings => _data.data;
  int tab = 0;
  late final Timer ticker;

  // Responsive: true on small phones (width < 360 px).
  bool get narrow => MediaQuery.sizeOf(context).width < 360;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(meetingsProvider(_dataKey).notifier);
    Future.microtask(() {
      if (mounted) loadMeetings();
    });
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && meetings.any((meeting) => meeting.status == 'running')) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.cancelLoads();
    ticker.cancel();
    super.dispose();
  }

  Future<void> loadMeetings() => _controller.load();

  Future<void> refreshMeetings() async {
    if (busy || isLoading) return;
    await loadMeetings();
  }

  Future<void> openEditor(Meeting meeting) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditMeetingScreen(meeting: meeting)),
    );
    if (changed == true && mounted) await loadMeetings();
  }

  Future<void> act(Meeting meeting, _MeetingAction action) async {
    if (busy || isLoading || errorMessage.isNotEmpty) return;
    if (meetings.any((m) => m.isActive && m.id != meeting.id)) return;
    final allowed = switch (action) {
      _MeetingAction.start => meeting.status == 'upcoming',
      // Restart only for finished meetings that still have unfinished groups.
      _MeetingAction.restart =>
        tab == 1 && meeting.status == 'done' && meeting.groupsIncomplete > 0,
      _MeetingAction.pauseResume || _MeetingAction.end => meeting.isActive,
    };
    if (!allowed) return;
    var restarted = false;
    _controller.setBusy(true);
    try {
      if (action != _MeetingAction.pauseResume) {
        final confirmed = await showConfirmDialog(
          context,
          title: switch (action) {
            _MeetingAction.start => 'Start meeting?',
            _MeetingAction.restart => 'Restart meeting?',
            _ => 'End meeting?',
          },
          message: switch (action) {
            _MeetingAction.start =>
              '${meeting.title}\n${formatDate(meeting.meetingDate)}',
            _MeetingAction.restart =>
              '"${meeting.title}" will continue as a running meeting. All timings, attendance and progress are kept. Only groups that were not held will become upcoming again.',
            _ =>
              'The running group will be finished and groups that were not held will be marked as skipped.',
          },
          confirmText: action == _MeetingAction.restart ? 'Restart' : 'Confirm',
        );
        if (!mounted) return;
        if (!confirmed) return;
      }
      widget.onBusyChanged(true);
      switch (action) {
        case _MeetingAction.start:
          await ref.read(meetingServiceProvider).startMeeting(meeting.id);
        case _MeetingAction.pauseResume:
          if (meeting.status == 'paused') {
            await ref.read(meetingServiceProvider).resumeMeeting(meeting.id);
          } else {
            await ref.read(meetingServiceProvider).pauseMeeting(meeting.id);
          }
        case _MeetingAction.end:
          await ref.read(meetingServiceProvider).endMeeting(meeting.id);
        case _MeetingAction.restart:
          await ref.read(meetingServiceProvider).restartMeeting(meeting.id);
          restarted = true;
      }
      if (!mounted) return;
      if (restarted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Meeting restarted')));
      }
      await loadMeetings();
      if (!mounted) return;
    } catch (e, stack) {
      final message = AppError.handle(e, stack, action: ErrorAction.meeting);
      restarted = false;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await loadMeetings();
      if (!mounted) return;
    } finally {
      widget.onBusyChanged(false);
      if (mounted) _controller.setBusy(false);
    }
    // After the busy flag is cleared (MainScreen ignores navigation while
    // busy), take the operator to Live to continue the restarted meeting.
    if (restarted && mounted) widget.onNavigate(kLive);
  }

  List<Meeting> get visibleMeetings {
    final visible = meetings
        .where(
          (m) => tab == 0
              ? m.status == 'upcoming' || m.isActive
              : m.status == 'done',
        )
        .toList();
    visible.sort((a, b) {
      if (tab == 0 && a.isActive != b.isActive) return a.isActive ? -1 : 1;
      final date = tab == 0
          ? a.meetingDate.compareTo(b.meetingDate)
          : b.meetingDate.compareTo(a.meetingDate);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
    return visible;
  }

  Widget meetingList() {
    final visible = visibleMeetings;
    final active = meetings.where((m) => m.isActive).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: refreshMeetings,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: isLoading || errorMessage.isNotEmpty || visible.isEmpty
                ? 1
                : visible.length,
            itemBuilder: (context, index) {
              if (isLoading || errorMessage.isNotEmpty || visible.isEmpty) {
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
                                    : tab == 0
                                    ? 'No coming meetings. Import a schedule first.'
                                    : 'No previous meetings yet.',
                                textAlign: TextAlign.center,
                                color: errorMessage.isNotEmpty
                                    ? Colors.red
                                    : null,
                              ),

                              if (errorMessage.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Button(text: 'Retry', onTap: loadMeetings),
                              ],

                              if (errorMessage.isEmpty && tab == 0) ...[
                                const SizedBox(height: 10),
                                Button(
                                  text: 'Go to Import',
                                  onTap: () => widget.onNavigate(kImport),
                                ),
                              ],
                            ],
                          ),
                  ),
                );
              }
              final meeting = visible[index];
              return MeetingCard(
                key: ValueKey(meeting.id),
                meeting: meeting,
                locked: active != null && active.id != meeting.id,
                busy: busy,
                onStart: () => act(meeting, _MeetingAction.start),
                onPauseResume: () => act(meeting, _MeetingAction.pauseResume),
                onEnd: () => act(meeting, _MeetingAction.end),
                onRestart: tab == 1 && meeting.groupsIncomplete > 0
                    ? () => act(meeting, _MeetingAction.restart)
                    : null,
                // Settings can now be edited while the meeting is running or
                // paused too (only finished meetings are locked).
                onDownload: () => downloadMeeting(meeting),
                onEdit: meeting.status != 'done'
                    ? () => openEditor(meeting)
                    : null,
                // Upcoming and finished (Previous) meetings can be deleted;
                // running or paused ones cannot.
                onDelete:
                    meeting.status == 'upcoming' || meeting.status == 'done'
                    ? () => deleteMeeting(meeting)
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  // Coming meetings: 9 columns. Previous (finished) meetings: + Attendance.
  Future<void> downloadMeeting(Meeting meeting) async {
    if (busy || isLoading) return;
    _controller.setBusy(true);
    try {
      final rows = await ref.read(meetingServiceProvider).fetchRows(meeting.id);
      if (!mounted) return;
      await downloadMeetingPdf(
        meeting,
        rows,
        withAttendance: meeting.status == 'done',
      );
    } catch (e, stack) {
      final message = AppError.handle(e, stack, action: ErrorAction.download);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) _controller.setBusy(false);
    }
  }

  Future<void> deleteMeeting(Meeting meeting) async {
    if (busy || isLoading) return;
    _controller.setBusy(true);
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Delete meeting?',
        message:
            '${meeting.title}\n${formatDate(meeting.meetingDate)}\n\nThis permanently deletes the meeting and all its groups.',
        confirmText: 'Delete',
      );
      if (!mounted) return;
      if (!confirmed) return;
      widget.onBusyChanged(true);
      await ref.read(meetingServiceProvider).deleteMeeting(meeting.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meeting deleted')));
      await loadMeetings();
    } catch (e, stack) {
      final message = AppError.handle(e, stack, action: ErrorAction.delete);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      widget.onBusyChanged(false);
      if (mounted) _controller.setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(meetingsProvider(_dataKey));
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
            CustomText(text: formatDate(DateTime.now())),
            CustomText(
              text: 'Meetings',
              fontSize: narrow ? 30 : 38,
              fontWeight: FontWeight.w900,
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: narrow ? 6 : 10,
                children: [
                  Filter(
                    text: 'Coming meetings',
                    isSelected: tab == 0,
                    onTap: () => setState(() => tab = 0),
                  ),
                  Filter(
                    text: 'Previous meetings',
                    isSelected: tab == 1,
                    onTap: () => setState(() => tab = 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Expanded(child: meetingList()),
          ],
        ),
      ),
    );
  }
}
