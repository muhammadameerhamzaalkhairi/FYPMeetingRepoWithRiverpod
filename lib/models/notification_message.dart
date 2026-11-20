/// Local operator shortcuts; no database lookup is needed for presets.
class NotificationPreset {
  const NotificationPreset(this.label, this.message);

  final String label;
  final String message;

  static const values = [
    NotificationPreset('Starting soon', 'Meeting is about to start.'),
    NotificationPreset('In 5 minutes', 'Meeting will start in 5 minutes.'),
    NotificationPreset('In 10 minutes', 'Meeting will start in 10 minutes.'),
    NotificationPreset('Please be ready', 'Please be ready for your meeting.'),
    NotificationPreset('Next group', 'The next group is requested to join.'),
    NotificationPreset('Delayed', 'Meeting has been delayed.'),
  ];
}

class NotificationMessage {
  NotificationMessage._();

  static const maxLength = 200;

  static String? validate(String? value) {
    final message = (value ?? '').trim();
    if (message.isEmpty) return 'Please enter a message.';
    // PostgreSQL counts Unicode code points, including multi-code-point emoji.
    if (message.runes.length > maxLength) {
      return 'Keep the message to 200 characters or fewer.';
    }
    return null;
  }
}
