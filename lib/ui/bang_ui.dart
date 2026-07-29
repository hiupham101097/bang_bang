import 'package:flutter/material.dart';

const bangGold = Color(0xffffc451);
const bangInk = Color(0xff160c08);
const bangPanel = Color(0xff26150e);

class BangPanel extends StatelessWidget {
  const BangPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: bangPanel.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xff80552f)),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 5)),
      ],
    ),
    child: Padding(padding: padding, child: child),
  );
}

class BangStatusPill extends StatelessWidget {
  const BangStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .72)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}
