import 'package:livemeet/models/meeting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MeetingService {
  static final _db = Supabase.instance.client;

  static Future<DateTime> fetchServerNow() async {
    final result = await _db.rpc('server_now');
    return DateTime.parse(result as String);
  }

  static Future<List<Meeting>> fetchMeetings() async {
    final rows = await _db.from('meetings_overview').select();
    return rows.map(Meeting.fromMap).toList();
  }

  static Future<Meeting?> fetchActiveMeeting() async {
    final rows = await _db
        .from('meetings_overview')
        .select()
        .inFilter('status', ['running', 'paused'])
        .limit(1);
    return rows.isEmpty ? null : Meeting.fromMap(rows.first);
  }

  static Future<List<Map<String, dynamic>>> fetchRows(int meetingId) async {
    return await _db
        .from('meeting_schedule')
        .select()
        .eq('meeting_id', meetingId)
        .order('group_no')
        .order('id');
  }

  static Future<Set<String>> fetchExistingDates(
    String title,
    List<String> dates,
  ) async {
    if (dates.isEmpty) return {};
    final rows = await _db
        .from('meetings')
        .select('meeting_date')
        .eq('title', title)
        .inFilter('meeting_date', dates);
    return rows.map((row) => row['meeting_date'] as String).toSet();
  }

  static Future<List<dynamic>> importSchedule(
    String title,
    List<Map<String, dynamic>> rows,
  ) async {
    return await _db.rpc(
          'import_schedule',
          params: {'p_title': title, 'p_rows': rows},
        )
        as List<dynamic>;
  }

  static Future<void> startMeeting(int id) async {
    await _db.rpc('start_meeting', params: {'p_id': id});
  }

  static Future<void> pauseMeeting(int id) async {
    await _db.rpc('pause_meeting', params: {'p_id': id});
  }

  static Future<void> resumeMeeting(int id) async {
    await _db.rpc('resume_meeting', params: {'p_id': id});
  }

  static Future<void> endMeeting(int id) async {
    await _db.rpc('end_meeting', params: {'p_id': id});
  }

  static Future<void> restartMeeting(int id) async {
    await _db.rpc('restart_meeting', params: {'p_id': id});
  }

  /// Starts an upcoming group. [present] = reg numbers of present students;
  /// null means everyone is present (the DB default).
  static Future<void> startGroup(
    int meetingId,
    int groupNo, {
    List<String>? present,
  }) async {
    await _db.rpc(
      'group_start',
      params: {
        'p_meeting': meetingId,
        'p_group': groupNo,
        if (present != null) 'p_present': present,
      },
    );
  }

  static Future<void> pauseGroup(int meetingId, int groupNo) async {
    await _db.rpc(
      'group_pause',
      params: {'p_meeting': meetingId, 'p_group': groupNo},
    );
  }

  static Future<void> resumeGroup(int meetingId, int groupNo) async {
    await _db.rpc(
      'group_resume',
      params: {'p_meeting': meetingId, 'p_group': groupNo},
    );
  }

  static Future<void> endGroup(int meetingId, int groupNo) async {
    await _db.rpc(
      'group_end',
      params: {'p_meeting': meetingId, 'p_group': groupNo},
    );
  }

  /// Old behaviour: only ADDS newly present students (never unmarks).
  /// Kept for compatibility; the Live screen now uses [setAttendance].
  static Future<int> markAttendance(
    int meetingId,
    int groupNo,
    List<String> present,
  ) async {
    final result = await _db.rpc(
      'mark_attendance',
      params: {
        'p_meeting': meetingId,
        'p_group': groupNo,
        'p_present': present,
      },
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// Sets attendance of a started group to EXACTLY [present] (reg numbers):
  /// listed students become present, all others in the group become absent.
  /// Returns how many students changed.
  static Future<int> setAttendance(
    int meetingId,
    int groupNo,
    List<String> present,
  ) async {
    final result = await _db.rpc(
      'set_attendance',
      params: {
        'p_meeting': meetingId,
        'p_group': groupNo,
        'p_present': present,
      },
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// Returns {updated, added, removed}.
  static Future<Map<String, dynamic>> saveSchedule(
    int meetingId,
    List<Map<String, dynamic>> rows,
  ) async {
    final result = await _db.rpc(
      'save_meeting_schedule',
      params: {'p_id': meetingId, 'p_rows': rows},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  static Future<void> deleteMeeting(int id) async {
    final deleted = await _db
        .from('meetings')
        .delete()
        .eq('id', id)
        .eq('status', 'upcoming')
        .select();
    if (deleted.isEmpty) {
      throw Exception('Only upcoming meetings can be deleted');
    }
  }
}