import 'package:flutter/material.dart';
import '../theme.dart';

/// Read-only monospaced block for displaying code.
class CodeBlockView extends StatelessWidget {
  final String code;

  const CodeBlockView({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        border: Border.all(color: BwbTheme.border),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          code,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: BwbTheme.text,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
