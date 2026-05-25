import 'package:flutter/material.dart';
import 'package:z1_engine/core/models/main_menu.dart';

class TopMenuBar extends StatelessWidget {
  const TopMenuBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final MainMenu selected;
  final ValueChanged<MainMenu> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: MainMenu.values.map((menu) {
            final isSelected = menu == selected;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: menu.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(menu),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : const Color(0xFFE3E7EF),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          menu.icon,
                          size: 18,
                          color: isSelected
                              ? colorScheme.primary
                              : const Color(0xFF5F6673),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          menu.label,
                          style: TextStyle(
                            color: isSelected
                                ? colorScheme.primary
                                : const Color(0xFF242A35),
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
