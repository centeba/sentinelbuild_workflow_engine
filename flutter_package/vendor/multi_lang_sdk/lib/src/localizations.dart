import 'package:flutter/widgets.dart';

class MultiLangLocalizations {
  final Map<String, dynamic> _localizedStrings;

  MultiLangLocalizations(this._localizedStrings);

  static MultiLangLocalizations? of(BuildContext context) {
    return Localizations.of<MultiLangLocalizations>(context, MultiLangLocalizations);
  }

  String translate(String key) {
    final keys = key.split('.');
    dynamic current = _localizedStrings;

    for (final k in keys) {
      if (current is Map<String, dynamic> && current.containsKey(k)) {
        current = current[k];
      } else {
        return key; // Return the key if translation is missing
      }
    }
    
    return current?.toString() ?? key;
  }
}
