import 'package:flutter/material.dart';
import '../theme.dart';

/// Editable monospaced TextField for the coding round.
class CodeEditorField extends StatelessWidget {
  final TextEditingController controller;
  final String? placeholder;

  const CodeEditorField({super.key, required this.controller, this.placeholder});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: null,
      minLines: 15,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: BwbTheme.text,
        height: 1.5,
      ),
      decoration: InputDecoration(
        hintText: placeholder ?? 'Write your code here...',
        hintStyle: const TextStyle(fontFamily: 'monospace', color: BwbTheme.muted),
        border: const OutlineInputBorder(
          borderSide: BorderSide(color: BwbTheme.border),
          borderRadius: BorderRadius.zero,
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: BwbTheme.border),
          borderRadius: BorderRadius.zero,
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: BwbTheme.border, width: 2),
          borderRadius: BorderRadius.zero,
        ),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
        contentPadding: const EdgeInsets.all(12),
      ),
    );
  }
}
