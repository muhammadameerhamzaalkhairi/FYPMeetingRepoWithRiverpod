// Preserve the existing widget filename required by the feature spec.
// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';

class Livedetailmeetingcard extends StatefulWidget {
  final int number;
  final String title;
  final String status;
  final String supervisor;
  final String time;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onExpand;
  final String? timerText;
  final String? totalText;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;
  final VoidCallback? onPauseResume;
  final bool canStart;
  final bool canEnd;
  final bool canPauseResume;
  final bool canEditAttendance;
  // Receives the FULL list of reg numbers that should be present.
  final ValueChanged<List<String>>? onSaveAttendance;
  final List<Map<String, dynamic>> students;

  const Livedetailmeetingcard({
    super.key,
    required this.number,
    required this.title,
    required this.status,
    required this.supervisor,
    required this.time,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    required this.onExpand,
    this.timerText,
    this.totalText,
    this.onStart,
    this.onEnd,
    this.onPauseResume,
    this.canStart = false,
    this.canEnd = false,
    this.canPauseResume = false,
    this.canEditAttendance = false,
    this.onSaveAttendance,
    this.students = const [],
  });

  @override
  State<Livedetailmeetingcard> createState() => _LivedetailmeetingcardState();
}

class _LivedetailmeetingcardState extends State<Livedetailmeetingcard> {
  // What the operator currently sees ticked (may differ from the DB until saved).
  late Set<String> checked;

  String get normalizedStatus => widget.status.toLowerCase();

  // Attendance can be edited for any group that has started (also after it
  // is done). Checkboxes are never locked by an earlier mark.
  bool get attendanceOpen =>
      normalizedStatus == 'running' ||
      normalizedStatus == 'paused' ||
      normalizedStatus == 'done';

  static String regOf(Map<String, dynamic> student) =>
      student['reg_no']?.toString() ?? '';

  static Set<String> savedPresent(List<Map<String, dynamic>> students) => {
    for (final s in students)
      if (s['is_present'] == true) regOf(s),
  };

  Set<String> get saved => savedPresent(widget.students);

  // number of students whose tick differs from what is saved
  int get changes => checked.difference(saved).length +
      saved.difference(checked).length;

  bool get dirty => changes > 0;

  @override
  void initState() {
    super.initState();
    checked = saved;
  }

  @override
  void didUpdateWidget(covariant Livedetailmeetingcard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = savedPresent(oldWidget.students);
    final after = saved;
    // Saved attendance changed (after Save or a refresh): show the DB state.
    // Otherwise keep the operator's unsaved ticks.
    if (before.length != after.length || !before.containsAll(after)) {
      checked = after;
    }
    if (!attendanceOpen) checked = after;
  }

  void toggle(String reg, bool value) {
    setState(() {
      if (value) {
        checked.add(reg);
      } else {
        checked.remove(reg);
      }
    });
  }

  void saveAttendance() {
    if (!widget.canEditAttendance || !dirty) return;
    widget.onSaveAttendance?.call(checked.toList());
  }

  // compact button, left of End / Start / Pause
  Widget saveIconButton({required bool narrow}) {
    final enabled = widget.canEditAttendance && dirty;
    return Tooltip(
      message: 'Save attendance',
      child: GestureDetector(
        onTap: enabled ? saveAttendance : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: narrow ? 52 : 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.how_to_reg_rounded, size: 22),
                if (dirty) ...[
                  const SizedBox(width: 2),
                  CustomText(
                    text: '$changes',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget studentRow(Map<String, dynamic> student) {
    final reg = regOf(student);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (attendanceOpen) ...[
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: checked.contains(reg),
                activeColor: Colors.black,
                checkColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                // Always editable (tick or untick), as long as no other
                // action is running.
                onChanged: widget.canEditAttendance
                    ? (value) => toggle(reg, value ?? false)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  text: student['student_name']?.toString() ?? '',
                  fontWeight: FontWeight.bold,
                ),
                CustomText(text: reg, fontSize: 12),
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
              child: CustomText(
                text: student['tech']?.toString() ?? '',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Running shows the live timer, paused shows the saved (frozen) time,
    // done shows the total.
    final timing = normalizedStatus == 'running' || normalizedStatus == 'paused'
        ? widget.timerText
        : normalizedStatus == 'done'
        ? widget.totalText
        : null;

    // Responsive: tighter sizes on narrow phones so the title gets more room.
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final pad = narrow ? 10.0 : 12.0;

    final showActionRow =
        widget.isSelected &&
        normalizedStatus != 'done' &&
        normalizedStatus != 'skipped';
    // Done groups (and cards that are not selected) have no action row, so
    // the save button appears under the student list as soon as a tick changes.
    final showInlineSave =
        widget.isExpanded &&
        attendanceOpen &&
        dirty &&
        !(showActionRow && normalizedStatus != 'done');

    return GestureDetector(
      onTap: widget.onTap,

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? const Color(0xFFDDF35C)
              : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(20),
        ),

        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: narrow ? 20 : 25,
                    height: narrow ? 20 : 25,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      color: Colors.white,
                      border: Border.all(),
                    ),
                    child: widget.isSelected
                        ? Container(
                            width: 25,
                            height: 25,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(50),
                            ),
                          )
                        : null,
                  ),
                  SizedBox(width: narrow ? 6 : 10),
                  CustomText(
                    text: widget.number.toString(),
                    fontSize: narrow ? 26 : 32,
                    fontWeight: FontWeight.bold,
                  ),
                  SizedBox(width: narrow ? 6 : 10),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomText(
                          text: widget.title,
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
                                text: widget.status,
                                fontSize: 12,
                              ),
                            ),

                            CustomText(
                              text: '${widget.supervisor} - ${widget.time}',
                              fontSize: 12,
                            ),
                            if (timing != null)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(
                                    255,
                                    219,
                                    219,
                                    219,
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: CustomText(text: timing, fontSize: 12),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    // FIX: onPressed was null, so the arrow was disabled
                    child: IconButton(
                      padding: narrow ? EdgeInsets.zero : null,
                      onPressed: widget.onExpand,
                      icon: widget.isExpanded
                          ? const Icon(
                              Icons.arrow_drop_up_rounded,
                              color: Colors.black,
                            )
                          : const Icon(
                              Icons.arrow_drop_down_rounded,
                              color: Colors.black,
                            ),
                    ),
                  ),
                ],
              ),

              if (widget.isExpanded) ...[
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.students.length,
                  itemBuilder: (context, index) =>
                      studentRow(widget.students[index]),
                ),
              ],

              if (showInlineSave) ...[
                const SizedBox(height: 10),
                Button(
                  text: 'Save attendance ($changes)',
                  height: 44,
                  fontSize: narrow ? 13 : 14,
                  enabled: widget.canEditAttendance,
                  onTap: saveAttendance,
                ),
              ],

              const SizedBox(height: 10),

              showActionRow
                  ? Row(
                      spacing: narrow ? 6 : 10,
                      children: [
                        if (attendanceOpen) saveIconButton(narrow: narrow),
                        Expanded(
                          child: Button(
                            text: 'End',
                            fontSize: narrow ? 14 : 15,
                            enabled: widget.canEnd,
                            onTap: widget.onEnd,
                          ),
                        ),
                        Expanded(
                          child: Button(
                            text: 'Start',
                            fontSize: narrow ? 14 : 15,
                            enabled: widget.canStart,
                            onTap: widget.onStart,
                          ),
                        ),
                        Expanded(
                          child: Button(
                            text: normalizedStatus == 'paused'
                                ? 'Resume'
                                : 'Pause',
                            fontSize: narrow ? 14 : 15,
                            enabled: widget.canPauseResume,
                            onTap: widget.onPauseResume,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(),
            ],
          ),
        ),
      ),
    );
  }
}