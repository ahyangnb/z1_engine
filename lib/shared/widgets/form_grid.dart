import 'package:flutter/material.dart';

class FormGrid extends StatelessWidget {
  const FormGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: children.map((child) {
            return SizedBox(width: width, child: child);
          }).toList(),
        );
      },
    );
  }
}
