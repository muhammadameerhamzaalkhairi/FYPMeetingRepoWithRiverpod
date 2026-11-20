import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/models/notification_message.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/utils/app_error.dart';

Future<bool> showNotificationDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NotificationDialog(),
    ) ??
    false;

class NotificationDialog extends ConsumerStatefulWidget {
  const NotificationDialog({super.key});

  @override
  ConsumerState<NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends ConsumerState<NotificationDialog> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  NotificationPreset? _preset;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(meetingServiceProvider)
          .sendCustomNotification(_message.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, stack) {
      final message = AppError.handle(
        e,
        stack,
        action: ErrorAction.notification,
      );
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send Notification',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Send a general announcement to students.'),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _form,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final presets =
                            DropdownButtonFormField<NotificationPreset>(
                              initialValue: _preset,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Message preset',
                                border: OutlineInputBorder(),
                              ),
                              hint: const Text('Choose a preset'),
                              items: [
                                for (final preset in NotificationPreset.values)
                                  DropdownMenuItem(
                                    value: preset,
                                    child: Text(preset.label),
                                  ),
                              ],
                              onChanged: _sending
                                  ? null
                                  : (preset) {
                                      if (preset == null) return;
                                      setState(() {
                                        _preset = preset;
                                        _message.text = preset.message;
                                      });
                                    },
                            );
                        final message = TextFormField(
                          controller: _message,
                          enabled: !_sending,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: NotificationMessage.maxLength,
                          maxLengthEnforcement: MaxLengthEnforcement.none,
                          validator: NotificationMessage.validate,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Message',
                            alignLabelWithHint: true,
                            hintText: 'Write or edit your announcement',
                            border: const OutlineInputBorder(),
                            counterText: '${_message.text.runes.length}/200',
                            errorMaxLines: 3,
                          ),
                        );
                        if (constraints.maxWidth < 560) {
                          return Column(
                            children: [
                              presets,
                              const SizedBox(height: 16),
                              message,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: presets),
                            const SizedBox(width: 20),
                            Expanded(flex: 2, child: message),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(foregroundColor: Colors.black),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: _sending ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF111111),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
