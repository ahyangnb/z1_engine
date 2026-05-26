import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class FilePathSelector extends StatefulWidget {
  const FilePathSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    required this.label,
    required this.hint,
    required this.dropHint,
    this.dialogTitle,
    this.allowedExtensions,
    this.icon = Icons.insert_drive_file_outlined,
    this.showDropTarget = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String title;
  final String label;
  final String hint;
  final String dropHint;
  final String? dialogTitle;
  final List<String>? allowedExtensions;
  final IconData icon;
  final bool showDropTarget;

  @override
  State<FilePathSelector> createState() => _FilePathSelectorState();
}

class _FilePathSelectorState extends State<FilePathSelector> {
  late final TextEditingController _controller;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(FilePathSelector oldWidget) {
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

  Future<void> _chooseFile() async {
    final selected = await FilePicker.pickFiles(
      allowMultiple: false,
      dialogTitle: widget.dialogTitle ?? widget.title,
      type: widget.allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: widget.allowedExtensions,
    );

    final path = selected?.files.single.path;
    if (path != null && path.trim().isNotEmpty) {
      if (!_isAllowedPath(path)) {
        _showInvalidExtensionMessage();
        return;
      }

      widget.onChanged(path);
    }
  }

  void _handleDrop(DropDoneDetails details) {
    if (details.files.isNotEmpty) {
      final path = details.files.first.path;
      if (_isAllowedPath(path)) {
        widget.onChanged(path);
      } else {
        _showInvalidExtensionMessage();
      }
    }

    setState(() => _isDragging = false);
  }

  bool _isAllowedPath(String path) {
    final allowedExtensions = widget.allowedExtensions;
    if (allowedExtensions == null || allowedExtensions.isEmpty) {
      return true;
    }

    final lowerPath = path.toLowerCase();
    return allowedExtensions.any((extension) {
      final normalizedExtension = extension.startsWith('.')
          ? extension.toLowerCase()
          : '.${extension.toLowerCase()}';
      return lowerPath.endsWith(normalizedExtension);
    });
  }

  void _showInvalidExtensionMessage() {
    final allowedExtensions = widget.allowedExtensions;
    if (allowedExtensions == null || allowedExtensions.isEmpty) {
      return;
    }

    final extensionsText = allowedExtensions
        .map(
          (extension) => extension.startsWith('.') ? extension : '.$extension',
        )
        .join(' / ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('仅允许选择 $extensionsText 文件')));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title.isNotEmpty) ...[
          Text(
            widget.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon),
            suffixIcon: IconButton(
              tooltip: widget.dialogTitle ?? widget.title,
              onPressed: _chooseFile,
              icon: const Icon(Icons.more_horiz_outlined),
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        if (widget.showDropTarget) ...[
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
                    Icons.file_upload_outlined,
                    color: _isDragging
                        ? colorScheme.primary
                        : const Color(0xFF647084),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.dropHint,
                      style: const TextStyle(color: Color(0xFF3B4351)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
