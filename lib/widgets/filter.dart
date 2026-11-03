import 'package:flutter/material.dart';

class Filter extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const Filter({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Responsive: slightly smaller text on narrow phones so more chips fit
    // on screen without scrolling.
    final width = MediaQuery.sizeOf(context).width;
    final fontSize = width < 360 ? 14.0 : 16.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF111111) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Center(
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF111111),
              fontSize: fontSize,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}