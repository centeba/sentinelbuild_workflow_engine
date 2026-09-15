import '../../models/page_element.dart';

class PaletteDrag {
  final PageElementType type;
  final Map<String, dynamic> defaultConfig;

  const PaletteDrag({
    required this.type,
    this.defaultConfig = const {},
  });
}

class CanvasDrag {
  final String elementId;
  const CanvasDrag({required this.elementId});
}
