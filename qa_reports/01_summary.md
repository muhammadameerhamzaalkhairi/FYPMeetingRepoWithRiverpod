# 01 — QA Audit Summary

Audit date: 2026-11-02
Project: `D:\7th Semester\Flutter\Project\livemeet`
Overall verdict: **Not ready for release or phone sign-off.**

The implemented UI is broad and largely coherent, and static analysis reports no errors or warnings. However, two critical backend contracts are missing from the supplied SQL, two normal user flows can lose or merge data, logout can strand a signed-out user, and the only automated test is obsolete. The live Supabase deployment, real workbook, phone layout, and timer accuracy were not available, so this verdict is a source/deployment-artifact review, not a device certification.

## Reports in this audit

| File | Contents |
|---|---|
| `01_summary.md` | This executive summary. |
| `02_static_analysis.md` | Toolchain, analyzer output, existing test result, SQL/Dart contract matrix, RLS/grants review, NOT VERIFIED list. |
| `03_bug_report.md` | 32 detailed findings (2 Critical, 4 High, 12 Medium, 14 Low), dismissed candidates, deployment/security observations. |
| `04_test_cases.md` | 132 manual test cases across auth, import, meetings, edit, live, home, timers, SQL/deployment, and layout/accessibility. |
| `05_git_status_before_after.md` | Before/after worktree status proving only `qa_reports/` changed. |
| `proposed_tests/` | Text-only test proposals. Not added to `test/` and not executed. |

## Finding counts

| Severity | Count |
|---|---:|
| Critical | 2 |
| High | 4 |
| Medium | 12 |
| Low | 14 |
| **Total** | **32** |

## Top 10 risks

1. **C-01 — Schedule editing cannot work on the supplied schema.** `save_meeting_schedule` is called from `meeting_service.dart:100-103` / `edit_meeting_screen.dart:272` but is not defined in either SQL file.
2. **C-02 — Re-import/update cannot work on the supplied schema.** `update_schedule` is called from `import_screen.dart:245-248` but is not defined in either SQL file, and its `updated/added/locked` result contract is undocumented.
3. **H-01 — Interleaved Excel dates silently merge distinct projects.** Group numbering restarts on every date change (`import_screen.dart:146-154`), so a date that reappears gets duplicate group numbers and Live treats distinct projects as one group.
4. **H-02 — Failed logout can expose the authenticated screen.** Installed `gotrue` 2.27.3 clears the local session before the remote call can throw; the app only navigates to Login on success (`dashboard_screen.dart:90-123`).
5. **H-03 — Header detection is too narrow.** Only a first cell starting with `s.no` is treated as a header (`import_screen.dart:109-115`); other header spellings become the meeting title and can split or duplicate meeting families.
6. **H-04 — Delete is offered where it must fail.** All meeting cards show delete (`meetings_screen.dart:238`), but the service deletes only `upcoming` meetings (`meeting_service.dart:106-116`); done/active deletes show a confirmation and then fail.
7. **M-01 — Duplicate reg numbers abort an import.** No pre-import duplicate validation; the SQL unique constraint (`migration:41`) rejects the whole transaction with a raw database error.
8. **M-02 — Unsupported date/time cells disappear silently.** Text/unsupported numeric date or time cells return null and are skipped before validation (`import_screen.dart:62-83,127-143`), producing partial or empty imports.
9. **Deployment D-01/D-02 — Required database setup is incomplete in the repository.** `meeting_schedule` RLS/grants are not defined by the migration, all RPCs are `SECURITY INVOKER`, and `restart_meeting` lives only in the separate SQL file.
10. **Deployment D-03 / unverified runtime — Security and layout limits.** Any authenticated user has full `meetings` CRUD (`migration:50-53`), sign-up state is unknown, and keyboard/short-screen overflow, large text, and real network latency were not rendered or measured.

## What was verified

- Full read of all application Dart files, both SQL files, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, the feature spec, and existing tests/reports.
- `flutter --version`: Flutter 3.44.4 stable, Dart 3.12.2, Windows 10.
- `flutter doctor -v`: Flutter/Windows/Chrome/Edge/Android device `SM A065F (Android 16, API 36)` available; Android licenses and Windows desktop workload warnings.
- `flutter analyze`: no errors, no warnings, 2 infos (deprecated `onReorder`; `use_build_context_synchronously`).
- `flutter test --reporter expanded`: FAIL 1/1 (stale counter test; Supabase not initialized in test).
- Dart/SQL RPC matrix: parameter names/types match for the eight defined RPCs; `import_schedule` row keys match exactly.
- Installed `file_picker` 13.1.0 and `excel` 4.0.6 APIs used by the import screen are valid.
- Installed `gotrue` 2.27.3 logout sequence: local session removal before the remote sign-out await.
- No `print`/`debugPrint` calls in `lib/`.
- No source, SQL, pubspec, or platform file was modified. `pubspec.lock` is unchanged.

## What was NOT verified

- Real Excel workbook totals/header/cell types (the acceptance target is 3 days / 104 groups / 389 students).
- Whether the live Supabase database contains `save_meeting_schedule` or `update_schedule`, or matches the repository SQL.
- Deployed `meeting_schedule` RLS, grants, Auth sign-up setting, installed migrations, or function list.
- Actual import, meeting, group, pause/resume, restart, and delete outcomes against a live backend.
- Pixel-level layout at 320 dp, landscape, tablet, dark mode, large text, or with the keyboard open.
- Real timer accuracy under network latency/multiple pauses; process death/session restoration.
- The exact presentation of failed logout, overflow, or accessibility issues on a phone.

## Quality assessment by area

| Area | Assessment |
|---|---|
| Authentication | Login validation is present and the loading guard was fixed, but failed logout routing (H-02), missing auth-state routing (L-14), raw errors (L-02), typo (L-01), and keyboard/autofill gaps (L-10) remain. |
| Import | Strong happy-path structure and matching eight-key payload, but two missing update/save contracts (C-01/C-02), interleaved-date corruption (H-01), narrow header detection (H-03), duplicate-reg aborts (M-01), unsupported cell skipping (M-02), and synchronous parsing (M-07) are release blockers or medium risks. |
| Meetings list | Status-based tabs, sorting, locking, and RPC actions are structurally sound. Delete policy mismatch (H-04), silent stale-state returns (L-05), and missing Retry (L-09) remain. |
| Meeting edit | Undo/redo, validation, reorder, and save UI are well structured, but the save RPC does not exist in the supplied SQL (C-01) and midnight wrapping is unguarded (M-11). |
| Live | Active-meeting grouping, search/filter, selection/accordion, and one-timer-per-screen rules are implemented. Nullable-row casts (M-03), keyboard-height overflow (M-06), and per-second rebuild cost (L-07) remain. |
| Home | Live card, counters, and Up next are present. Pastel tiles are missing (M-09); clock-offset error (M-04) affects timer accuracy. |
| SQL/backend | Eight RPCs and the overview view match Dart. Missing save/update RPCs, undocumented result contracts, incomplete schedule security, separate restart migration, and destructive migration rerun risk are the main gaps. |
| Tests/CI | Only a stale counter test exists; it fails. No meaningful automated regression suite. |
| Accessibility/layout | Not certified. Gesture-only controls, missing semantics/tooltips, large-text risks, and keyboard/short-screen overflow need device/accessibility testing. |

## Recommended fix order

1. **Release blockers:** add/review `save_meeting_schedule` and `update_schedule` SQL contracts (or remove the Dart paths); fix interleaved-date grouping; fix failed-logout routing; restrict or implement non-upcoming delete.
2. **Before sign-off:** strengthen header detection; validate duplicate regs; handle/report unsupported date/time cells; verify `meeting_schedule` grants/RLS and install both SQL files; confirm Auth sign-up is disabled.
3. **Reliability/accuracy:** use round-trip-aware clock sync; preserve fractional pause duration; guard nullable API fields; move Excel parsing off the UI isolate.
4. **Usability/accessibility:** fix login overflow and typo; add retry actions and keyboard/autofill affordances; restore pastel Up-next tiles; verify 320 dp, landscape, 200% text, and keyboard-open layouts.
5. **Test suite:** replace the stale widget test with focused time/model/widget tests, then add parser and integration tests once the missing RPC contracts are available.

## Release recommendation

Do not ship until C-01, C-02, H-01, H-02, and H-04 are resolved or explicitly accepted, and until the live Supabase schema/grants and both SQL migrations are verified. After those fixes, run the 132-case manual suite in `04_test_cases.md` on the target Android device, with the real workbook and a representative live/staging backend.
