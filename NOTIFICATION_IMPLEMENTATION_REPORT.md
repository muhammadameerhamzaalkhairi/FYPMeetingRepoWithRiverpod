# Notification implementation report

Implemented on 8 November 2026.

## Behavior

- Dashboard now offers Send Notification, including when no meeting is active.
- The dialog provides six locally maintained presets and an editable message field. Presets appear on the left on wider screens and above the message on narrow screens.
- Empty messages and messages longer than 200 Unicode code points are rejected in both the dialog and service. Messages are trimmed before insertion. Long project names in generated group announcements are shortened while preserving the group number and “meeting has started” ending.
- Sending shows progress, disables editing and actions, blocks back navigation, and prevents repeated submissions. Failures retain the draft and allow retry; successful sends close the dialog and show confirmation.
- Group notifications run only after the existing group_start RPC succeeds. Concurrent calls for the same meeting/group share one operation. Existing notification history prevents another announcement when a reset group is started after a meeting restart.
- Notification delivery failure is reported separately from group-start failure, so the group remains running and the operator can continue using its controls.
- Existing Riverpod providers and Supabase client are reused. No new provider or service was introduced. Errors use the existing friendly-message and redacted debug-log mechanisms.

## Added or modified files

- lib/screens/dashboard_screen.dart — dashboard entry point, navigation busy state and success feedback.
- lib/screens/live_screen.dart — passes project name into group start and reports notification delivery failure separately.
- lib/widgets/notification_dialog.dart — responsive composer, validation and sending state.
- lib/models/notification_message.dart — local presets, shared validation and bounded group-start messages.
- lib/services/meeting_service.dart — custom insertion, group-start insertion, in-flight guard and persisted duplicate lookup.
- lib/utils/app_error.dart — safe notification error fallback.
- test/notification_service_test.dart — real Supabase query builders with mocked HTTP responses.
- test/notification_dialog_test.dart — dialog and dashboard/group workflow regression tests.
- test/support/fake_meeting_service.dart — updated group-start result contract for existing tests.
- pubspec.yaml and pubspec.lock — http is explicitly declared as a development dependency for HTTP test fixtures; its existing locked version is unchanged.
- NOTIFICATION_IMPLEMENTATION_REPORT.md — this report.

## Database operations

Application code uses the existing authenticated Supabase client:

1. Custom announcement: INSERT into public.notifications with kind=custom, trimmed message, meeting_id=null and group_no=null.
2. Group start: call the existing group_start RPC with the original meeting, group and attendance parameters.
3. After successful group start: SELECT id from notifications filtered by kind=group_start, meeting_id and group_no, limited to one record.
4. If no prior record exists: INSERT with kind=group_start, the actual meeting_id/group_no and generated message.

The database supplies id and created_at. No schema, RLS, Realtime, migration, table, column or existing record was changed. Pause, resume, end, restart and timer calculations retain their existing implementations. No React or browser push code was added.

## Verification

- flutter pub get --offline: passed.
- flutter analyze --no-pub: passed, no issues found.
- flutter test --no-pub --reporter expanded: passed, 80 tests total, including 22 new notification tests.
- git diff --check: passed.

Coverage includes all presets, editable/custom messages, blank input, the exact 200-character boundary, Unicode, long project names, custom insert failure and retry, pending-send controls, responsive layouts with larger text and keyboard insets, RPC-before-notification ordering, actual meeting/group identifiers, failed starts, duplicate concurrent starts, persisted deduplication across service recreation and restart, notification lookup/insert failures, timer ticks, tab revisits, attendance and existing meeting/group controls.

## Remaining verification and limits

No known failures remain in automated checks. Tests used in-memory fixtures and mocked HTTP; no live Supabase writes were made. Live authenticated INSERT/SELECT policies and Realtime consumption still need environment verification. Duplicate lookup requires the operator's SELECT policy to expose prior group-start notifications for the relevant meeting/group.

Duplicate prevention combines the existing RPC's serialized upcoming-to-running transition, the service's in-flight guard and persisted notification history. Group start and notification insertion remain separate requests: interruption between them can leave a started group without a confirmed notification. A database-wide exactly-once guarantee under crashes or overlapping clients/restarts would require an atomic backend operation or database uniqueness rule, which was left outside the requested schema-preserving scope.

Nothing was committed or pushed.
