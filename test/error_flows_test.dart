import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/providers/editor_provider.dart';
import 'package:livemeet/providers/import_provider.dart';
import 'package:livemeet/providers/meeting_providers.dart';
import 'package:livemeet/screens/edit_meeting_screen.dart';
import 'package:livemeet/screens/import_screen.dart';
import 'package:livemeet/screens/login_screen.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/utils/app_error.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/LiveDetailMeetingCard.dart';
import 'package:livemeet/widgets/MeetingCard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'import_provider_test.dart' show workbook;
import 'import_screen_test.dart' show PreparedImport;
import 'meeting_screens_test.dart' show openApp, tapButton;
import 'support/fake_auth_client.dart';
import 'support/fake_meeting_service.dart';

const privateError = PostgrestException(
  message: 'private SQL relation internal_table failed',
  code: 'XX000',
  details: 'internal database context',
);

class FailingService extends FakeMeetingService {
  Object? failure;
  bool failClock = false;
  @override
  Future<DateTime> fetchServerNow() async {
    if (failClock) throw privateError;
    return super.fetchServerNow();
  }

  @override
  Future<Map<String, dynamic>> saveSchedule(
    int id,
    List<Map<String, dynamic>> rows,
  ) async {
    if (failure case final error?) throw error;
    return super.saveSchedule(id, rows);
  }

  @override
  Future<void> deleteMeeting(int id) async {
    if (failure case final error?) throw error;
    return super.deleteMeeting(id);
  }

  @override
  Future<List<dynamic>> importSchedule(
    String title,
    List<Map<String, dynamic>> rows,
  ) async {
    if (failure case final error?) throw error;
    return super.importSchedule(title, rows);
  }

  @override
  Future<List<dynamic>> updateSchedule(
    String title,
    List<Map<String, dynamic>> rows,
  ) async {
    if (failure case final error?) throw error;
    return super.updateSchedule(title, rows);
  }

  @override
  Future<void> pauseGroup(int meetingId, int groupNo) async {
    if (failure case final error?) throw error;
    return super.pauseGroup(meetingId, groupNo);
  }

  @override
  Future<int> setAttendance(
    int meetingId,
    int groupNo,
    List<String> present,
  ) async {
    if (failure case final error?) throw error;
    return super.setAttendance(meetingId, groupNo, present);
  }
}

void noTechnicalUi(WidgetTester tester) {
  expect(find.textContaining('private SQL'), findsNothing);
  expect(find.textContaining('internal_table'), findsNothing);
  expect(find.textContaining('PostgrestException'), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final error in [
    privateError,
    const SocketException('private host lookup'),
    const AuthException('private token', code: 'refresh_token_not_found'),
    StateError('private internal state'),
  ]) {
    test('All load controllers recover from ${error.runtimeType}', () async {
      final service = FakeMeetingService();
      final container = ProviderContainer.test(
        overrides: [meetingServiceProvider.overrideWithValue(service)],
      );
      final active = activeMeetingProvider(Object());
      final meetings = meetingsProvider(Object());
      final editor = editorProvider(Object());
      container.listen(active, (_, _) {});
      container.listen(meetings, (_, _) {});
      container.listen(editor, (_, _) {});
      await container.read(active.notifier).load();
      await container.read(meetings.notifier).load();
      await container.read(editor.notifier).load(1);
      service.activeLoader = () async => throw error;
      service.meetingsLoader = () async => throw error;
      service.rowsLoader = (_) async => throw error;
      await container.read(active.notifier).load();
      await container.read(meetings.notifier).load();
      await container.read(editor.notifier).load(1);
      expect(
        container.read(active).errorMessage,
        AppError.message(error, action: ErrorAction.loadGroups),
      );
      expect(
        container.read(meetings).errorMessage,
        AppError.message(error, action: ErrorAction.loadMeetings),
      );
      expect(
        container.read(editor).errorMessage,
        AppError.message(error, action: ErrorAction.loadGroups),
      );
      expect(container.read(active).isLoading, isFalse);
      expect(container.read(meetings).isLoading, isFalse);
      expect(container.read(editor).isLoading, isFalse);
      expect(container.read(active).data.meeting, isNotNull);
      expect(container.read(meetings).data, isNotEmpty);
      expect(container.read(editor).groups, isNotEmpty);
    });
  }

  test(
    'A silent refresh replacing an initial load clears loading after failure',
    () async {
      final service = FakeMeetingService();
      final container = ProviderContainer.test(
        overrides: [meetingServiceProvider.overrideWithValue(service)],
      );
      final provider = activeMeetingProvider(Object());
      container.listen(provider, (_, _) {});
      service.activeLoader = () async => throw privateError;
      await container.read(provider.notifier).load(silent: true);
      expect(container.read(provider).isLoading, isFalse);
      expect(container.read(provider).errorMessage, isNotEmpty);
    },
  );

  test('Missing spreadsheet fields retain the exact row correction', () async {
    final service = FakeMeetingService();
    final container = ProviderContainer.test(
      overrides: [meetingServiceProvider.overrideWithValue(service)],
    );
    final provider = importProvider(Object());
    container.listen(provider, (_, _) {});
    final excel = Excel.decodeBytes(workbook());
    excel.tables.values.first
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
        .value = TextCellValue(
      '',
    );
    await expectLater(
      container
          .read(provider.notifier)
          .preview(Uint8List.fromList(excel.save()!), 'Schedule.xlsx'),
      throwsA(
        isA<UserMessageException>().having(
          (e) => e.message,
          'message',
          'Row 2 is missing a reg #.',
        ),
      ),
    );
    expect(service.calls, isEmpty);
  });

  testWidgets(
    'Failed login stops loading, stays on login, and supports retry',
    (tester) async {
      final auth = FakeAuthClient()
        ..signInError = const AuthException(
          'private SQL',
          code: 'invalid_credentials',
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseClientProvider.overrideWithValue(
              FakeAuthSupabaseClient(auth),
            ),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'user@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.ensureVisible(find.widgetWithText(Button, 'Sign in'));
      await tapButton(tester, 'Sign in');
      expect(
        find.textContaining('email or password is incorrect'),
        findsOneWidget,
      );
      expect(find.byType(MainScreen), findsNothing);
      expect(
        tester.widget<Button>(find.widgetWithText(Button, 'Sign in')).enabled,
        isTrue,
      );
      noTechnicalUi(tester);
      await tapButton(tester, 'Sign in');
      expect(auth.signInCalls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Clock failure replaces the dashboard spinner with a safe error',
    (tester) async {
      await openApp(tester, FailingService()..failClock = true);
      expect(
        find.text('Unable to load the meeting. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      noTechnicalUi(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Failed meeting mutation releases busy lock and reloads', (
    tester,
  ) async {
    final service = FakeMeetingService()
      ..pauseHandler = () async => throw privateError;
    await openApp(tester, service);
    await tapButton(tester, 'Meetings');
    await tapButton(tester, 'Pause');
    expect(
      find.text('Unable to update the meeting. Refresh and try again.'),
      findsOneWidget,
    );
    expect(service.calls.where((c) => c == 'meetings'), hasLength(2));
    noTechnicalUi(tester);
    await tapButton(tester, 'Live');
    expect(find.byType(Livedetailmeetingcard), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Failed attendance does not show a saved message', (
    tester,
  ) async {
    final service = FailingService()..rows = [rowFixture(status: 'running')];
    await openApp(tester, service);
    await tapButton(tester, 'Live');
    service.failure = privateError;
    tester
        .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
        .onSaveAttendance!([]);
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to save attendance. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Attendance saved'), findsNothing);
    expect(find.text('Attendance already up to date'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    noTechnicalUi(tester);
    await tapButton(tester, 'Meetings');
    expect(find.byType(MeetingCard), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final existing in [false, true]) {
    for (final malformed in [false, true]) {
      testWidgets(
        'Import existing=$existing malformed=$malformed reports failure and releases locks',
        (tester) async {
          final service = FailingService()
            ..failure = malformed ? null : privateError
            ..importResult = [{}]
            ..updateResult = [
              {'state': 'unknown'},
            ];
          final destinations = <int>[], busy = <bool>[];
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                meetingServiceProvider.overrideWithValue(service),
                importProvider.overrideWith2(
                  (owner) => PreparedImport(owner, existing),
                ),
              ],
              child: MaterialApp(
                home: ImportScreen(
                  onNavigate: destinations.add,
                  onBusyChanged: busy.add,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tapButton(
            tester,
            existing ? 'Update existing data' : 'Confirm import',
          );
          if (existing) {
            await tester.tap(find.text('Update').last);
            await tester.pumpAndSettle();
          }
          expect(
            find.textContaining('Unable to import the schedule.'),
            findsOneWidget,
          );
          expect(find.textContaining('meeting(s) added'), findsNothing);
          expect(destinations, isEmpty);
          expect(busy.last, isFalse);
          expect(
            tester
                .widget<Button>(
                  find.widgetWithText(
                    Button,
                    existing ? 'Update existing data' : 'Confirm import',
                  ),
                )
                .enabled,
            isFalse,
          );
          noTechnicalUi(tester);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('Failed editor save keeps edits and allows retry', (
    tester,
  ) async {
    final service = FailingService();
    await openApp(tester, service);
    await tapButton(tester, 'Meetings');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste group'));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(find.byType(EditMeetingScreen)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    service.failure = privateError;
    await tapButton(tester, 'Save changes');
    expect(find.byType(EditMeetingScreen), findsOneWidget);
    expect(
      find.text('Unable to save your changes. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Meeting updated'), findsNothing);
    expect(
      tester
          .widget<Button>(find.widgetWithText(Button, 'Save changes'))
          .enabled,
      isTrue,
    );
    noTechnicalUi(tester);
    service.failure = null;
    await tapButton(tester, 'Save changes');
    expect(find.byType(EditMeetingScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Failed delete and PDF download release the meeting controls', (
    tester,
  ) async {
    final service = FailingService()
      ..active = null
      ..meetings = [meetingFixture(status: 'upcoming')];
    await openApp(tester, service);
    await tapButton(tester, 'Meetings');
    service.failure = privateError;
    tester.widget<MeetingCard>(find.byType(MeetingCard)).onDelete!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to delete the meeting. Refresh and try again.'),
      findsOneWidget,
    );
    expect(find.text('Meeting deleted'), findsNothing);
    expect(tester.widget<MeetingCard>(find.byType(MeetingCard)).busy, isFalse);
    ScaffoldMessenger.of(
      tester.element(find.byType(MeetingCard)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    service.rowsLoader = (_) async => throw privateError;
    tester.widget<MeetingCard>(find.byType(MeetingCard)).onDownload!();
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to download the meeting PDF. Please try again.'),
      findsOneWidget,
    );
    expect(tester.widget<MeetingCard>(find.byType(MeetingCard)).busy, isFalse);
    noTechnicalUi(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Sign out still returns to login when remote logout fails after local removal',
    (tester) async {
      final service = FakeMeetingService();
      final auth = FakeAuthClient()
        ..signOutError = const SocketException('private network details');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meetingServiceProvider.overrideWithValue(service),
            supabaseClientProvider.overrideWithValue(
              FakeAuthSupabaseClient(auth),
            ),
          ],
          child: const MaterialApp(home: MainScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Logout').last);
      await tester.pumpAndSettle();
      expect(auth.signOutCalls, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      expect(find.text(AppError.connection), findsOneWidget);
      noTechnicalUi(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Empty PDF exports give a correction without invoking the share plugin',
    (tester) async {
      final service = FakeMeetingService()
        ..active = null
        ..rows = [];
      await openApp(tester, service);
      await tapButton(tester, 'Meetings');
      tester.widget<MeetingCard>(find.byType(MeetingCard)).onDownload!();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This meeting has no students to export.'),
        findsOneWidget,
      );
      expect(
        tester.widget<MeetingCard>(find.byType(MeetingCard)).busy,
        isFalse,
      );
      noTechnicalUi(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final existing in [false, true]) {
    testWidgets(
      'Import existing=$existing with no changed meetings gives a correction',
      (tester) async {
        final service = FailingService()
          ..importResult = [
            {'already_added': true},
          ]
          ..updateResult = [
            {'state': 'locked'},
          ];
        final destinations = <int>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              meetingServiceProvider.overrideWithValue(service),
              importProvider.overrideWith2(
                (owner) => PreparedImport(owner, existing),
              ),
            ],
            child: MaterialApp(
              home: ImportScreen(
                onNavigate: destinations.add,
                onBusyChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapButton(
          tester,
          existing ? 'Update existing data' : 'Confirm import',
        );
        if (existing) {
          await tester.tap(find.text('Update').last);
          await tester.pumpAndSettle();
        }
        expect(
          find.textContaining(existing ? 'already finished' : 'already exist'),
          findsOneWidget,
        );
        expect(find.textContaining('0 meeting(s) added'), findsNothing);
        expect(destinations, isEmpty);
        noTechnicalUi(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Failed group action keeps status and releases navigation', (
    tester,
  ) async {
    final service = FailingService()..rows = [rowFixture(status: 'running')];
    await openApp(tester, service);
    await tapButton(tester, 'Live');
    service.failure = privateError;
    tester
        .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
        .onPauseResume!();
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to update the group. Refresh and try again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Livedetailmeetingcard>(find.byType(Livedetailmeetingcard))
          .status,
      'Running',
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    noTechnicalUi(tester);
    await tapButton(tester, 'Meetings');
    expect(find.byType(MeetingCard), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
