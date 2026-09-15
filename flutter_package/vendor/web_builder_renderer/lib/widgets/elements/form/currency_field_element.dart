import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/page_element.dart';
import '../../../design/palette.dart';
import '../../../design/tokens.dart';
import '../element_renderer.dart';
import '_form_field_shell.dart';
import 'form_scope.dart';

/// Currency input — number field with a read-only currency-symbol prefix
/// and digits + single-decimal restriction. Currency code from
/// `config['currency']` (e.g. "USD", "EUR"); symbol mapped from a small
/// built-in lookup with USD as the fallback. Reports raw numeric string
/// to the FormScope; downstream consumers handle formatting.
class CurrencyFieldElement extends StatelessWidget {
  final PageElement element;
  final RenderMode mode;

  const CurrencyFieldElement({
    super.key,
    required this.element,
    required this.mode,
  });

  static const _symbols = <String, String>{
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'INR': '₹',
    'CAD': r'C$',
    'AUD': r'A$',
  };

  @override
  Widget build(BuildContext context) {
    final label = element.config['label'] as String? ?? 'Amount';
    final placeholder =
        element.config['placeholder'] as String? ?? '0.00';
    final required = element.config['required'] as bool? ?? false;
    final code = (element.config['currency'] as String? ?? 'USD').toUpperCase();
    final symbol = _symbols[code] ?? code;
    final interactive = mode != RenderMode.builder;

    return FormFieldShell(
      label: label,
      required: required,
      child: TextField(
        enabled: interactive,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: false),
        // digits + single decimal point, max two fractional digits.
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          TextInputFormatter.withFunction((old, next) {
            // Reject more than one decimal separator.
            if (next.text.indexOf('.') != next.text.lastIndexOf('.')) {
              return old;
            }
            // Cap to two fractional digits.
            final dot = next.text.indexOf('.');
            if (dot >= 0 && next.text.length - dot - 1 > 2) return old;
            return next;
          }),
        ],
        decoration: InputDecoration(
          hintText: placeholder,
          prefixText: '$symbol ',
          prefixStyle: GoogleFonts.inter(
            fontSize: OTokens.textSm,
            color: OPaletteScope.of(context).textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        onChanged: (v) =>
            FormScope.maybeOf(context)?.report(element.id, v),
      ),
    );
  }
}
