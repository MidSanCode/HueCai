import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../providers/app_settings.dart';
import '../providers/tool_provider.dart';
import '../utils/logger.dart';
import '../services/config_service.dart';

enum SettingsTab { general, drawing, debug, about }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsTab _currentTab = SettingsTab.general;

  bool get _isWide => MediaQuery.of(context).size.width >= 600;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('app.name'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: _isWide
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: DropdownButton<SettingsTab>(
                    value: _currentTab,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: SettingsTab.values.map((tab) {
                      return DropdownMenuItem(
                        value: tab,
                        child: Text(_tabLabel(tab)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _currentTab = v);
                    },
                  ),
                ),
              ),
      ),
      body: Row(
        children: [
          if (_isWide)
            NavigationRail(
              selectedIndex: SettingsTab.values.indexOf(_currentTab),
              onDestinationSelected: (i) =>
                  setState(() => _currentTab = SettingsTab.values[i]),
              labelType: NavigationRailLabelType.all,
              destinations: SettingsTab.values.map((tab) {
                return NavigationRailDestination(
                  icon: Icon(_tabIcon(tab)),
                  label: Text(_tabLabel(tab)),
                );
              }).toList(),
            ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildContent(context),
            ),
          ),
        ],
      ),
    );
  }

  String _tabLabel(SettingsTab tab) {
    switch (tab) {
      case SettingsTab.general: return 'settings.tab.general'.tr();
      case SettingsTab.drawing: return 'settings.tab.drawing'.tr();
      case SettingsTab.debug: return 'settings.tab.debug'.tr();
      case SettingsTab.about: return 'settings.tab.about'.tr();
    }
  }

  IconData _tabIcon(SettingsTab tab) {
    switch (tab) {
      case SettingsTab.general: return Icons.tune;
      case SettingsTab.drawing: return Icons.brush;
      case SettingsTab.debug: return Icons.bug_report;
      case SettingsTab.about: return Icons.info_outline;
    }
  }

  Widget _buildContent(BuildContext context) {
    switch (_currentTab) {
      case SettingsTab.general: return _GeneralContent();
      case SettingsTab.drawing: return _DrawingContent();
      case SettingsTab.debug: return _DebugContent();
      case SettingsTab.about: return _AboutContent();
    }
  }
}

// ─── General ───────────────────────────────────────────────────

class _GeneralContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<AppSettings>();
    final locale = context.locale;

    return ListView(
      children: [
        _sectionCard(theme: theme, title: 'settings.appearance'.tr(), children: [
          ListTile(
            title: Text('settings.theme_mode'.tr()),
            subtitle: Text(settings.themeMode == ThemeMode.dark
                ? 'settings.dark'.tr()
                : settings.themeMode == ThemeMode.light
                    ? 'settings.light'.tr()
                    : 'settings.system'.tr()),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text('settings.theme_mode'.tr()),
                  children: [
                    SimpleDialogOption(
                      onPressed: () { settings.setThemeMode(ThemeMode.light); Navigator.of(ctx).pop(); },
                      child: Text('settings.light'.tr(), style: TextStyle(
                        fontWeight: settings.themeMode == ThemeMode.light ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                    SimpleDialogOption(
                      onPressed: () { settings.setThemeMode(ThemeMode.dark); Navigator.of(ctx).pop(); },
                      child: Text('settings.dark'.tr(), style: TextStyle(
                        fontWeight: settings.themeMode == ThemeMode.dark ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                    SimpleDialogOption(
                      onPressed: () { settings.setThemeMode(ThemeMode.system); Navigator.of(ctx).pop(); },
                      child: Text('settings.system'.tr(), style: TextStyle(
                        fontWeight: settings.themeMode == ThemeMode.system ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                  ],
                ),
              );
            },
          ),
        ]),
        _sectionCard(theme: theme, title: 'settings.language'.tr(), children: [
          ListTile(
            title: Text('settings.language'.tr()),
            subtitle: Text(locale.languageCode == 'zh' ? '中文' : 'English'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text('settings.select_language'.tr()),
                  children: [
                    SimpleDialogOption(
                      onPressed: () {
                        context.setLocale(const Locale('zh'));
                        settings.setLanguageCode('zh');
                        Navigator.of(ctx).pop();
                      },
                      child: Text('中文', style: TextStyle(
                        fontWeight: locale.languageCode == 'zh' ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        context.setLocale(const Locale('en'));
                        settings.setLanguageCode('en');
                        Navigator.of(ctx).pop();
                      },
                      child: Text('English', style: TextStyle(
                        fontWeight: locale.languageCode == 'en' ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                  ],
                ),
              );
            },
          ),
        ]),
      ],
    );
  }
}

// ─── Drawing ───────────────────────────────────────────────────

class _DrawingContent extends StatefulWidget {
  @override
  State<_DrawingContent> createState() => _DrawingContentState();
}

class _DrawingContentState extends State<_DrawingContent> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<AppSettings>();
    return ListView(
      children: [
        _sectionCard(theme: theme, title: 'settings.stabilizer'.tr(), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text('settings.stabilizer'.tr(), style: const TextStyle(fontSize: 13)),
                const Spacer(),
                Text('${settings.stabilizer.round()}', style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Slider(
              value: settings.stabilizer,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${settings.stabilizer.round()}',
              onChanged: (v) => settings.setStabilizer(v),
            ),
          ),
        ]),
        _sectionCard(theme: theme, title: 'settings.fill'.tr(), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text('settings.fill_tolerance'.tr(), style: const TextStyle(fontSize: 13)),
                const Spacer(),
                Text('${settings.fillTolerance}', style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Slider(
              value: settings.fillTolerance.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              label: '${settings.fillTolerance}',
              onChanged: (v) => settings.setFillTolerance(v.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text('settings.fill_grow_shrink'.tr(), style: const TextStyle(fontSize: 13)),
                const Spacer(),
                Text(
                  '${settings.fillGrowShrink > 0 ? '+' : ''}${settings.fillGrowShrink} px',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Slider(
              value: settings.fillGrowShrink.toDouble(),
              min: -25,
              max: 25,
              divisions: 50,
              label: '${settings.fillGrowShrink > 0 ? '+' : ''}${settings.fillGrowShrink}',
              onChanged: (v) => settings.setFillGrowShrink(v.round()),
            ),
          ),
          SwitchListTile(
            title: Text('settings.fill_antialias'.tr(), style: const TextStyle(fontSize: 13)),
            value: settings.fillAntiAlias,
            onChanged: (v) => settings.setFillAntiAlias(v),
          ),
        ]),
        _sectionCard(theme: theme, title: 'settings.toolbar'.tr(), children: [
          ListTile(
            title: Text('settings.customize_toolbar'.tr()),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _showToolbarEditor(context, settings),
          ),
        ]),
      ],
    );
  }

  void _showToolbarEditor(BuildContext context, AppSettings settings) {
    final allTools = ToolType.values.where((t) => t != ToolType.perspectiveGuide && t != ToolType.symmetry).toList();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final currentTools = List<String>.from(settings.toolbarTools);
          final available = allTools.where((t) => !currentTools.contains(t.name)).toList();
          return AlertDialog(
            title: Text('settings.customize_toolbar'.tr()),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('settings.toolbar_visible'.tr(), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ReorderableListView(
                      shrinkWrap: true,
                      children: List.generate(currentTools.length, (i) {
                        final name = currentTools[i];
                        final tool = ToolType.values.firstWhere(
                          (t) => t.name == name,
                          orElse: () => ToolType.brush,
                        );
                        return ListTile(
                          key: ValueKey(name),
                          leading: Icon(Icons.drag_handle, size: 18),
                          title: Text(_toolLabel(tool), style: const TextStyle(fontSize: 13)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            onPressed: () {
                              settings.removeToolbarTool(name);
                              setState(() {});
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        );
                      }),
                      onReorderItem: (oldIndex, newIndex) {
                        settings.moveToolbarTool(oldIndex, newIndex);
                        setState(() {});
                      },
                    ),
                  ),
                  if (available.isNotEmpty) ...[
                    const Divider(),
                    Text('settings.toolbar_available'.tr(), style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        children: available.map((tool) {
                          return ListTile(
                            leading: Icon(Icons.add_circle_outline, size: 18),
                            title: Text(_toolLabel(tool), style: const TextStyle(fontSize: 13)),
                            onTap: () {
                              settings.addToolbarTool(tool.name);
                              setState(() {});
                            },
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('dialog.close'.tr()),
              ),
            ],
          );
        },
      ),
    );
  }

  String _toolLabel(ToolType tool) {
    switch (tool) {
      case ToolType.move: return 'Move';
      case ToolType.shape: return 'Shape';
      case ToolType.pen: return 'Pen';
      case ToolType.text: return 'Text';
      case ToolType.select: return 'Select';
      case ToolType.brush: return 'Brush';
      case ToolType.eraser: return 'Eraser';
      case ToolType.fill: return 'Fill';
      case ToolType.gradient: return 'Gradient';
      case ToolType.eyedropper: return 'Eyedropper';
      case ToolType.smudge: return 'Smudge';
      case ToolType.willowLeaf: return 'Willow Leaf';
      case ToolType.liquify: return 'Liquify';
      case ToolType.perspectiveGuide: return 'Perspective Guide';
      case ToolType.symmetry: return 'Symmetry';
    }
  }
}

// ─── Debug ─────────────────────────────────────────────────────

class _DebugContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        _sectionCard(theme: theme, title: 'settings.logs'.tr(), children: [
          ListTile(
            leading: const Icon(Icons.file_download),
            title: Text('settings.export_log'.tr()),
            subtitle: Text('settings.export_log_desc'.tr()),
            onTap: () async {
              final logPath = await AppLogger().export();
              final result = await FilePicker.platform.saveFile(
                dialogTitle: 'settings.export_log'.tr(),
                fileName: 'huecai_log.txt',
                type: FileType.any,
              );
              if (result != null) {
                try {
                  await File(logPath).copy(result);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('settings.export_done'.tr())),
                    );
                  }
                } catch (_) {}
              }
            },
          ),
        ]),
      ],
    );
  }
}

// ─── About ─────────────────────────────────────────────────────

class _AboutContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 32),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.brush, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('app.name'.tr(), style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('app.subtitle'.tr(), style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _infoCard(context, 'settings.version'.tr(), ConfigService.buildVersion),
          _infoCard(context, 'settings.build'.tr(), ConfigService.buildNumber),
          const SizedBox(height: 24),
          Text('settings.inspired_by'.tr(), style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 8),
          Text('settings.copyright'.tr(), style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _infoCard(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 2),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
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

// ─── Shared ────────────────────────────────────────────────────

Widget _sectionCard({
  required ThemeData theme,
  required String title,
  required List<Widget> children,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}