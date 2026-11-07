import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/providers/import_provider.dart';
import 'package:livemeet/screens/import_screen.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/widgets/Button.dart';
import 'support/fake_meeting_service.dart';

class PreparedImport extends ImportController {
  PreparedImport(super.owner, this.existing);
  final bool existing;
  @override
  ImportState build() => ImportState(
    step: 'Step 2 of 2',
    isUploaded: true,
    canImport: true,
    hasExisting: existing,
    meetingTitle: 'Schedule',
    fileName: 'Schedule.xlsx',
    rows: [rowFixture()],
  );
}

void main() {
  for (final existing in [false, true]) {
    testWidgets(
      'Import ${existing ? 'update' : 'new schedule'} runs once and keeps navigation order',
      (tester) async {
        final service = FakeMeetingService();
        final busy = <bool>[], destinations = <int>[];
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
        await tester.tap(
          find.widgetWithText(
            Button,
            existing ? 'Update existing data' : 'Confirm import',
          ),
        );
        await tester.pumpAndSettle();
        if (existing) {
          await tester.tap(find.text('Update').last);
          await tester.pumpAndSettle();
        }
        expect(service.calls, [
          existing ? 'update:Schedule' : 'import:Schedule',
        ]);
        expect(destinations, [kMeetings]);
        expect(busy, [true, false, false]);
        expect(find.text('Step 1 of 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('A cancelled update keeps the preview and sends no RPC', (
    tester,
  ) async {
    final service = FakeMeetingService();
    final destinations = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meetingServiceProvider.overrideWithValue(service),
          importProvider.overrideWith2((owner) => PreparedImport(owner, true)),
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
    await tester.tap(find.widgetWithText(Button, 'Update existing data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(service.calls, isEmpty);
    expect(destinations, isEmpty);
    expect(find.text('Schedule.xlsx'), findsOneWidget);
    expect(
      tester
          .widget<Button>(find.widgetWithText(Button, 'Update existing data'))
          .enabled,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
