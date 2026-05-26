import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/file_path_selector.dart';
import 'package:z1_engine/shared/widgets/form_grid.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';

class SignPage extends StatelessWidget {
  const SignPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '签名',
      subtitle: '管理 Android 签名配置，选择 APK 后执行 zipalign + apksigner 签名命令。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SigningConfigHeader(),
          const SizedBox(height: 12),
          _SigningConfigList(controller: controller),
          const SizedBox(height: 24),
          FilePathSelector(
            value: controller.signingApkPath,
            onChanged: context
                .read<EngineMenuController>()
                .updateSigningApkPath,
            title: '第二步：选择 APK',
            label: 'APK 路径',
            hint: '/build/app-release.apk',
            dropHint: '拖拽 APK 到这里，或在上方手动输入/点击按钮选择',
            dialogTitle: '选择 APK',
            allowedExtensions: const ['apk'],
            icon: Icons.android_outlined,
          ),
          const SizedBox(height: 24),
          Text(
            '第三步：输出与执行',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SigningOutputAndCommand(controller: controller),
          const SizedBox(height: 18),
          _SigningActions(controller: controller),
          const SizedBox(height: 18),
          LogOutputPanel(
            logs: controller.signingLogs,
            emptyText: '暂无日志，点击执行签名后查看输出。',
          ),
        ],
      ),
    );
  }
}

class _SigningConfigHeader extends StatelessWidget {
  const _SigningConfigHeader();

  Future<void> _showAddDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _SigningConfigDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '第一步：签名配置',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton.icon(
          onPressed: () => _showAddDialog(context),
          icon: const Icon(Icons.add_outlined),
          label: const Text('添加签名'),
        ),
      ],
    );
  }
}

class _SigningConfigDialog extends StatefulWidget {
  const _SigningConfigDialog();

  @override
  State<_SigningConfigDialog> createState() => _SigningConfigDialogState();
}

class _SigningConfigDialogState extends State<_SigningConfigDialog> {
  final TextEditingController _aliasController = TextEditingController();
  final TextEditingController _storePasswordController =
      TextEditingController();
  final TextEditingController _keyPasswordController = TextEditingController();
  String _keystorePath = '';
  AndroidSigningScheme _signingScheme = AndroidSigningScheme.v2;

  bool get _canAddConfig {
    return _keystorePath.trim().isNotEmpty &&
        _aliasController.text.trim().isNotEmpty &&
        _storePasswordController.text.isNotEmpty;
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _storePasswordController.dispose();
    _keyPasswordController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  void _addConfig() {
    if (!_canAddConfig) {
      return;
    }

    context.read<EngineMenuController>().addAndroidSigningConfig(
      keystorePath: _keystorePath,
      keyAlias: _aliasController.text,
      storePassword: _storePasswordController.text,
      keyPassword: _keyPasswordController.text,
      signingScheme: _signingScheme,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加签名'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormGrid(
                children: [
                  TextField(
                    controller: _aliasController,
                    onChanged: (_) => _refresh(),
                    decoration: const InputDecoration(
                      labelText: '别名 alias',
                      hintText: 'release',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                  ),
                  TextField(
                    controller: _storePasswordController,
                    obscureText: true,
                    onChanged: (_) => _refresh(),
                    decoration: const InputDecoration(
                      labelText: '密钥库密码',
                      hintText: 'store password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                  ),
                  TextField(
                    controller: _keyPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密钥密码',
                      hintText: '为空时默认使用密钥库密码',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SigningSchemePicker(
                value: _signingScheme,
                onChanged: (value) {
                  setState(() => _signingScheme = value);
                },
              ),
              const SizedBox(height: 16),
              FilePathSelector(
                value: _keystorePath,
                onChanged: (value) => setState(() => _keystorePath = value),
                title: '',
                label: '签名文件',
                hint: '/release.jks 或 /release.keystore',
                dropHint: '',
                dialogTitle: '选择签名文件',
                allowedExtensions: const ['jks', 'keystore'],
                icon: Icons.vpn_key_outlined,
                showDropTarget: false,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _canAddConfig ? _addConfig : null,
          icon: const Icon(Icons.add_outlined),
          label: const Text('添加签名'),
        ),
      ],
    );
  }
}

class _SigningSchemePicker extends StatelessWidget {
  const _SigningSchemePicker({required this.value, required this.onChanged});

  final AndroidSigningScheme value;
  final ValueChanged<AndroidSigningScheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('签名方案', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        DropdownButtonFormField<AndroidSigningScheme>(
          initialValue: value,
          isExpanded: true,
          items: AndroidSigningScheme.values.map((scheme) {
            return DropdownMenuItem<AndroidSigningScheme>(
              value: scheme,
              child: Text(scheme.label),
            );
          }).toList(),
          onChanged: (scheme) {
            if (scheme != null) {
              onChanged(scheme);
            }
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SigningConfigList extends StatelessWidget {
  const _SigningConfigList({required this.controller});

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
          '暂无签名配置，请先在上方添加签名文件、别名和密码。',
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
                secondary: IconButton(
                  tooltip: '删除签名配置',
                  onPressed: () => context
                      .read<EngineMenuController>()
                      .removeAndroidSigningConfig(config.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SigningOutputAndCommand extends StatefulWidget {
  const _SigningOutputAndCommand({required this.controller});

  final EngineMenuController controller;

  @override
  State<_SigningOutputAndCommand> createState() =>
      _SigningOutputAndCommandState();
}

class _SigningOutputAndCommandState extends State<_SigningOutputAndCommand> {
  late final TextEditingController _outputController;

  @override
  void initState() {
    super.initState();
    _outputController = TextEditingController(
      text: widget.controller.signingOutputPath,
    );
  }

  @override
  void didUpdateWidget(_SigningOutputAndCommand oldWidget) {
    super.didUpdateWidget(oldWidget);
    final outputPath = widget.controller.signingOutputPath;
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
    final controller = widget.controller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _outputController,
          onChanged: context
              .read<EngineMenuController>()
              .updateSigningOutputPath,
          decoration: const InputDecoration(
            labelText: '输出 APK 路径',
            hintText: '默认生成在源 APK 目录，文件名追加 _signed',
            prefixIcon: Icon(Icons.output_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD6DDE8)),
          ),
          child: SelectableText(
            controller.signingCommandPreview,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _SigningActions extends StatelessWidget {
  const _SigningActions({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    final hasLogs = controller.signingLogs.isNotEmpty;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: controller.canExecuteSigning
              ? () {
                  context.read<EngineMenuController>().executeAndroidSigning();
                }
              : null,
          icon: Icon(
            controller.isSigning
                ? Icons.hourglass_top_outlined
                : Icons.play_arrow_outlined,
          ),
          label: Text(controller.isSigning ? '签名中' : '执行签名'),
        ),
        OutlinedButton.icon(
          onPressed: hasLogs
              ? context.read<EngineMenuController>().clearSigningLogs
              : null,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清空日志'),
        ),
      ],
    );
  }
}
