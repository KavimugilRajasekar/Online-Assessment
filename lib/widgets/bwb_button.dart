import 'package:flutter/material.dart';
import '../theme.dart';

class BwbButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color? borderColor;

  const BwbButton({
    super.key,
    required this.label,
    this.onPressed,
    this.filled = true,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return ElevatedButton(
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: borderColor ?? BwbTheme.border),
      ),
      child: Text(label),
    );
  }
}
