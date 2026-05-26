import 'package:flutter/material.dart';

class LogOutputPanel extends StatelessWidget {
  const LogOutputPanel({
    super.key,
    required this.logs,
    this.emptyText = '暂无日志，点击执行混淆后查看输出。',
  });

  final List<String> logs;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final hasLogs = logs.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '日志输出',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF293244)),
          ),
          child: SelectableText(
            hasLogs ? logs.join('\n') : emptyText,
            style: const TextStyle(
              color: Color(0xFFE5E7EB),
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
