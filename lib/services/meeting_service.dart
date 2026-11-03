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

  static Future<void> startGroup(int meetingId, int groupNo) async {
    await _db.rpc(
      'group_start',
      params: {'p_meeting': meetingId, 'p_group': groupNo},
    );
  }

  static Future<void> endGroup(int meetingId, int groupNo) async {
    await _db.rpc(
      'group_end',
      params: {'p_meeting': meetingId, 'p_group': groupNo},
    );
  }




    static Future<void> saveSchedule(
    int meetingId,
    List<Map<String, dynamic>> rows,
  ) async {
    await _db.rpc(
      'save_meeting_schedule',
      params: {'p_id': meetingId, 'p_rows': rows},
    );
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
