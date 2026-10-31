import 'dart:convert';

import 'models.dart';
import 'password_crypt.dart';
import 'storytel_http.dart';

const _loginUrl = 'https://www.storytel.com/api/login.action';
const _bookshelfUrl = 'https://api.storytel.net/libraries/bookshelf';
const _bookmarksUrl = 'https://api.storytel.net/bookmarks/positional';

class StorytelClient {
  StorytelClient(
    this._http, {
    this.onCredentialsRejected,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final StorytelHttp _http;
  final void Function()? onCredentialsRejected;
  final DateTime Function() _clock;

  String? _email;
  String? _encryptedPassword;
  String? _jwt;
  Future<void>? _pendingLogin;

  Future<StorytelCredentials> login(String email, String password) async {
    final trimmedEmail = email.trim();
    final encrypted = encryptPassword(password.trim());
    final jwt = await _requestJwt(trimmedEmail, encrypted);
    _email = trimmedEmail;
    _encryptedPassword = encrypted;
    _jwt = jwt;
    return StorytelCredentials(
      email: trimmedEmail,
      encryptedPassword: encrypted,
    );
  }

  void restore(StorytelCredentials c) {
    _email = c.email;
    _encryptedPassword = c.encryptedPassword;
    _jwt = null;
  }

  Future<String> _requestJwt(String email, String encryptedPassword) async {
    final res = await _http.send(
      url: _loginUrl,
      query: {'m': '1', 'uid': email, 'pwd': encryptedPassword},
    );
    final data = res.data;
    final info = data is Map ? data['accountInfo'] : null;
    final jwt = info is Map ? info['jwt'] : null;
    if (jwt is! String || jwt.isEmpty) throw StorytelLoginException();
    return jwt;
  }

  /// Re-login with the stored credentials; concurrent callers share one call.
  Future<void> _refreshLogin() {
    final email = _email;
    final password = _encryptedPassword;
    if (email == null || password == null) {
      throw StorytelAuthException(null, isLoginFailure: true);
    }
    return _pendingLogin ??= () async {
      try {
        _jwt = await _requestJwt(email, password);
      } on StorytelAuthException {
        onCredentialsRejected?.call();
        rethrow;
      }
    }().whenComplete(() => _pendingLogin = null);
  }

  /// Seconds-since-epoch `exp` of the jwt, or null when unreadable.
  int? _expiry(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map ? payload['exp'] : null;
      return exp is num ? exp.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _bearer() async {
    final jwt = _jwt;
    if (jwt != null) {
      final exp = _expiry(jwt);
      final nowSec = _clock().millisecondsSinceEpoch ~/ 1000;
      if (exp == null || exp - 60 > nowSec) return jwt;
    }
    await _refreshLogin();
    return _jwt!;
  }

  Future<StorytelResponse> _authed({
    String method = 'GET',
    required String url,
    Map<String, String>? query,
    Map<String, String>? headers,
    String? formBody,
    Object? jsonBody,
  }) async {
    Future<StorytelResponse> attempt(String bearer) => _http.send(
      method: method,
      url: url,
      query: query,
      headers: {...?headers, 'authorization': 'Bearer $bearer'},
      formBody: formBody,
      jsonBody: jsonBody,
    );

    // Resolved outside the try: a login rejection while obtaining the bearer
    // must reach the caller as is, never trigger another login.
    final first = await _bearer();
    try {
      return await attempt(first);
    } on StorytelAuthException catch (e) {
      if (e.isLoginFailure || _email == null || _encryptedPassword == null) {
        rethrow;
      }
      try {
        await _refreshLogin();
      } on StorytelAuthException {
        // A rejected re-login still means "session expired" to the caller.
        throw StorytelAuthException(e.data);
      }
      return attempt(_jwt!);
    }
  }

  Future<List<ShelfBook>> bookshelf() async {
    final res = await _authed(
      method: 'POST',
      url: _bookshelfUrl,
      headers: {'accept': '*/*'},
      formBody: '',
    );
    final data = res.data;
    final items = data is Map ? data['items'] : null;
    if (items is! Map) return [];
    final books = <ShelfBook>[];
    for (final entry in items.values) {
      final model = entry is Map ? entry['model'] : null;
      if (model is! Map) continue;
      final formats = model['formats'];
      final abook = formats is List
          ? formats.whereType<Map>().cast<Map?>().firstWhere(
              (f) => f?['type'] == 'abook',
              orElse: () => null,
            )
          : null;
      if (abook == null) continue;
      final position = abook['position'];
      final authors = model['authors'];
      books.add(
        ShelfBook(
          consumableId: '${model['id']}',
          title: (model['title'] as String?) ?? '',
          authors: authors is List
              ? authors
                    .whereType<Map>()
                    .map((a) => a['name'])
                    .whereType<String>()
                    .where((n) => n.isNotEmpty)
                    .join(', ')
              : '',
          kidsBook: model['kidsBook'] == true,
          coverUrl: (abook['cover'] as Map?)?['url'] as String?,
          durationMs: (abook['durationInMilliseconds'] as num?)?.toInt() ?? 0,
          positionMs: position is Map
              ? (position['position'] as num?)?.toInt()
              : null,
          positionUpdatedTime: position is Map
              ? _parseDate(position['updatedTime'])
              : null,
          stateUpdateTime: _parseDate(model['stateUpdateTime']),
        ),
      );
    }
    return books;
  }

  Future<String> streamUrl(String consumableId) async {
    final res = await _authed(
      url: 'https://api.storytel.net/assets/v2/consumables/$consumableId/abook',
      headers: {'accept': '*/*'},
    );
    final location = res.headers['location'];
    if (location == null || location.isEmpty) {
      throw StorytelHttpException(res.status, null);
    }
    return location;
  }

  Future<RemotePosition?> readPosition(String consumableId) async {
    final res = await _authed(
      url: _bookmarksUrl,
      query: {
        'kidsMode': 'false',
        'orderBy': 'updated',
        'orderDirection': 'desc',
        'consumableIds': consumableId,
      },
    );
    final data = res.data;
    final bookmarks = data is Map ? data['bookmarks'] : null;
    if (bookmarks is! List) return null;
    for (final b in bookmarks) {
      if (b is Map && b['type'] == 'abook' && b['position'] is num) {
        return RemotePosition(
          (b['position'] as num).toInt(),
          _parseDate(b['updatedTime']),
        );
      }
    }
    return null;
  }

  Future<void> writePosition(
    String consumableId,
    int positionMs,
    String deviceId,
  ) async {
    await _authed(
      method: 'POST',
      url: _bookmarksUrl,
      jsonBody: {
        'deviceId': deviceId,
        'action': 'player_paused',
        'secondsSinceCreated': 0,
        'position': positionMs,
        'type': 'abook',
        'kidsMode': false,
        'consumableId': consumableId,
      },
    );
  }
}

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
