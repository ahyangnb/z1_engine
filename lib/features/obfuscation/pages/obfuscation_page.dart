import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/core/models/obfuscation_config.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/checkbox_grid.dart';
import 'package:z1_engine/shared/widgets/contact_banner.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/project_path_selector.dart';
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
          ProjectPathSelector(
            value: controller.obfuscationProjectPath,
            onChanged: context
                .read<EngineMenuController>()
                .updateObfuscationProjectPath,
          ),
          const SizedBox(height: 24),
          Text(
            '第二步：选择混淆类型',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
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
            '第三步：混淆配置',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          CheckboxGrid(
            options: [
              ...obfuscationConfigOptions,
              if (controller.isVipServiceActive) ...vipObfuscationConfigOptions,
            ],
            selectedOptions: controller.selectedObfuscationConfig,
            onChanged: context
                .read<EngineMenuController>()
                .toggleObfuscationOption,
          ),
          if (!controller.isVipServiceActive) ...[
            const SizedBox(height: 12),
            const _VipObfuscationBanner(),
          ],
          const SizedBox(height: 22),
          const ContactBanner(text: '定制开发请联系我们'),
          const SizedBox(height: 24),
          Text(
            '第四步：执行并查看日志',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ObfuscationActions(controller: controller),
          const SizedBox(height: 18),
          LogOutputPanel(logs: controller.obfuscationLogs),
        ],
      ),
    );
  }
}

class _VipObfuscationBanner extends StatelessWidget {
  const _VipObfuscationBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: context.read<EngineMenuController>().openVipServicePage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF8D36A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1B8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.workspace_premium_outlined,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VIP 增值混淆参数',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '解锁控制流平坦化、调用链重排、反调试探针、重复度扰动等更多参数，防重复度更高。',
                    style: TextStyle(color: Color(0xFF647084), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_outlined, color: Color(0xFF7A4A00)),
          ],
        ),
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
          onPressed: controller.hasObfuscationProjectPath
              ? context.read<EngineMenuController>().executeObfuscation
              : null,
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
