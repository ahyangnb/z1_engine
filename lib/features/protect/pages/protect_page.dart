import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/core/models/code_transparency_signing_config.dart';
import 'package:z1_engine/core/models/hardening_artifact.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/features/protect/controllers/hardening_controller.dart';
import 'package:z1_engine/shared/widgets/file_path_selector.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/project_path_selector.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';

class ProtectPage extends StatelessWidget {
  const ProtectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final hardening = context.watch<HardeningController>();
    final engine = context.watch<EngineMenuController>();
    final needsUploadSigning =
        hardening.selectedType == HardeningArtifactType.apk ||
        hardening.selectedType == HardeningArtifactType.aab ||
        (hardening.selectedType == HardeningArtifactType.androidProject &&
            hardening.enableAabProjectGuard);
    final needsTransparency =
        hardening.selectedType == HardeningArtifactType.aab ||
        (hardening.selectedType == HardeningArtifactType.androidProject &&
            hardening.enableAabProjectGuard);

    return SectionPanel(
      title: '加固',
      subtitle: _subtitle(hardening.selectedType),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HardeningTypeSelector(controller: hardening),
          const SizedBox(height: 24),
          if (hardening.selectedType == HardeningArtifactType.androidProject)
            _ProjectInput(controller: hardening)
          else
            _ArtifactInput(controller: hardening),
          if (needsUploadSigning) ...[
            const SizedBox(height: 24),
            _SectionTitle(
              text: hardening.selectedType == HardeningArtifactType.aab
                  ? '第二步：选择 upload 签名'
                  : '第二步：选择签名配置',
            ),
            const SizedBox(height: 12),
            _UploadSigningConfigList(controller: engine),
          ],
          if (needsTransparency) ...[
            const SizedBox(height: 24),
            _TransparencyConfigSection(controller: hardening),
          ],
          const SizedBox(height: 24),
          if (hardening.selectedType == HardeningArtifactType.sharedObject)
            _SoOptions(controller: hardening),
          if (hardening.selectedType == HardeningArtifactType.androidProject)
            _ProjectOptions(controller: hardening),
          if (hardening.selectedType != HardeningArtifactType.androidProject)
            _OutputField(controller: hardening),
          const SizedBox(height: 18),
          _HardeningActions(
            hardening: hardening,
            uploadSigningConfig: engine.selectedSigningConfig,
          ),
          const SizedBox(height: 18),
          LogOutputPanel(
            logs: hardening.logs,
            emptyText: '暂无日志，完成当前产物配置后执行加固。',
          ),
        ],
      ),
    );
  }

  String _subtitle(HardeningArtifactType type) {
    return switch (type) {
      HardeningArtifactType.apk => 'APK 运行时 Guard：DEX 壳、签名与包体完整性、存储和 Hook 检测。',
      HardeningArtifactType.aab =>
        'AAB 发布保护：代码透明、JAR 签名、bundletool 与生成 APK 验证。',
      HardeningArtifactType.sharedObject =>
        'SO 兼容加固：保存调试符号、strip 调试段并核对 ELF ABI 与导出。',
      HardeningArtifactType.androidProject => '源码工程：持久接入 AAB Guard 与原生编译期安全选项。',
    };
  }
}

class _HardeningTypeSelector extends StatelessWidget {
  const _HardeningTypeSelector({required this.controller});

  final HardeningController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(text: '加固类型'),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<HardeningArtifactType>(
            segments: const [
              ButtonSegment(
                value: HardeningArtifactType.apk,
                label: Text('APK'),
                icon: Icon(Icons.android_outlined),
              ),
              ButtonSegment(
                value: HardeningArtifactType.aab,
                label: Text('AAB'),
                icon: Icon(Icons.inventory_2_outlined),
              ),
              ButtonSegment(
                value: HardeningArtifactType.sharedObject,
                label: Text('SO'),
                icon: Icon(Icons.memory_outlined),
              ),
              ButtonSegment(
                value: HardeningArtifactType.androidProject,
                label: Text('源码工程'),
                icon: Icon(Icons.account_tree_outlined),
              ),
            ],
            selected: {controller.selectedType},
            showSelectedIcon: false,
            onSelectionChanged: (values) {
              controller.selectType(values.first);
            },
          ),
        ),
      ],
    );
  }
}

class _ArtifactInput extends StatelessWidget {
  const _ArtifactInput({required this.controller});

  final HardeningController controller;

  @override
  Widget build(BuildContext context) {
    final type = controller.selectedType;
    final extension = type.extension.substring(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilePathSelector(
          value: controller.artifactPath,
          onChanged: controller.updateArtifactPath,
          title: '第一步：选择 ${type.label} 文件',
          label: '${type.label} 路径',
          hint: '/build/output${type.extension}',
          dropHint: '拖拽 ${type.label} 文件到这里，或点击按钮选择',
          dialogTitle: '选择 ${type.label}',
          allowedExtensions: [extension],
          icon: switch (type) {
            HardeningArtifactType.sharedObject => Icons.memory_outlined,
            HardeningArtifactType.aab => Icons.inventory_2_outlined,
            _ => Icons.android_outlined,
          },
        ),
        if (controller.artifactInspectionMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.artifactInspectionMessage!,
            style: TextStyle(
              color: controller.artifactInspectionMessage!.startsWith('已识别')
                  ? const Color(0xFF137A46)
                  : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProjectInput extends StatelessWidget {
  const _ProjectInput({required this.controller});

  final HardeningController controller;

  @override
  Widget build(BuildContext context) {
    return ProjectPathSelector(
      value: controller.projectPath,
      onChanged: controller.updateProjectPath,
      title: '第一步：选择 Android 或 Flutter 工程',
    );
  }
}

class _UploadSigningConfigList extends StatelessWidget {
  const _UploadSigningConfigList({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    final configs = controller.androidSigningConfigs;
    if (configs.isEmpty) {
      return const _EmptyConfig(text: '暂无签名配置，请先到“签名”页面添加 upload keystore。');
    }
    return RadioGroup<String>(
      groupValue: controller.selectedSigningConfigId,
      onChanged: (value) {
        if (value != null) {
          controller.selectAndroidSigningConfig(value);
        }
      },
      child: Column(
        children: configs.map((config) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RadioListTile<String>(
              value: config.id,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFD6DDE8)),
              ),
              title: Text(
                config.keyAlias,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                config.keystorePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TransparencyConfigSection extends StatelessWidget {
  const _TransparencyConfigSection({required this.controller});

  final HardeningController controller;

  Future<void> _openDialog(
    BuildContext context, [
    CodeTransparencySigningConfig? config,
  ]) {
    return showDialog<void>(
      context: context,
      builder: (_) => _TransparencyConfigDialog(config: config),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle(text: '第三步：代码透明签名')),
            FilledButton.icon(
              onPressed: () => _openDialog(context),
              icon: const Icon(Icons.add_outlined),
              label: const Text('添加'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (controller.transparencyConfigs.isEmpty)
          const _EmptyConfig(text: '暂无独立代码透明密钥，请添加后继续。')
        else
          RadioGroup<String>(
            groupValue: controller.selectedTransparencyConfigId,
            onChanged: (value) {
              if (value != null) {
                controller.selectTransparencyConfig(value);
              }
            },
            child: Column(
              children: controller.transparencyConfigs.map((config) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RadioListTile<String>(
                    value: config.id,
                    contentPadding: const EdgeInsets.only(left: 12, right: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFFD6DDE8)),
                    ),
                    title: Text(
                      config.keyAlias,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      config.keystorePath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    secondary: MenuAnchor(
                      builder: (context, menuController, child) {
                        return IconButton(
                          tooltip: '代码透明签名操作',
                          onPressed: () => menuController.isOpen
                              ? menuController.close()
                              : menuController.open(),
                          icon: const Icon(Icons.more_vert),
                        );
                      },
                      menuChildren: [
                        MenuItemButton(
                          leadingIcon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openDialog(context, config),
                          child: const Text('编辑'),
                        ),
                        MenuItemButton(
                          leadingIcon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            controller.removeTransparencyConfig(config.id);
                          },
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _TransparencyConfigDialog extends StatefulWidget {
  const _TransparencyConfigDialog({this.config});

  final CodeTransparencySigningConfig? config;

  @override
  State<_TransparencyConfigDialog> createState() =>
      _TransparencyConfigDialogState();
}

class _TransparencyConfigDialogState extends State<_TransparencyConfigDialog> {
  late String _keystorePath;
  late final TextEditingController _aliasController;
  late final TextEditingController _storePasswordController;
  late final TextEditingController _keyPasswordController;
  late final TextEditingController _remarkController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _keystorePath = config?.keystorePath ?? '';
    _aliasController = TextEditingController(text: config?.keyAlias ?? '');
    _storePasswordController = TextEditingController(
      text: config?.storePassword ?? '',
    );
    _keyPasswordController = TextEditingController(
      text: config?.keyPassword ?? '',
    );
    _remarkController = TextEditingController(text: config?.remark ?? '');
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _storePasswordController.dispose();
    _keyPasswordController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _chooseKeystore() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      dialogTitle: '选择代码透明 keystore',
      type: FileType.custom,
      allowedExtensions: const ['jks', 'keystore', 'p12', 'pfx'],
    );
    final path = result?.files.single.path;
    if (path != null && mounted) {
      setState(() => _keystorePath = path);
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await context
        .read<HardeningController>()
        .saveTransparencyConfig(
          id: widget.config?.id,
          keystorePath: _keystorePath,
          keyAlias: _aliasController.text,
          storePassword: _storePasswordController.text,
          keyPassword: _keyPasswordController.text,
          remark: _remarkController.text,
        );
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.config == null ? '添加代码透明签名' : '编辑代码透明签名'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                readOnly: true,
                controller: TextEditingController(text: _keystorePath),
                decoration: InputDecoration(
                  labelText: 'keystore',
                  suffixIcon: IconButton(
                    tooltip: '选择 keystore',
                    onPressed: _chooseKeystore,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _aliasController,
                decoration: const InputDecoration(labelText: 'alias'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _storePasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'keystore 密码'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'key 密码'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remarkController,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '校验中' : '保存'),
        ),
      ],
    );
  }
}

class _SoOptions extends StatelessWidget {
  const _SoOptions({required this.controller});

  final HardeningController controller;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: controller.saveDebugSymbols,
      onChanged: controller.setSaveDebugSymbols,
      title: const Text(
        '保存独立调试符号',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('输出同名 .dbg；加固 SO 只去除调试段，不删除动态导出符号。'),
    );
  }
}

class _ProjectOptions extends StatelessWidget {
  const _ProjectOptions({required this.controller});

  final HardeningController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(text: '工程加固选项'),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: controller.enableAabProjectGuard,
          onChanged: (value) {
            controller.setEnableAabProjectGuard(value ?? false);
          },
          title: const Text(
            'AAB 运行时 Guard',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            '注入 Application/Provider，base dex 加密，构建后输出 _z1guard.aab。',
          ),
        ),
        if (controller.enableAabProjectGuard) ...[
          const SizedBox(height: 8),
          TextField(
            minLines: 2,
            maxLines: 4,
            onChanged: controller.updatePlayCertificateText,
            decoration: const InputDecoration(
              labelText: 'Play App Signing SHA-256',
              hintText: '支持多个指纹，用换行、逗号或分号分隔',
              prefixIcon: Icon(Icons.verified_user_outlined),
              border: OutlineInputBorder(),
            ),
          ),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: controller.enableNativeBuildHardening,
          onChanged: (value) {
            controller.setEnableNativeBuildHardening(value ?? false);
          },
          title: const Text(
            'SO 编译期基础防护',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'RELRO/NOW、NX、stack protector、FORTIFY 和 section GC。',
          ),
        ),
        if (controller.enableNativeBuildHardening) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: controller.enableCfi,
            onChanged: controller.setEnableCfi,
            title: const Text('CFI + ThinLTO'),
            subtitle: const Text('默认关闭；仅在全量原生依赖兼容时开启。'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: controller.enableHiddenVisibility,
            onChanged: controller.setEnableHiddenVisibility,
            title: const Text('全局隐藏符号'),
            subtitle: const Text('默认关闭；开启前需为 JNI/dlsym API 添加显式导出。'),
          ),
        ],
      ],
    );
  }
}

class _OutputField extends StatefulWidget {
  const _OutputField({required this.controller});

  final HardeningController controller;

  @override
  State<_OutputField> createState() => _OutputFieldState();
}

class _OutputFieldState extends State<_OutputField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.controller.outputPath);
  }

  @override
  void didUpdateWidget(_OutputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.controller.outputPath) {
      _controller.value = TextEditingValue(
        text: widget.controller.outputPath,
        selection: TextSelection.collapsed(
          offset: widget.controller.outputPath.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.controller.updateOutputPath,
      decoration: InputDecoration(
        labelText: '输出 ${widget.controller.selectedType.label} 路径',
        prefixIcon: const Icon(Icons.output_outlined),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _HardeningActions extends StatelessWidget {
  const _HardeningActions({
    required this.hardening,
    required this.uploadSigningConfig,
  });

  final HardeningController hardening;
  final AndroidSigningConfig? uploadSigningConfig;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: hardening.canExecuteWith(uploadSigningConfig)
              ? () => hardening.execute(uploadSigningConfig)
              : null,
          icon: Icon(
            hardening.isRunning
                ? Icons.hourglass_top_outlined
                : Icons.security_outlined,
          ),
          label: Text(hardening.isRunning ? '处理中' : '执行加固'),
        ),
        if (hardening.selectedType == HardeningArtifactType.androidProject)
          OutlinedButton.icon(
            onPressed: hardening.isRunning
                ? null
                : hardening.removeProjectGuard,
            icon: const Icon(Icons.settings_backup_restore_outlined),
            label: const Text('移除 AAB Guard'),
          ),
        OutlinedButton.icon(
          onPressed: hardening.logs.isEmpty ? null : hardening.clearLogs,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清空日志'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _EmptyConfig extends StatelessWidget {
  const _EmptyConfig({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6DDE8)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF3B4351))),
    );
  }
}
