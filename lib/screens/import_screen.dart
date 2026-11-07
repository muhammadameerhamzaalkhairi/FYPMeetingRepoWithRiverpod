import 'package:livemeet/utils/app_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livemeet/providers/app_providers.dart';
import 'package:livemeet/providers/import_provider.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:livemeet/widgets/confirm_dialog.dart';
import 'package:file_picker/file_picker.dart';

class ImportScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  final ValueChanged<bool> onBusyChanged;

  const ImportScreen({
    super.key,
    required this.onNavigate,
    required this.onBusyChanged,
  });

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _importKey = Object();
  late final ImportController _controller;
  ImportState get _import => ref.read(importProvider(_importKey));
  String get step => _import.step;
  bool get isUploaded => _import.isUploaded;
  String get fileName => _import.fileName;
  bool get isError => _import.isError;
  String get errorText => _import.errorText;
  String get summary => _import.summary;
  String get meetingTitle => _import.meetingTitle;
  String get alreadyAddedText => _import.alreadyAddedText;
  bool get alreadyAdded => _import.alreadyAdded;
  bool get hasExisting => _import.hasExisting;
  bool get canImport => _import.canImport;
  bool get busy => _import.busy;
  List<Map<String, dynamic>> get rows => _import.rows;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(importProvider(_importKey).notifier);
  }

  @override
  void dispose() {
    _controller.cancelPreview();
    super.dispose();
  }

  // Responsive: true on small phones (width < 360 px).
  bool get narrow => MediaQuery.sizeOf(context).width < 360;

  void resetState() => _controller.reset();

  Future<void> pickFile() async {
    if (busy) return;
    _controller.setBusy(true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (!mounted) return;

      // user ne cancel kar diya
      if (file == null) return;

      resetState();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _controller.preview(bytes, file.name);
    } catch (e, stack) {
      final message = AppError.handle(e, stack, action: ErrorAction.preview);
      showImportError(message);
    } finally {
      if (mounted) _controller.setBusy(false);
    }
  }

  void showImportError(String message) {
    if (!mounted) return;
    _controller.showError(message);
  }

  Future<void> confirmImport() async {
    if (!canImport || busy) return;
    _controller.setBusy(true);
    try {
      // Pehle se mojood data update hoga -> pehle confirmation lo
      if (hasExisting) {
        final confirmed = await showConfirmDialog(
          context,
          title: 'Update existing data?',
          message:
              'This file will update the already added meeting data for "$meetingTitle". Groups that already started or finished are kept as they are. Students no longer in the file will be removed from upcoming groups.',
          confirmText: 'Update',
        );
        if (!mounted) return;
        if (!confirmed) return;
      }

      widget.onBusyChanged(true);

      if (hasExisting) {
        final raw = await ref
            .read(meetingServiceProvider)
            .updateSchedule(meetingTitle, rows);
        if (!mounted) return;
        final result = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (result.isEmpty) {
          throw StateError('No import result was returned.');
        }
        if (!result.every(
          (row) => const ['updated', 'added', 'locked'].contains(row['state']),
        )) {
          throw StateError('Invalid schedule update response');
        }
        final updated = result.where((r) => r['state'] == 'updated').length;
        final added = result.where((r) => r['state'] == 'added').length;
        // 'locked' now means the meeting is finished.
        final locked = result.where((r) => r['state'] == 'locked').length;

        if (updated + added == 0) {
          throw const UserMessageException(
            'These meetings are already finished, so they cannot be updated.',
          );
        }

        final parts = <String>[
          if (updated > 0) '$updated meeting(s) updated',
          if (added > 0) '$added meeting(s) added',
          if (locked > 0) '$locked finished meeting(s) not changed',
        ];
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(parts.join(' · '))));
      } else {
        final result = await ref
            .read(meetingServiceProvider)
            .importSchedule(meetingTitle, rows);
        if (!mounted) return;
        if (result.isEmpty) {
          throw StateError('No import result was returned.');
        }
        if (!result.every(
          (item) => item is Map && item['already_added'] is bool,
        )) {
          throw StateError('Invalid schedule import response');
        }
        final added = result
            .where((item) => item['already_added'] != true)
            .length;
        if (added == 0) {
          throw const UserMessageException(
            'These meetings already exist. Choose the file again to review and update the existing schedule.',
          );
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$added meeting(s) added')));
      }

      resetState();
      widget.onBusyChanged(false);
      widget.onNavigate(kMeetings);
    } catch (e, stack) {
      final message = AppError.handle(
        e,
        stack,
        action: ErrorAction.importSchedule,
      );
      showImportError(message);
    } finally {
      widget.onBusyChanged(false);
      if (mounted) _controller.setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(importProvider(_importKey));
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          narrow ? 14 : 18,
          60,
          narrow ? 14 : 18,
          18,
        ),
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(text: step),
                CustomText(
                  text: 'Import schedule',
                  fontSize: narrow ? 30 : 38,
                  fontWeight: FontWeight.w900,
                ),

                const SizedBox(height: 10),

                GestureDetector(
                  onTap: busy ? null : pickFile,
                  child: AnimatedContainer(
                    width: double.infinity,
                    padding: EdgeInsets.all(narrow ? 24 : 48),
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          isUploaded
                              ? Column(
                                  children: [
                                    CustomText(
                                      text: fileName,
                                      fontSize: narrow ? 20 : 24,
                                      fontWeight: FontWeight.bold,
                                      textAlign: TextAlign.center,
                                    ),
                                    CustomText(
                                      text: summary,
                                      textAlign: TextAlign.center,
                                    ),
                                    if (alreadyAddedText.isNotEmpty)
                                      CustomText(
                                        text: alreadyAddedText,
                                        textAlign: TextAlign.center,
                                        color: alreadyAdded ? Colors.red : null,
                                      ),
                                    const CustomText(
                                      text: 'Tap to choose another Excel file',
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                )
                              : const CustomText(
                                  text: 'Tap to upload Excel file',
                                  textAlign: TextAlign.center,
                                ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                isError
                    ? AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 255, 223, 221),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: CustomText(text: errorText, color: Colors.red),
                      )
                    : const SizedBox(),
                const SizedBox(height: 10),
                Button(
                  enabled: canImport && !busy,
                  text: hasExisting ? 'Update existing data' : 'Confirm import',
                  onTap: confirmImport,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
