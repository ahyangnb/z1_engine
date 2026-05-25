import 'package:flutter/material.dart';

class CheckboxGrid extends StatelessWidget {
  const CheckboxGrid({
    super.key,
    required this.options,
    required this.selectedOptions,
    required this.onChanged,
  });

  final List<String> options;
  final Set<String> selectedOptions;
  final void Function(String option, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 4
            : width >= 640
            ? 3
            : width >= 420
            ? 2
            : 1;
        final itemWidth = (width - (columns - 1) * 12) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: options.map((option) {
            final selected = selectedOptions.contains(option);

            return SizedBox(
              width: itemWidth,
              child: CheckboxListTile(
                value: selected,
                onChanged: (value) => onChanged(option, value ?? false),
                title: Text(option),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFFE3E7EF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                tileColor: Colors.white,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.06),
                selected: selected,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
