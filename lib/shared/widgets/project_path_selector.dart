import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ProjectPathSelector extends StatefulWidget {
  const ProjectPathSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.title = '第一步：选择项目路径',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String title;

  @override
  State<ProjectPathSelector> createState() => _ProjectPathSelectorState();
}

class _ProjectPathSelectorState extends State<ProjectPathSelector> {
  late final TextEditingController _controller;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(ProjectPathSelector oldWidget) {
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

  Future<void> _chooseProjectPath() async {
    final selectedPath = await FilePicker.getDirectoryPath(
      dialogTitle: '选择项目路径',
      initialDirectory: widget.value.isEmpty ? null : widget.value,
    );

    if (selectedPath != null && selectedPath.trim().isNotEmpty) {
      widget.onChanged(selectedPath);
    }
  }

  void _handleDrop(DropDoneDetails details) {
    if (details.files.isNotEmpty) {
      widget.onChanged(details.files.first.path);
    }

    setState(() => _isDragging = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            labelText: '项目路径',
            hintText: '例如：/Users/name/project 或 D:\\project',
            prefixIcon: const Icon(Icons.folder_open_outlined),
            suffixIcon: IconButton(
              tooltip: '选择项目路径',
              onPressed: _chooseProjectPath,
              icon: const Icon(Icons.more_horiz_outlined),
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: _handleDrop,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: _isDragging
                  ? colorScheme.primaryContainer
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isDragging
                    ? colorScheme.primary
                    : const Color(0xFFD6DDE8),
                width: _isDragging ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.drive_folder_upload_outlined,
                  color: _isDragging
                      ? colorScheme.primary
                      : const Color(0xFF647084),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '拖拽项目文件夹到这里，或在上方手动输入/点击按钮选择',
                    style: TextStyle(color: Color(0xFF3B4351)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
