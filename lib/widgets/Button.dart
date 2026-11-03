// Preserve the existing widget filename required by the feature spec.
// ignore_for_file: file_names

import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? foreColor;
  final VoidCallback? onTap;
  final bool enabled;
  final double fontSize;
  final double height;
  final FontWeight? fontWeight;

  const Button({
    super.key,
    required this.text,
    this.color,
    this.foreColor,
    this.onTap,
    this.enabled = true,
    this.fontSize = 18,
    this.height = 60,
    this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF111111),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Center(
            // Responsive: text shrinks to fit the button instead of wrapping
            // onto a second line on narrow screens.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: color == null ? Colors.white : Colors.black,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}