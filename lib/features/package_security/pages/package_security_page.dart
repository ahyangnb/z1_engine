import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/file_path_selector.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';

class PackageSecurityPage extends StatelessWidget {
  const PackageSecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '包安全检测',
      subtitle: '上传 APK 后执行包体安全检测。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilePathSelector(
            value: controller.packageSecurityApkPath,
            onChanged: context
                .read<EngineMenuController>()
                .updatePackageSecurityApkPath,
            title: '第一步：上传 APK',
            label: 'APK 路径',
            hint: '/build/app-release.apk',
            dropHint: '仅支持拖拽 APK 文件到这里，或点击按钮选择 APK',
            dialogTitle: '选择 APK',
            allowedExtensions: const ['apk'],
            icon: Icons.android_outlined,
          ),
          const SizedBox(height: 24),
          Text(
            '第二步：开始检测',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _PackageSecurityActions(controller: controller),
          const SizedBox(height: 18),
          LogOutputPanel(
            logs: controller.packageSecurityLogs,
            emptyText: '暂无日志，上传 APK 后点击开始检测。',
          ),
        ],
      ),
    );
  }
}

class _PackageSecurityActions extends StatelessWidget {
  const _PackageSecurityActions({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    final hasLogs = controller.packageSecurityLogs.isNotEmpty;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: controller.canExecutePackageSecurityCheck
              ? () {
                  context
                      .read<EngineMenuController>()
                      .executePackageSecurityCheck();
                }
              : null,
          icon: Icon(
            controller.isCheckingPackageSecurity
                ? Icons.hourglass_top_outlined
                : Icons.health_and_safety_outlined,
          ),
          label: Text(controller.isCheckingPackageSecurity ? '检测中' : '开始检测'),
        ),
        OutlinedButton.icon(
          onPressed: hasLogs
              ? context.read<EngineMenuController>().clearPackageSecurityLogs
              : null,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清空日志'),
        ),
      ],
    );
  }
}
