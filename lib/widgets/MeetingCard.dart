// Keep the widget filename specified by the feature spec.
// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/utils/time_utils.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';

class MeetingCard extends StatelessWidget {
  final Meeting meeting;
  final bool locked;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onPauseResume;
  final VoidCallback onEnd;
  final VoidCallback? onRestart;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const MeetingCard({
    super.key,
    required this.meeting,
    required this.locked,
    required this.busy,
    required this.onStart,
    required this.onPauseResume,
    required this.onEnd,
    this.onRestart,
    this.onEdit,
    this.onDelete,
  });

  Widget chip(String text) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color.fromARGB(255, 219, 219, 219),
      borderRadius: BorderRadius.circular(25),
    ),
    child: CustomText(text: text, fontSize: 12),
  );

  String timeLabel(DateTime? time) => time == null ? '—' : formatTime(time);

  @override
  Widget build(BuildContext context) {
    const labels = {
      'upcoming': 'Upcoming',
      'running': 'Running',
      'paused': 'Paused',
      'done': 'Done',
    };
    final enabled = !locked && !busy;
    final startedAt = meeting.startedAt;

    // Responsive: tighter padding and smaller timer on narrow phones.
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final pad = narrow ? 10.0 : 12.0;

    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: meeting.isActive ? const Color(0xFFDDF35C) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CustomText(
                    text: meeting.title,
                    fontSize: narrow ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (onEdit != null)
                  GestureDetector(
                    onTap: busy ? null : onEdit,
                    child: Opacity(
                      opacity: busy ? 0.4 : 1,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.settings_outlined, size: 24),
                      ),
                    ),
                  ),
                if (onDelete != null)
                  GestureDetector(
                    onTap: busy ? null : onDelete,
                    child: Opacity(
                      opacity: busy ? 0.4 : 1,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 24,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                chip(labels[meeting.status] ?? meeting.status),
                const SizedBox(width: 5),
                Expanded(
                  child: CustomText(
                    text: formatDate(meeting.meetingDate),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            CustomText(
              text:
                  '${meeting.groupsTotal} groups · ${meeting.studentsTotal} students',
            ),
            const SizedBox(height: 10),
            if (meeting.status == 'upcoming')
              const CustomText(text: 'Not started'),
            if (meeting.isActive) ...[
              CustomText(text: 'Started ${timeLabel(startedAt)}'),
              CustomText(
                text: startedAt == null
                    ? '—'
                    : formatClock(
                        elapsedSec(
                          startedAt: startedAt,
                          pausedSeconds: meeting.pausedSeconds,
                          frozenAt: meeting.pausedAt,
                        ),
                      ),
                fontSize: narrow ? 24 : 28,
                fontWeight: FontWeight.bold,
              ),
            ],
            if (meeting.status == 'done') ...[
              CustomText(
                text:
                    'Started ${timeLabel(startedAt)} · Ended ${timeLabel(meeting.endedAt)}',
              ),
              const SizedBox(height: 5),
              chip(
                'Total ${meeting.totalSeconds == null ? '—' : formatTotal(meeting.totalSeconds!)}',
              ),
              const SizedBox(height: 5),
              CustomText(
                text:
                    'Done ${meeting.groupsDone} · Skipped ${meeting.groupsSkipped}',
              ),
              if (onRestart != null) ...[
                const SizedBox(height: 10),
                Button(
                  text: 'Restore meeting',
                  height: 48,
                  fontSize: narrow ? 14 : 15,
                  enabled: enabled,
                  onTap: onRestart,
                ),
              ],
            ],
            if (meeting.status != 'done') ...[
              const SizedBox(height: 10),
              Row(
                spacing: narrow ? 6 : 10,
                children: [
                  Expanded(
                    child: Button(
                      text: 'Start',
                      height: 48,
                      fontSize: narrow ? 14 : 15,
                      enabled: enabled && meeting.status == 'upcoming',
                      onTap: onStart,
                    ),
                  ),
                  Expanded(
                    child: Button(
                      text: meeting.status == 'paused' ? 'Resume' : 'Pause',
                      height: 48,
                      fontSize: narrow ? 14 : 15,
                      enabled: enabled && meeting.isActive,
                      onTap: onPauseResume,
                    ),
                  ),
                  Expanded(
                    child: Button(
                      text: 'End',
                      height: 48,
                      fontSize: narrow ? 14 : 15,
                      enabled: enabled && meeting.isActive,
                      onTap: onEnd,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}