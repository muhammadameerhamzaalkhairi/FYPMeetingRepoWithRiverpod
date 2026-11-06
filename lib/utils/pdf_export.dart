import 'dart:math' as math;

import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/utils/time_utils.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Premium green, used for the table header row only.
const _green = PdfColor.fromInt(0xFF1E6B45);
const _line = PdfColor.fromInt(0xFFBFC5C1);
const _present = PdfColor.fromInt(0xFF1B8A3E);
const _absent = PdfColor.fromInt(0xFFD32F2F);

const _fs = 8.5; // body font size
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _shortDate(DateTime d) => '${_two(d.day)} ${_months[d.month - 1]} ${d.year}';

bool _held(String? status) =>
    status == 'running' || status == 'paused' || status == 'done';

// Attendance is only meaningful for groups that were actually held.
String _attendance(Map<String, dynamic> row) {
  if (_held(row['status'] as String?)) {
    return row['is_present'] == true ? 'Present' : 'Absent';
  }
  return 'Not held';
}

// Saved group duration (pauses already excluded by the database).
String _total(Map<String, dynamic> row) {
  final status = row['status'];
  final seconds = (row['duration_sec'] as num?)?.toInt();
  if ((status == 'done' || status == 'paused') && seconds != null) {
    return formatTotal(seconds);
  }
  if (status == 'running') return 'Running';
  return '-';
}

String _fileName(Meeting meeting) {
  final title = meeting.title
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  return '${title.isEmpty ? 'Meeting' : title}_${_isoDate(meeting.meetingDate)}.pdf';
}

// Rough height of a wrapped text cell. Cells have a fixed height so merged
// group cells line up exactly with the student rows next to them.
double _cellH(String text, double width, {double fs = _fs, double k = 0.58}) {
  final usable = math.max(10, width - 8);
  final lines = ((text.length * fs * k) / usable).ceil().clamp(1, 99);
  return lines * fs * 1.3 + 10;
}

pw.Widget _cell(
  String text,
  double width,
  double height, {
  bool header = false,
  bool first = false,
  bool center = false,
  bool bold = false,
  PdfColor? color,
}) {
  final side = pw.BorderSide(color: _line, width: 0.5);
  // Only right + bottom lines per cell (plus top on the header and left on
  // the first column), so neighbouring cells never draw a double line.
  final border = header && first
      ? pw.Border(top: side, right: side, bottom: side, left: side)
      : header
      ? pw.Border(top: side, right: side, bottom: side)
      : first
      ? pw.Border(right: side, bottom: side, left: side)
      : pw.Border(right: side, bottom: side);
  return pw.Container(
    width: width,
    height: height,
    alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4),
    decoration: pw.BoxDecoration(
      color: header ? _green : null,
      border: border,
    ),
    child: pw.Text(
      text,
      textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: header ? 9 : _fs,
        fontWeight: header || bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: header ? PdfColors.white : (color ?? PdfColors.black),
      ),
    ),
  );
}

pw.Widget _stat(String label, String value) => pw.Expanded(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text(
        label,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ),
);

/// Builds the meeting PDF from [rows] (meeting_schedule rows) and saves/shares
/// it as `MeetingTitle_Date.pdf`. [withAttendance] adds the Attendance column
/// (Previous meetings). Supervisor, Project, Start Time, Date and Total Time
/// are shown once per group in vertically merged cells.
Future<void> downloadMeetingPdf(
  Meeting meeting,
  List<Map<String, dynamic>> rows, {
  required bool withAttendance,
}) async {
  if (rows.isEmpty) throw Exception('This meeting has no students.');

  // Always group 1, 2, 3... (then the DB row order inside a group).
  rows = [...rows]..sort((a, b) {
    final byGroup = (a['group_no'] as num).compareTo(b['group_no'] as num);
    if (byGroup != 0) return byGroup;
    return ((a['id'] as num?) ?? 0).compareTo((b['id'] as num?) ?? 0);
  });
  final groups = <int, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    groups.putIfAbsent((r['group_no'] as num).toInt(), () => []).add(r);
  }

  // ---------- summary (actual saved meeting timestamps) ----------
  final firstRows = [for (final g in groups.values) g.first];
  final attended = firstRows.where((r) => _held(r['status'] as String?)).length;
  final skipped = firstRows.where((r) => r['status'] == 'skipped').length;
  final started = meeting.startedAt;
  final ended = meeting.endedAt;
  final startText = started == null ? 'Not started' : formatTime(started);
  final endText = ended != null
      ? formatTime(ended)
      : (started == null ? '-' : 'In progress');

  // ------- columns --------
  final labels = [
    'S.No',
    'Reg #',
    'Student',
    'Supervisor',
    'Project',
    'Tech',
    'Time',
    'Date',
    'Total Time',
    if (withAttendance) 'Attendance',
  ];

  final base = <double>[34, 88, 112, 80, 150, 72, 58, 62, 52, if (withAttendance) 62];
  final pageWidth = PdfPageFormat.a4.landscape.width - 56; // 28pt margins
  final scale = pageWidth / base.fold<double>(0, (a, b) => a + b);
  final w = [for (final b in base) b * scale];

  final headerH = [
    for (var i = 0; i < labels.length; i++)
      _cellH(labels[i], w[i], fs: 9, k: 0.64),
  ].reduce(math.max);

  final date = _shortDate(meeting.meetingDate);

  pw.Widget groupBlock(List<Map<String, dynamic>> g, int firstSerial) {
    final head = g.first;
    final supervisor = '${head['supervisor'] ?? ''}';
    final project = '${head['project'] ?? ''}';
    final start = formatTime(DateTime.parse('2000-01-01T${head['meeting_time']}'));
    final total = _total(head);

    // Student-level texts, one per row.
    final regs = [for (final r in g) '${r['reg_no'] ?? ''}'];
    final names = [for (final r in g) '${r['student_name'] ?? ''}'];
    final techs = [for (final r in g) '${r['tech'] ?? ''}'];
    final atts = [for (final r in g) _attendance(r)];

    // Row heights: tallest student-level cell in each row.
    final heights = [
      for (var k = 0; k < g.length; k++)
        math.max(
          22.0,
          [
            _cellH(regs[k], w[1]),
            _cellH(names[k], w[2]),
            _cellH(techs[k], w[5]),
          ].reduce(math.max),
        ),
    ];
    // The merged group cells may need more height than the student rows.
    final groupNeed = [
      _cellH(supervisor, w[3]),
      _cellH(project, w[4]),
      _cellH(start, w[6]),
      _cellH(date, w[7]),
      _cellH(total, w[8]),
    ].reduce(math.max);
    final students = heights.fold<double>(0, (a, b) => a + b);
    final groupH = math.max(students, groupNeed);
    final extra = (groupH - students) / g.length;
    for (var k = 0; k < heights.length; k++) {
      heights[k] += extra;
    }

    pw.Widget studentCol(
      int i,
      String Function(int) text, {
      bool first = false,
      bool center = false,
      PdfColor? Function(int)? color,
    }) => pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (var k = 0; k < g.length; k++)
          _cell(
            text(k),
            w[i],
            heights[k],
            first: first,
            center: center,
            color: color?.call(k),
            bold: color?.call(k) != null,
          ),
      ],
    );

    pw.Widget merged(int i, String text) =>
        _cell(text, w[i], groupH, center: true);

    PdfColor? attColor(int k) => switch (atts[k]) {
      'Present' => _present,
      'Absent' => _absent,
      _ => null,
    };

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        studentCol(0, (k) => '${firstSerial + k}', first: true, center: true),
        studentCol(1, (k) => regs[k]),
        studentCol(2, (k) => names[k]),
        merged(3, supervisor),
        merged(4, project),
        studentCol(5, (k) => techs[k]),
        merged(6, start),
        merged(7, date),
        merged(8, total),
        if (withAttendance) studentCol(9, (k) => atts[k], color: attColor),
      ],
    );
  }

  // Built once, up front, so S.No numbering can't drift if the page builder
  // runs more than once.
  final blocks = <pw.Widget>[];
  var serial = 0;
  for (final g in groups.values) {
    blocks.add(groupBlock(g, serial + 1));
    serial += g.length;
  }

  final doc = pw.Document(title: meeting.title, author: 'Live Meet');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      // Title, summary and the green header appear once, on page 1.
      // Each group is one unbreakable block, so it never splits across pages.
      build: (_) => [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              meeting.title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              formatDate(meeting.meetingDate),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line, width: 0.5),
              ),
              child: pw.Row(
                children: [
                  _stat('Total Groups', '${groups.length}'),
                  _stat('Groups Attended', '$attended'),
                  _stat('Groups Skipped', '$skipped'),
                  // _stat('Actual Start Time', startText),
                  // _stat('Actual End Time', endText),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        pw.Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              _cell(labels[i], w[i], headerH, header: true, first: i == 0),
          ],
        ),
        ...blocks,
      ],
    ),
  );

  await Printing.sharePdf(bytes: await doc.save(), filename: _fileName(meeting));
}