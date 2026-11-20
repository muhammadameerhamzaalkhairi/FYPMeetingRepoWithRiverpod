import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/models/notification_message.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/widgets/notification_dialog.dart';
import 'package:livemeet/widgets/LiveDetailMeetingCard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'meeting_screens_test.dart' show openApp, tapButton;
import 'support/fake_meeting_service.dart';

class NotificationFakeService extends FakeMeetingService {
  final messages = <String>[];
  Future<void> Function()? sendHandler;
  Object? startError;

  @override
  Future<void> sendCustomNotification(String message) async {
    messages.add(message);
    await sendHandler?.call();
  }

  @override
  Future<void> startGroup(
    int meetingId,
    int groupNo, {
    List<String>? present,
  }) async {
    if (startError case final error?) throw error;
    await super.startGroup(meetingId, groupNo, present: present);
  }
}

Future<void> openDialog(
  WidgetTester tester,
  NotificationFakeService service, {
  Size size = const Size(900, 700),
  double textScale = 1,
  double keyboardHeight = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [meetingServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNotificationDialog(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Every preset populates an editable message field', (
    tester,
  ) async {
    final service = NotificationFakeService();
    await openDialog(tester, service);
    for (final preset in NotificationPreset.values) {
      await tester.tap(
        find.byType(DropdownButtonFormField<NotificationPreset>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(preset.label).last);
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller!.text, preset.message);
    }
    await tester.enterText(
      find.byType(TextFormField),
      'A revised announcement',
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(service.messages, ['A revised announcement']);
    expect(find.byType(NotificationDialog), findsNothing);
  });

  testWidgets('Empty and 201-character messages remain open; 200 can send', (
    tester,
  ) async {
    final service = NotificationFakeService();
    await openDialog(tester, service);
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a message.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'x' * 201);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(
      find.text('Keep the message to 200 characters or fewer.'),
      findsOneWidget,
    );
    expect(service.messages, isEmpty);
    expect(find.byType(NotificationDialog), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'x' * 200);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(service.messages.single.length, 200);
    expect(find.byType(NotificationDialog), findsNothing);
  });

  testWidgets(
    'Pending send blocks repeat submissions, edits, cancel and back',
    (tester) async {
      final pending = Completer<void>();
      final service = NotificationFakeService()
        ..sendHandler = () => pending.future;
      await openDialog(tester, service);
      await tester.enterText(find.byType(TextFormField), 'Hello students');
      // Invoke the captured callback twice before the widget has rebuilt.
      final send = tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Send'))
          .onPressed!;
      send();
      send();
      await tester.pump();
      expect(service.messages, ['Hello students']);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(NotificationDialog), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(NotificationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Failed send shows friendly error, retains text and allows retry',
    (tester) async {
      final service = NotificationFakeService()
        ..sendHandler = () async => throw const PostgrestException(
          message: 'private SQL details',
          code: 'XX000',
        );
      await openDialog(tester, service);
      await tester.enterText(find.byType(TextFormField), 'Please be ready.');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to send the notification. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private SQL'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NotificationDialog), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Please be ready.',
      );
      service.sendHandler = null;
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(service.messages, hasLength(2));
      expect(find.byType(NotificationDialog), findsNothing);
    },
  );

  for (final width in [320.0, 900.0]) {
    testWidgets('Dialog lays out at $width with large text and a keyboard', (
      tester,
    ) async {
      await openDialog(
        tester,
        NotificationFakeService(),
        size: Size(width, 900),
        textScale: 1.5,
        keyboardHeight: 300,
      );
      final preset = tester.getTopLeft(
        find.byType(DropdownButtonFormField<NotificationPreset>),
      );
      final message = tester.getTopLeft(find.byType(TextFormField));
      if (width > 560) {
        expect(preset.dx, lessThan(message.dx));
        expect(preset.dy, message.dy);
      } else {
        expect(preset.dy, lessThan(message.dy));
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationDialog), findsNothing);
    });
  }

  testWidgets(
    'Running meeting FAB opens composer, cancels and reports success',
    (tester) async {
      final service = NotificationFakeService();
      await openApp(tester, service);
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.tooltip, 'Send Notification');
      expect(fab.backgroundColor, Colors.black);
      expect(fab.foregroundColor, Colors.white);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.messages, isEmpty);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Custom announcement');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Notification sent successfully.'), findsOneWidget);
      await tapButton(tester, 'Live'); // Navigation busy flag was cleared.
      expect(find.byType(Livedetailmeetingcard), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'FAB appears only for running meetings and respects sending permissions',
    (tester) async {
      for (final status in [null, 'upcoming', 'paused', 'done', 'restricted']) {
        final service = NotificationFakeService()
          ..active = status == null
              ? null
              : meetingFixture(
                  status: status == 'restricted' ? 'running' : status,
                )
          ..canSendNotifications = status != 'restricted';
        await openApp(tester, service);
        final fab = find.byType(FloatingActionButton);
        if (status == 'restricted') {
          expect(tester.widget<FloatingActionButton>(fab).onPressed, isNull);
        } else {
          expect(fab, findsNothing);
        }
        if (status == null) {
          expect(find.text('No meeting is running'), findsOneWidget);
          await tapButton(tester, 'Go to Meetings');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'Ticks, tab revisits and resume do not repeat the group-start action',
    (tester) async {
      final service = NotificationFakeService()..rows = [rowFixture()];
      await openApp(tester, service);
      await tapButton(tester, 'Live');
      tester
          .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
          .onTap();
      await tester.pump();
      // Two callbacks before rebuilding must still open only one start dialog.
      final start = tester
          .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
          .onStart!;
      start();
      start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tapButton(tester, 'Pause');
      await tapButton(tester, 'Resume');
      await tapButton(tester, 'Home');
      await tapButton(tester, 'Live');
      await tester.pump(const Duration(seconds: 3));
      expect(
        service.calls.where((call) => call.startsWith('group-start:')),
        hasLength(1),
      );
      expect(
        service.calls.where((call) => call == 'group-resume:1:1'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Failed group start leaves upcoming state and releases busy flag',
    (tester) async {
      final service = NotificationFakeService()
        ..rows = [rowFixture()]
        ..startError = const PostgrestException(
          message: 'private start failure',
          code: 'XX000',
        );
      await openApp(tester, service);
      await tapButton(tester, 'Live');
      tester
          .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
          .onTap();
      await tester.pump();
      await tapButton(tester, 'Start');
      await tester.tap(find.text('Start').last);
      await tester.pumpAndSettle();
      final card = tester.widget<Livedetailmeetingcard>(
        find.byType(Livedetailmeetingcard),
      );
      expect(card.status, 'Upcoming');
      expect(card.canStart, isTrue);
      expect(find.textContaining('private start failure'), findsNothing);
      expect(find.textContaining('Group started, but'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
