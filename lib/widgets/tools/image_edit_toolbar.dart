import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/project_provider.dart';

class ImageEditToolbar extends StatelessWidget {
  const ImageEditToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pp = context.watch<ProjectProvider>();
    if (!pp.isPlacingImage) return const SizedBox.shrink();

    return Container(
      height: 40,
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _toolBtn(Icons.flip, 'Flip H', () {
            pp.updateImagePlacement(flipH: !pp.imagePlacingFlipH);
          }),
          const SizedBox(width: 8),
          _toolBtn(Icons.flip, 'Flip V', () {
            pp.updateImagePlacement(flipV: !pp.imagePlacingFlipV);
          }),
          const SizedBox(width: 8),
          _toolBtn(Icons.close, 'Cancel', () {
            pp.cancelImagePlacement();
          }),
          const SizedBox(width: 8),
          _toolBtn(Icons.check, 'Confirm', () {
            pp.confirmImagePlacement();
          }),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}