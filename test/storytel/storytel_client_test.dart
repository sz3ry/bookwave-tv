import 'dart:convert';
import 'dart:io';

import 'package:bookwave_tv/storytel/models.dart';
import 'package:bookwave_tv/storytel/storytel_client.dart';
import 'package:bookwave_tv/storytel/storytel_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String jwt({required int exp}) {
  String enc(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${enc({'alg': 'none'})}.${enc({'exp': exp})}.sig';
}

int nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

http.Response loginOk(String token) => http.Response(
  jsonEncode({
    'accountInfo': {'jwt': token},
  }),
  200,
);

http.Response shelfResponse() => http.Response.bytes(
  utf8.encode(File('test/fixtures/bookshelf.json').readAsStringSync()),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  late List<http.Request> requests;
  late int logins;
  late String nextJwt;

  /// Routes login.action itself; [handler] answers everything else.
  StorytelClient make(
    http.Response Function(http.Request) handler, {
    void Function()? onRejected,
    http.Response Function(http.Request)? loginHandler,
  }) {
    requests = [];
    logins = 0;
    nextJwt = jwt(exp: nowSec() + 3600);
    return StorytelClient(
      StorytelHttp(
        MockClient((req) async {
          requests.add(req);
          if (req.url.path.endsWith('login.action')) {
            logins++;
            return loginHandler != null ? loginHandler(req) : loginOk(nextJwt);
          }
          return handler(req);
        }),
      ),
      onCredentialsRejected: onRejected,
    );
  }

  final creds = StorytelCredentials(email: 'a@b.c', encryptedPassword: 'ENC');

  test('login sends m, uid, encrypted pwd', () async {
    final c = make((_) => http.Response('{}', 200));
    final result = await c.login('a@b.c', 'secret');
    final req = requests.single;
    expect(req.method, 'GET');
    expect(
      req.url.origin + req.url.path,
      'https://www.storytel.com/api/login.action',
    );
    expect(req.url.queryParameters['m'], '1');
    expect(req.url.queryParameters['uid'], 'a@b.c');
    expect(req.url.queryParameters['pwd'], 'EA28CEC50BCD4410067D143BA5FC8885');
    expect(result.email, 'a@b.c');
    expect(result.encryptedPassword, 'EA28CEC50BCD4410067D143BA5FC8885');
  });

  test('login without jwt throws StorytelLoginException', () async {
    final c = make(
      (_) => http.Response('{}', 200),
      loginHandler: (_) => http.Response('{"accountInfo":{}}', 200),
    );
    expect(c.login('a@b.c', 'secret'), throwsA(isA<StorytelLoginException>()));
  });

  test('login 401 throws StorytelAuthException(isLoginFailure)', () async {
    final c = make(
      (_) => http.Response('{}', 200),
      loginHandler: (_) => http.Response('nope', 401),
    );
    expect(
      c.login('a@b.c', 'bad'),
      throwsA(
        isA<StorytelAuthException>().having(
          (e) => e.isLoginFailure,
          'isLoginFailure',
          true,
        ),
      ),
    );
  });

  test('bookshelf posts empty form and maps abooks', () async {
    final c = make((_) => shelfResponse());
    nextJwt = 'JWT1';
    await c.login('a@b.c', 'secret');
    final books = await c.bookshelf();
    final req = requests.last;
    expect(req.method, 'POST');
    expect(
      req.url.origin + req.url.path,
      'https://api.storytel.net/libraries/bookshelf',
    );
    expect(req.headers['authorization'], 'Bearer JWT1');
    expect(req.headers['accept'], '*/*');
    expect(req.body, '');

    expect(books, hasLength(2));
    final a = books[0];
    expect(a.consumableId, '42');
    expect(a.title, 'Dzieci z Bullerbyn – Łódź');
    expect(a.authors, 'Astrid Lindgren, Jan Kowalski');
    expect(a.kidsBook, true);
    expect(a.coverUrl, 'https://cdn/abook42.jpg');
    expect(a.durationMs, 3600000);
    expect(a.positionMs, 120000);
    expect(a.positionUpdatedTime, DateTime.utc(2026, 10, 30, 20));
    expect(a.stateUpdateTime, DateTime.utc(2026, 10, 29, 10));
    final b = books[1];
    expect(b.consumableId, '43');
    expect(b.kidsBook, false);
    expect(b.positionMs, isNull);
    expect(b.positionUpdatedTime, isNull);
    expect(b.durationMs, 7200000);

    final round = ShelfBook.fromJson(a.toJson());
    expect(round.title, a.title);
    expect(round.positionUpdatedTime, a.positionUpdatedTime);
  });

  test('streamUrl returns location', () async {
    final c = make(
      (_) => http.Response('', 302, headers: {'location': 'https://cdn/x.mp3'}),
    );
    await c.login('a@b.c', 'secret');
    expect(await c.streamUrl('42'), 'https://cdn/x.mp3');
    expect(
      requests.last.url.origin + requests.last.url.path,
      'https://api.storytel.net/assets/v2/consumables/42/abook',
    );
    expect(requests.last.headers['accept'], '*/*');
  });

  test('streamUrl without location throws', () async {
    final c = make((_) => http.Response('', 200));
    await c.login('a@b.c', 'secret');
    expect(c.streamUrl('42'), throwsA(isA<StorytelHttpException>()));
  });

  test('readPosition picks abook entry', () async {
    final c = make(
      (_) => http.Response(
        jsonEncode({
          'bookmarks': [
            {'type': 'ebook', 'position': 5},
            {
              'type': 'abook',
              'position': 120000,
              'updatedTime': '2026-10-30T20:00:00Z',
            },
          ],
        }),
        200,
      ),
    );
    await c.login('a@b.c', 'secret');
    final p = await c.readPosition('42');
    expect(p!.positionMs, 120000);
    expect(p.updatedTime, DateTime.utc(2026, 10, 30, 20));
    final q = requests.last.url;
    expect(q.origin + q.path, 'https://api.storytel.net/bookmarks/positional');
    expect(q.queryParameters['kidsMode'], 'false');
    expect(q.queryParameters['orderBy'], 'updated');
    expect(q.queryParameters['orderDirection'], 'desc');
    expect(q.queryParameters['consumableIds'], '42');
  });

  test('readPosition without abook returns null', () async {
    final c = make(
      (_) => http.Response(
        jsonEncode({
          'bookmarks': [
            {'type': 'ebook', 'position': 5},
          ],
        }),
        200,
      ),
    );
    await c.login('a@b.c', 'secret');
    expect(await c.readPosition('42'), isNull);
  });

  test('writePosition body', () async {
    final c = make((_) => http.Response('{}', 200));
    await c.login('a@b.c', 'secret');
    await c.writePosition('42', 120000, 'DEV');
    final req = requests.last;
    expect(req.method, 'POST');
    expect(
      req.url.origin + req.url.path,
      'https://api.storytel.net/bookmarks/positional',
    );
    expect(jsonDecode(req.body), {
      'deviceId': 'DEV',
      'action': 'player_paused',
      'secondsSinceCreated': 0,
      'position': 120000,
      'type': 'abook',
      'kidsMode': false,
      'consumableId': '42',
    });
  });

  test('401 triggers one re-login and retry', () async {
    var shelfCalls = 0;
    final c = make((req) {
      shelfCalls++;
      return shelfCalls == 1 ? http.Response('expired', 401) : shelfResponse();
    });
    await c.login('a@b.c', 'secret');
    expect(logins, 1);
    nextJwt = 'FRESH';
    final books = await c.bookshelf();
    expect(books, hasLength(2));
    expect(logins, 2);
    expect(shelfCalls, 2);
    expect(requests.last.headers['authorization'], 'Bearer FRESH');
  });

  test('restored client logs in on first request', () async {
    final c = make((_) => shelfResponse());
    c.restore(creds);
    await c.bookshelf();
    expect(logins, 1);
    expect(requests.first.url.queryParameters['pwd'], 'ENC');
  });

  test('expired jwt triggers one re-login', () async {
    final c = make((_) => shelfResponse());
    nextJwt = jwt(exp: nowSec() + 30);
    await c.login('a@b.c', 'secret');
    expect(logins, 1);
    nextJwt = jwt(exp: nowSec() + 3600);
    await c.bookshelf();
    expect(logins, 2);
    await c.bookshelf();
    expect(logins, 2);
  });

  test('concurrent requests share one login', () async {
    final c = make((_) => shelfResponse());
    c.restore(creds);
    await Future.wait([c.bookshelf(), c.bookshelf()]);
    expect(logins, 1);
  });

  test('rejected re-login calls onCredentialsRejected and throws', () async {
    var rejected = 0;
    var loginCall = 0;
    final c = make(
      (_) => http.Response('expired', 401),
      onRejected: () => rejected++,
      loginHandler: (_) =>
          ++loginCall == 1 ? loginOk('J') : http.Response('no', 401),
    );
    await c.login('a@b.c', 'secret');
    await expectLater(c.bookshelf(), throwsA(isA<StorytelAuthException>()));
    expect(rejected, 1);
  });

  test('second 401 after re-login is thrown', () async {
    var shelfCalls = 0;
    final c = make((_) {
      shelfCalls++;
      return http.Response('expired', 401);
    });
    await c.login('a@b.c', 'secret');
    await expectLater(c.bookshelf(), throwsA(isA<StorytelAuthException>()));
    expect(shelfCalls, 2);
    expect(logins, 2);
  });
}
