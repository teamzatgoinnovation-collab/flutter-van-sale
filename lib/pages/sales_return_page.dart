import 'package:flutter/material.dart';

import '../widgets/widgets.dart';

/// UI placeholder for the Sales Return workflow — no return functionality
/// exists in the backend/repo layer yet. This exists so the quick-actions
/// grid has a real destination instead of a dead tile; wire up the actual
/// return flow (product/qty selection, refund handling) once the backend
/// API for it exists.
class SalesReturnPage extends StatelessWidget {
  const SalesReturnPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Sales Return',
      subtitle: 'Coming soon',
      child: const EmptyHint(
        'Sales return isn\'t available yet — check back once this is '
        'wired up on the backend.',
        icon: Icons.assignment_return_outlined,
      ),
    );
  }
}
