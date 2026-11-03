import 'package:flutter/material.dart';
import 'package:livemeet/widgets/CustomText.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Confirm',
  String cancelText = 'Cancel',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      // Responsive: keep the dialog from touching the screen edges on narrow
      // phones, and stop it from stretching too wide on desktop/tablet.
      final width = MediaQuery.sizeOf(dialogContext).width;
      final narrow = width < 360;

      return AlertDialog(
        backgroundColor: Colors.white,
        insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 16 : 40,
          vertical: 24,
        ),
        titlePadding: EdgeInsets.fromLTRB(
          narrow ? 18 : 24,
          narrow ? 18 : 24,
          narrow ? 18 : 24,
          0,
        ),
        contentPadding: EdgeInsets.fromLTRB(
          narrow ? 18 : 24,
          16,
          narrow ? 18 : 24,
          8,
        ),
        actionsPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 10 : 16,
          vertical: 8,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: CustomText(text: title, fontWeight: FontWeight.bold),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          // Scrolls if the message is long (e.g. the import update warning)
          // on a small screen instead of overflowing.
          child: SingleChildScrollView(child: CustomText(text: message)),
        ),
        // OverflowBar wraps the buttons onto two lines if they don't fit.
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF111111),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}