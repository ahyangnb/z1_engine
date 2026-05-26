import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/features/package/widgets/package_form.dart';
import 'package:z1_engine/shared/widgets/project_path_selector.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';
import 'package:z1_engine/shared/widgets/target_tabs.dart';

class PackagePage extends StatelessWidget {
  const PackagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '出新包',
      subtitle: '选择平台后填写基础出包信息，当前仅展示界面形式。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProjectPathSelector(
            value: controller.packageProjectPath,
            onChanged: context
                .read<EngineMenuController>()
                .updatePackageProjectPath,
          ),
          const SizedBox(height: 24),
          Text(
            '第二步：选择出包类型',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TargetTabs(
            selected: controller.selectedPackageTarget,
            androidLabel: 'android出新包',
            flutterLabel: 'flutter出新包',
            onSelected: context
                .read<EngineMenuController>()
                .selectPackageTarget,
          ),
          const SizedBox(height: 24),
          Text(
            '第三步：出新包配置',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          PackageForm(
            target: controller.selectedPackageTarget,
            canSubmit: controller.hasPackageProjectPath,
          ),
        ],
      ),
    );
  }
}
