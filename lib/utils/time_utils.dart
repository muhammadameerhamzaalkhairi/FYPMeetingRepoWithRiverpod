int elapsedSec({
  required DateTime startedAt,
  DateTime? now,
  int pausedSeconds = 0,
  DateTime? frozenAt,
  DateTime? endedAt,
}) {
  final end = endedAt ?? frozenAt ?? now ?? DateTime.now();
  final seconds = end.difference(startedAt).inSeconds - pausedSeconds;
  return seconds < 0 ? 0 : seconds;
}

String formatClock(int sec) {
  final seconds = sec < 0 ? 0 : sec;
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return seconds < 3600
      ? '$minutes:$remainder'
      : '${seconds ~/ 3600}:$minutes:$remainder';
}

String formatTotal(int sec) {
  if (sec < 60) return '<1 min';
  if (sec < 3600) return '${sec ~/ 60} min';
  return '${sec ~/ 3600}h ${sec ~/ 60 % 60}m';
}

String formatTime(DateTime t) {
  final local = t.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

String formatDate(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  // Meeting dates are calendar dates, so preserve their day without conversion.
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
}
