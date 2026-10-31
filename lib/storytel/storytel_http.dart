import 'dart:convert';

import 'package:http/http.dart' as http;

const storytelAppVersion = '25.38.0';

const storytelBaseHeaders = <String, String>{
  'x-storytel-terminal': 'ios',
  'user-agent': 'Storytel/25.38.0 (iOS 26.0; iPhone16,2) Release/924.1',
  'accept': 'application/json, text/plain, */*',
};

class StorytelResponse {
  StorytelResponse(this.status, this.headers, this.data);

  final int status;
  final Map<String, String> headers;

  /// Parsed JSON when the body looks like JSON, else the raw string.
  final Object? data;
}

class StorytelHttpException implements Exception {
  StorytelHttpException(this.status, this.data);

  final int status;
  final Object? data;

  @override
  String toString() => 'StorytelHttpException: status $status';
}

class StorytelAuthException extends StorytelHttpException {
  StorytelAuthException(Object? data, {this.isLoginFailure = false})
    : super(401, data);

  final bool isLoginFailure;
}

Object? _parseBody(String text) {
  final trimmed = text.trim();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return text;
    }
  }
  return text;
}

class StorytelHttp {
  StorytelHttp(this._client);

  final http.Client _client;

  Future<StorytelResponse> send({
    String method = 'GET',
    required String url,
    Map<String, String>? query,
    Map<String, String>? headers,
    String? formBody,
    Object? jsonBody,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final base = Uri.parse(url);
    final uri = base.replace(
      queryParameters: {
        ...base.queryParameters,
        ...?query,
        'version': storytelAppVersion,
      },
    );

    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll(storytelBaseHeaders);
    // The request header map is case-insensitive, so this replaces defaults.
    request.headers.addAll(headers ?? const <String, String>{});
    if (formBody != null) {
      request.headers['content-type'] = 'application/x-www-form-urlencoded';
      request.body = formBody;
    } else if (jsonBody != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    }

    // Bodies of login.action replies carry tokens and are never logged here.
    final isLogin = uri.path.contains('login.action');
    final streamed = await _client.send(request).timeout(timeout);
    final res = await http.Response.fromStream(streamed).timeout(timeout);
    final data = _parseBody(res.body);

    if (res.statusCode == 401) {
      throw StorytelAuthException(
        isLogin ? null : data,
        isLoginFailure: isLogin,
      );
    }
    if (res.statusCode >= 400) {
      throw StorytelHttpException(res.statusCode, data);
    }
    return StorytelResponse(res.statusCode, res.headers, data);
  }
}
