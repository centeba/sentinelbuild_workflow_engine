import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin client over the multi-lang service.
///
/// Phase L1: degrades gracefully when the namespace/locale combination
/// is missing or the service is unreachable. Returning ``{}`` lets
/// the host app render with the source-code key strings instead of
/// crashing the whole UI.
class MultiLangApiClient {
  final String baseUrl;

  MultiLangApiClient({required this.baseUrl});

  Future<Map<String, dynamic>> fetchTranslations(
    String namespace, {
    required String locale,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/translations/$namespace').replace(
      queryParameters: {'locale': locale},
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map && body['data'] is Map) {
          return Map<String, dynamic>.from(body['data'] as Map);
        }
        return const {};
      }
      return const {};
    } catch (_) {
      return const {};
    }
  }
}
