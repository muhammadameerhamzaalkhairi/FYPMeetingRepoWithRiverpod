import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/screens/edit_meeting_screen.dart';
import 'package:livemeet/screens/meetings_screen.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/LiveDetailMeetingCard.dart';
import 'package:livemeet/widgets/filter.dart';
import 'support/fake_meeting_service.dart';

Future<void> openApp(WidgetTester tester, FakeMeetingService service) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [meetingServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: MainScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapButton(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Button, label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Group start, pause, resume and end preserve selection and timers',
    (tester) async {
      final service = FakeMeetingService()..rows = [rowFixture()];
      await openApp(tester, service);
      await tapButton(tester, 'Live');
      tester
          .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
          .onTap();
      await tester.pump();
      await tapButton(tester, 'Start');
      await tester.tap(find.text('Start').last);
      await tester.pumpAndSettle();
      expect(
        service.calls.where((c) => c == 'group-start:1:1:R1'),
        hasLength(1),
      );
      await tapButton(tester, 'Pause');
      expect(service.calls.where((c) => c == 'group-pause:1:1'), hasLength(1));
      final paused = tester.widget<Livedetailmeetingcard>(
        find.byType(Livedetailmeetingcard),
      );
      expect(paused.status, 'Paused');
      expect(paused.timerText, '01:00');
      expect(paused.isSelected, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(
        tester
            .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
            .timerText,
        '01:00',
      );
      await tapButton(tester, 'Resume');
      expect(service.calls.where((c) => c == 'group-resume:1:1'), hasLength(1));
      await tapButton(tester, 'End');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(service.calls.where((c) => c == 'group-end:1:1'), hasLength(1));
      expect(
        tester
            .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
            .status,
        'Done',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pending mutation blocks tab changes and duplicate actions', (
    tester,
  ) async {
    final pending = Completer<void>();
    final service = FakeMeetingService()..pauseHandler = () => pending.future;
    await openApp(tester, service);
    await tapButton(tester, 'Meetings');
    await tapButton(tester, 'Pause');
    await tapButton(tester, 'Pause');
    await tapButton(tester, 'Live');
    expect(find.byType(MeetingsScreen), findsOneWidget);
    expect(service.calls.where((c) => c == 'pause:1'), hasLength(1));
    pending.complete();
    await tester.pumpAndSettle();
    await tapButton(tester, 'Live');
    expect(find.byType(Livedetailmeetingcard), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Editor copy, paste, undo, redo and save preserve locked groups',
    (tester) async {
      final service = FakeMeetingService()
        ..rows = [
          rowFixture(),
          {
            ...rowFixture(group: 2, reg: 'R2', status: 'done'),
            'meeting_time': '09:15:00',
          },
        ];
      await openApp(tester, service);
      await tapButton(tester, 'Meetings');
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(EditMeetingScreen), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Paste group'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Save changes');
      expect(service.calls.where((c) => c == 'save:1'), hasLength(1));
      expect(service.savedRows!.map((r) => r['group_no']), [1, 3]);
      expect(service.savedRows!.map((r) => r['reg_no']), ['R1', 'R1-copy']);
      expect(service.savedRows!.any((r) => r['reg_no'] == 'R2'), isFalse);
      expect(find.byType(EditMeetingScreen), findsNothing);
      expect(service.calls.where((c) => c == 'meetings'), hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Tab revisits refetch and reset local filters; timers dispose', (
    tester,
  ) async {
    final service = FakeMeetingService();
    await openApp(tester, service);
    await tapButton(tester, 'Meetings');
    await tester.ensureVisible(find.text('Previous meetings'));
    await tester.tap(find.text('Previous meetings'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Import');
    await tapButton(tester, 'Meetings');
    expect(service.calls.where((c) => c == 'meetings'), hasLength(2));
    final coming = tester.widget<Filter>(
      find.widgetWithText(Filter, 'Coming meetings'),
    );
    expect(coming.isSelected, isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Meeting pause, resume and end each run once and reload', (
    tester,
  ) async {
    final service = FakeMeetingService();
    await openApp(tester, service);
    await tapButton(tester, 'Meetings');
    await tapButton(tester, 'Pause');
    expect(service.calls.where((c) => c == 'pause:1'), hasLength(1));
    await tapButton(tester, 'Resume');
    expect(service.calls.where((c) => c == 'resume:1'), hasLength(1));
    await tapButton(tester, 'End');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(service.calls.where((c) => c == 'end:1'), hasLength(1));
    expect(service.calls.where((c) => c == 'meetings'), hasLength(4));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Restart navigates to Live only after the busy lock is cleared', (
    tester,
  ) async {
    final service = FakeMeetingService()
      ..active = null
      ..meetings = [meetingFixture(status: 'done', incomplete: 1)];
    await openApp(tester, service);
    await tapButton(tester, 'Meetings');
    await tester.ensureVisible(find.text('Previous meetings'));
    await tester.tap(find.text('Previous meetings'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Restart');
    await tester.tap(find.text('Restart').last);
    await tester.pumpAndSettle();
    expect(service.calls.where((c) => c == 'restart:1'), hasLength(1));
    expect(find.byType(Livedetailmeetingcard), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Unsaved attendance survives ticks and saving uses exact attendance',
    (tester) async {
      final service = FakeMeetingService()
        ..rows = [rowFixture(status: 'running')];
      await openApp(tester, service);
      await tapButton(tester, 'Live');
      final card = find.byType(Livedetailmeetingcard);
      final widget = tester.widget<Livedetailmeetingcard>(card);
      widget.onExpand();
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      // The card's normal save callback follows the same screen action path.
      tester.widget<Livedetailmeetingcard>(card).onSaveAttendance!([]);
      await tester.pumpAndSettle();
      expect(service.calls.where((c) => c == 'attendance:1:1:'), hasLength(1));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
