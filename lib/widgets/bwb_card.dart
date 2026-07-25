import 'package:flutter/material.dart';
import '../theme.dart';

class BwbCard extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const BwbCard({
    super.key,
    required this.child,
    this.borderColor = BwbTheme.border,
    this.padding,
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? BwbTheme.surface,
        border: Border.all(color: borderColor, width: 1),
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
    if (onTap != null) {
      return InkWell(onTap: onTap, child: card);
    }
    return card;
  }
}
