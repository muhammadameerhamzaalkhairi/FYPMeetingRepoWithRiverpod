import 'package:livemeet/models/meeting.dart';
import 'package:livemeet/services/meeting_service.dart';

Meeting meetingFixture({
  int id = 1,
  String status = 'running',
  int incomplete = 0,
}) => Meeting.fromMap({
  'id': id,
  'title': 'FYP meeting $id',
  'meeting_date': '2026-11-07',
  'status': status,
  'started_at': status == 'upcoming' ? null : '2026-11-07T09:00:00Z',
  'paused_at': status == 'paused' ? '2026-11-07T09:01:00Z' : null,
  'ended_at': status == 'done' ? '2026-11-07T09:02:00Z' : null,
  'paused_seconds': 0,
  'total_seconds': status == 'done' ? 120 : null,
  'groups_total': 2,
  'students_total': 2,
  'groups_done': 0,
  'groups_skipped': 0,
  'groups_remaining': 2,
  'groups_incomplete': incomplete,
});

Map<String, dynamic> rowFixture({
  int group = 1,
  String reg = 'R1',
  String status = 'upcoming',
}) => {
  'id': reg == 'R1' ? 1 : 2,
  'meeting_id': 1,
  'group_no': group,
  'meeting_time': '09:00:00',
  'meeting_date': '2026-11-07',
  'project': 'Project $group',
  'supervisor': 'Supervisor',
  'reg_no': reg,
  'student_name': 'Student $reg',
  'tech': 'Flutter',
  'status': status,
  'started_at': status == 'upcoming' ? null : '2026-11-07T09:00:00Z',
  'paused_at': status == 'paused' ? '2026-11-07T09:01:00Z' : null,
  'paused_seconds': 0,
  'duration_sec': status == 'paused' ? 60 : null,
  'is_present': status != 'upcoming',
};

class FakeMeetingService implements MeetingService {
  List<Map<String, dynamic>>? savedRows;
  String? savedTitle;
  Set<String> existingDates = {};
  Future<Set<String>> Function()? existingDatesLoader;
  List<dynamic> importResult = [
    {'already_added': false},
  ];
  List<dynamic> updateResult = [
    {'state': 'updated'},
  ];
  Meeting? active = meetingFixture();
  List<Meeting> meetings = [meetingFixture()];
  List<Map<String, dynamic>> rows = [
    rowFixture(),
    rowFixture(group: 2, reg: 'R2'),
  ];
  final calls = <String>[];
  Future<Meeting?> Function()? activeLoader;
  Future<List<Meeting>> Function()? meetingsLoader;
  Future<List<Map<String, dynamic>>> Function(int)? rowsLoader;
  Future<void> Function()? pauseHandler;

  @override
  Future<DateTime> fetchServerNow() async {
    calls.add('clock');
    return DateTime.now();
  }

  @override
  Future<Meeting?> fetchActiveMeeting() async {
    calls.add('active');
    return activeLoader == null ? active : await activeLoader!();
  }

  @override
  Future<List<Meeting>> fetchMeetings() async {
    calls.add('meetings');
    return meetingsLoader == null ? meetings : await meetingsLoader!();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRows(int id) async {
    calls.add('rows:$id');
    return rowsLoader == null
        ? rows.map((r) => Map<String, dynamic>.from(r)).toList()
        : await rowsLoader!(id);
  }

  void _meetingStatus(int id, String status) {
    final updated = meetingFixture(id: id, status: status);
    meetings = [
      for (final m in meetings)
        if (m.id == id) updated else m,
    ];
    active = updated.isActive ? updated : null;
  }

  @override
  Future<void> startMeeting(int id) async {
    calls.add('start:$id');
    _meetingStatus(id, 'running');
  }

  @override
  Future<void> pauseMeeting(int id) async {
    calls.add('pause:$id');
    await pauseHandler?.call();
    _meetingStatus(id, 'paused');
  }

  @override
  Future<void> resumeMeeting(int id) async {
    calls.add('resume:$id');
    _meetingStatus(id, 'running');
  }

  @override
  Future<void> endMeeting(int id) async {
    calls.add('end:$id');
    _meetingStatus(id, 'done');
  }

  @override
  Future<void> restartMeeting(int id) async {
    calls.add('restart:$id');
    _meetingStatus(id, 'running');
  }

  @override
  Future<void> deleteMeeting(int id) async {
    calls.add('delete:$id');
    meetings = meetings.where((m) => m.id != id).toList();
  }

  void _groupStatus(int group, String status) {
    rows = [
      for (final r in rows)
        if (r['group_no'] == group)
          {
            ...r,
            'status': status,
            'started_at': r['started_at'] ?? '2026-11-07T09:00:00Z',
            'duration_sec': status == 'paused' ? 60 : null,
          }
        else
          r,
    ];
  }

  @override
  Future<void> startGroup(
    int meetingId,
    int groupNo, {
    List<String>? present,
  }) async {
    calls.add('group-start:$meetingId:$groupNo:${present?.join(',')}');
    _groupStatus(groupNo, 'running');
    await setAttendance(
      meetingId,
      groupNo,
      present ??
          rows
              .where((r) => r['group_no'] == groupNo)
              .map((r) => r['reg_no'] as String)
              .toList(),
    );
  }

  @override
  Future<void> pauseGroup(int meetingId, int groupNo) async {
    calls.add('group-pause:$meetingId:$groupNo');
    _groupStatus(groupNo, 'paused');
  }

  @override
  Future<void> resumeGroup(int meetingId, int groupNo) async {
    calls.add('group-resume:$meetingId:$groupNo');
    _groupStatus(groupNo, 'running');
  }

  @override
  Future<void> endGroup(int meetingId, int groupNo) async {
    calls.add('group-end:$meetingId:$groupNo');
    _groupStatus(groupNo, 'done');
  }

  @override
  Future<int> setAttendance(
    int meetingId,
    int groupNo,
    List<String> present,
  ) async {
    calls.add('attendance:$meetingId:$groupNo:${present.join(',')}');
    var changed = 0;
    rows = [
      for (final r in rows)
        if (r['group_no'] == groupNo)
          {
            ...r,
            'is_present': (() {
              final value = present.contains(r['reg_no']);
              if (value != r['is_present']) changed++;
              return value;
            })(),
          }
        else
          r,
    ];
    return changed;
  }

  @override
  Future<Set<String>> fetchExistingDates(
    String title,
    List<String> dates,
  ) async {
    calls.add('dates:$title');
    return existingDatesLoader == null
        ? existingDates
        : await existingDatesLoader!();
  }

  @override
  Future<List<dynamic>> importSchedule(
    String title,
    List<Map<String, dynamic>> rows,
  ) async {
    calls.add('import:$title');
    savedTitle = title;
    savedRows = rows;
    return importResult;
  }

  @override
  Future<List<dynamic>> updateSchedule(
    String title,
    List<Map<String, dynamic>> rows,
  ) async {
    calls.add('update:$title');
    savedTitle = title;
    savedRows = rows;
    return updateResult;
  }

  @override
  Future<Map<String, dynamic>> saveSchedule(
    int meetingId,
    List<Map<String, dynamic>> rows,
  ) async {
    calls.add('save:$meetingId');
    savedRows = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    return {'updated': rows.length, 'added': 0, 'removed': 0};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
