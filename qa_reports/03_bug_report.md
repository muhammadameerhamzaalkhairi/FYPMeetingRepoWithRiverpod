# 03 — Bug Report

Audit date: 2026-11-02
Project: `D:\7th Semester\Flutter\Project\livemeet`
Mode: read-only static audit. No source, SQL, pubspec or platform file was modified.
Companion reports: `01_summary.md`, `02_static_analysis.md`, `04_test_cases.md`, `05_git_status_before_after.md`.

## Severity model

| Severity | Meaning |
|---|---|
| Critical | Core feature cannot work, or a required backend contract is missing from the supplied SQL. |
| High | A normal user flow corrupts data, leaves the user stranded, or offers an action that must fail. |
| Medium | A plausible edge case causes wrong data, a crash, an unresponsive UI, or a requirement miss. |
| Low | Usability, accessibility, maintainability, or accuracy issue with limited immediate impact. |

Verification labels used below:

- **Static confirmed** — directly visible in the reviewed source, SQL, installed package source, or analyzer output.
- **Runtime unverified** — the code path exists, but the exact device/layout/network presentation was not reproduced. No phone or backend test was run.
- **Deployment-dependent** — depends on the live Supabase schema, grants, policies, Auth settings, or which SQL files were applied.

## Finding counts

| Severity | Count |
|---|---:|
| Critical | 2 |
| High | 4 |
| Medium | 12 |
| Low | 14 |
| **Total** | **32** |

The production defect count is 32. Deployment/security observations are listed separately in section 9 and are not included in that total.

## 1. Finding index

| ID | Severity | Title | Primary location |
|---|---|---|---|
| C-01 | Critical | `save_meeting_schedule` RPC is called but is not defined by either supplied SQL file | `lib/services/meeting_service.dart:100-103`; `lib/screens/edit_meeting_screen.dart:272` |
| C-02 | Critical | `update_schedule` RPC is called but is not defined by either supplied SQL file | `lib/screens/import_screen.dart:245-248` |
| H-01 | High | Interleaved Excel dates restart group numbering and merge distinct projects | `lib/screens/import_screen.dart:119-154` |
| H-02 | High | A failed logout can leave a signed-out user on the populated authenticated screen | `lib/screens/dashboard_screen.dart:90-123` |
| H-03 | High | Header detection only recognises a first cell starting with `s.no` | `lib/screens/import_screen.dart:109-115` |
| H-04 | High | Delete is offered for every meeting, but the service only deletes `upcoming` meetings | `lib/screens/meetings_screen.dart:238`; `lib/widgets/MeetingCard.dart:90-104`; `lib/services/meeting_service.dart:106-116` |
| M-01 | Medium | Duplicate reg numbers are not validated before import; one duplicate aborts the whole import | `lib/screens/import_screen.dart:156-165`; migration `:41`, `:109-117` |
| M-02 | Medium | Date/time cells stored as text or unsupported numeric forms are silently skipped | `lib/screens/import_screen.dart:62-83`, `:127-143` |
| M-03 | Medium | Unguarded casts on API rows can crash screens if nullable/legacy data is returned | `lib/screens/dashboard_screen.dart:327,450,455`; `lib/screens/live_screen.dart:324,328,330,332`; `lib/screens/edit_meeting_screen.dart:109` |
| M-04 | Medium | Server-clock offset ignores network round-trip time and can make live timers lag/jump | `lib/utils/time_utils.dart:5-8` |
| M-05 | Medium | Login title row can overflow at 320 dp width or large system text | `lib/screens/login_screen.dart:40-50` |
| M-06 | Medium | Live header can still overflow when the keyboard leaves very little height | `lib/screens/live_screen.dart:362-401` |
| M-07 | Medium | Excel decoding and parsing run synchronously on the UI isolate | `lib/screens/import_screen.dart:99-166` |
| M-08 | Medium | Each pause duration is rounded to whole seconds before accumulation | migration `:173`, `:199`, `:206-207`, `:218-219`, `:260` |
| M-09 | Medium | Up-next number tiles lost the required pastel colour treatment | `lib/screens/dashboard_screen.dart:432-437` |
| M-10 | Medium | An import/update error disables Confirm and forces the user to re-pick the same file | `lib/screens/import_screen.dart:216-223`, `:291-296`, `:379-383` |
| M-11 | Medium | Adding a late time slot wraps past midnight instead of rejecting/flagging it | `lib/screens/edit_meeting_screen.dart:17-20`, `:224` |
| M-12 | Medium | The only automated test is a stale counter template and always fails | `test/widget_test.dart:14-29`; `lib/main.dart:48` |
| L-01 | Low | Login brand text contains the typo `BIIT FYP Meeitngs` | `lib/screens/login_screen.dart:45` |
| L-02 | Low | Generic exception text is shown directly to users | `lib/screens/login_screen.dart:121`; dashboard `:118,173`; meetings `:151,277`; live `:212` |
| L-03 | Low | `Button.foreColor` is accepted but ignored | `lib/widgets/Button.dart:9,45`; caller `lib/screens/main_screen.dart:40` |
| L-04 | Low | `formatTotal` labels a negative duration as `<1 min` | `lib/utils/time_utils.dart:33-37` |
| L-05 | Low | An action can be silently ignored when another meeting is already active | `lib/screens/meetings_screen.dart:91-99` |
| L-06 | Low | Bottom navigation is blocked while busy but looks enabled | `lib/screens/main_screen.dart:24-27`, `:34-44` |
| L-07 | Low | Every screen ticker rebuilds the entire screen/list once per second | `lib/screens/dashboard_screen.dart:41-45`; live `:56-60`; meetings `:44-48` |
| L-08 | Low | Supabase URL and anon key are hardcoded in the app source | `lib/main.dart:10-15` |
| L-09 | Low | Live and Meetings error states have no explicit Retry button | `lib/screens/live_screen.dart:281-317`; `lib/screens/meetings_screen.dart:191-221` |
| L-10 | Low | Login fields have no `textInputAction`, autofill hints, or keyboard-submit handling | `lib/widgets/TextBox.dart:26-38`; `lib/screens/login_screen.dart:60-92` |
| L-11 | Low | Gesture-based buttons/filters and some icon buttons lack button semantics/tooltips | `lib/widgets/Button.dart:30-54`; `lib/widgets/filter.dart:17-39`; `lib/widgets/MeetingCard.dart:79-104` |
| L-12 | Low | Four bottom-nav labels may overflow at large text on a 320 dp device | `lib/screens/main_screen.dart:56-72` |
| L-13 | Low | Deprecated `ReorderableListView.onReorder` is still used | `lib/screens/edit_meeting_screen.dart:500` |
| L-14 | Low | No app-level auth-state listener; a session invalidated outside the Logout button leaves the authenticated shell open | `lib/main.dart:48-50` |

## 2. Critical findings

### C-01 — `save_meeting_schedule` RPC is missing from the supplied SQL

- **Verification:** Static confirmed in the repository. Live deployment NOT VERIFIED.
- **Caller:** `lib/services/meeting_service.dart:96-104` calls `_db.rpc('save_meeting_schedule', params: {'p_id': meetingId, 'p_rows': rows})`.
- **UI trigger:** Saving edits on `EditMeetingScreen` at `lib/screens/edit_meeting_screen.dart:272`.
- **Evidence:** Neither `lib/SQLandMDFileFolder/supabase_meetings_migration.sql` nor `lib/SQLandMDFileFolder/restart_meeting.sql` defines `save_meeting_schedule`. The main migration's function/grant section lists only `server_now`, `import_schedule`, `start_meeting`, `pause_meeting`, `resume_meeting`, `end_meeting`, `group_start`, `group_end`.
- **Reproduction (static):** Open an upcoming meeting, change a group, tap **Save changes**. The app calls the missing RPC.
- **Expected:** The edited schedule is saved and the previous screen reloads.
- **Actual:** On a database built from the supplied SQL, PostgREST returns a function-not-found error; the screen shows `Save failed: ...` and no changes are persisted.
- **Additional risk:** The payload omits `meeting_date` (`edit_meeting_screen.dart:258-270`). Even if an undocumented function exists in the deployed database, its row contract cannot be validated against this repository.
- **Suggested fix:** Add a reviewed SQL migration for `save_meeting_schedule(BIGINT, JSONB)` with an explicit replacement strategy, transaction, parameter validation, grants, and tests. Confirm whether `meeting_date` is required in each row and document the contract in the spec.

### C-02 — `update_schedule` RPC is missing from the supplied SQL

- **Verification:** Static confirmed in the repository. Live deployment NOT VERIFIED.
- **Caller:** `lib/screens/import_screen.dart:245-248` calls `Supabase.instance.client.rpc('update_schedule', params: {'p_title': meetingTitle, 'p_rows': rows})`.
- **UI trigger:** Re-importing a workbook when at least one date already exists (`hasExisting == true`), then confirming **Update existing data**.
- **Evidence:** Neither supplied SQL file defines `update_schedule`. The main migration defines `import_schedule`, but it deliberately skips existing `(title, date)` meetings (`supabase_meetings_migration.sql:103-118`).
- **Expected:** Existing upcoming meetings are updated, duplicate regs are handled, and the response reports `updated`, `added`, and `locked` counts.
- **Actual:** On a database built from the supplied SQL, PostgREST returns a function-not-found error. The UI reports `Import error: ...`; the partial-update path cannot work.
- **Additional risk:** The expected result shape (`state` equal to `updated`, `added`, or `locked`) is invented only in Dart (`import_screen.dart:250-269`). No SQL function documents or enforces it.
- **Suggested fix:** Add and review `update_schedule(TEXT, JSONB)`, with an explicit per-date locking rule, duplicate-reg policy, transaction boundaries, return schema, grants, and integration tests. If updating is out of scope, remove the update path and keep the upload card disabled when all dates already exist.

## 3. High findings

### H-01 — Interleaved Excel dates restart group numbering and merge distinct projects

- **Verification:** Static confirmed logic. A prior audit also reproduced the counter behaviour with an in-memory transcription. Real workbook impact NOT VERIFIED.
- **Location:** `lib/screens/import_screen.dart:119-154`, especially the reset at `:146-149`.
- **Cause:** One global `groupNo` and one `lastRow` are used. Every date change resets `groupNo` to zero. When a date reappears later (for example 13 Oct, 19 Oct, 13 Oct), the second 13 Oct block starts at group 1 again.
- **Reproduction:** Import rows in this order: `13 Oct / 11:00 / Project A`, `19 Oct / 11:00 / Project B`, `13 Oct / 12:00 / Project C`, all with distinct reg numbers. Rows A and C both receive `group_no = 1` for 13 Oct.
- **Effect:** The overview counts two groups for the 13 Oct meeting. Live groups by `group_no` and uses the first row for project/supervisor/status (`live_screen.dart:87-89`, `323-330`). The two projects are displayed and started/ended as one group. The summary still counts three distinct keys, so the preview contradicts the saved data.
- **Expected:** Either reject interleaved date blocks with the Excel row number, or maintain a separate group counter/last-key per date.
- **Suggested fix:** Validate that dates are contiguous before enabling import; simplest fix is to reject a date that reappears after its block has ended. If interleaving is required, use per-date counters and last keys, and add parser tests for interleaved input.

### H-02 — A failed logout can leave a signed-out user on the authenticated screen

- **Verification:** Static confirmed from app code and installed `gotrue` 2.27.3. Offline presentation on a phone NOT VERIFIED.
- **Location:** `lib/screens/dashboard_screen.dart:90-123`; route start at `lib/main.dart:48-50`.
- **Cause:** `signOut()` is awaited at `dashboard_screen.dart:103`. In the installed package, `_signOut` removes the local session and emits `signedOut` before awaiting the remote sign-out request (`gotrue-2.27.3/lib/src/gotrue_client.dart:1088-1109`). Qualifying remote failures rethrow.
- **Reproduction:** Sign in, disconnect the network, confirm Logout. The local session is cleared, the remote call fails, and the app's catch only shows a SnackBar. The Home screen and its meeting data remain visible with no authenticated session.
- **Expected:** Once the local session is gone, the app should remove authenticated routes and show Login, even if the remote sign-out request failed. Any remote failure can still be reported.
- **Suggested fix:** After a sign-out error, check `auth.currentSession`. If null, replace the route stack with Login using the existing mounted guard. Alternatively subscribe to auth `signedOut` events centrally and route from there. Do not leave the authenticated shell visible without a session.

### H-03 — Header detection only recognises a first cell starting with `s.no`

- **Verification:** Static confirmed. Real workbook header text NOT VERIFIED.
- **Location:** `lib/screens/import_screen.dart:109-115`.
- **Cause:** `firstCell.toLowerCase().startsWith('s.no')` is the only check that suppresses A1 as the title. Any other header spelling (for example `S #`, `S.No` variants with different punctuation, `Reg #`, or a blank first header cell followed by a populated row) becomes the meeting title.
- **Effect:** The title controls meeting identity `(title, date)` in SQL. A header-derived title can create a separate meeting family or make a re-import appear new.
- **Expected:** Detect the header row by the actual expected column labels, or support both the documented title/A1 format and the header-only format with a stricter rule.
- **Suggested fix:** Normalise punctuation/whitespace and compare the full expected header set, not just the first cell prefix. Add tests for title-row and header-only workbooks, including blank A1.

### H-04 — Delete is offered for every meeting but only `upcoming` meetings can be deleted

- **Verification:** Static confirmed.
- **Location:** `lib/screens/meetings_screen.dart:238` always passes `onDelete`; `lib/widgets/MeetingCard.dart:90-104` renders the delete icon; `lib/services/meeting_service.dart:106-116` filters `.eq('status', 'upcoming')` and throws when no row is deleted.
- **Cause:** The card does not restrict delete by status, and the service intentionally restricts deletion to upcoming meetings.
- **Reproduction:** Open **Previous meetings**, tap the red delete icon on a done card, confirm deletion. The service deletes zero rows and throws `Only upcoming meetings can be deleted`. The same failure occurs on active/running/paused cards.
- **Effect:** A destructive confirmation is shown for an operation that cannot succeed. The UI and backend disagree.
- **Expected:** Show delete only for `upcoming` meetings, or implement a deliberate, documented delete policy for other statuses (for example blocked with an explanation).
- **Suggested fix:** Pass `onDelete` only when `meeting.status == 'upcoming'`, matching the edit rule. Recheck status in the handler and show a clear message if the state changed in another session.

## 4. Medium findings

### M-01 — Duplicate reg numbers are not validated before import

- **Verification:** Static confirmed.
- **Location:** `lib/screens/import_screen.dart:156-165`; SQL unique constraint at `supabase_meetings_migration.sql:41`; insert at `:109-117`.
- **Cause:** The parser does not detect duplicate `reg_no` values within the same meeting date. SQL enforces `UNIQUE (meeting_id, reg_no)`.
- **Reproduction:** Import a workbook with the same reg number twice on the same date. `import_schedule` raises a unique-violation and the whole RPC transaction fails.
- **Expected:** Report the duplicate row numbers before confirming, or define a deterministic merge policy.
- **Actual:** The user gets a raw database error after confirming; no meetings from that import are created.
- **Suggested fix:** Validate duplicates per `meeting_date` during parsing and show the first conflicting Excel row. Add a parser test for duplicates.

### M-02 — Text/numeric date and time cells are silently skipped

- **Verification:** Static confirmed. Real workbook cell types NOT VERIFIED.
- **Location:** `lib/screens/import_screen.dart:62-83`, `:127-143`.
- **Cause:** `cellDate` accepts only `DateCellValue` and `DateTimeCellValue`; `cellTime` accepts only `TimeCellValue` and `DateTimeCellValue`. Any other representation returns null, and the row is skipped before required-cell validation.
- **Effect:** If part of a workbook stores dates/times as text or an unsupported numeric form, those rows disappear without an error. If all rows are affected, the user sees only the generic `No valid rows were found in this file.` message.
- **Expected:** Parse common text/numeric representations or fail with a row-specific unsupported-format message.
- **Suggested fix:** Add explicit handling for text dates/times and numeric Excel serials; otherwise report `Row N has an unsupported date/time format` rather than silently skipping.

### M-03 — Unguarded API-row casts can crash screens

- **Verification:** Static confirmed as a crash path if nullable data is returned. The deployed `meeting_schedule` column nullability was not available.
- **Location:** `lib/screens/dashboard_screen.dart:327,450,455`; `lib/screens/live_screen.dart:324,328,330,332`; `lib/screens/edit_meeting_screen.dart:109`.
- **Cause:** Values such as `row['project'] as String`, `row['supervisor'] as String`, `row['status'] as String`, and `row['meeting_time'] as String` are cast without null guards. `Meeting.fromMap` also uses several non-null casts (`lib/models/meeting.dart:34-53`).
- **Effect:** A legacy or manually edited row with a null project/supervisor/status/time throws a type error during build/load and can blank the screen.
- **Expected:** Render a safe placeholder or surface a data error without crashing.
- **Suggested fix:** Use `?.toString() ?? ''` for display fields and validate required API fields centrally when mapping rows. Add a test with null fields.

### M-04 — Clock offset ignores network round-trip time

- **Verification:** Static confirmed formula. Real latency impact NOT VERIFIED.
- **Location:** `lib/utils/time_utils.dart:5-8`; called from Home `:60`, Live `:79`, Meetings `:63`.
- **Cause:** `serverOffset` subtracts the local receipt time from the server timestamp, so the full response latency is counted as clock skew.
- **Effect:** On a slow response, live timers run behind by roughly the latency. A later faster refresh moves them forward. Finished durations stored by SQL can appear inconsistent with the displayed timer.
- **Expected:** Estimate the offset using the request/response midpoint or retain the best low-latency sample.
- **Suggested fix:** Capture local time before and after the RPC and use the midpoint; discard/retry samples with excessive round-trip time.

### M-05 — Login title row can overflow

- **Verification:** Static layout risk. Runtime unverified.
- **Location:** `lib/screens/login_screen.dart:40-50`; fixed page padding at `:34`.
- **Cause:** Non-flexible logo plus a 24 px bold title in a `Row`. At 320 dp width with 42 dp side padding, the remaining width after the 56 dp logo and 10 dp gap is about 170 dp. `BIIT FYP Meeitngs` does not fit at default scale; large system text makes it worse.
- **Expected:** No overflow at 320 dp, large text, or landscape.
- **Suggested fix:** Wrap the title in `Expanded`/`Flexible` and allow wrapping, or reduce logo/title size on narrow layouts. Renderer verification is required.

### M-06 — Live header can overflow on very short keyboard-reduced heights

- **Verification:** Static layout risk. Runtime unverified.
- **Location:** `lib/screens/live_screen.dart:362-401`.
- **Cause:** When the keyboard is visible, the heading is hidden, but the paused banner, search field, filter strip, three 10 dp gaps, and 78 dp vertical padding remain outside the expanded list. On a short landscape/small viewport, these fixed controls can exceed the remaining body height.
- **Expected:** All controls and results remain reachable without overflow.
- **Suggested fix:** Put the remaining header controls in a sliver/scrollable composition or add a height-aware compact layout. Preserve lazy group building and pull-to-refresh.

### M-07 — Excel decoding and parsing block the UI isolate

- **Verification:** Static confirmed implementation. Perceived duration depends on file size/device.
- **Location:** `lib/screens/import_screen.dart:99-166`.
- **Cause:** `Excel.decodeBytes`, worksheet traversal, validation, grouping, and summary calculation all run synchronously inside `pickFile`.
- **Effect:** Large workbooks can freeze the UI and delay the busy indicator/feedback.
- **Expected:** Keep the app responsive while parsing.
- **Suggested fix:** Move decoding/parsing to an isolate (`compute`) or a worker, returning a plain parsed result. Add a progress/loading state.

### M-08 — Pause rounding accumulates timer error

- **Verification:** Static SQL confirmed. Real repeated-pause impact NOT VERIFIED.
- **Location:** `supabase_meetings_migration.sql:173`, `:199`, `:206-207`, `:218-219`, `:260`; display truncation at `lib/utils/time_utils.dart:20`.
- **Cause:** Each pause delta is cast/rounded to integer seconds before adding. Errors accumulate across pauses.
- **Effect:** Many short pauses can add several seconds of error to meeting/group durations, beyond normal one-second display granularity.
- **Expected:** Preserve fractional pause time internally and round only once for display/final output.
- **Suggested fix:** Store pause durations as numeric seconds or integer milliseconds; adjust Dart parsing and final duration calculations consistently.

### M-09 — Up-next number tiles lost the required pastel colours

- **Verification:** Static confirmed against the feature spec.
- **Location:** `lib/screens/dashboard_screen.dart:432-437`; spec table at `livemeet_codex_spec.md:48` and Up next requirement at `:299`.
- **Cause:** The pastel colour list and the tile `color` line are commented out. The number container has no background.
- **Effect:** The Home Up next list no longer matches the documented design (blue/peach/lilac/yellow tiles).
- **Expected:** Number tiles use the documented pastel palette.
- **Suggested fix:** Restore the palette and apply it by index modulo the list length.

### M-10 — Import/update errors force a full re-pick

- **Verification:** Static confirmed.
- **Location:** `lib/screens/import_screen.dart:216-223`, `:291-296`, `:379-383`; reset only after a non-null pick at `:98`.
- **Cause:** `showImportError` sets `canImport = false`. The parsed rows and title remain, but Confirm is disabled. The only reset path is picking a file again.
- **Effect:** A transient RPC failure or a locked-date message cannot be retried with the same parsed file. The user must reopen the picker.
- **Expected:** A failed import should allow retry with the same rows when the data is still valid, or clearly offer a **Choose file** action.
- **Suggested fix:** Keep `canImport = true` for retryable server errors while showing the error, or add an explicit retry/re-pick button. Distinguish validation errors from network errors.

### M-11 — Late time slots wrap past midnight

- **Verification:** Static confirmed.
- **Location:** `lib/screens/edit_meeting_screen.dart:17-20`, `:224`.
- **Cause:** `_hhmm` applies `m % 1440`. Adding a group after a 23:45 slot with a 15-minute gap produces `00:00` instead of flagging the invalid schedule.
- **Effect:** A meeting slot silently moves to the next day's time, which can confuse ordering and display.
- **Expected:** Reject or warn when the computed slot reaches/exceeds 24:00.
- **Suggested fix:** Bound slot creation and show a validation message; keep display formatting responsible only for valid 0–1439 values.

### M-12 — Stale automated test always fails

- **Verification:** Static confirmed and executed. `flutter test --reporter expanded` fails 1/1.
- **Location:** `test/widget_test.dart:14-29`; `lib/main.dart:48`.
- **Cause 1:** The test expects the Flutter counter template (`0`, `1`, `Icons.add`), which this app does not have.
- **Cause 2:** `MyApp.build` reads `Supabase.instance` without `Supabase.initialize()` in the test.
- **Effect:** The repository has no passing automated regression suite; failures are expected and cannot signal real regressions.
- **Expected:** Replace with tests that initialise/mock the dependency boundary and exercise real widgets/utilities.
- **Suggested fix:** Delete the counter test and add focused tests from `qa_reports/proposed_tests/` (time utilities, model mapping, MeetingCard, Button/Filter). Keep them text-only until the user explicitly asks to add test files.

## 5. Low findings

### L-01 — Login brand typo

- **Location:** `lib/screens/login_screen.dart:45`.
- **Problem:** The visible brand text is `BIIT FYP Meeitngs`.
- **Expected:** `BIIT FYP Meetings` (or the approved brand spelling).
- **Suggested fix:** Correct the string and add a widget assertion for the visible title.

### L-02 — Generic exception text shown to users

- **Locations:** `lib/screens/login_screen.dart:121`; dashboard `:118`, `:173`; meetings `:151`, `:277`; live `:212`; edit `:140`, `:279`, `:305`.
- **Problem:** Catch-all blocks interpolate `$e` directly into SnackBars/error text. This can expose stack-like library details, URLs, or confusing messages instead of a user action.
- **Expected:** Known `PostgrestException`/`AuthException` messages are shown; generic failures use a stable friendly message with optional logging.
- **Suggested fix:** Map exception types to short action-oriented messages. Keep technical detail out of the UI.

### L-03 — `Button.foreColor` is ignored

- **Location:** `lib/widgets/Button.dart:9,45`; caller at `lib/screens/main_screen.dart:40`.
- **Problem:** `foreColor` is stored but text colour is computed only from `color`. The parameter is part of the documented widget API.
- **Effect:** Callers cannot control label colour; the selected/unselected nav contract is only accidentally readable.
- **Expected:** Honour `foreColor` (with a sensible fallback) or remove it from the API and callers.
- **Suggested fix:** Use `foreColor ?? (color == null ? Colors.white : Colors.black)` and update callers, or delete the unused parameter.

### L-04 — Negative duration displays as `<1 min`

- **Location:** `lib/utils/time_utils.dart:33-37`.
- **Problem:** `formatTotal` returns `<1 min` for every value below 60, including negatives. SQL currently clamps most durations with `GREATEST(0, ...)`, so this is defensive.
- **Expected:** Clamp to zero or show an explicit `—`/invalid marker.
- **Suggested fix:** `if (sec <= 0) return '0 min';` (or the approved empty label) before the other branches.

### L-05 — Action can be silently ignored when another meeting is active

- **Location:** `lib/screens/meetings_screen.dart:91-99`, especially `:93`.
- **Problem:** The handler returns with no feedback when any other meeting is active. Under normal rendering the card is locked/disabled, but stale data or a state change on another device can reach this branch.
- **Expected:** Show a short message such as `Another meeting is already running` and reload.
- **Suggested fix:** Replace the silent return with a SnackBar and a guarded reload.

### L-06 — Bottom navigation blocked while busy without visual feedback

- **Location:** `lib/screens/main_screen.dart:24-27`, `:34-44`.
- **Problem:** `go()` ignores taps while `busy`, but the nav buttons keep their normal enabled appearance.
- **Expected:** Disabled visual state or a brief explanation while a mutation is pending.
- **Suggested fix:** Pass `enabled: !busy` to the nav `Button`s or apply a reduced opacity.

### L-07 — Per-second tickers rebuild whole screens

- **Locations:** Home `lib/screens/dashboard_screen.dart:41-45`; Live `lib/screens/live_screen.dart:56-60`; Meetings `lib/screens/meetings_screen.dart:44-48`.
- **Problem:** `setState(() {})` rebuilds the entire screen and its lists every second while running.
- **Effect:** Unnecessary work on 100+ group lists; may cause jank on low-end devices. It is not a correctness bug.
- **Expected:** Keep the single ticker rule but scope repaint to the timer widgets, or throttle rebuilds.
- **Suggested fix:** Use `ValueListenableBuilder`/`AnimatedBuilder` around timer text or a small notifier; preserve the single-timer disposal rule.

### L-08 — Supabase credentials are hardcoded

- **Location:** `lib/main.dart:10-15`.
- **Problem:** Project URL and anon key are committed in source.
- **Note:** Supabase anon keys are public by design, but hardcoding impedes environment separation and key rotation.
- **Suggested fix:** Use `--dart-define`/flavours for URL and anon key, with documented defaults for local development. Never commit a service-role key.

### L-09 — Live/Meetings error states have no explicit Retry

- **Locations:** `lib/screens/live_screen.dart:281-317`; `lib/screens/meetings_screen.dart:191-221`.
- **Problem:** Errors are shown inside a pull-to-refresh list, but there is no visible Retry button. On a short/empty list, users may not discover the gesture. Home and Edit do provide Retry.
- **Expected:** Consistent explicit recovery action.
- **Suggested fix:** Add a `Button(text: 'Retry', onTap: loadMeeting/loadMeetings)` under the error text, matching Home/Edit.

### L-10 — Login fields lack keyboard/autofill affordances

- **Locations:** `lib/widgets/TextBox.dart:26-38`; `lib/screens/login_screen.dart:60-92`.
- **Problem:** No `textInputAction`, `autofillHints`, `onFieldSubmitted`, or password autofill. The Enter key does not submit.
- **Expected:** Email keyboard can advance to password; password keyboard can submit; platform autofill works.
- **Suggested fix:** Add optional `textInputAction`, `autofillHints`, and `onFieldSubmitted` to `TextBox`; wire `next`/`done` and submit on done.

### L-11 — Gesture controls lack button semantics/tooltips

- **Locations:** `lib/widgets/Button.dart:30-54`; `lib/widgets/filter.dart:17-39`; `lib/widgets/MeetingCard.dart:79-104`; `lib/widgets/LiveDetailMeetingCard.dart:157-168`.
- **Problem:** `GestureDetector`-based controls are not exposed as buttons to assistive technology; the edit/delete/expand icons have no tooltips (some other icon buttons do).
- **Expected:** Controls expose button semantics, labels, and state; icons have tooltips where meaning is not otherwise visible.
- **Suggested fix:** Use `InkWell`/`Semantics(button: true, label: ...)` or `TextButton`/`IconButton` with tooltips. Preserve the visual design.

### L-12 — Bottom-nav labels may overflow at large text

- **Verification:** Static layout risk. Runtime unverified.
- **Location:** `lib/screens/main_screen.dart:56-72`.
- **Problem:** Four `Expanded` pill buttons with `fontSize: 14` and `spacing: 6`, inside 12 dp outer padding/margin. At 320 dp width the available label width is small; large accessibility text can clip or overflow.
- **Expected:** All four labels remain readable without overflow.
- **Suggested fix:** Allow text scaling/wrapping, reduce label size at large text, or use icon+label layout. Verify at 320 dp and 200% text scale.

### L-13 — Deprecated `onReorder` callback

- **Location:** `lib/screens/edit_meeting_screen.dart:500`; analyzer info.
- **Problem:** `ReorderableListView.onReorder` is deprecated after Flutter 3.41 in favour of `onReorderItem`.
- **Effect:** No current runtime failure; future Flutter upgrades may remove the API.
- **Expected:** Migrate before upgrading past the removal window.
- **Suggested fix:** Use `onReorderItem` and verify index-adjustment semantics (the new callback already adjusts `newIndex` for the removed item).

### L-14 — No app-level auth-state listener

- **Location:** `lib/main.dart:48-50`.
- **Problem:** The root chooses Login/MainScreen once from `currentSession`. There is no `onAuthStateChange` subscription to route on external sign-out, refresh failure, or session invalidation.
- **Effect:** If the session is cleared outside the Logout button, the authenticated shell can remain visible until restart. This is related to H-02 but covers non-Logout invalidation.
- **Expected:** A single central auth listener routes to Login when the session becomes null.
- **Suggested fix:** Subscribe in a stateful root, store/cancel the subscription, and navigate on `signedOut`/session loss.

## 6. Analyzer and test status

`flutter analyze` (all targets) found no errors or warnings and two infos:

1. `lib/screens/edit_meeting_screen.dart:500:7` — deprecated `onReorder` (L-13).
2. `lib/screens/edit_meeting_screen.dart:521:46` — `use_build_context_synchronously`. The code checks `mounted` before `Navigator.pop`; no crash path was established. This is not counted as a runtime bug.

`flutter test --reporter expanded` failed 1/1 because of M-12. Full output and analysis are in `02_static_analysis.md`.

## 7. Reviewed and dismissed

### Dismissed: `deleteGroup` removes `slots.removeLast()` instead of the deleted index

- **Location:** `lib/screens/edit_meeting_screen.dart:229-243`.
- **Why it was considered:** Deleting a middle group does not remove that group's specific time slot.
- **Why it is not a defect from the available evidence:** The code comment at `:241` states the intended behaviour: later groups move up into earlier time slots. Removing the last slot and keeping the remaining slot list in place achieves that compaction. Delete-first, delete-middle, and delete-last all preserve equal `groups`/`slots` lengths and reassign times by position.
- **What would make it a defect:** A documented requirement that a deleted group's time slot must be removed while all other groups keep their original times. No such requirement is present in the reviewed spec/source.
- **Action:** Not counted. Confirm the intended scheduling rule with the product owner before changing it.

### Dismissed: Restore should switch from Previous to Coming automatically

- The meeting correctly disappears from Previous after reload and reappears under Coming. No reviewed requirement mandates an automatic tab switch. This is a possible UX enhancement, not a defect.

### Dismissed: Meeting header uses the device date when there is no active meeting

- `Meetings` intentionally shows today, and Home/Live fall back to today when there is no meeting date. This matches the reviewed spec. Only timer timestamps use server-corrected time.

## 8. Deployment and security observations (not counted above)

### D-01 — `meeting_schedule` RLS/grants are not defined by the supplied migration

- The migration alters `meeting_schedule` but does not enable RLS or grant table/sequence privileges (`supabase_meetings_migration.sql:31-43`).
- All listed RPCs use default `SECURITY INVOKER`.
- A deployment whose existing table lacks the required authenticated grants/policies will fail imports and timer actions with permission errors.
- **Status:** Deployment-dependent; inspect the live schema/policies before sign-off.

### D-02 — `restart_meeting` is only in the second SQL file

- `restart_meeting` is defined in `restart_meeting.sql:3-36`, not in the main migration.
- A deployment that runs only `supabase_meetings_migration.sql` will reject the Restore action with a function-not-found error.
- **Status:** Deployment checklist item; include both SQL files in the release runbook.

### D-03 — Broad authenticated CRUD and no owner separation

- `meetings` has `GRANT SELECT, INSERT, UPDATE, DELETE TO authenticated` and a policy `USING (true) WITH CHECK (true)` (`supabase_meetings_migration.sql:50-53`).
- Any authenticated account can read/modify all meetings through PostgREST, not only through the state-machine RPCs.
- This matches the documented single-PA/shared-backend model only if sign-up is disabled and only trusted accounts exist.
- **Status:** Auth sign-up setting and live policies NOT VERIFIED. Confirm before release.

### D-04 — Re-running the migration deletes all schedule rows

- `DELETE FROM meeting_schedule;` at `supabase_meetings_migration.sql:33` is destructive and the file is documented as run-once.
- **Status:** Release-process risk. Never re-run on a live database without a verified backup.

### D-05 — The reviewed SQL may not match the live database

- The live project may already contain `save_meeting_schedule`/`update_schedule` or different grants/constraints. No database query, migration or RPC was executed.
- **Status:** NOT VERIFIED. The critical findings are based on the repository artifacts and must be confirmed against the deployed schema before being closed as deployment-only issues.

## 9. Verification limits

- No app, emulator, or phone session was launched.
- No real Excel workbook was available; row counts, header text, and cell types were not observed.
- No Supabase connection, query, RPC, migration, or Auth operation was performed.
- No live RLS policy, grant, sign-up setting, installed migration, or function list was available.
- Layout/overflow, accessibility, network latency, logout failure presentation, repeated-pause accuracy, and process-death behaviour are source-supported risks, not reproduced device results.
- The analyzer result is authoritative for compile/static diagnostics under Flutter 3.44.4. The test failure is authoritative for the current `test/widget_test.dart`, but it tests obsolete app behaviour.
