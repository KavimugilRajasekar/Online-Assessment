import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;

  const ApiException(this.statusCode, this.message, {this.body});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Singleton HTTP client that persists the Django session cookie.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final Map<String, String> _cookies = {};

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      };

  void _updateCookies(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) return;
    // Parse multiple Set-Cookie values (they may be comma-separated or single)
    for (final part in setCookie.split(',')) {
      final cookiePart = part.trim().split(';').first.trim();
      final eqIdx = cookiePart.indexOf('=');
      if (eqIdx > 0) {
        final key = cookiePart.substring(0, eqIdx).trim();
        final value = cookiePart.substring(eqIdx + 1).trim();
        _cookies[key] = value;
      }
    }
  }

  Uri _uri(String path) => Uri.parse('$kApiBase$path');

  Future<dynamic> get(String path) async {
    final resp = await http.get(_uri(path), headers: _headers);
    _updateCookies(resp);
    return _handleResponse(resp);
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final resp = await http.post(
      _uri(path),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    _updateCookies(resp);
    return _handleResponse(resp);
  }

  dynamic _handleResponse(http.Response resp) {
    if (resp.statusCode == 204) return null;
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return null;
      return jsonDecode(resp.body);
    }
    // Error
    Map<String, dynamic>? errorBody;
    try { errorBody = jsonDecode(resp.body) as Map<String, dynamic>; } catch (_) {}
    final msg = errorBody?['detail'] ?? resp.reasonPhrase ?? 'Unknown error';
    throw ApiException(resp.statusCode, msg.toString(), body: errorBody);
  }
}
