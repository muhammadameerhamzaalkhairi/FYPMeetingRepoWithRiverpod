class Meeting {
  final int id;
  final String title;
  final DateTime meetingDate;
  final String status;
  final DateTime? startedAt, endedAt, pausedAt;
  final int pausedSeconds;
  final int? totalSeconds;
  final int groupsTotal,
      studentsTotal,
      groupsDone,
      groupsSkipped,
      groupsRemaining,
      groupsPaused,
      groupsIncomplete;

  const Meeting({
    required this.id,
    required this.title,
    required this.meetingDate,
    required this.status,
    this.startedAt,
    this.endedAt,
    this.pausedAt,
    required this.pausedSeconds,
    this.totalSeconds,
    required this.groupsTotal,
    required this.studentsTotal,
    required this.groupsDone,
    required this.groupsSkipped,
    required this.groupsRemaining,
    required this.groupsPaused,
    required this.groupsIncomplete,
  });

  bool get isActive => status == 'running' || status == 'paused';

  factory Meeting.fromMap(Map<String, dynamic> m) {
    DateTime? timestamp(String key) =>
        m[key] == null ? null : DateTime.parse(m[key] as String);

    return Meeting(
      id: (m['id'] as num).toInt(),
      title: m['title'] as String,
      meetingDate: DateTime.parse(m['meeting_date'] as String),
      status: m['status'] as String,
      startedAt: timestamp('started_at'),
      endedAt: timestamp('ended_at'),
      pausedAt: timestamp('paused_at'),
      pausedSeconds: (m['paused_seconds'] as num).toInt(),
      totalSeconds: (m['total_seconds'] as num?)?.toInt(),
      groupsTotal: (m['groups_total'] as num).toInt(),
      studentsTotal: (m['students_total'] as num).toInt(),
      groupsDone: (m['groups_done'] as num).toInt(),
      groupsSkipped: (m['groups_skipped'] as num).toInt(),
      groupsRemaining: (m['groups_remaining'] as num).toInt(),
      groupsPaused: (m['groups_paused'] as num?)?.toInt() ?? 0,
      groupsIncomplete: (m['groups_incomplete'] as num?)?.toInt() ?? 0,
    );
  }
}