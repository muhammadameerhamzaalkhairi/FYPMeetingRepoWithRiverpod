import 'package:flutter/material.dart';
import 'package:livemeet/widgets/CustomText.dart';

/// Shown when a group is started. All students are checked (present) by
/// default; unchecked = absent. Returns the list of present reg numbers,
/// or null if the operator cancelled.
Future<List<String>?> showAttendanceDialog(
  BuildContext context, {
  required int number,
  required String project,
  required List<Map<String, dynamic>> students,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _AttendanceDialog(number: number, project: project, students: students),
  );
}

class _AttendanceDialog extends StatefulWidget {
  final int number;
  final String project;
  final List<Map<String, dynamic>> students;

  const _AttendanceDialog({
    required this.number,
    required this.project,
    required this.students,
  });

  @override
  State<_AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<_AttendanceDialog> {
  late final List<String> regs;
  late final Set<String> present;

  @override
  void initState() {
    super.initState();
    regs = [for (final s in widget.students) s['reg_no'].toString()];
    present = regs.toSet(); // everyone checked by default
  }

  bool get allPresent => present.length == regs.length;

  @override
  Widget build(BuildContext context) {
    // Responsive: same dialog spacing rules as showConfirmDialog.
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 16 : 40,
        vertical: 24,
      ),
      titlePadding: EdgeInsets.fromLTRB(
        narrow ? 18 : 24,
        narrow ? 18 : 24,
        narrow ? 18 : 24,
        0,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        narrow ? 18 : 24,
        16,
        narrow ? 18 : 24,
        8,
      ),
      actionsPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 16,
        vertical: 8,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      title: CustomText(
        text: 'Start group ${widget.number}?',
        fontWeight: FontWeight.bold,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(text: widget.project),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: CustomText(
                      text: '${present.length} of ${regs.length} present',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (allPresent) {
                        present.clear();
                      } else {
                        present.addAll(regs);
                      }
                    }),
                    style: TextButton.styleFrom(foregroundColor: Colors.black),
                    child: Text(allPresent ? 'Uncheck all' : 'Check all'),
                  ),
                ],
              ),
              for (final student in widget.students)
                CheckboxListTile(
                  value: present.contains(student['reg_no'].toString()),
                  onChanged: (value) => setState(() {
                    final reg = student['reg_no'].toString();
                    if (value == true) {
                      present.add(reg);
                    } else {
                      present.remove(reg);
                    }
                  }),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.black,
                  checkColor: Colors.white,
                  title: CustomText(
                    text: student['student_name']?.toString() ?? '',
                    fontWeight: FontWeight.bold,
                  ),
                  subtitle: CustomText(
                    text: student['reg_no']?.toString() ?? '',
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(
            context,
          ).pop([for (final reg in regs) if (present.contains(reg)) reg]),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF111111),
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
          ),
          child: const Text('Start'),
        ),
      ],
    );
  }
}