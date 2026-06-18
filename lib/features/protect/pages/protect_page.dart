import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/file_path_selector.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';

class ProtectPage extends StatelessWidget {
  const ProtectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '加固',
      subtitle: '上传 APK 后注入早启动防护，校验包名、签名证书、包体摘要并检测运行时风险。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilePathSelector(
            value: controller.protectApkPath,
            onChanged: context
                .read<EngineMenuController>()
                .updateProtectApkPath,
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
            '第二步：选择签名配置',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ProtectSigningConfigList(controller: controller),
          const SizedBox(height: 24),
          Text(
            '第三步：输出与执行',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ProtectOutputField(controller: controller),
          const SizedBox(height: 18),
          _HardeningActions(controller: controller),
          const SizedBox(height: 18),
          LogOutputPanel(
            logs: controller.hardeningLogs,
            emptyText: '暂无日志，上传 APK 并选择签名配置后点击执行加固。',
          ),
        ],
      ),
    );
  }
}

class _ProtectSigningConfigList extends StatelessWidget {
  const _ProtectSigningConfigList({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    final configs = controller.androidSigningConfigs;
    if (configs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD6DDE8)),
        ),
        child: const Text(
          '暂无签名配置，请先到“签名”页面添加 keystore、alias 和密码。',
          style: TextStyle(color: Color(0xFF3B4351)),
        ),
      );
    }

    return RadioGroup<String>(
      groupValue: controller.selectedSigningConfigId,
      onChanged: (value) {
        if (value != null) {
          context.read<EngineMenuController>().selectAndroidSigningConfig(
            value,
          );
        }
      },
      child: Column(
        children: configs.map((config) {
          final selected = controller.selectedSigningConfigId == config.id;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFEFF6FF) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFFD6DDE8),
                ),
              ),
              child: RadioListTile<String>(
                value: config.id,
                title: Text(
                  config.keyAlias,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${config.signingScheme.label}\n${config.keystorePath}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ProtectOutputField extends StatefulWidget {
  const _ProtectOutputField({required this.controller});

  final EngineMenuController controller;

  @override
  State<_ProtectOutputField> createState() => _ProtectOutputFieldState();
}

class _ProtectOutputFieldState extends State<_ProtectOutputField> {
  late final TextEditingController _outputController;

  @override
  void initState() {
    super.initState();
    _outputController = TextEditingController(
      text: widget.controller.protectOutputPath,
    );
  }

  @override
  void didUpdateWidget(_ProtectOutputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final outputPath = widget.controller.protectOutputPath;
    if (outputPath != _outputController.text) {
      _outputController.value = TextEditingValue(
        text: outputPath,
        selection: TextSelection.collapsed(offset: outputPath.length),
      );
    }
  }

  @override
  void dispose() {
    _outputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _outputController,
      onChanged: context.read<EngineMenuController>().updateProtectOutputPath,
      decoration: const InputDecoration(
        labelText: '输出 APK 路径',
        hintText: '默认生成在源 APK 目录，文件名追加 _z1guard',
        prefixIcon: Icon(Icons.output_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
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
          onPressed: controller.canExecuteApkHardening
              ? () {
                  context.read<EngineMenuController>().executeApkHardening();
                }
              : null,
          icon: Icon(
            controller.isHardeningApk
                ? Icons.hourglass_top_outlined
                : Icons.security_outlined,
          ),
          label: Text(controller.isHardeningApk ? '加固中' : '执行 APK 加固'),
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
