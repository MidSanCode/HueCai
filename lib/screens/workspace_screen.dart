import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../providers/project_provider.dart';
import '../models/project.dart';
import '../models/canvas_settings.dart';
import 'new_project_dialog.dart';
import 'editor_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().loadRecentProjects();
    });
  }

  Future<void> _showNewProjectDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const NewProjectDialog(),
    );
    if (result != null && mounted) {
      await context.read<ProjectProvider>().createNewProject(
            name: result['name'] as String,
            width: result['width'] as int,
            height: result['height'] as int,
            unit: result['unit'] as CanvasUnit,
            resolution: result['resolution'] as double,
            colorModel: result['colorModel'] as ColorModel,
            channelDepth: result['channelDepth'] as int,
            iccProfileData: result['iccData'] as List<int>?,
          );
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('app.name'.tr()),
        centerTitle: true,
      ),
      body: Consumer<ProjectProvider>(
        builder: (ctx, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActionCards(
                  onNew: _showNewProjectDialog,
                  onOpen: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('file_picker not available')),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'workspace.recent'.tr(),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: provider.recentProjects.isEmpty
                      ? _EmptyState()
                      : GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _crossAxisCount(context),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.2,
                          ),
                          itemCount: provider.recentProjects.length,
                          itemBuilder: (ctx, i) {
                            final project = provider.recentProjects[i];
                            return _ProjectCard(
                              project: project,
                              onTap: () async {
                                if (project.filePath != null) {
                                  await provider.openProject(project.filePath!);
                                  if (context.mounted) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => const EditorScreen()),
                                    );
                                  }
                                }
                              },
                              onDelete: () async {
                                if (project.filePath != null) {
                                  await provider.deleteProject(project.filePath!);
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _crossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 900) return 4;
    if (width > 600) return 3;
    return 2;
  }
}

class _ActionCards extends StatelessWidget {
  final VoidCallback onNew;
  final VoidCallback onOpen;

  const _ActionCards({required this.onNew, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onNew,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.add_circle_outline,
                        size: 40, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(height: 8),
                    Text('workspace.new'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            elevation: 0,
            color: theme.colorScheme.secondaryContainer,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.folder_open,
                        size: 40, color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(height: 8),
                    Text('workspace.open'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.palette_outlined,
              size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text('workspace.no_projects'.tr(),
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: theme.colorScheme.surfaceContainerHigh,
                child: Center(
                  child: Icon(Icons.image_outlined,
                      size: 48, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${project.settings.width}x${project.settings.height}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    _formatDate(project.modifiedAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
