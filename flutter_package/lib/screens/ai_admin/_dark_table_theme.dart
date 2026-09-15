import 'package:flutter/material.dart';

import '../../theme.dart';

/// Wrap a ``PaginatedDataTable`` so its internal ``Card`` + heading
/// row pick up the AI-Admin dark palette.
///
/// Why this exists: ``PaginatedDataTable`` reaches for
/// ``Theme.of(context).cardColor`` to paint its outer Material, and
/// ``Theme.of(context).dataTableTheme`` for the row/header colours.
/// Both default to light values in this app's theme, so the table
/// renders white text on white background otherwise. Overriding here
/// keeps the rest of the page (which DOES want the dark page bg) free
/// of theme inheritance side-effects.
Widget darkenedTable({required Widget child}) {
  return Builder(
    builder: (context) {
      final base = Theme.of(context);
      final headingColor = WidgetStateProperty.all<Color>(AppTheme.bgSurface);
      final dataColor = WidgetStateProperty.all<Color>(AppTheme.bgSurface);
      return Theme(
        data: base.copyWith(
          cardColor: AppTheme.bgSurface,
          cardTheme: base.cardTheme.copyWith(color: AppTheme.bgSurface),
          dataTableTheme: base.dataTableTheme.copyWith(
            headingRowColor: headingColor,
            dataRowColor: dataColor,
            // Divider between heading + body rows; subtle but distinct
            // against the dark surface.
            dividerThickness: 0.5,
          ),
          dividerColor: AppTheme.bgRaised,
          // ── Pagination footer + icons ───────────────────────────
          // PaginatedDataTable's footer (rows-per-page dropdown,
          // "X-Y of Z" text, first/prev/next/last arrows) inherits
          // its colors from ``colorScheme.onSurface`` /
          // ``colorScheme.onSurfaceVariant`` and ``iconTheme.color``.
          // Without these overrides the controls render dark-on-dark
          // against ``cardColor=bgSurface`` and look invisible — the
          // pagination IS there, you just can't see it. Override the
          // surface/onSurface pair plus the icon theme so the footer
          // reads cleanly.
          colorScheme: base.colorScheme.copyWith(
            surface: AppTheme.bgSurface,
            onSurface: AppTheme.textBright,
            onSurfaceVariant: AppTheme.textSecondary,
          ),
          iconTheme: base.iconTheme.copyWith(color: AppTheme.textSecondary),
          // The dropdown menu shown when the user clicks
          // "Rows per page" lives in its own popup card; theme it
          // dark too so it doesn't pop out as a white sheet.
          dropdownMenuTheme: base.dropdownMenuTheme.copyWith(
            menuStyle: MenuStyle(
              backgroundColor:
                  WidgetStateProperty.all<Color>(AppTheme.bgRaised),
            ),
          ),
          popupMenuTheme: base.popupMenuTheme.copyWith(
            color: AppTheme.bgRaised,
            textStyle: const TextStyle(color: AppTheme.textBright),
          ),
        ),
        child: child,
      );
    },
  );
}
