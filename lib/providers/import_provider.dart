import 'package:livemeet/utils/app_error.dart';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/providers/app_providers.dart';

class ImportState {
  final String step,
      fileName,
      errorText,
      summary,
      meetingTitle,
      alreadyAddedText;
  final bool isUploaded, isError, alreadyAdded, hasExisting, canImport, busy;
  final List<Map<String, dynamic>> rows;
  ImportState({
    this.step = 'Step 1 of 2',
    this.fileName = '',
    this.errorText = '',
    this.summary = '',
    this.meetingTitle = '',
    this.alreadyAddedText = '',
    this.isUploaded = false,
    this.isError = false,
    this.alreadyAdded = false,
    this.hasExisting = false,
    this.canImport = false,
    this.busy = false,
    List<Map<String, dynamic>> rows = const [],
  }) : rows = List.unmodifiable(
         rows.map((row) => Map<String, dynamic>.unmodifiable(row)),
       );
  ImportState copyWith({
    bool? busy,
    bool? isError,
    String? errorText,
    bool? canImport,
  }) => ImportState(
    step: step,
    fileName: fileName,
    errorText: errorText ?? this.errorText,
    summary: summary,
    meetingTitle: meetingTitle,
    alreadyAddedText: alreadyAddedText,
    isUploaded: isUploaded,
    isError: isError ?? this.isError,
    alreadyAdded: alreadyAdded,
    hasExisting: hasExisting,
    canImport: canImport ?? this.canImport,
    busy: busy ?? this.busy,
    rows: rows,
  );
}

final importProvider = NotifierProvider.autoDispose
    .family<ImportController, ImportState, Object>(ImportController.new);

class ImportController extends Notifier<ImportState> {
  ImportController(this.owner);
  final Object owner;
  int _request = 0;
  bool _closed = false;
  @override
  ImportState build() {
    ref.onDispose(cancelPreview);
    return ImportState();
  }

  void cancelPreview() {
    _closed = true;
    _request++;
  }

  bool _current(int request) => !_closed && ref.mounted && request == _request;
  void setBusy(bool value) => state = state.copyWith(busy: value);
  void reset() {
    _request++;
    state = ImportState(busy: state.busy);
  }

  void showError(String message) => state = state.copyWith(
    isError: true,
    errorText: message,
    canImport: false,
  );

  String cellText(Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    return v.toString().trim();
  }

  // cell ki date -> '2026-10-13'
  String? cellDate(Data? cell) {
    final v = cell?.value;
    if (v is DateCellValue) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    if (v is DateTimeCellValue) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    return null;
  }

  // cell ka time -> '11:00'
  String? cellTime(Data? cell) {
    final v = cell?.value;
    if (v is TimeCellValue) {
      return '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    }
    if (v is DateTimeCellValue) {
      return '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    }
    return null;
  }

  Future<void> preview(Uint8List bytes, String name) async {
    final request = ++_request;
    final service = ref.read(meetingServiceProvider);
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const UserMessageException(
        'This file has no worksheet. Choose an Excel file containing your schedule.',
      );
    }
    final sheet = excel.tables[excel.tables.keys.first]!;
    final sheetRows = sheet.rows;
    // New file format has no title row: row 1 is the header (S.No., Reg #, ...).
    // In that case the meeting title comes from the file name.
    final firstCell = sheetRows.isEmpty || sheetRows.first.isEmpty
        ? ''
        : cellText(sheetRows.first.first);
    final title = firstCell.toLowerCase().startsWith('s.no') ? '' : firstCell;
    final parsedTitle = title.isEmpty
        ? name.replaceFirst(RegExp(r'\.xlsx$', caseSensitive: false), '')
        : title;

    final list = <Map<String, dynamic>>[];

    int groupNo = 0;
    String lastRow = '';
    String lastDate = '';

    for (var index = 0; index < sheetRows.length; index++) {
      final row = sheetRows[index];
      if (row.length < 8) continue;

      final date = cellDate(row[7]);
      final time = cellTime(row[6]);

      if (date == null || time == null) continue;
      final requiredCells = {
        1: 'a reg #',
        2: 'a student name',
        3: 'a supervisor',
        4: 'a project',
      };
      for (final entry in requiredCells.entries) {
        if (cellText(row[entry.key]).isEmpty) {
          throw UserMessageException(
            'Row ${index + 1} is missing ${entry.value}.',
          );
        }
      }
      final key = '$date|$time|${cellText(row[4])}|${cellText(row[3])}';

      if (date != lastDate) {
        groupNo = 0;
        lastDate = date;
      }

      if (key != lastRow) {
        groupNo++;
        lastRow = key;
      }

      list.add({
        'group_no': groupNo,
        'meeting_date': date,
        'meeting_time': time,
        'project': cellText(row[4]),
        'supervisor': cellText(row[3]),
        'reg_no': cellText(row[1]),
        'student_name': cellText(row[2]),
        'tech': cellText(row[5]),
      });
    }
    if (list.isEmpty) {
      throw const UserMessageException(
        'No schedule rows were found. Add student rows with valid Excel dates and times, then choose the file again.',
      );
    }

    final dates = list.map((r) => r['meeting_date'] as String).toSet();
    final days = dates.length;
    final groups = list
        .map(
          (r) =>
              '${r['meeting_date']}|${r['meeting_time']}|${r['project']}|${r['supervisor']}',
        )
        .toSet()
        .length;

    final existingDates = await service.fetchExistingDates(
      parsedTitle,
      dates.toList(),
    );
    if (!_current(request)) return;
    final existingCount = dates.intersection(existingDates).length;

    state = ImportState(
      rows: list,
      meetingTitle: parsedTitle,
      fileName: name,
      summary: '$days days | $groups groups | ${list.length} students',
      isUploaded: true,
      isError: false,
      step: 'Step 2 of 2',
      alreadyAdded: existingCount == days,
      hasExisting: existingCount > 0,
      alreadyAddedText: existingCount == days
          ? 'Already added. Importing this file will update the upcoming groups of these meetings. Groups that already started or finished are kept as they are, and finished meetings are not changed.'
          : existingCount > 0
          ? '$existingCount of $days days already added. Their upcoming groups will be updated (started or finished groups are kept as they are), the rest will be imported.'
          : '',
      canImport: true,
      busy: state.busy,
    );
  }
}
