import 'package:flutter/material.dart';

class SectionPanel extends StatelessWidget {
  const SectionPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE3E7EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Text(
            //   title,
            //   style: Theme.of(
            //     context,
            //   ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            // ),
            // const SizedBox(height: 6),
            // Text(
            //   subtitle,
            //   style: Theme.of(
            //     context,
            //   ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF647084)),
            // ),
            // const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}
