import 'package:flutter/material.dart';

import '../services/aging_service.dart';
import 'widgets.dart';

class AgingSummaryCard extends StatelessWidget {
  const AgingSummaryCard({super.key, required this.summary, this.onOpenDetail});

  final AgingSummary summary;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = summary.buckets;
    return Card(
      child: InkWell(
        onTap: onOpenDetail,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Receivables aging',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (summary.fromCache)
                    Text(
                      'Cached',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (onOpenDetail != null)
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                summary.asOf.isEmpty
                    ? 'Outstanding AR'
                    : 'As of ${summary.asOf}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Total',
                      value: money(b.total),
                      emphasize: true,
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: 'Overdue',
                      value: money(b.overdue),
                      color: theme.colorScheme.error,
                    ),
                  ),
                  Expanded(
                    child: _Metric(label: 'Current', value: money(b.current)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _BucketChip(label: '1–30', amount: b.d130),
                  _BucketChip(label: '31–60', amount: b.d3160),
                  _BucketChip(label: '61–90', amount: b.d6190),
                  _BucketChip(label: '91–120', amount: b.d91120),
                  _BucketChip(label: '120+', amount: b.d120Plus),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.color,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label ${money(amount)}',
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}
