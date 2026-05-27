import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/file_path_selector.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';

class DuplicationPage extends StatelessWidget {
  const DuplicationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '重复度',
      subtitle: '选择两个 APK 包后，真实解包并执行文件 MD5 重复度对比。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第一步：选择两个 APK 包',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ApkPairSelector(controller: controller),
          const SizedBox(height: 24),
          Text(
            '第二步：检测范围',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const _DuplicationScopePanel(),
          const SizedBox(height: 24),
          Text(
            '第三步：开始对比并查看日志',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _DuplicationActions(controller: controller),
          const SizedBox(height: 18),
          LogOutputPanel(
            logs: controller.duplicationLogs,
            emptyText: '暂无日志，选择两个 APK 后点击开始对比。',
          ),
        ],
      ),
    );
  }
}

class _ApkPairSelector extends StatelessWidget {
  const _ApkPairSelector({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useHorizontalLayout = constraints.maxWidth >= 760;
        final firstSelector = FilePathSelector(
          value: controller.duplicationFirstApkPath,
          onChanged: context
              .read<EngineMenuController>()
              .updateDuplicationFirstApkPath,
          title: '',
          label: 'APK A 路径',
          hint: '/build/app-release-a.apk',
          dropHint: '拖拽第一个 APK 到这里，或点击按钮选择',
          dialogTitle: '选择 APK A',
          allowedExtensions: const ['apk'],
          icon: Icons.android_outlined,
        );
        final secondSelector = FilePathSelector(
          value: controller.duplicationSecondApkPath,
          onChanged: context
              .read<EngineMenuController>()
              .updateDuplicationSecondApkPath,
          title: '',
          label: 'APK B 路径',
          hint: '/build/app-release-b.apk',
          dropHint: '拖拽第二个 APK 到这里，或点击按钮选择',
          dialogTitle: '选择 APK B',
          allowedExtensions: const ['apk'],
          icon: Icons.android_outlined,
        );

        if (useHorizontalLayout) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: firstSelector),
              const SizedBox(width: 16),
              Expanded(child: secondSelector),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [firstSelector, const SizedBox(height: 16), secondSelector],
        );
      },
    );
  }
}

class _DuplicationScopePanel extends StatelessWidget {
  const _DuplicationScopePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6DDE8)),
      ),
      child: const Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ScopeChip(
            icon: Icons.folder_copy_outlined,
            label: '资源文件结构',
            stateLabel: '暂不支持',
          ),
          _ScopeChip(
            icon: Icons.fingerprint_outlined,
            label: '文件 MD5',
            stateLabel: '已支持',
            active: true,
          ),
          _ScopeChip(
            icon: Icons.data_object_outlined,
            label: 'dex 内部形态',
            stateLabel: '暂不支持',
          ),
          _ScopeChip(
            icon: Icons.image_search_outlined,
            label: 'png 内部元素',
            stateLabel: '暂不支持',
          ),
          _ScopeChip(
            icon: Icons.account_tree_outlined,
            label: 'smali / class 特征',
            stateLabel: '暂不支持',
          ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.icon,
    required this.label,
    required this.stateLabel,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String stateLabel;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = active ? colorScheme.primary : const Color(0xFF647084);
    final background = active ? const Color(0xFFEFF6FF) : Colors.white;
    final borderColor = active ? colorScheme.primary : const Color(0xFFD6DDE8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF1F2937) : const Color(0xFF3B4351),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            stateLabel,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicationActions extends StatelessWidget {
  const _DuplicationActions({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    final hasLogs = controller.duplicationLogs.isNotEmpty;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: controller.canExecuteDuplicationCompare
              ? () {
                  context
                      .read<EngineMenuController>()
                      .executeApkDuplicationCompare();
                }
              : null,
          icon: Icon(
            controller.isComparingDuplication
                ? Icons.hourglass_top_outlined
                : Icons.play_arrow_outlined,
          ),
          label: Text(controller.isComparingDuplication ? '对比中' : '开始对比'),
        ),
        OutlinedButton.icon(
          onPressed: hasLogs
              ? context.read<EngineMenuController>().clearDuplicationLogs
              : null,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清空日志'),
        ),
      ],
    );
  }
}
