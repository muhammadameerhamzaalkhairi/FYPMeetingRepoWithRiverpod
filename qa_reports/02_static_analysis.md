# 02 — Static Analysis, Compile Review and SQL/Dart Cross-Check

Audit date: 2026-11-02
Project: `D:\7th Semester\Flutter\Project\livemeet`
Mode: read-only audit. No source, SQL, pubspec or platform file was modified.

## 1. Toolchain

```text
Flutter 3.44.4 • channel stable
Framework revision ad70ec4617 (2026-06-24)
Engine revision a10d8ac38d
Dart 3.12.2
DevTools 2.57.0
```

`flutter doctor -v` result:

- Flutter: OK, Windows: OK, Chrome/Edge: OK, connected device `SM A065F (Android 16, API 36)`: OK
- Android toolchain: warning — some Android licenses not accepted
- Visual Studio (Windows desktop): warning — missing Desktop C++ workload / Windows SDK
- Network resources: OK

`flutter pub get` was **not** run. It is only allowed if it cannot change `pubspec.lock`; that cannot be known in advance without running it. The existing `.dart_tool/package_config.json` was already valid: `flutter analyze` and `flutter test` both resolved packages and ran. `pubspec.lock` was unchanged at the end of the audit (see `05_git_status_before_after.md`).

## 2. `flutter analyze` — full output

Command: `flutter analyze` (from project root, all targets).

```text
Analyzing livemeet...

   info - 'onReorder' is deprecated and shouldn't be used. Use the onReorderItem callback instead. The onReorderItem callback adjusts the newIndex parameter for a removed item at the oldIndex. This feature was deprecated after v3.41.0-0.0.pre. Try replacing the use of the deprecated member with the replacement - lib\screens\edit_meeting_screen.dart:500:7 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check. Guard a 'State.context' use with a 'mounted' check on the State, and other BuildContext use with a 'mounted' check on the BuildContext - lib\screens\edit_meeting_screen.dart:521:46 - use_build_context_synchronously

2 issues found. (ran in 48.1s)
```

### Analysis of the two infos

| Line | Info | Assessment |
|---|---|---|
| `lib/screens/edit_meeting_screen.dart:500` | `onReorder` deprecated | Not a runtime bug under Flutter 3.44.4. The callback still works. Future Flutter versions may remove it; migration to `onReorderItem` is advisable. |
| `lib/screens/edit_meeting_screen.dart:521` | `use_build_context_synchronously` | The code does check `mounted` on the State before `Navigator.of(context).pop(false)` (line 521). No crash path was identified; the lint is triggered because the analyzer cannot prove the guard is unrelated. Still technically safe under the current code. |

There are **no analyzer errors and no warnings**. There are **no compile errors**, missing imports, undefined constructor parameters, or missing classes found by the compiler.

### Compile-level cross-check performed manually

- Every widget constructor call was compared with its class definition. No call passes a parameter that the constructor does not define.
- Every import resolves. `file_picker` 13.1.0 exposes the static `FilePicker.pickFile` and `PlatformFile.readAsBytes` APIs used by `import_screen.dart`; this was verified in the installed package source.
- `excel` 4.0.6 exposes `DateCellValue`, `TimeCellValue` and `DateTimeCellValue` with the `year/month/day/hour/minute` fields used by `import_screen.dart`.
- `Meeting.fromMap` keys match the `meetings_overview` columns (see section 4).
- No `print` / `debugPrint` calls were found in `lib/`.

## 3. Existing automated test — `flutter test`

Command: `flutter test --reporter expanded`

Result: **FAIL (1/1 test failed)**.

The only test is the stale Flutter counter template at `test/widget_test.dart`.

Two independent failures:

1. `MyApp.build` at `lib/main.dart:48` reads `Supabase.instance` without `Supabase.initialize()` being called in the test, producing:
   `You must initialize the supabase instance before calling Supabase.instance`
2. The test expects a counter (`find.text('0')`, `find.byIcon(Icons.add)`), which this app no longer has.

This is a test-suite defect, not a production-code compile failure. No test file was modified. Proposed replacement tests are in `qa_reports/proposed_tests/` as plain text and were not executed.

## 4. SQL / Dart cross-check

SQL files in the repository:

- `lib/SQLandMDFileFolder/supabase_meetings_migration.sql`
- `lib/SQLandMDFileFolder/restart_meeting.sql`

### 4.1 RPC call matrix

| Dart caller | RPC name | Params sent | Defined in supplied SQL? | Match |
|---|---|---|---|---|
| `meeting_service.dart:8` | `server_now` | none | Yes — `supabase_meetings_migration.sql:78-79` | OK |
| `meeting_service.dart:52-56` | `import_schedule` | `p_title`, `p_rows` | Yes — `supabase_meetings_migration.sql:84-129` | OK (param names/types match; returns JSONB array) |
| `meeting_service.dart:60` | `start_meeting` | `p_id` | Yes — `:132-145` | OK |
| `meeting_service.dart:64` | `pause_meeting` | `p_id` | Yes — `:148-157` | OK |
| `meeting_service.dart:68` | `resume_meeting` | `p_id` | Yes — `:160-181` | OK |
| `meeting_service.dart:72` | `end_meeting` | `p_id` | Yes — `:184-221` | OK |
| `meeting_service.dart:76` | `restart_meeting` | `p_id` | Yes — `restart_meeting.sql:3-36` (separate file) | OK only if the second SQL file is also run |
| `meeting_service.dart:80-83` | `group_start` | `p_meeting`, `p_group` | Yes — `:224-245` | OK |
| `meeting_service.dart:87-90` | `group_end` | `p_meeting`, `p_group` | Yes — `:248-266` | OK |
| `meeting_service.dart:100-103` | `save_meeting_schedule` | `p_id`, `p_rows` | **NO** | **MISMATCH — function is not defined anywhere in the supplied SQL** |
| `import_screen.dart:245-248` | `update_schedule` | `p_title`, `p_rows` | **NO** | **MISMATCH — function is not defined anywhere in the supplied SQL** |

`restart_meeting` is only in `restart_meeting.sql`, not in `supabase_meetings_migration.sql`. Its own GRANT/REVOKE block exists at `restart_meeting.sql:38-39`, so it is deployable, but a database built from the migration alone will reject the Restore action.

### 4.2 Table / view / column matrix

| Dart access | SQL object | Columns used in Dart | Assessment |
|---|---|---|---|
| `meeting_service.dart:13` | view `meetings_overview` | all columns in `Meeting.fromMap`: `id,title,meeting_date,status,started_at,ended_at,paused_at,paused_seconds,total_seconds,groups_total,students_total,groups_done,groups_skipped,groups_remaining` | OK — all are selected by the view at `supabase_meetings_migration.sql:58-68` |
| `meeting_service.dart:19` | `meetings_overview` | `status` filter | OK |
| `meeting_service.dart:28-32` | table `meeting_schedule` | `meeting_id,group_no,id` and `select()` returns all columns | OK, assuming the pre-existing table is present |
| `meeting_service.dart:41-45` | table `meetings` | `title,meeting_date` | OK |
| `meeting_service.dart:107-112` | table `meetings` | `id,status` delete filter | OK (DELETE grant at migration `:50`) |
| `import_screen.dart:245-248` | RPC `update_schedule` | expects list of maps with `state` in `updated/added/locked` | **No SQL contract exists**; the expected return shape is invented by the Dart caller |
| `edit_meeting_screen.dart:272` + `meeting_service.dart:100-103` | RPC `save_meeting_schedule` | expects VOID; rows contain `group_no, meeting_time, project, supervisor, reg_no, student_name, tech` (no `meeting_date`) | **No SQL contract exists**; cannot verify parameter/row semantics |

### 4.3 Parameter names and types

- `p_id` is `BIGINT` in SQL and `int` in Dart. OK.
- `p_meeting` is `BIGINT`, `p_group` is `INT` in SQL, both `int` in Dart. OK.
- `p_title` is `TEXT`, `p_rows` is `JSONB`; Dart sends `String` and `List<Map<String, dynamic>>` which Supabase serializes to JSON. OK.
- `server_now` returns `TIMESTAMPTZ`; Dart parses the returned string with `DateTime.parse`. OK.
- `import_schedule` returns `JSONB` array; Dart casts `as List<dynamic>`. PostgREST decodes JSON arrays to `List`, so this is OK at the type level, but it will throw if the function returned an object/null.
- `Meeting.fromMap` casts `meeting_date` to `String` and parses it. PostgREST normally serializes DATE as `YYYY-MM-DD`, so this works; it would crash if the column were ever returned as a different type.
- `Meeting.fromMap` casts aggregate columns with `as num`. The view casts them with `::int`, so OK.

### 4.4 Import payload row keys

Dart sends exactly the eight keys documented by the SQL comment:

`group_no, meeting_date, meeting_time, project, supervisor, reg_no, student_name, tech`

SQL reads them through `jsonb_to_recordset` with matching names and types at `supabase_meetings_migration.sql:114-116`. **OK.**

The edit screen's `save_meeting_schedule` payload omits `meeting_date` (`edit_meeting_screen.dart:258-270`). Since that function does not exist in the repository, its expected row contract cannot be checked.

## 5. SQL logic, RLS and grants review (read-only; no SQL executed)

### 5.1 What is correctly protected

| Object | Observation |
|---|---|
| `meetings` RLS | Enabled at `supabase_meetings_migration.sql:48`. `anon` privileges revoked (`:49`). `authenticated` gets SELECT/INSERT/UPDATE/DELETE (`:50`) and sequence usage (`:51`). Policy `authenticated full access` is `FOR ALL TO authenticated USING (true) WITH CHECK (true)` (`:52-53`). |
| `meetings_overview` | `security_invoker = true` (`:58`), `anon` revoked, `authenticated` SELECT granted (`:70-71`). |
| RPC EXECUTE | `PUBLIC` and `anon` revoked; `authenticated` granted for all eight migration RPCs (`:271-278`). |
| `one_active_meeting` | Partial unique index on `((true)) WHERE status IN ('running','paused')` (`:27-28`) enforces at most one active meeting even under a race. |
| `start_meeting`, `pause_meeting`, `resume_meeting`, `end_meeting`, `group_start`, `group_end` | State-machine predicates are applied in the `UPDATE`/`SELECT`; duplicate/invalid transitions raise exceptions. `resume_meeting`, `end_meeting` and `group_start` use row/table locks. |
| `import_schedule` | Single RPC call = one transaction; inserts one meeting per date and skips already-existing `(title, date)`; returns per-date result. |
| `restart_meeting` | Locks `meetings` in `SHARE ROW EXCLUSIVE` (`restart_meeting.sql:7`), rejects another active meeting, updates only `done` meetings, resets schedule timing in the same transaction. |

### 5.2 Security / deployment gaps (NOT VERIFIED against the live database)

1. **`meeting_schedule` RLS and grants are not defined by the supplied migration.** The migration only deletes rows and adds columns/constraints (`supabase_meetings_migration.sql:31-43`). It does not enable RLS or grant table/sequence privileges on `meeting_schedule`. All RPCs are `SECURITY INVOKER` (default), so `import_schedule`, `group_start`, `group_end`, `resume_meeting`, `end_meeting` and `restart_meeting` depend on the caller (`authenticated`) already having the needed `SELECT/INSERT/UPDATE` privileges and on the existing RLS policy allowing those writes. If the deployed table is not configured the same way as the development database, imports and timer actions can fail with permission errors. This cannot be confirmed from the repository.
2. **Broad authenticated table access.** The `meetings` policy allows any authenticated account full CRUD, not just the RPC state machine. If email sign-up is enabled in Supabase Auth, any person who can create an account can read/delete/update all meetings through PostgREST. Whether sign-up is enabled is **NOT VERIFIED**. The app itself assumes a single PA user.
3. **No owner/role separation.** There is no `user_id` column or policy. This matches the stated single-user design, but it is a security assumption worth confirming.
4. **`restart_meeting` is a second migration.** A deployment that runs only `supabase_meetings_migration.sql` will have the Restore button fail with “function not found”. The file header says to run it separately, so this is a deployment checklist item rather than a code defect.
5. **`import_schedule` accepts client-supplied `group_no`.** It does not recompute group numbering. Combined with the Dart interleaved-date bug, it can store colliding group numbers on the same date. This is a data-integrity gap, not an RLS gap.
6. **The migration deletes all existing `meeting_schedule` rows** (`:33`). It is a one-time destructive migration; documented in the file header, but it must never be re-run on a live database without a backup. Not a code bug; a release-process risk.

## 6. Static observations that are not analyzer findings

- `lib/main.dart:10-15` contains the Supabase project URL and anon key in source. Anon keys are designed to be public in client apps, but committing them makes environment rotation and separation harder. See bug L-08.
- `lib/widgets/Button.dart:9,45` stores `foreColor` but never reads it; the text color is always derived from `color`. See bug L-03.
- `lib/screens/edit_meeting_screen.dart:500` uses the deprecated `onReorder`; see the analyzer note above.
- The only existing test (`test/widget_test.dart`) is a stale counter template and cannot run against this app. See section 3.

## 7. NOT VERIFIED items

These were not claimed as passes or failures because they require a device/backend:

- Real Excel workbook totals (3 days / 104 groups / 389 students) and real header/A1 cell content.
- Any behaviour against the live Supabase project, including whether `update_schedule` or `save_meeting_schedule` exist in the deployed database but not in the repository.
- Deployed `meeting_schedule` RLS/grants, Auth sign-up setting, and installed migration state.
- Pixel-level layout on 320 dp, landscape, tablet, large system text, dark mode.
- Actual timer accuracy under real network latency and multiple pause/resume cycles.
- Process-death/session-restoration behaviour.
- Real log-out failure behaviour on a phone (the library source path is established, the device presentation is not).
