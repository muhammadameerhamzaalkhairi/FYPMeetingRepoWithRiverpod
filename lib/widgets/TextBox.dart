// Preserve the existing widget filename required by the feature spec.
// ignore_for_file: file_names

import 'package:flutter/material.dart';

class TextBox extends StatelessWidget {
  final String? hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;

  const TextBox({
    super.key,
    this.hintText,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    // Responsive: slightly tighter padding and font on narrow phones so
    // hints, typed text and the suffix icon don't get squeezed.
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(fontSize: narrow ? 14 : 16),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(fontSize: narrow ? 14 : 16),
        suffixIcon: suffixIcon,
        fillColor: Colors.white,
        filled: true,
        isDense: narrow,
        contentPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 14 : 16,
          vertical: narrow ? 14 : 16,
        ),
        errorMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(50)),
      ),
    );
  }
}