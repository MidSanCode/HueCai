import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../../providers/project_provider.dart';
import '../../services/script_engine.dart';
import '../../services/script_runner.dart';

/// 脚本控制台（路线图第 18 项「脚本插件能力」）。
///
/// 左侧代码区 + 右侧帮助速查；「预览」先解析计数，「运行」把结果落到当前
/// 工程（一次可撤销的编辑）。可保存/加载 `.huescript` 纯文本插件。
Future<void> showScriptConsole(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const ScriptConsoleDialog(),
    );

class ScriptConsoleDialog extends StatefulWidget {
  const ScriptConsoleDialog({super.key});

  @override
  State<ScriptConsoleDialog> createState() => _ScriptConsoleDialogState();
}

class _ScriptConsoleDialogState extends State<ScriptConsoleDialog> {
  final _controller = TextEditingController();
  String _status = '';
  String? _error;
  bool _running = false;
  bool _succeeded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller.text = '# 绘彩脚本\nrect 40,40,120,80 #FF8800\n'
        'dot 200,80 red 6\n'
        'text 40,150 已生成 by script #333333\n';
  }

  Future<void> _run() async {
    final pp = context.read<ProjectProvider>();
    setState(() {
      _running = true;
      _error = null;
      _status = '';
      _succeeded = false;
    });
    try {
      final runner = ScriptRunner(pp);
      final count = runner.previewShapeCount(_controller.text);
      final added = await runner.execute(_controller.text);
      setState(() {
        _succeeded = true;
        _status = 'script.done'.tr(namedArgs: {'n': '$added'});
      });
      assert(count >= 0);
    } on ScriptException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _save() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'script.save'.tr(),
      fileName: 'plugin.huescript',
      type: FileType.custom,
      allowedExtensions: ['huescript', 'txt'],
    );
    if (path == null) return;
    try {
      await File(path).writeAsString(_controller.text);
      if (!mounted) return;
      setState(() => _status = 'script.saved'.tr());
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'script.io_error'.tr());
    }
  }

  Future<void> _load() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['huescript', 'txt'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final text = await File(path).readAsString();
      if (!mounted) return;
      setState(() {
        _controller.text = text;
        _error = null;
        _status = 'script.loaded'.tr();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'script.io_error'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('script.title'.tr()),
      content: SizedBox(
        width: 640,
        height: 420,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _running ? null : _run,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: Text('script.run'.tr()),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: _save,
                        child: Text('script.save'.tr()),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: _load,
                        child: Text('script.load'.tr()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(fontSize: 11.5, height: 1.5),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('script.help_title'.tr(),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('script.help_body'.tr()),
                        const SizedBox(height: 8),
                        if (_error != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          )
                        else if (_status.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _succeeded
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(_status, style: const TextStyle(fontSize: 11.5)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('dialog.close'.tr()),
        ),
      ],
    );
  }
}
