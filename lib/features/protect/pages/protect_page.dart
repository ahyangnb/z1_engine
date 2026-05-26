import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/project_path_selector.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';

class ProtectPage extends StatelessWidget {
  const ProtectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '加固',
      subtitle: '为 Android/Flutter 项目接入 SO 构建加固配置。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProjectPathSelector(
            value: controller.protectProjectPath,
            onChanged: context
                .read<EngineMenuController>()
                .updateProtectProjectPath,
            title: '第一步：选择项目路径',
          ),
          const SizedBox(height: 24),
          Text(
            '第二步：执行 SO 构建加固',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _HardeningActions(controller: controller),
          const SizedBox(height: 18),
          LogOutputPanel(
            logs: controller.hardeningLogs,
            emptyText: '暂无日志，点击执行后查看 SO 构建加固输出。',
          ),
        ],
      ),
    );
  }
}

class _HardeningActions extends StatelessWidget {
  const _HardeningActions({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    final hasLogs = controller.hardeningLogs.isNotEmpty;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: controller.canApplyAndroidSoHardening
              ? () {
                  context
                      .read<EngineMenuController>()
                      .executeAndroidSoHardening();
                }
              : null,
          icon: Icon(
            controller.isApplyingNativeHardening
                ? Icons.hourglass_top_outlined
                : Icons.security_outlined,
          ),
          label: Text(
            controller.isApplyingNativeHardening ? '加固中' : '执行 SO 加固',
          ),
        ),
        OutlinedButton.icon(
          onPressed: hasLogs
              ? context.read<EngineMenuController>().clearHardeningLogs
              : null,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清空日志'),
        ),
      ],
    );
  }
}
