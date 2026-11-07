# Live Meet error-handling report

Implemented on 7 November 2026. Existing uncommitted work was retained. No packages were added, no Supabase schema or data was changed, and nothing was committed or pushed.

**Implementation**

All 15 application catch boundaries now use `AppError.handle`, which records sanitized diagnostics before returning an app-authored message. Screens retain their existing SnackBars, inline errors, dialogs, layout, colors, and navigation patterns. Startup failures now render a readable error using the existing app theme instead of leaving startup as an unhandled exception.

The shared mapper handles network/TLS failures, request timeouts, authentication and expired sessions, permissions, database constraint conflicts, invalid data, unavailable services, rate limits, known meeting/group state conflicts, Excel parsing and validation, file-access errors, and unexpected exceptions. Unknown backend messages always use a safe operation-specific fallback. Only explicitly app-authored `UserMessageException` corrections can pass through as text; parser and server messages are never wrapped in that type.

Debug builds retain the exception type, diagnostic message, database/authentication code, available details/hints, and stack trace after redaction. Configured environment values, credential assignments, authorization values, URLs, email addresses, quoted values, database key/row values, and token-like strings are redacted. Workbook contents and platform-exception payloads are not logged. Release builds do not emit these diagnostic logs.

Loading and busy flags clear in failure paths, including an initial silent refresh. Malformed save, attendance, and import responses now fail instead of generating misleading success messages. Imports with no added/updated meetings display a correction. A remote sign-out error after local session removal still returns the user to Login and displays the failure.

**Files changed by this task**

Shared handling and configuration:

- [lib/utils/app_error.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/utils/app_error.dart>) — new mapping, trusted corrections, logging, and redaction.
- [lib/utils/network_error_io.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/utils/network_error_io.dart>) — native network exception detection, including subclasses.
- [lib/utils/network_error_stub.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/utils/network_error_stub.dart>) — keeps native imports out of web builds.
- [lib/main.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/main.dart>) — safe startup failure handling.
- [analysis_options.yaml](<D:/7th Semester/Flutter/Project/livemeet/analysis_options.yaml>) — excludes generated `build/**` artifacts, including stale verification code, from analysis.

Providers and services:

- [lib/providers/meeting_providers.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/providers/meeting_providers.dart>) — safe load errors and loading cleanup.
- [lib/providers/editor_provider.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/providers/editor_provider.dart>) — safe editor load errors.
- [lib/providers/import_provider.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/providers/import_provider.dart>) — explicit app-authored Excel corrections, including row and missing field.
- [lib/services/meeting_service.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/services/meeting_service.dart>) — rejects malformed save/attendance responses and explains unsuccessful deletion.
- [lib/utils/pdf_export.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/utils/pdf_export.dart>) — actionable empty-export correction; removes unused summary variables.

Screens:

- [lib/screens/login_screen.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/screens/login_screen.dart>) — safe sign-in errors, shared injectable auth client, loading cleanup.
- [lib/screens/dashboard_screen.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/screens/dashboard_screen.dart>) — sign-out and meeting-action errors; session-aware sign-out failure recovery.
- [lib/screens/live_screen.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/screens/live_screen.dart>) — group and attendance errors.
- [lib/screens/meetings_screen.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/screens/meetings_screen.dart>) — meeting actions, delete, and PDF errors.
- [lib/screens/import_screen.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/screens/import_screen.dart>) — file/parse/import errors and invalid-response protection.
- [lib/screens/edit_meeting_screen.dart](<D:/7th Semester/Flutter/Project/livemeet/lib/screens/edit_meeting_screen.dart>) — save/delete errors and field-specific required corrections. Analyzer cleanup uses the current reorder callback with an adapter preserving the controller's existing index semantics, and checks the relevant context after the discard dialog.

Tests:

- [test/app_error_test.dart](<D:/7th Semester/Flutter/Project/livemeet/test/app_error_test.dart>) — new mapper and diagnostic-redaction tests.
- [test/error_flows_test.dart](<D:/7th Semester/Flutter/Project/livemeet/test/error_flows_test.dart>) — new provider and widget failure/retry tests.
- [test/meeting_service_errors_test.dart](<D:/7th Semester/Flutter/Project/livemeet/test/meeting_service_errors_test.dart>) — new RPC response validation tests.
- [test/support/fake_auth_client.dart](<D:/7th Semester/Flutter/Project/livemeet/test/support/fake_auth_client.dart>) — new in-memory auth fake.
- [test/import_provider_test.dart](<D:/7th Semester/Flutter/Project/livemeet/test/import_provider_test.dart>) — recognizes explicit validation corrections.
- [test/meeting_providers_test.dart](<D:/7th Semester/Flutter/Project/livemeet/test/meeting_providers_test.dart>) — verifies untrusted database text is replaced while cached data is retained.
- [test/widget_test.dart](<D:/7th Semester/Flutter/Project/livemeet/test/widget_test.dart>) — verifies readable startup failures without exposing configuration details.

This report is also new. Other pre-existing project changes are outside this list.

**Old versus new examples**

- Sign-in: `Error: $e` → “The email or password is incorrect. Please check both and try again.” for invalid credentials; other auth/network failures receive their matching correction.
- Network failure: interpolated exception text → “Unable to connect. Please check your internet connection and try again.”
- Permission failure: raw database/auth text → “You don't have permission to perform this action.”
- Expired session: raw token/auth error → “Your session has expired. Please sign in again.”
- Save: `Save failed: $e` → “Unable to save your changes. Please try again.”
- Unknown database error during loading: `e.message` → “Unable to load groups. Please try again.”
- Invalid Excel file: parser `FormatException.message` → “Unable to read this Excel file. Choose a valid .xlsx file and try again.”
- Local Excel correction remains precise: “Row 2 is missing a reg #.”
- Editor field validation: “Required” → “Enter a project name.”, “Enter a supervisor name.”, “Enter the student name.”, or “Enter a registration number.”

**Verification**

- Full Flutter test suite: **58 passed**.
- Final mapper/redaction rerun after expanding credential and failing-row redaction: **5 passed**.
- `flutter analyze --no-pub`: **no issues found**.
- `git diff --check`: passed.
- Source audit of every Dart catch boundary and user-facing exception interpolation: no remaining arbitrary exception/message display found in application-authored UI.
- Automated failure cases cover all three data-loading controllers; cached-data retention; silent-refresh cleanup; clock failure; login retry; local sign-out despite remote failure; meeting/group/attendance failures; editor save failure and retry; delete/download failures; empty PDF export; new/existing imports; malformed RPC responses; duplicate/finished imports; exact Excel row validation; startup configuration failures; and debug-log redaction with retained stack traces.
- Existing successful workflow tests also passed, covering navigation locks, meeting/group actions, attendance, editor clipboard/undo/redo/save, imports, timer behavior, stale responses, and disposal.

The installed Flutter wrapper initially could not access its SDK lockfile inside the sandbox. Checks were completed using the installed `flutter_tools.snapshot` with SDK-cache access; no SDK or dependency changes were made for this task.

**Remaining verification limits**

No remaining raw technical errors were found in application-authored user-facing error paths. These checks cover the app's own handling, not every diagnostic a framework or dependency may emit.

No real Supabase mutations or live multi-device conflict tests were performed. Actual deployed error variants, real expired-token responses, offline behavior on a physical device, native file-picker permissions, native PDF sharing, and device/web release behavior still require integration testing. Unknown server variants remain covered by safe fallbacks. No emulator/phone visual comparison was performed; existing widget workflows passed and screen styling/layout definitions were retained.
