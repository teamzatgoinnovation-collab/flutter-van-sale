import '../../core/widgets/entity_thumb.dart';
import 'package:flutter/material.dart';

/// Product thumbnail — thin wrapper over shared [EntityThumb].
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.path,
    this.size = 48,
    this.radius = 8,
  });

  final String? path;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return EntityThumb(
      path: path,
      size: size,
      radius: radius,
      fallbackIcon: Icons.inventory_2_outlined,
    );
  }
}
