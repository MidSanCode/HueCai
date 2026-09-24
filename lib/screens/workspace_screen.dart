import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/project_provider.dart';
import '../providers/cloud_sync_provider.dart';
import '../models/project.dart';
import '../widgets/cloud_user_card.dart';
import '../widgets/cloud_conflict_dialog.dart';
import '../widgets/cloud_setup_dialog.dart';
import '../models/canvas_settings.dart';
import '../models/drawable.dart';
import '../services/project_service.dart';
import 'new_project_dialog.dart';
import 'editor_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};
  bool _showTrash = false;
  List<File> _trashFiles = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Bumped every time we come back from the editor so project cards
  /// reload their (possibly regenerated) thumbnails.
  int _thumbRevision = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshAfterEditor() {
    if (!mounted) return;
    context.read<ProjectProvider>().loadRecentProjects();
    setState(() => _thumbRevision++);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().loadRecentProjects();
    });
  }

  void _openProject(BuildContext context) async {
    final pp = context.read<ProjectProvider>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['hcp', 'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (path.endsWith('.hcp')) {
        await pp.openProject(path);
      } else {
        await pp.importImage(path);
      }
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        ).then((_) => _refreshAfterEditor());
      }
    }
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
        ).then((_) => _refreshAfterEditor());
      }
    }
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) _selectionMode = false;
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  Future<void> _showRenameDialog(BuildContext ctx, Project project) async {
    final pp = context.read<ProjectProvider>();
    final controller = TextEditingController(text: project.name);
    final result = await showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text('workspace.rename'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dCtx).pop(), child: Text('dialog.cancel'.tr())),
          TextButton(onPressed: () => Navigator.of(dCtx).pop(controller.text), child: Text('dialog.confirm'.tr())),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && project.filePath != null) {
      await pp.renameProject(project.filePath!, result);
      if (context.mounted) pp.loadRecentProjects();
    }
  }

  Future<void> _showCreateFolderDialog() async {
    final pp = context.read<ProjectProvider>();
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text('workspace.new_folder'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(isDense: true, hintText: 'workspace.folder_hint'.tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dCtx).pop(), child: Text('dialog.cancel'.tr())),
          TextButton(onPressed: () => Navigator.of(dCtx).pop(controller.text), child: Text('dialog.confirm'.tr())),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await pp.createFolder(result);
      if (context.mounted) pp.loadRecentProjects();
    }
  }

  Future<void> _showMoveDialog(BuildContext ctx) async {
    final pp = context.read<ProjectProvider>();
    final folders = await pp.listFolders();
    if (!ctx.mounted) return;
    final folder = await showDialog<String>(
      context: ctx,
      builder: (dCtx) => SimpleDialog(
        title: Text('workspace.move_to'.tr()),
        children: [
          ...folders.map((f) => SimpleDialogOption(
            onPressed: () => Navigator.of(dCtx).pop(f),
            child: Text(f),
          )),
        ],
      ),
    );
    if (folder != null) {
      await pp.moveToFolder(_selectedPaths.toList(), folder);
      _exitSelection();
      if (context.mounted) pp.loadRecentProjects();
    }
  }

  Future<void> _showBatchExportDialog() async {
    final pp = context.read<ProjectProvider>();
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'workspace.batch_export'.tr(),
    );
    if (result != null) {
      await pp.batchExport(_selectedPaths.toList(), result);
      _exitSelection();
    }
  }

  Future<void> _loadTrash() async {
    final files = await context.read<ProjectProvider>().listTrashFiles();
    if (mounted) setState(() => _trashFiles = files);
  }

  Future<void> _showCardContextMenu(BuildContext ctx, Project project) async {
    final theme = Theme.of(context);
    final result = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(100, 100, 100, 100),
      items: [
        PopupMenuItem(value: 'sync', child: ListTile(
          leading: Icon(Icons.cloud_upload_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
          title: const Text('Sync to Cloud'), dense: true,
        )),
        PopupMenuItem(value: 'rename', child: ListTile(
          leading: Icon(Icons.edit, size: 18, color: theme.colorScheme.onSurfaceVariant),
          title: Text('workspace.rename'.tr()), dense: true,
        )),
        PopupMenuItem(value: 'delete', child: ListTile(
          leading: Icon(Icons.delete, size: 18, color: theme.colorScheme.error),
          title: Text('workspace.delete'.tr()), dense: true,
        )),
      ],
    );
    final pp = context.read<ProjectProvider>();
    if (result == 'sync') {
      await _syncProject(ctx, project);
    } else if (result == 'rename') {
      _showRenameDialog(ctx, project);
    } else if (result == 'delete') {
      await pp.deleteProject(project.filePath!);
      if (context.mounted) pp.loadRecentProjects();
    }
  }

  Future<void> _syncProject(BuildContext ctx, Project project) async {
    final syncProvider = context.read<CloudSyncProvider>();

    // Cloud sync now requires a provider + credentials. When none are stored
    // yet, walk the user through the setup dialog instead of failing.
    if (!syncProvider.isLoggedIn) {
      final config = await showCloudSetupDialog(ctx);
      if (config == null) return;
      if (!syncProvider.isLoggedIn) return;
    }

    var cancelled = false;
    final outcome = await syncProvider.syncProject(
      project,
      (localTime, remoteTime) async {
        final resolution = await showCloudConflictDialog(
          ctx,
          localTime: localTime,
          remoteTime: remoteTime,
          projectName: project.name,
          localSize: _fileSize(project.filePath),
        );
        // `null` means the user dismissed the dialog: abort the sync rather
        // than defaulting to one side and silently discarding the other.
        if (resolution == null) {
          cancelled = true;
          return SyncResolution.local;
        }
        return resolution;
      },
    );

    if (!mounted) return;

    if (cancelled && outcome == SyncOutcome.conflictResolved) return;

    final message = switch (outcome) {
      SyncOutcome.uploaded => 'Cloud sync: "${project.name}" uploaded.',
      SyncOutcome.downloaded => 'Cloud sync: "${project.name}" updated from cloud.',
      SyncOutcome.upToDate => 'Cloud sync: "${project.name}" is already up to date.',
      SyncOutcome.conflictResolved => 'Cloud sync: conflict resolved for '
          '"${project.name}".',
      SyncOutcome.failed =>
        syncProvider.syncErrorMessage ?? 'Cloud sync failed.',
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: outcome == SyncOutcome.failed
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );

    // A download rewrote the project file, so refresh the grid/thumbnails.
    if (outcome == SyncOutcome.downloaded ||
        outcome == SyncOutcome.conflictResolved) {
      syncProvider.markDirty(project.id);
      await context.read<ProjectProvider>().loadRecentProjects();
    }
  }

  /// Size of a local project file in bytes, or `null` when unavailable.
  int? _fileSize(String? path) {
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pp = context.watch<ProjectProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelection)
            : null,
        title: _selectionMode
            ? Text('workspace.selected'.tr(namedArgs: {'count': '${_selectedPaths.length}'}))
            : Text('app.name'.tr()),
        centerTitle: !_selectionMode,
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  tooltip: 'workspace.delete'.tr(),
                  onPressed: () async {
                    for (final p in _selectedPaths) {
                      await pp.deleteProject(p);
                    }
                    _exitSelection();
                    if (context.mounted) pp.loadRecentProjects();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move, size: 20),
                  tooltip: 'workspace.move_to'.tr(),
                  onPressed: () => _showMoveDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.file_download, size: 20),
                  tooltip: 'workspace.batch_export'.tr(),
                  onPressed: _showBatchExportDialog,
                ),
              ]
            : [
                IconButton(
                  icon: Icon(_showTrash ? Icons.folder : Icons.delete_outline, size: 20),
                  tooltip: 'workspace.trash'.tr(),
                  onPressed: () {
                    setState(() => _showTrash = !_showTrash);
                    if (_showTrash) _loadTrash();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder, size: 20),
                  tooltip: 'workspace.new_folder'.tr(),
                  onPressed: _showCreateFolderDialog,
                ),
              ],
      ),
      body: _showTrash ? _buildTrashView(context, theme) : _buildWorkspaceBody(context, theme, pp),
    );
  }

  Widget _buildWorkspaceBody(BuildContext context, ThemeData theme, ProjectProvider pp) {
    return Column(
      children: [
        const CloudUserCard(),
        Expanded(
          child: _buildProjectGrid(context, theme, pp),
        ),
      ],
    );
  }

  Widget _buildTrashView(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('workspace.trash'.tr(), style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: Text('workspace.empty_trash'.tr()),
                onPressed: () async {
                  await context.read<ProjectProvider>().emptyTrash();
                  setState(() => _trashFiles.clear());
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _trashFiles.isEmpty
                ? Center(child: Text('workspace.trash_empty'.tr(), style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                : ListView.builder(
                    itemCount: _trashFiles.length,
                    itemBuilder: (ctx, i) {
                      final file = _trashFiles[i];
                      final name = file.uri.pathSegments.last;
                      return ListTile(
                        title: Text(name),
                        trailing: IconButton(
                          icon: const Icon(Icons.restore, size: 20),
                          tooltip: 'workspace.restore'.tr(),
                          onPressed: () async {
                            await context.read<ProjectProvider>().restoreProject(file.path);
                            _loadTrash();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectGrid(BuildContext context, ThemeData theme, ProjectProvider provider) {
    final cloudSync = context.watch<CloudSyncProvider>();
    if (provider.loading) return const Center(child: CircularProgressIndicator());
    if (provider.recentProjects.isEmpty) {
      return _EmptyState(
        onNew: _showNewProjectDialog,
        onOpen: () => _openProject(context),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final projects = query.isEmpty
        ? provider.recentProjects
        : provider.recentProjects.where((p) => p.name.toLowerCase().contains(query)).toList();
    final count = _crossAxisCount(context);
    final tileW = (MediaQuery.of(context).size.width - 32 - 12 * (count - 1)) / count;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('workspace.recent'.tr(), style: theme.textTheme.titleMedium),
              const SizedBox(width: 12),
              Expanded(child: _buildSearchField(theme)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: projects.isEmpty
                ? Center(child: Text('workspace.no_results'.tr(), style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: projects.length + 2,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return _NewCard(onTap: _showNewProjectDialog);
                      }
                      if (i == 1) {
                        return _OpenCard(onTap: () => _openProject(context));
                      }
                      final project = projects[i - 2];
                      return _ProjectCard(
                        project: project,
                        thumbWidth: tileW,
                        revision: _thumbRevision,
                        syncStatus: cloudSync.statusOf(project.id),
                        onSync: cloudSync.isLoggedIn ? () => _syncProject(context, project) : null,
                        selected: _selectionMode && project.filePath != null && _selectedPaths.contains(project.filePath),
                        showCheckbox: _selectionMode,
                        onTap: () {
                          if (_selectionMode && project.filePath != null) {
                            _toggleSelection(project.filePath!);
                          } else if (project.filePath != null) {
                            _openAndNavigate(context, provider, project.filePath!);
                          }
                        },
                        onLongPress: () {
                          if (project.filePath != null) {
                            setState(() {
                              _selectionMode = true;
                              _selectedPaths.add(project.filePath!);
                            });
                          }
                        },
                        onContextMenu: () => _showCardContextMenu(context, project),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'workspace.search_hint'.tr(),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHigh,
        ),
      ),
    );
  }

  void _openAndNavigate(BuildContext context, ProjectProvider provider, String filePath) async {
    await provider.openProject(filePath);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditorScreen()))
          .then((_) => _refreshAfterEditor());
    }
  }

  int _crossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 900) return 4;
    if (width > 600) return 3;
    return 2;
  }
}

class _NewCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NewCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: theme.colorScheme.primaryContainer,
                child: Center(
                  child: Icon(Icons.add_circle_outline, size: 48,
                      color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text('workspace.new'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenCard extends StatelessWidget {
  final VoidCallback onTap;
  const _OpenCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: theme.colorScheme.secondaryContainer,
                child: Center(
                  child: Icon(Icons.folder_open, size: 48,
                      color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text('workspace.open'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  final VoidCallback onOpen;
  const _EmptyState({required this.onNew, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.palette_outlined,
                size: 64, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('workspace.no_projects'.tr(),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('workspace.new'.tr()),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text('workspace.open'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatefulWidget {
  final Project project;
  final bool selected;
  final bool showCheckbox;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onContextMenu;

  /// Cloud sync status shown as a small icon on the thumbnail.
  final SyncStatus syncStatus;
  final VoidCallback? onSync;

  /// Approximate card tile width (logical px). Used to cap the decoded
  /// thumbnail resolution so large previews don't consume excessive memory.
  final double thumbWidth;

  /// Incremented by the workspace whenever we return from the editor so
  /// stale thumbnails get reloaded.
  final int revision;

  const _ProjectCard({
    required this.project,
    this.thumbWidth = 0,
    this.revision = 0,
    this.selected = false,
    this.showCheckbox = false,
    required this.onTap,
    this.onLongPress,
    this.onContextMenu,
    this.syncStatus = SyncStatus.idle,
    this.onSync,
  });

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  String? _thumbPath;
  int _stamp = 0;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(_ProjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.project.filePath != widget.project.filePath) {
      _loadThumbnail();
    }
  }

  void _loadThumbnail() {
    if (widget.project.filePath == null) return;
    final thumbFile = File('${widget.project.filePath}.thumb.png');
    if (thumbFile.existsSync()) {
      final stamp = thumbFile.lastModifiedSync().millisecondsSinceEpoch;
      // Evict the decoded image from Flutter's cache when the file changed,
      // otherwise the same path keeps showing the old preview.
      if (_thumbPath == thumbFile.path && stamp != _stamp) {
        FileImage(thumbFile).evict();
      }
      _stamp = stamp;
      _thumbPath = thumbFile.path;
      if (mounted) setState(() {});
    } else {
      _thumbPath = null;
      if (mounted) setState(() {});
    }
  }

  Widget _thumbPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Center(
        child: Icon(Icons.image_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  /// Physical-pixel width used to cap thumbnail decode size. Clamped to a
  /// sensible range regardless of the reported tile width.
  int _thumbDecodeWidth(BuildContext context) {
    if (widget.thumbWidth <= 0) return 300;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (widget.thumbWidth * dpr).round().clamp(96, 512);
  }

  Widget _syncIcon(ThemeData theme) {
    final color = switch (widget.syncStatus) {
      SyncStatus.success => Colors.greenAccent,
      SyncStatus.error => theme.colorScheme.error,
      SyncStatus.syncing => Colors.amber,
      SyncStatus.idle => Colors.white70,
    };
    final icon = switch (widget.syncStatus) {
      SyncStatus.success => Icons.cloud_done,
      SyncStatus.error => Icons.cloud_off,
      SyncStatus.syncing => Icons.cloud_sync,
      SyncStatus.idle => Icons.cloud_outlined,
    };
    return Icon(icon, size: 18, color: color);
  }

  /// Human-readable sync state shown under the project name.
  String _syncLabel() => switch (widget.syncStatus) {
        SyncStatus.success => 'cloud.status_synced'.tr(),
        SyncStatus.error => 'cloud.status_failed'.tr(),
        SyncStatus.syncing => 'cloud.status_syncing'.tr(),
        SyncStatus.idle => 'cloud.status_unsynced'.tr(),
      };

  Color _syncLabelColor(ThemeData theme) => switch (widget.syncStatus) {
        SyncStatus.success => Colors.green,
        SyncStatus.error => theme.colorScheme.error,
        SyncStatus.syncing => Colors.orange,
        SyncStatus.idle => theme.colorScheme.outline,
      };

  void _showReplay(BuildContext context) async {
    final project = widget.project;
    if (project.filePath == null) return;

    final service = ProjectService();
    final loaded = await service.loadProject(project.filePath!);
    if (loaded == null || !context.mounted) return;

    final allDrawables = <Drawable>[];
    for (final layer in loaded.layers) {
      if (!layer.visible) continue;
      // Raster layer content (baked selection applies, liquify warps,
      // imported images) isn't a drawable — wrap it so replay still shows
      // everything painted before the baked strokes.
      if (layer.image != null) {
        allDrawables.add(Drawable(
          id: 'replay-img-${layer.id}',
          points: [Offset.zero],
          liquifyImage: layer.image,
          isLiquify: true,
        ));
      }
      allDrawables.addAll(layer.drawables);
    }
    if (allDrawables.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ReplayDialog(drawables: allDrawables, project: loaded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onSecondaryTap: widget.onContextMenu,
      onLongPress: widget.onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: widget.selected ? theme.colorScheme.primaryContainer : null,
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_thumbPath != null)
                      Image.file(
                        File(_thumbPath!),
                        key: ValueKey('$_thumbPath#$_stamp'),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        // Decode at roughly the rendered size to keep the
                        // grid light even with very large canvases.
                        cacheWidth: _thumbDecodeWidth(context),
                        errorBuilder: (_, _, _) => _thumbPlaceholder(theme),
                      )
                    else
                      _thumbPlaceholder(theme),
                    if (widget.showCheckbox)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: Icon(
                          widget.selected ? Icons.check_circle : Icons.circle_outlined,
                          size: 22,
                          color: widget.selected ? theme.colorScheme.primary : Colors.white70,
                        ),
                      ),
                    if (widget.onSync != null)
                      Positioned(
                        left: 4,
                        top: widget.showCheckbox ? 30 : 4,
                        child: Material(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: widget.onSync,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: _syncIcon(theme),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Material(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _showReplay(context),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.play_circle_filled,
                                size: 22, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.project.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.project.settings.width}x${widget.project.settings.height}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      _formatDate(widget.project.modifiedAt),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    // Cloud sync state: 已同步 / 同步失败 / 未同步.
                    if (widget.onSync != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            switch (widget.syncStatus) {
                              SyncStatus.success => Icons.cloud_done,
                              SyncStatus.error => Icons.cloud_off,
                              SyncStatus.syncing => Icons.cloud_sync,
                              SyncStatus.idle => Icons.cloud_outlined,
                            },
                            size: 12,
                            color: _syncLabelColor(theme),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _syncLabel(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _syncLabelColor(theme),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _ReplayDialog extends StatefulWidget {
  final List<Drawable> drawables;
  final Project project;

  const _ReplayDialog({required this.drawables, required this.project});

  @override
  State<_ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends State<_ReplayDialog> {
  /// Fractional stroke counter. Kept as a double so slow speeds (0.5x)
  /// actually advance — the old int field floor-dropped the 0.5 increment
  /// every tick and the 0.5x chip appeared dead.
  double _progress = 0;
  bool _paused = false;
  bool _finished = false;
  double _speed = 1.0;
  Timer? _timer;

  /// Incremental render cache: strokes [0, _baseCount) baked into one
  /// image. Repainting used to redraw every visible stroke from scratch
  /// each tick (O(n²) over a replay), which made playback crawl at ~1/5
  /// of the nominal speed on larger drawings. With the cache each frame
  /// only blits the baked image and draws the few newest strokes.
  ui.Image? _baseImage;
  int _baseCount = 0;
  bool _baking = false;

  static const List<double> _speeds = [0.5, 1.0, 2.0, 4.0];

  int get _visibleCount => _progress.floor().clamp(0, widget.drawables.length);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    if (!mounted || _paused || _finished) {
      _stopTimer();
      return;
    }
    _progress = (_progress + _speed).clamp(0.0, widget.drawables.length.toDouble());
    if (_progress >= widget.drawables.length) {
      _finished = true;
      _stopTimer();
    }
    _bakeIfNeeded();
    setState(() {});
  }

  void _bakeIfNeeded() {
    final target = _visibleCount;
    if (target > _baseCount && !_baking) {
      _bake(target);
    }
  }

  Future<void> _bake(int upTo) async {
    _baking = true;
    try {
      final w = widget.project.settings.width.toInt();
      final h = widget.project.settings.height.toInt();
      if (w <= 0 || h <= 0) return;
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      if (_baseImage != null) {
        c.drawImage(_baseImage!, Offset.zero, Paint());
      }
      for (int i = _baseCount; i < upTo && i < widget.drawables.length; i++) {
        widget.drawables[i].draw(c, Paint());
      }
      final img = await recorder.endRecording().toImage(w, h);
      if (!mounted) {
        img.dispose();
        return;
      }
      final old = _baseImage;
      _baseImage = img;
      _baseCount = upTo;
      old?.dispose();
      setState(() {});
    } catch (_) {
      // Cache failure is non-fatal: the painter falls back to live drawing.
    } finally {
      _baking = false;
    }
  }

  void _resetBaseCache() {
    _baseImage?.dispose();
    _baseImage = null;
    _baseCount = 0;
  }

  void _restartFromStart() {
    _resetBaseCache();
    _progress = 0;
    _finished = false;
    _paused = false;
    _startTimer();
    setState(() {});
  }

  void _togglePause() {
    setState(() {
      if (_finished) {
        // Play after the end: replay again from the beginning.
        _restartFromStart();
      } else {
        _paused = !_paused;
        if (_paused) {
          _stopTimer();
        } else {
          _startTimer();
        }
      }
    });
  }

  void _seekTo(double value) {
    setState(() {
      _progress = value.clamp(0.0, widget.drawables.length.toDouble());
      final target = _visibleCount;
      if (target < _baseCount) {
        // Seeking backwards invalidates the baked prefix.
        _resetBaseCache();
      }
      if (target < widget.drawables.length) {
        _finished = false;
        // The old code checked `_timer == null`, but a finished timer was
        // cancelled, not nulled — seeking after completion could never
        // restart playback. _stopTimer now nulls it.
        if (_timer == null && !_paused) _startTimer();
      } else {
        _finished = true;
        _stopTimer();
      }
    });
    _bakeIfNeeded();
  }

  @override
  void dispose() {
    _stopTimer();
    _baseImage?.dispose();
    _baseImage = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = widget.project.settings.width.toDouble();
    final h = widget.project.settings.height.toDouble();
    final available = MediaQuery.of(context).size.width * 0.8;
    final scale = (available / w).clamp(0.1, 1.0);
    final dw = w * scale;
    final dh = h * scale;
    final total = widget.drawables.length;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.project.name, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ClipRect(
              child: SizedBox(
                width: dw,
                height: dh,
                  child: CustomPaint(
                    size: Size(dw, dh),
                    painter: _ReplayPainter(
                      drawables: widget.drawables,
                      visibleCount: _visibleCount,
                      baseImage: _baseImage,
                      baseCount: _baseCount,
                      canvasW: widget.project.settings.width.toDouble(),
                      canvasH: widget.project.settings.height.toDouble(),
                    ),
                  ),
              ),
            ),
            const SizedBox(height: 8),
            // Progress bar
            Slider(
              value: _progress.clamp(0, total).toDouble(),
              min: 0,
              max: total > 0 ? total.toDouble() : 1,
              onChanged: _seekTo,
            ),
            // Controls row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Speed buttons
                ..._speeds.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text('${s}x', style: const TextStyle(fontSize: 11)),
                    selected: _speed == s,
                    onSelected: (v) {
                      setState(() => _speed = s);
                      if (_finished) {
                        _restartFromStart();
                      } else if (_timer == null && !_paused) {
                        _startTimer();
                      }
                    },
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                )),
                const SizedBox(width: 12),
                // Pause/Play
                IconButton(
                  icon: Icon(
                    _paused || _finished ? Icons.play_arrow : Icons.pause,
                    size: 24,
                  ),
                  onPressed: _togglePause,
                ),
                const SizedBox(width: 8),
                Text('$_visibleCount / $total', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            // Close button
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('dialog.close'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayPainter extends CustomPainter {
  final List<Drawable> drawables;
  final int visibleCount;
  final ui.Image? baseImage;
  final int baseCount;
  final double canvasW;
  final double canvasH;

  _ReplayPainter({
    required this.drawables,
    required this.visibleCount,
    this.baseImage,
    this.baseCount = 0,
    required this.canvasW,
    required this.canvasH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / (canvasW > 0 ? canvasW : 1);
    final scaleY = size.height / (canvasH > 0 ? canvasH : 1);
    canvas.save();
    canvas.scale(min(scaleX, scaleY));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint()..color = Colors.white,
    );
    // Blit the baked prefix image, then draw only the strokes added since
    // the last bake. Falls back to drawing everything live when the cache
    // is unavailable.
    final useBase = baseImage != null && baseCount > 0 && baseCount <= visibleCount;
    if (useBase) {
      canvas.drawImage(baseImage!, Offset.zero, Paint());
      for (int i = baseCount; i < drawables.length && i < visibleCount; i++) {
        drawables[i].draw(canvas, Paint());
      }
    } else {
      for (int i = 0; i < drawables.length && i < visibleCount; i++) {
        drawables[i].draw(canvas, Paint());
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReplayPainter old) =>
      old.visibleCount != visibleCount ||
      old.baseImage != baseImage ||
      old.baseCount != baseCount;
}
