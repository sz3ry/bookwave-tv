import 'dart:convert';

import 'package:bookwave_tv/storytel/storytel_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.BaseRequest captured;
  StorytelHttp make(http.Response Function(http.Request) handler) {
    return StorytelHttp(
      MockClient((req) async {
        captured = req;
        return handler(req);
      }),
    );
  }

  test('sends base headers and version', () async {
    final h = make((_) => http.Response('{}', 200));
    await h.send(url: 'https://api.test/x', query: {'a': 'b'});
    expect(captured.headers['x-storytel-terminal'], 'ios');
    expect(
      captured.headers['user-agent'],
      'Storytel/25.38.0 (iOS 26.0; iPhone16,2) Release/924.1',
    );
    expect(captured.headers['accept'], 'application/json, text/plain, */*');
    expect(captured.url.queryParameters['version'], '25.38.0');
    expect(captured.url.queryParameters['a'], 'b');
  });

  test('caller headers override defaults', () async {
    final h = make((_) => http.Response('{}', 200));
    await h.send(url: 'https://api.test/x', headers: {'Accept': '*/*'});
    expect(captured.headers['accept'], '*/*');
  });

  test('form and json bodies', () async {
    final h = make((_) => http.Response('{}', 200));
    await h.send(method: 'POST', url: 'https://api.test/x', formBody: '');
    expect(
      captured.headers['content-type'],
      startsWith('application/x-www-form-urlencoded'),
    );
    expect((captured as http.Request).body, '');
    await h.send(method: 'POST', url: 'https://api.test/x', jsonBody: {'a': 1});
    expect(captured.headers['content-type'], startsWith('application/json'));
    expect((captured as http.Request).body, '{"a":1}');
  });

  test('does not follow redirects', () async {
    final h = make(
      (_) => http.Response('', 302, headers: {'location': 'https://cdn/x.mp3'}),
    );
    final r = await h.send(url: 'https://api.test/x');
    expect(captured.followRedirects, false);
    expect(r.status, 302);
    expect(r.headers['location'], 'https://cdn/x.mp3');
  });

  test('parses json with wrong content-type', () async {
    final h = make(
      (_) => http.Response(
        '{"a":1}',
        200,
        headers: {'content-type': 'text/plain'},
      ),
    );
    final r = await h.send(url: 'https://api.test/x');
    expect(r.data, {'a': 1});
  });

  test('error statuses', () async {
    var h = make((_) => http.Response('{}', 401));
    await expectLater(
      h.send(url: 'https://api.test/x'),
      throwsA(
        isA<StorytelAuthException>().having(
          (e) => e.isLoginFailure,
          'isLoginFailure',
          false,
        ),
      ),
    );
    await expectLater(
      h.send(url: 'https://api.test/login.action'),
      throwsA(
        isA<StorytelAuthException>().having(
          (e) => e.isLoginFailure,
          'isLoginFailure',
          true,
        ),
      ),
    );
    h = make((_) => http.Response('x', 500));
    await expectLater(
      h.send(url: 'https://api.test/x'),
      throwsA(
        isA<StorytelHttpException>().having((e) => e.status, 'status', 500),
      ),
    );
  });

  test('decodes bodies as UTF-8 even without a charset', () async {
    final h = make(
      (_) => http.Response.bytes(
        utf8.encode('{"title":"Dzieci z Bullerbyn – Łódź"}'),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final res = await h.send(url: 'https://api.test/x');
    expect((res.data as Map)['title'], 'Dzieci z Bullerbyn – Łódź');
  });

  test('decodes UTF-8 for a content-type that defaults to latin1', () async {
    final h = make(
      (_) => http.Response.bytes(
        utf8.encode('{"title":"Dzieci z Bullerbyn – Łódź"}'),
        200,
        headers: {'content-type': 'text/json'},
      ),
    );
    final res = await h.send(url: 'https://api.test/x');
    expect((res.data as Map)['title'], 'Dzieci z Bullerbyn – Łódź');
  });
}
