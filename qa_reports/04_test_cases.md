# 04 — Manual Test Cases

Audit date: 2026-11-02
Project: `D:\7th Semester\Flutter\Project\livemeet`
Case count: **132**

These are manual test cases for the target Android device and a controlled Supabase environment. None were executed for this audit; results and evidence must be recorded by the tester. Priorities: **P0** release blocker, **P1** must pass before sign-off, **P2** should pass, **P3** polish/risk check.

Use a staging project or a disposable authenticated account. Do not run destructive SQL against production. The real workbook should be the one that must produce **3 days / 104 groups / 389 students** if that is still the acceptance target.

## A. Authentication and session (12)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| AUTH-01 | Launch with no session; enter a valid registered email and password; tap Sign in. | Login succeeds; `MainScreen` opens on Home; Back does not return to Login. | P0 | — |
| AUTH-02 | Enter `not-an-email`, any password; tap Sign in. | Inline `Enter a valid email`; no auth request/navigation. | P1 | — |
| AUTH-03 | Leave email blank; tap Sign in. | Inline `Email is required`; no request. | P1 | — |
| AUTH-04 | Leave password blank; tap Sign in. | Inline `Password is required`; no request. | P1 | — |
| AUTH-05 | Enter a valid email with a wrong password. | Error SnackBar appears; button re-enables; user can retry. | P1 | L-02 |
| AUTH-06 | Enter a password; toggle the eye icon twice. | Password is obscured, then visible, then obscured; text is preserved. | P2 | — |
| AUTH-07 | Tap Sign in twice rapidly while the request is pending. | Only one request is sent; the button reads `Signing in...` and is visually disabled. | P1 | — |
| AUTH-08 | Sign in, force-stop the app, reopen. | Session is restored; Home opens without showing Login. | P1 | — |
| AUTH-09 | Tap Logout, then Cancel. | User stays signed in; no auth call is made; Home state remains usable. | P1 | — |
| AUTH-10 | Disconnect network; tap Logout and confirm. | If the local session is cleared, the app must route to Login and not leave authenticated data visible; any remote failure may be reported. | P0 | H-02 |
| AUTH-11 | Invalidate/revoke the session outside the app (dashboard/another client), then return to the app and trigger a request. | App detects session loss and routes to Login, or clearly blocks the authenticated UI. | P1 | L-14 |
| AUTH-12 | Focus the email field, press Next/Enter; focus password, press Done/Enter. | Keyboard action moves to password, then submits the form (after the L-10 fix). | P2 | L-10 |

## B. Import parsing, validation and upload (28)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| IMP-01 | Pick the real acceptance workbook. | Upload card shows `3 days \| 104 groups \| 389 students` (or documented current totals); Step 2; Confirm enabled. | P0 | — |
| IMP-02 | Open the picker and press Cancel/Back. | No error; previous state is preserved; busy clears. | P1 | — |
| IMP-03 | Select a corrupt/renamed non-Excel file with an `.xlsx` extension. | Readable error box; Confirm disabled; no crash; re-pick works. | P1 | L-02 |
| IMP-04 | Select a valid workbook with no worksheets. | `No worksheet was found in this file.` in the error box; Confirm disabled. | P1 | — |
| IMP-05 | Select a workbook whose A1 is `Meeting Schedule Fall 2026` plus a header row. | Title is the trimmed A1 text; header/title rows are skipped; summary is correct. | P0 | — |
| IMP-06 | Select a header-only workbook with blank A1. | Title falls back to the file name without `.xlsx`; header row is skipped. | P1 | — |
| IMP-07 | Select a header-only workbook whose A1 is `S.No.`. | Title falls back to the file name; summary is correct. | P1 | — |
| IMP-08 | Select a header-only workbook whose A1 is `S #` / `Reg #` / another header spelling. | Title must still fall back to the file name, not the header text. | P1 | H-03 |
| IMP-09 | Use A1 with leading/trailing spaces. | Stored/title text is trimmed. | P2 | — |
| IMP-10 | Include a row with fewer than 8 cells. | Row is skipped; no crash; remaining rows import normally. | P2 | — |
| IMP-11 | Include a valid date/time row with blank reg #. | Red error box names the Excel row and `a reg #`; Confirm disabled; no import. | P1 | — |
| IMP-12 | Include a valid date/time row with blank student name. | Error names the row and `a student name`; Confirm disabled. | P1 | — |
| IMP-13 | Include a valid date/time row with blank supervisor. | Error names the row and `a supervisor`; Confirm disabled. | P1 | — |
| IMP-14 | Include a valid date/time row with blank project. | Error names the row and `a project`; Confirm disabled. | P1 | — |
| IMP-15 | Store all date/time cells as text (`13/10/2026`, `11:00 AM`). | Rows are parsed, or a row-specific unsupported-format error is shown; no silent partial import. | P1 | M-02 |
| IMP-16 | Store date/time as a numeric Excel serial with a date/time number format. | Rows are parsed, or a row-specific unsupported-format error is shown. | P1 | M-02 |
| IMP-17 | Use interleaved dates: 13 Oct A, 19 Oct B, 13 Oct C (distinct regs). | Import is rejected with a row-specific error, or A/C receive distinct group numbers on 13 Oct. | P0 | H-01 |
| IMP-18 | Use three contiguous date blocks with known groups/students. | Summary days/groups/students match the workbook; group numbers restart only per date block. | P0 | — |
| IMP-19 | Put the same reg # twice on the same date. | Pre-import validation reports both row numbers; no RPC is sent. | P1 | M-01 |
| IMP-20 | Put the same reg # on two different dates. | Import succeeds; uniqueness is per meeting/date. | P2 | — |
| IMP-21 | Import a workbook whose title/dates all already exist; try to confirm. | Update path is offered only if supported; otherwise Confirm is disabled with an `Already added` explanation. | P0 | C-02 |
| IMP-22 | Import a workbook where 2 of 3 dates exist. | Message states `2 of 3 days already added...`; update/import path matches the documented contract. | P1 | C-02 |
| IMP-23 | On the update prompt, tap Cancel. | No RPC is sent; parsed rows remain available; busy clears. | P1 | — |
| IMP-24 | On the update prompt, tap Update on a database with only the supplied SQL. | A readable function-not-found error is shown; no partial update; the app remains usable. | P0 | C-02 |
| IMP-25 | Update a meeting whose date/status is locked (started/finished). | Result reports `locked` per date; no locked data is overwritten; message explains skips. | P1 | C-02 |
| IMP-26 | Force the import/update RPC to fail once (offline), then reconnect. | Error is shown; user can retry the same parsed rows without re-picking (or a clear Retry/Choose file action exists). | P2 | M-10 |
| IMP-27 | Complete a successful import. | Screen resets to Step 1; navigation opens Meetings/Coming; busy clears; no duplicate tap path remains. | P0 | — |
| IMP-28 | Pick a very large workbook and immediately interact with the screen. | Busy/progress is visible and the UI does not freeze during decode/parse. | P2 | M-07 |

## C. Meetings tab and meeting actions (16)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| MTG-01 | Open Meetings/Coming with no upcoming/active meetings. | Centered `No coming meetings. Import a schedule first.` and `Go to Import`; navigation works. | P1 | — |
| MTG-02 | Open Meetings/Previous with no done meetings. | Centered `No previous meetings yet.`; no action buttons required. | P2 | — |
| MTG-03 | With one active and several upcoming meetings, open Coming. | Active card is first; others follow by ascending date then id; active card is lime. | P1 | — |
| MTG-04 | With one active meeting, inspect every other Coming card. | Other cards are faded to 0.5 and their action buttons are disabled. | P1 | — |
| MTG-05 | Tap Start on an upcoming card; Cancel the dialog. | No RPC is sent; card state is unchanged. | P1 | — |
| MTG-06 | Tap Start; confirm. | Meeting becomes running; other cards lock; Home shows live; busy clears; reload reflects the server. | P0 | — |
| MTG-07 | Trigger Start when another meeting is active (second device or stale state). | Server message is shown in a SnackBar; list reloads; no second active meeting. | P1 | — |
| MTG-08 | On a running meeting, tap Pause, then Resume. | No confirm dialogs; state toggles; timers freeze/continue; reload succeeds. | P1 | — |
| MTG-09 | Tap End on an active card; Cancel, then repeat and confirm. | Cancel does nothing; Confirm ends the meeting and moves it to Previous. | P0 | — |
| MTG-10 | Open Previous after ending a meeting. | Card shows Started/Ended, stored total, Done/Skipped counts; no action row. | P1 | — |
| MTG-11 | On Previous, tap Restore; Cancel, then confirm. | Cancel does nothing; Confirm resets progress and the meeting returns to Coming. | P1 | D-02 |
| MTG-12 | While another meeting is active, inspect a Previous card. | Restore is faded/disabled; handler rejects stale taps. | P1 | — |
| MTG-13 | On an upcoming card, tap Delete; confirm. | Meeting and schedule rows are deleted; list reloads; no error. | P1 | — |
| MTG-14 | On a done/active card, tap Delete; confirm. | Delete must not be offered, or a clear non-destructive explanation is shown before the call. | P0 | H-04 |
| MTG-15 | Inspect edit icons across statuses. | Edit is available only for upcoming; no edit icon on running/paused/done. | P1 | — |
| MTG-16 | Pull to refresh; double-tap action buttons during a pending action. | Refresh works; only one RPC is sent; buttons remain disabled until completion. | P1 | — |

## D. Meeting edit screen (14)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| EDIT-01 | Open an upcoming meeting with multiple groups/students. | Loading spinner; groups ordered by `group_no`; each group shows project, supervisor, time, and students. | P1 | — |
| EDIT-02 | Search `3`, a student name, a reg #, a supervisor, and `group 3`. | Flexible all-word matching returns the expected group(s); no match message is correct. | P2 | — |
| EDIT-03 | Search text that matches nothing. | `No groups match your search.`; drag/reorder unavailable while searching. | P2 | — |
| EDIT-04 | Tap +, fill project/supervisor/student, tap Add. | New group appears at the end with the next slot; expansion state is sensible; no save yet. | P1 | — |
| EDIT-05 | Add two students with the same reg # (case/space variants). | Inline duplicate-reg error; bottom sheet stays open; no group saved. | P1 | — |
| EDIT-06 | Add a reg # already used in another group. | Inline duplicate-reg error; no group saved. | P1 | — |
| EDIT-07 | Edit a group's project/supervisor/student/tech; Save in the sheet. | Card updates; undo is available; save button becomes enabled. | P1 | — |
| EDIT-08 | Delete a middle group; confirm. | Group is removed; later groups move up into earlier time slots; remaining times are consistent. | P2 | — |
| EDIT-09 | Make several changes, tap Undo twice, then Redo once. | State reverts/reapplies in order; undo/redo buttons enable correctly. | P2 | — |
| EDIT-10 | Drag groups to a new order. | Numbers and time labels follow position; save becomes enabled; no key/duplicate errors. | P1 | — |
| EDIT-11 | Change a group, then tap Save changes on a database with only the supplied SQL. | A readable function-not-found error is shown; no false success; data is not silently lost. | P0 | C-01 |
| EDIT-12 | Open the screen and make no changes. | Save changes is disabled; back leaves without a discard prompt. | P2 | — |
| EDIT-13 | Make a change, press Back, then Cancel/Confirm the discard prompt. | Cancel keeps the screen; Confirm discards and returns; no stale route. | P2 | — |
| EDIT-14 | Add groups until the computed slot exceeds 23:59 (for example 23:45 + 15 min). | Slot creation is rejected/warned; no silent wrap to `00:00`. | P2 | M-11 |

## E. Live screen (20)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| LIVE-01 | Open Live with no active meeting. | Header and `No meeting is running`; `Go to Meetings` navigates to Meetings. | P1 | — |
| LIVE-02 | Open Live during an active meeting. | All groups load; fields come from the meeting's schedule; meeting date is shown. | P0 | — |
| LIVE-03 | Inspect order with running/upcoming/done groups. | Running first, upcoming by group number, done at the bottom. | P0 | — |
| LIVE-04 | Cycle All/Running/Upcoming/Done. | Only matching groups show; filter and search combine. | P1 | — |
| LIVE-05 | Search `3` with groups 3, 13, 30 and regs containing 3. | Matches exactly group 3 (and `group 3`), not group 13/30 or regs. | P1 | — |
| LIVE-06 | Search `13` with groups 13 and 130. | Matches exactly group 13. | P1 | — |
| LIVE-07 | Search a 4+ digit reg #/student/project/supervisor/tech fragment. | Matches by substring in the allowed fields. | P1 | — |
| LIVE-08 | Search multiple words, including `group 3`. | Every word must match; results are correctly narrowed. | P2 | — |
| LIVE-09 | Tap a card, then tap it again. | Selection toggles; action buttons show only for the selected non-done/skipped group. | P2 | — |
| LIVE-10 | Expand one card, then expand another. | Only the latest card stays expanded. | P2 | — |
| LIVE-11 | Select an upcoming group; tap Start; Cancel. | No RPC; selection remains; no state change. | P1 | — |
| LIVE-12 | Start an upcoming group; confirm. | Group becomes running, moves to top, is selected, timer ticks; other Start buttons disable. | P0 | — |
| LIVE-13 | While group A runs, try Start on group B. | Start is disabled; no RPC; server would reject a competing start. | P0 | — |
| LIVE-14 | Pause the meeting, then inspect group actions. | Meeting banner shows paused; group Start/End are disabled; timers freeze. | P1 | — |
| LIVE-15 | End the running group; confirm. | Group becomes done, shows stored total, moves down; Home counters update after reload. | P0 | — |
| LIVE-16 | Toggle Pause/Resume from Live. | No confirm dialogs; timers freeze/resume; paused time is excluded; load succeeds. | P1 | — |
| LIVE-17 | Use long project/supervisor/student/tech names and a long meeting title. | Text wraps/expands without horizontal overflow at default scale. | P2 | — |
| LIVE-18 | Load a row with a null project/supervisor/status/time (legacy/test data). | Screen shows a safe placeholder or a readable data error; no type-cast crash. | P1 | M-03 |
| LIVE-19 | Open Search in portrait, short landscape, paused state, and large text. | Header/results remain reachable; no overflow; pull-to-refresh still works. | P2 | M-06 |
| LIVE-20 | Force a load error. | Error is shown with a visible Retry action (or pull-to-refresh is clearly discoverable); recovery works. | P2 | L-09 |

## F. Home / Dashboard (12)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| HOME-01 | Open Home with no active meeting. | Date, `No meeting is running`, short hint, `Go to Meetings`; navigation works. | P1 | — |
| HOME-02 | Open Home during a running meeting. | Date, `Meeting is live`, lime card, Open Live, End/Pause buttons, counters, Up next. | P0 | — |
| HOME-03 | Pause from Home. | `Meeting is paused`; status pill Paused; timers freeze; button becomes Resume. | P1 | — |
| HOME-04 | Start a group, return to Home. | Running group number/project/supervisor/start time and live group timer are shown. | P1 | — |
| HOME-05 | Active meeting with no running group and groups remaining. | `No group running`; `Open Live to start the next group`; Open Live works. | P1 | — |
| HOME-06 | Active meeting with no running group and no remaining groups. | `All groups are finished. You can end the meeting.` | P1 | — |
| HOME-07 | Inspect counters after known Done/Remaining/Total values. | Three white cards show the overview values; numbers scale down rather than overflow. | P1 | — |
| HOME-08 | With many upcoming groups, inspect Up next. | At most three, ascending by group number; each row shows number, project, time · supervisor, Upcoming chip. | P1 | — |
| HOME-09 | Inspect Up next number tiles. | Blue/peach/lilac/yellow pastel backgrounds are present. | P2 | M-09 |
| HOME-10 | Tap See all and Open Live. | Both navigate to Live; no lost busy state. | P2 | — |
| HOME-11 | Test Pause/Resume and End meeting from Home. | Pause/Resume has no dialog; End confirms; success reloads and shows empty state after End. | P1 | — |
| HOME-12 | Force a load error and use a very long meeting/project title. | Error plus Retry; long text wraps without overflow; retry succeeds. | P2 | L-09 |

## G. Time and timer accuracy (10)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| TIME-01 | Unit/device-check `formatClock` at 0, 59, 60, 3599, 3600, 3661. | `00:00`, `00:59`, `01:00`, `59:59`, `1:00:00`, `1:01:01`; negatives clamp to `00:00`. | P2 | — |
| TIME-02 | Check `formatTotal` at 0, 59, 60, 3599, 3600, 4320. | `<1 min`, `<1 min`, `1 min`, `59 min`, `1h 0m`, `1h 12m`. | P2 | — |
| TIME-03 | Call `formatTotal` with a negative value. | Zero-safe label (not `<1 min` for a negative duration). | P3 | L-04 |
| TIME-04 | Check `formatTime` at 00:00, 11:22, 12:00, 23:59 in the device timezone. | `12:00 AM`, `11:22 AM`, `12:00 PM`, `11:59 PM`; uses local time. | P2 | — |
| TIME-05 | Check `formatDate` for a known date and month boundary. | Correct `Tue, 13 Oct 2026` style weekday/month; no off-by-one day from timezone conversion. | P2 | — |
| TIME-06 | Start a group; compare timer with an independent stopwatch for 2 minutes. | Timer advances approximately one second per second; no duplicate speed-up. | P1 | — |
| TIME-07 | Pause/resume several times; compare active total with a stopwatch. | Paused intervals are excluded; frozen timer does not advance; final stored duration is consistent. | P1 | M-08 |
| TIME-08 | Intentionally set the phone clock several minutes wrong; open a screen. | Server-corrected timer shows the right elapsed time after sync. | P1 | — |
| TIME-09 | Add 5 seconds of response delay to `server_now`; reload Live. | Timer does not lag by the full response latency; offset uses a latency-aware estimate. | P2 | M-04 |
| TIME-10 | Kill/reopen while running and while paused; wait, then resume. | Timers recover from persisted timestamps; paused time is not counted; no reset to zero. | P1 | — |

## H. SQL, Supabase and deployment (9)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| SQL-01 | Apply `supabase_meetings_migration.sql` to a fresh staging database (with pre-existing `meeting_schedule` as required). | Meetings table, columns, constraints, view, indexes, and eight documented RPCs exist; no SQL error. | P0 | — |
| SQL-02 | Apply only the main migration; tap Restore. | Restore fails with a clear function-not-found error until `restart_meeting.sql` is also applied. Document the required order. | P0 | D-02 |
| SQL-03 | Inspect deployed functions after applying both files. | `save_meeting_schedule` and `update_schedule` exist with contracts matching Dart, or the Dart features are disabled. | P0 | C-01, C-02 |
| SQL-04 | Inspect `meeting_schedule` RLS/grants as an authenticated user. | Import and all timer RPCs can read/write required rows; `anon` is denied. | P0 | D-01 |
| SQL-05 | Start two meetings concurrently; start two groups concurrently. | The active-meeting unique index and row locks allow only one active meeting and one running group. | P1 | — |
| SQL-06 | Import the same `(title, date)` twice. | Existing date is reported as `already_added`; no duplicate schedule rows. | P1 | — |
| SQL-07 | Exercise the update contract with new/unchanged/locked dates and duplicate regs. | Per-date `updated/added/locked` results match the documented contract; locked dates are not modified; duplicates are resolved deterministically. | P0 | C-02 |
| SQL-08 | Perform 20 pauses of about 1.6 seconds each; end the meeting. | Accumulated pause/total error stays within the accepted rounding tolerance. | P2 | M-08 |
| SQL-09 | Re-run the migration on a populated staging database. | The documented destructive `DELETE` is understood and blocked by the runbook; a verified backup exists. | P1 | D-04 |

## I. Navigation, layout, accessibility and error UX (11)

| ID | Scenario / steps | Expected | Priority | Bug |
|---|---|---|---|---|
| UX-01 | Inspect the login brand text. | `BIIT FYP Meeitngs` is corrected to the approved spelling. | P3 | L-01 |
| UX-02 | Render Login at 320 dp wide and 200% text. | Logo/title row wraps without overflow; fields/button remain reachable. | P2 | M-05 |
| UX-03 | Use the email/password keyboard actions and platform autofill. | Next/Done work; email/password autofill suggestions appear. | P2 | L-10 |
| UX-04 | Render the bottom bar at 320 dp and 200% text. | Home/Live/Meetings/Import labels remain readable without clipping/overflow. | P2 | L-12 |
| UX-05 | Trigger a slow mutation; inspect the bottom bar. | Navigation is visibly disabled or otherwise explains why taps are ignored. | P3 | L-06 |
| UX-06 | Inspect the selected/unselected nav labels and call `Button(foreColor: ...)`. | Requested foreground colour is honoured, or the parameter is removed; labels stay readable. | P3 | L-03 |
| UX-07 | Navigate with TalkBack/screen reader; inspect Button, Filter, edit/delete/expand icons. | Controls announce button role/name; icons have meaningful tooltips/labels. | P2 | L-11 |
| UX-08 | Force a generic non-Postgrest exception (network/library failure). | User sees a short friendly message, not a raw exception/stack/library detail. | P2 | L-02 |
| UX-09 | Test 320 dp portrait, short landscape, tablet width, and keyboard-open states across Home/Live/Meetings/Import/Edit. | No overflow stripes, clipped errors, unreachable actions, or hidden results. | P2 | M-05, M-06, L-12 |
| UX-10 | Test 200% system text on every screen and dialog. | Text wraps/scrolls; buttons and lists remain usable; no fixed-height clipping. | P1 | M-05, M-06, L-12 |
| UX-11 | On Live and Meetings, force an error while the list is short/empty; try to recover. | A visible Retry action or clearly discoverable refresh restores data. | P3 | L-09 |

## Execution checklist

- [ ] Record build/commit, Flutter version, device model/API, text scale, display size, and backend project for every run.
- [ ] Attach screenshots for any layout, overflow, accessibility, or error-message finding.
- [ ] Record network conditions for H-02, M-04, M-07, and M-10.
- [ ] Record stopwatch evidence for TIME-06/TIME-07/TIME-08/TIME-09/TIME-10 and SQL-08.
- [ ] Confirm which SQL files, functions, grants, policies, and Auth sign-up settings exist in the tested project.
- [ ] Do not close C-01/C-02 merely because a manually patched staging database happens to contain undocumented functions; update the repository contracts and re-test.
- [ ] Re-run `flutter analyze` and the replacement automated tests after any fix.
