import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/project_provider.dart';

/// Floating zoom control bar positioned at the bottom‑right of the canvas
/// area. Shows zoom percentage, fit‑to‑screen, and 1:1 buttons.
class CanvasZoomOverlay extends StatelessWidget {
  const CanvasZoomOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<CanvasProvider>();
    final theme = Theme.of(context);
    final pct = '${(cp.scale * 100).round()}%';

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _zoomBtn(Icons.remove, 'menu.view.zoom_out'.tr(), cp.zoomOut),
              _zoomBtn(Icons.fit_screen, 'menu.view.fit_screen'.tr(), () {
                final pp = context.read<ProjectProvider>();
                final project = pp.currentProject;
                if (project != null) {
                  cp.fitToScreen(
                    MediaQuery.of(context).size.width,
                    MediaQuery.of(context).size.height,
                    project.settings.width.toDouble(),
                    project.settings.height.toDouble(),
                  );
                }
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: InkWell(
                  onTap: cp.resetView,
                  borderRadius: BorderRadius.circular(4),
                  child: Text(
                    pct,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              _zoomBtn(Icons.add, 'menu.view.zoom_in'.tr(), cp.zoomIn),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zoomBtn(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}