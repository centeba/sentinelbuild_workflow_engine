import 'package:flutter/material.dart';

import '../../i18n/translate_extension.dart';
import '../../theme.dart';

/// Pagination row rendered ABOVE the AI Admin tables.
///
/// We rolled this rather than using ``PaginatedDataTable`` because
/// that widget hard-codes its controls into a footer below the
/// rows, which puts them below the page fold on shorter viewports
/// and forces dark-mode contrast struggles. Top placement keeps
/// the controls in the same eye-line as the search box and table
/// header, in bright ``textBright`` so the row reads at a glance
/// against the dark surface.
class PaginationToolbar extends StatelessWidget {
  const PaginationToolbar({
    super.key,
    required this.rowCount,
    required this.pageIndex,
    required this.pageSize,
    required this.onFirst,
    required this.onPrev,
    required this.onNext,
    required this.onLast,
    required this.onPageSizeChange,
    this.availablePageSizes = const [10, 25, 50, 100],
  });

  final int rowCount;
  final int pageIndex;
  final int pageSize;
  final VoidCallback onFirst;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onLast;
  final ValueChanged<int> onPageSizeChange;
  final List<int> availablePageSizes;

  @override
  Widget build(BuildContext context) {
    final start = rowCount == 0 ? 0 : pageIndex * pageSize + 1;
    final end = ((pageIndex + 1) * pageSize).clamp(0, rowCount);
    final lastPage = rowCount == 0 ? 0 : (rowCount - 1) ~/ pageSize;
    final atFirst = pageIndex <= 0;
    final atLast = pageIndex >= lastPage;

    const labelStyle = TextStyle(color: AppTheme.textBright, fontSize: 12);
    const iconColor = AppTheme.textBright;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Text('Rows per page:', style: labelStyle),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: availablePageSizes.contains(pageSize)
                ? pageSize
                : availablePageSizes.first,
            dropdownColor: AppTheme.bgRaised,
            style: labelStyle,
            iconEnabledColor: iconColor,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: availablePageSizes
                .map((n) => DropdownMenuItem(
                      value: n,
                      child: Text('$n', style: labelStyle),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onPageSizeChange(v);
            },
          ),
          const SizedBox(width: 24),
          Text('$start–$end ${context.t('common.of_label')} $rowCount',
              style: labelStyle),
          const Spacer(),
          _NavIcon(
            icon: Icons.first_page,
            tooltip: context.t('pagination.first'),
            onPressed: atFirst ? null : onFirst,
            color: iconColor,
          ),
          _NavIcon(
            icon: Icons.chevron_left,
            tooltip: context.t('pagination.previous'),
            onPressed: atFirst ? null : onPrev,
            color: iconColor,
          ),
          _NavIcon(
            icon: Icons.chevron_right,
            tooltip: context.t('pagination.next'),
            onPressed: atLast ? null : onNext,
            color: iconColor,
          ),
          _NavIcon(
            icon: Icons.last_page,
            tooltip: context.t('pagination.last'),
            onPressed: atLast ? null : onLast,
            color: iconColor,
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      // Disabled state goes muted; enabled stays bright.
      color: onPressed == null ? AppTheme.textMuted : color,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
