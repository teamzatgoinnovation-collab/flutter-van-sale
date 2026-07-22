import 'dart:io';

import 'package:flutter/material.dart';

/// Cached entity thumbnail (local file or network URL).
class EntityThumb extends StatelessWidget {
  const EntityThumb({
    super.key,
    required this.path,
    this.size = 48,
    this.radius = 8,
    this.fallbackIcon = Icons.image_outlined,
  });

  final String? path;
  final double size;
  final double radius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = path?.trim() ?? '';
    Widget child;
    if (p.isEmpty) {
      child = Icon(fallbackIcon, color: scheme.onSurfaceVariant);
    } else if (p.startsWith('http://') || p.startsWith('https://')) {
      child = Image.network(
        p,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, error, stack) =>
            Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
      );
    } else {
      final file = File(p);
      child = file.existsSync()
          ? Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, error, stack) => Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            )
          : Icon(fallbackIcon, color: scheme.onSurfaceVariant);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }
}
