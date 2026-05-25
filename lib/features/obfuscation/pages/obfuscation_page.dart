import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/core/models/obfuscation_config.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/checkbox_grid.dart';
import 'package:z1_engine/shared/widgets/contact_banner.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';
import 'package:z1_engine/shared/widgets/target_tabs.dart';

class ObfuscationPage extends StatelessWidget {
  const ObfuscationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '混淆',
      subtitle: '选择平台后配置混淆项，当前仅展示界面形式。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TargetTabs(
            selected: controller.selectedObfuscationTarget,
            androidLabel: 'android混淆',
            flutterLabel: 'flutter混淆',
            onSelected: context
                .read<EngineMenuController>()
                .selectObfuscationTarget,
          ),
          const SizedBox(height: 24),
          Text(
            '混淆配置',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          CheckboxGrid(
            options: obfuscationConfigOptions,
            selectedOptions: controller.selectedObfuscationConfig,
            onChanged: context
                .read<EngineMenuController>()
                .toggleObfuscationOption,
          ),
          const SizedBox(height: 22),
          const ContactBanner(text: '定制开发请联系我们'),
          const SizedBox(height: 24),
          _ObfuscationActions(controller: controller),
          const SizedBox(height: 18),
          LogOutputPanel(logs: controller.obfuscationLogs),
        ],
      ),
    );
  }
}

class _ObfuscationActions extends StatelessWidget {
  const _ObfuscationActions({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    final targetLabel = controller.selectedObfuscationTargetLabel;
    final hasLogs = controller.obfuscationLogs.isNotEmpty;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: context.read<EngineMenuController>().executeObfuscation,
          icon: const Icon(Icons.play_arrow_outlined),
          label: Text('执行$targetLabel'),
        ),
        OutlinedButton.icon(
          onPressed: hasLogs
              ? context.read<EngineMenuController>().clearObfuscationLogs
              : null,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清空日志'),
        ),
      ],
    );
  }
}
