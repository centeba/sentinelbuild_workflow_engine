// A page definition may carry a colour as a literal `#RRGGBB` or as a
// `token:<role>` reference resolved against the active palette. The token form
// is what lets published page content follow the brand and brightness instead
// of freezing one hex into the saved page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_builder_renderer/web_builder_renderer.dart';

void main() {
  final light = OPaletteData.fromPd(pdPalette(PdBrand.restoration, Brightness.light));
  final dark = OPaletteData.fromPd(pdPalette(PdBrand.restoration, Brightness.dark));

  test('a literal hex resolves to itself, whatever the palette', () {
    const style = ElementStyle(
      color: '#FF0000',
      backgroundColor: '#00FF00',
      borderColor: '#0000FF',
    );
    expect(style.resolvedColor(light), const Color(0xFFFF0000));
    expect(style.resolvedBackgroundColor(dark), const Color(0xFF00FF00));
    expect(style.resolvedBorderColor(dark), const Color(0xFF0000FF));
  });

  test('a token reference resolves against the palette it is given', () {
    const style = ElementStyle(
      color: 'token:textBright',
      backgroundColor: 'token:bgSurface',
      borderColor: 'token:borderSubtle',
    );
    expect(style.resolvedColor(light), light.textBright);
    expect(style.resolvedBackgroundColor(light), light.bgSurface);
    expect(style.resolvedBorderColor(light), light.borderSubtle);
  });

  test('the same token gives a different colour per brightness', () {
    const style = ElementStyle(color: 'token:textBright');
    expect(style.resolvedColor(light), isNot(style.resolvedColor(dark)));
    expect(style.resolvedColor(dark), dark.textBright);
  });

  test('status tints resolve, and invert between light and dark', () {
    const style = ElementStyle(backgroundColor: 'token:errorLight');
    expect(style.resolvedColor(light), isNull);
    expect(style.resolvedBackgroundColor(light), light.errorLight);
    expect(style.resolvedBackgroundColor(dark), dark.errorLight);
    // Light mode tints are pale, dark mode tints are deep.
    expect(light.errorLight.computeLuminance(),
        greaterThan(dark.errorLight.computeLuminance()));
  });

  test('an unset or unknown colour reads as "no colour"', () {
    const unset = ElementStyle();
    expect(unset.resolvedColor(light), isNull);
    const bogus = ElementStyle(color: 'token:notARole', borderColor: 'chartreuse');
    expect(bogus.resolvedColor(light), isNull);
    expect(bogus.resolvedBorderColor(light), isNull);
  });

  test('every role name the page definitions use is resolvable', () {
    // The roles emitted by the pages/ tokenisation. A typo here would silently
    // drop a colour on a published page, so pin the whole set.
    const used = [
      'bgSurface', 'bgRaised', 'bgHover',
      'infoLight', 'errorLight', 'warningLight', 'successLight',
      'borderSubtle',
      'textBright', 'textMuted', 'textSecondary',
      'neutralBlue', 'warningAmber', 'gainGreen', 'lossRed',
    ];
    for (final role in used) {
      expect(light.role(role), isNotNull, reason: '$role missing from OPaletteData');
      expect(dark.role(role), isNotNull, reason: '$role missing from OPaletteData');
    }
  });
}
