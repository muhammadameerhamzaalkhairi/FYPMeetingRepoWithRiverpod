import 'package:livemeet/utils/app_error.dart';
import 'package:livemeet/models/meeting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MeetingService {
  MeetingService(this._db);
  final SupabaseClient _db;

  Future<DateTime> fetchServerNow() async {
    final result = await _db.rpc('server_now');
    return DateTime.parse(result as String);
  }

  Future<List<Meeting>> fetchMeetings() async {
    final rows = await _db.from('meetings_overview').select();
    return rows.map(Meeting.fromMap).toList();
  }

  Future<Meeting?> fetchActiveMeeting() async {
    final rows = await _db
        .from('meetings_overview')
        .select()
        .inFilter('status', ['running', 'paused'])
        .limit(1);
    return rows.isEmpty ? null : Meeting.fromMap(rows.first);
  }

  Future<List<Map<String, dynamic>>> fetchRows(int meetingId) async {
    return await _db
        .from('meeting_schedule')
        .select()
        .eq('meeting_id', meetingId)
        .order('group_no')
        .order('id');
  }

  Future<Set<String>> fetchExistingDates(
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

  Future<List<dynamic>> importSchedule(
    String title,
    List<Map<String, dynamic>> rows,
  ) async {
    return await _db.rpc(
          'import_schedule',
          params: {'p_title': title, 'p_rows': rows},
        )
        as List<dynamic>;
  }

  Future<void> startMeeting(int id) async {
    await _db.rpc('start_meeting', params: {'p_id': id});
  }

  Future<List<dynamic>> updateSchedule(
    String title,
    List<Map<String, dynamic>> rows,
  ) async {
    return await _db.rpc(
          'update_schedule',
          params: {'p_title': title, 'p_rows': rows},
        )
        as List<dynamic>;
  }

  Future<void> pauseMeeting(int id) async {
    await _db.rpc('pause_meeting', params: {'p_id': id});
  }

  Future<void> resumeMeeting(int id) async {
    await _db.rpc('resume_meeting', params: {'p_id': id});
  }

  Future<void> endMeeting(int id) async {
    await _db.rpc('end_meeting', params: {'p_id': id});
  }

  Future<void> restartMeeting(int id) async {
    await _db.rpc('restart_meeting', params: {'p_id': id});
  }

  /// Starts an upcoming group. [present] = reg numbers of present students;
  /// null means everyone is present (the DB default).
  Future<void> startGroup(
    int meetingId,
    int groupNo, {
    List<String>? present,
  }) async {
    await _db.rpc(
      'group_start',
      params: {
        'p_meeting': meetingId,
        'p_group': groupNo,
        'p_present': ?present,
      },
    );
  }

  Future<void> pauseGroup(int meetingId, int groupNo) async {
    await _db.rpc(
      'group_pause',
      params: {'p_meeting': meetingId, 'p_group': groupNo},
    );
  }

  Future<void> resumeGroup(int meetingId, int groupNo) async {
    await _db.rpc(
      'group_resume',
      params: {'p_meeting': meetingId, 'p_group': groupNo},
    );
  }

  Future<void> endGroup(int meetingId, int groupNo) async {
    await _db.rpc(
      'group_end',
      params: {'p_meeting': meetingId, 'p_group': groupNo},
    );
  }

  /// Old behaviour: only ADDS newly present students (never unmarks).
  /// Kept for compatibility; the Live screen now uses [setAttendance].
  Future<int> markAttendance(
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
    if (result is! num) throw StateError('Invalid attendance response');
    return result.toInt();
  }

  /// Sets attendance of a started group to EXACTLY [present] (reg numbers):
  /// listed students become present, all others in the group become absent.
  /// Returns how many students changed.
  Future<int> setAttendance(
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
    if (result is! num) throw StateError('Invalid attendance response');
    return result.toInt();
  }

  /// Returns {updated, added, removed}.
  Future<Map<String, dynamic>> saveSchedule(
    int meetingId,
    List<Map<String, dynamic>> rows,
  ) async {
    final result = await _db.rpc(
      'save_meeting_schedule',
      params: {'p_id': meetingId, 'p_rows': rows},
    );
    if (result is! Map ||
        !['updated', 'added', 'removed'].every((key) => result[key] is num)) {
      throw StateError('Invalid save schedule response');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<void> deleteMeeting(int id) async {
    final deleted = await _db.from('meetings').delete().eq('id', id).inFilter(
      'status',
      ['upcoming', 'done'],
    ).select();
    if (deleted.isEmpty) {
      throw const UserMessageException(
        'This meeting could not be deleted. It may have started or already been removed. Refresh and try again.',
      );
    }
  }
}
