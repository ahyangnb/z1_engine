import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/file_path_selector.dart';
import 'package:z1_engine/shared/widgets/form_grid.dart';
import 'package:z1_engine/shared/widgets/log_output_panel.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';

class ChannelPackagePage extends StatelessWidget {
  const ChannelPackagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '渠道包',
      subtitle: '上传已签名 APK 母包后，批量写入渠道后缀并生成不同文件名的渠道包。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ChannelPackageHeader(),
          const SizedBox(height: 18),
          FilePathSelector(
            value: controller.channelPackageApkPath,
            onChanged: context
                .read<EngineMenuController>()
                .updateChannelPackageApkPath,
            title: '第一步：上传已签名 APK 母包',
            label: 'APK 母包路径',
            hint: '/build/app-release.apk',
            dropHint: '拖拽已签名 APK 到这里，或点击按钮选择 APK',
            dialogTitle: '选择 APK 母包',
            allowedExtensions: const ['apk'],
            icon: Icons.android_outlined,
          ),
          const SizedBox(height: 24),
          Text(
            '第二步：渠道配置',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ChannelPackageSettings(controller: controller),
          const SizedBox(height: 24),
          Text(
            '第三步：预览与生成',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ChannelPackagePreview(controller: controller),
          const SizedBox(height: 18),
          _ChannelPackageActions(controller: controller),
          const SizedBox(height: 18),
          LogOutputPanel(
            logs: controller.channelPackageLogs,
            emptyText: '暂无日志，上传母包并配置渠道数量后点击开始生成。',
          ),
        ],
      ),
    );
  }
}

class _ChannelPackageHeader extends StatelessWidget {
  const _ChannelPackageHeader();

  void _openGuide(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ChannelReaderGuidePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '渠道包',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '不重新签名，不修改包名，仅在 APK Signing Block 写入渠道码。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF647084),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: () => _openGuide(context),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('读取方式说明'),
        ),
      ],
    );
  }
}

class _ChannelPackageSettings extends StatelessWidget {
  const _ChannelPackageSettings({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormGrid(
          children: [
            _SyncedTextField(
              value: controller.channelPackageCount.toString(),
              onChanged: context
                  .read<EngineMenuController>()
                  .updateChannelPackageCount,
              label: '生成数量',
              hint: '100',
              icon: Icons.format_list_numbered_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            _SyncedTextField(
              value: controller.channelPackagePrefix,
              onChanged: context
                  .read<EngineMenuController>()
                  .updateChannelPackagePrefix,
              label: '渠道后缀前缀',
              hint: 'ch',
              icon: Icons.sell_outlined,
            ),
            _SyncedTextField(
              value: controller.channelPackageStartIndex.toString(),
              onChanged: context
                  .read<EngineMenuController>()
                  .updateChannelPackageStartIndex,
              label: '起始序号',
              hint: '1',
              icon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OutputDirectoryField(
          value: controller.channelPackageOutputDirectory,
          onChanged: context
              .read<EngineMenuController>()
              .updateChannelPackageOutputDirectory,
        ),
      ],
    );
  }
}

class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
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
      onChanged: widget.onChanged,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: Icon(widget.icon),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}

class _OutputDirectoryField extends StatefulWidget {
  const _OutputDirectoryField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_OutputDirectoryField> createState() => _OutputDirectoryFieldState();
}

class _OutputDirectoryFieldState extends State<_OutputDirectoryField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_OutputDirectoryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _chooseDirectory() async {
    final selectedPath = await FilePicker.getDirectoryPath(
      dialogTitle: '选择渠道包输出目录',
      initialDirectory: widget.value.isEmpty ? null : widget.value,
    );
    if (selectedPath != null && selectedPath.trim().isNotEmpty) {
      widget.onChanged(selectedPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: '输出目录',
        hintText: '默认生成在母包同级 channel_packages 目录',
        prefixIcon: const Icon(Icons.folder_open_outlined),
        suffixIcon: IconButton(
          tooltip: '选择输出目录',
          onPressed: _chooseDirectory,
          icon: const Icon(Icons.more_horiz_outlined),
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }
}

class _ChannelPackagePreview extends StatelessWidget {
  const _ChannelPackagePreview({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6DDE8)),
      ),
      child: SelectableText(
        controller.channelPackagePreview,
        style: const TextStyle(
          color: Color(0xFF1F2937),
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}

class _ChannelPackageActions extends StatelessWidget {
  const _ChannelPackageActions({required this.controller});

  final EngineMenuController controller;

  @override
  Widget build(BuildContext context) {
    final hasLogs = controller.channelPackageLogs.isNotEmpty;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: controller.canGenerateChannelPackages
              ? () {
                  context
                      .read<EngineMenuController>()
                      .executeChannelPackageGeneration();
                }
              : null,
          icon: Icon(
            controller.isGeneratingChannelPackages
                ? Icons.hourglass_top_outlined
                : Icons.play_arrow_outlined,
          ),
          label: Text(controller.isGeneratingChannelPackages ? '生成中' : '开始生成'),
        ),
        OutlinedButton.icon(
          onPressed: hasLogs
              ? context.read<EngineMenuController>().clearChannelPackageLogs
              : null,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('清空日志'),
        ),
      ],
    );
  }
}

class ChannelReaderGuidePage extends StatelessWidget {
  const ChannelReaderGuidePage({super.key});

  static const String _kotlinSnippet = '''
val channel = WalleChannelReader.getChannel(this) ?: "official"
''';

  static const String _flutterBridgeSnippet = '''
// android/app/src/main/kotlin/.../MainActivity.kt
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.channel/apk"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sourceDir" -> result.success(applicationInfo.sourceDir)
                else -> result.notImplemented()
            }
        }
    }
}
''';

  static const String _flutterDartSnippet = '''
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

const _apkChannel = MethodChannel('app.channel/apk');
const _channelBlockId = 0x71777777;
const _apkSigningBlockMagic = [
  0x41, 0x50, 0x4B, 0x20, 0x53, 0x69, 0x67, 0x20,
  0x42, 0x6C, 0x6F, 0x63, 0x6B, 0x20, 0x34, 0x32,
];

Future<String> currentChannel() async {
  final sourceDir = await _apkChannel.invokeMethod<String>('sourceDir');
  if (sourceDir == null || sourceDir.isEmpty) {
    return 'official';
  }

  return await readApkChannel(sourceDir) ?? 'official';
}

Future<String?> readApkChannel(String apkPath) async {
  final bytes = await File(apkPath).readAsBytes();
  final eocdOffset = _findEocd(bytes);
  final centralDirOffset = _u32(bytes, eocdOffset + 16);

  final magicOffset = centralDirOffset - _apkSigningBlockMagic.length;
  for (var i = 0; i < _apkSigningBlockMagic.length; i += 1) {
    if (bytes[magicOffset + i] != _apkSigningBlockMagic[i]) return null;
  }

  final blockSize = _u64(bytes, centralDirOffset - 24);
  final blockStart = centralDirOffset - blockSize - 8;
  var cursor = blockStart + 8;
  final pairsEnd = centralDirOffset - 24;

  while (cursor < pairsEnd) {
    final pairLength = _u64(bytes, cursor);
    final pairStart = cursor + 8;
    final pairEnd = pairStart + pairLength;
    final id = _u32(bytes, pairStart);

    if (id == _channelBlockId) {
      return utf8.decode(bytes.sublist(pairStart + 4, pairEnd));
    }

    cursor = pairEnd;
  }

  return null;
}

int _findEocd(Uint8List bytes) {
  const eocdMinLength = 22;
  const maxCommentLength = 0xFFFF;
  const eocdSignature = 0x06054B50;
  final stopOffset = (bytes.length - eocdMinLength - maxCommentLength)
      .clamp(0, bytes.length);

  for (var offset = bytes.length - eocdMinLength;
      offset >= stopOffset;
      offset -= 1) {
    if (_u32(bytes, offset) != eocdSignature) continue;

    final commentLength = _u16(bytes, offset + 20);
    if (offset + eocdMinLength + commentLength == bytes.length) {
      return offset;
    }
  }

  throw StateError('APK EOCD not found');
}

int _u16(Uint8List bytes, int offset) {
  return ByteData.sublistView(bytes, offset, offset + 2)
      .getUint16(0, Endian.little);
}

int _u32(Uint8List bytes, int offset) {
  return ByteData.sublistView(bytes, offset, offset + 4)
      .getUint32(0, Endian.little);
}

int _u64(Uint8List bytes, int offset) {
  return ByteData.sublistView(bytes, offset, offset + 8)
      .getUint64(0, Endian.little);
}
''';

  static const String _androidNativeSnippet = '''
import android.content.Context
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets

object ApkChannelReader {
    private const val CHANNEL_BLOCK_ID = 0x71777777
    private const val EOCD_SIGNATURE = 0x06054B50
    private val APK_SIG_BLOCK_MAGIC = byteArrayOf(
        0x41, 0x50, 0x4B, 0x20, 0x53, 0x69, 0x67, 0x20,
        0x42, 0x6C, 0x6F, 0x63, 0x6B, 0x20, 0x34, 0x32
    )

    fun getChannel(context: Context): String {
        return readChannel(context.applicationInfo.sourceDir) ?: "official"
    }

    fun readChannel(apkPath: String): String? {
        RandomAccessFile(apkPath, "r").use { file ->
            val bytes = ByteArray(file.length().toInt())
            file.readFully(bytes)
            val eocdOffset = findEocd(bytes)
            val centralDirOffset = u32(bytes, eocdOffset + 16)

            val magicOffset = centralDirOffset - APK_SIG_BLOCK_MAGIC.size
            if (!APK_SIG_BLOCK_MAGIC.indices.all {
                    bytes[magicOffset + it] == APK_SIG_BLOCK_MAGIC[it]
                }) {
                return null
            }

            val blockSize = u64(bytes, centralDirOffset - 24)
            val blockStart = centralDirOffset - blockSize - 8
            var cursor = blockStart + 8
            val pairsEnd = centralDirOffset - 24

            while (cursor < pairsEnd) {
                val pairLength = u64(bytes, cursor)
                val pairStart = cursor + 8
                val pairEnd = pairStart + pairLength
                val id = u32(bytes, pairStart)

                if (id == CHANNEL_BLOCK_ID) {
                    return String(
                        bytes.copyOfRange(pairStart + 4, pairEnd),
                        StandardCharsets.UTF_8
                    )
                }

                cursor = pairEnd
            }
        }

        return null
    }

    private fun findEocd(bytes: ByteArray): Int {
        val minLength = 22
        val maxCommentLength = 0xFFFF
        val stopOffset = maxOf(0, bytes.size - minLength - maxCommentLength)

        for (offset in bytes.size - minLength downTo stopOffset) {
            if (u32(bytes, offset) != EOCD_SIGNATURE) continue
            val commentLength = u16(bytes, offset + 20)
            if (offset + minLength + commentLength == bytes.size) {
                return offset
            }
        }

        error("APK EOCD not found")
    }

    private fun u16(bytes: ByteArray, offset: Int): Int {
        return ByteBuffer.wrap(bytes, offset, 2)
            .order(ByteOrder.LITTLE_ENDIAN)
            .short.toInt() and 0xFFFF
    }

    private fun u32(bytes: ByteArray, offset: Int): Int {
        return ByteBuffer.wrap(bytes, offset, 4)
            .order(ByteOrder.LITTLE_ENDIAN)
            .int
    }

    private fun u64(bytes: ByteArray, offset: Int): Int {
        return ByteBuffer.wrap(bytes, offset, 8)
            .order(ByteOrder.LITTLE_ENDIAN)
            .long
            .toInt()
    }
}
''';

  static const String _formatSnippet = '''
Block ID: 0x71777777
Value: UTF-8 channel code, such as ch001, ch002, google_play
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('渠道码读取说明')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App 运行时读取当前渠道',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '渠道码写在 APK Signing Block 的自定义字段中，系统安装和覆盖升级不会读取它，App 需要集成兼容读取逻辑。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF647084),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _GuideSectionTitle('写入格式'),
                  const SizedBox(height: 10),
                  const _CodeBlock(text: _formatSnippet),
                  const SizedBox(height: 24),
                  const _GuideSectionTitle('推荐读取方式'),
                  const SizedBox(height: 10),
                  const _GuideParagraph(
                    'Android 工程集成 Walle 兼容 Reader 后，在 Application、启动页或埋点初始化位置读取渠道码。读取不到时建议回退到 official。',
                  ),
                  const SizedBox(height: 10),
                  const _CodeBlock(text: _kotlinSnippet),
                  const SizedBox(height: 24),
                  const _GuideSectionTitle('Flutter / Dart 直接读取'),
                  const SizedBox(height: 10),
                  const _GuideParagraph(
                    'Flutter 侧需要先通过 Android 原生桥接拿到当前已安装 APK 的 sourceDir，然后 Dart 直接解析 APK Signing Block。',
                  ),
                  const SizedBox(height: 10),
                  const _CodeBlock(text: _flutterBridgeSnippet),
                  const SizedBox(height: 12),
                  const _CodeBlock(text: _flutterDartSnippet),
                  const SizedBox(height: 24),
                  const _GuideSectionTitle('Android 原生 Kotlin 直接读取'),
                  const SizedBox(height: 10),
                  const _GuideParagraph(
                    '原生 Android 可以直接使用 applicationInfo.sourceDir 读取当前 APK，并从 Block ID 0x71777777 中取出 UTF-8 渠道码。',
                  ),
                  const SizedBox(height: 10),
                  const _CodeBlock(text: _androidNativeSnippet),
                  const SizedBox(height: 24),
                  const _GuideSectionTitle('覆盖安装关系'),
                  const SizedBox(height: 10),
                  const _GuideParagraph(
                    '这些渠道包不修改 applicationId、证书和 versionCode，因此同一母包生成出的渠道包可以按同一个 App 互相覆盖安装。若后续经过加固、重签名或重新打包，需要重新生成渠道包。',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideSectionTitle extends StatelessWidget {
  const _GuideSectionTitle(this.text);

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

class _GuideParagraph extends StatelessWidget {
  const _GuideParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF3B4351),
        height: 1.55,
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF293244)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          text.trim(),
          style: const TextStyle(
            color: Color(0xFFE5E7EB),
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
