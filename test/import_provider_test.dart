import 'package:livemeet/utils/app_error.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/providers/import_provider.dart';
import 'support/fake_meeting_service.dart';

Uint8List workbook({bool validDate = true}) {
  final excel = Excel.createExcel(), sheetName = 'Sheet1';
  final sheet = excel[sheetName];
  sheet.appendRow([
    TextCellValue('S.No.'),
    TextCellValue('Reg #'),
    TextCellValue('Student'),
    TextCellValue('Supervisor'),
    TextCellValue('Project'),
    TextCellValue('Tech'),
    TextCellValue('Time'),
    TextCellValue('Date'),
  ]);
  for (final reg in ['R1', 'R2']) {
    sheet.appendRow([
      IntCellValue(1),
      TextCellValue(reg),
      TextCellValue('Student $reg'),
      TextCellValue('Supervisor'),
      TextCellValue('Project'),
      TextCellValue('Flutter'),
      TimeCellValue(hour: 9, minute: 0),
      validDate
          ? DateCellValue(year: 2026, month: 11, day: 7)
          : TextCellValue('unsupported date'),
    ]);
  }
  return Uint8List.fromList(excel.save()!);
}

void main() {
  late FakeMeetingService service;
  late ProviderContainer container;
  setUp(() {
    service = FakeMeetingService();
    container = ProviderContainer.test(
      overrides: [meetingServiceProvider.overrideWithValue(service)],
    );
  });

  test(
    'Workbook preview preserves grouping, title fallback and duplicate-date message',
    () async {
      service.existingDates = {'2026-11-07'};
      final provider = importProvider(Object());
      container.listen(provider, (_, _) {});
      final controller = container.read(provider.notifier);
      controller.setBusy(true);
      await controller.preview(workbook(), 'Schedule.xlsx');
      final state = container.read(provider);
      expect(state.meetingTitle, 'Schedule');
      expect(state.summary, '1 days | 1 groups | 2 students');
      expect(state.rows.map((r) => r['group_no']), [1, 1]);
      expect(state.rows.first.keys.toSet(), {
        'group_no',
        'meeting_date',
        'meeting_time',
        'project',
        'supervisor',
        'reg_no',
        'student_name',
        'tech',
      });
      expect(state.alreadyAdded, isTrue);
      expect(state.hasExisting, isTrue);
      expect(state.canImport, isTrue);
      expect(state.busy, isTrue);
      expect(state.alreadyAddedText, startsWith('Already added.'));
      expect(
        () => state.rows.first['reg_no'] = 'changed',
        throwsUnsupportedError,
      );
      controller.showError('offline');
      expect(container.read(provider).canImport, isFalse);
      expect(container.read(provider).fileName, 'Schedule.xlsx');
      controller.reset();
      expect(container.read(provider).step, 'Step 1 of 2');
      expect(container.read(provider).rows, isEmpty);
      expect(container.read(provider).busy, isTrue);
    },
  );

  test(
    'Unsupported date rows retain the existing validation outcome',
    () async {
      final provider = importProvider(Object());
      container.listen(provider, (_, _) {});
      await expectLater(
        container
            .read(provider.notifier)
            .preview(workbook(validDate: false), 'Schedule.xlsx'),
        throwsA(isA<UserMessageException>()),
      );
      expect(service.calls, isEmpty);
    },
  );

  test(
    'Late duplicate-date response cannot restore a discarded import preview',
    () async {
      final pending = Completer<Set<String>>();
      service.existingDatesLoader = () => pending.future;
      final provider = importProvider(Object());
      container.listen(provider, (_, _) {});
      final controller = container.read(provider.notifier);
      final loading = controller.preview(workbook(), 'Schedule.xlsx');
      controller.cancelPreview();
      pending.complete({});
      await loading;
      expect(container.read(provider).isUploaded, isFalse);
      final fresh = importProvider(Object());
      container.listen(fresh, (_, _) {});
      expect(container.read(fresh).rows, isEmpty);
    },
  );
}
