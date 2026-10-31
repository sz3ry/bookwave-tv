import 'dart:async';

import 'package:bookwave_tv/app_state.dart';
import 'package:bookwave_tv/storage/credentials_store.dart';
import 'package:bookwave_tv/storage/local_store.dart';
import 'package:bookwave_tv/storytel/models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class Setup {
  late FakeClient client;
  late FakeController controller;
  late CredentialsStore creds;
  late LocalStore local;
  late AppState state;

  static Future<Setup> create({
    bool withCredentials = true,
    ShelfBook? lastBook,
  }) async {
    FlutterSecureStorage.setMockInitialValues({
      if (withCredentials) 'storytel_email': 'a@b.pl',
      if (withCredentials) 'storytel_encrypted_password': 'ENC',
    });
    SharedPreferences.setMockInitialValues({});
    final s = Setup();
    s.client = FakeClient();
    s.controller = FakeController();
    s.creds = CredentialsStore(const FlutterSecureStorage());
    s.local = await LocalStore.open();
    if (lastBook != null) await s.local.setLastBook(lastBook);
    s.state = AppState(
      client: s.client,
      credentials: s.creds,
      store: s.local,
      controller: s.controller,
    );
    return s;
  }
}

void main() {
  test('start routes to login without credentials', () async {
    final s = await Setup.create(withCredentials: false);
    await s.state.start();
    expect(s.state.route, AppRoute.login);
  });

  test('start routes to player with last book', () async {
    final s = await Setup.create(lastBook: shelfBook('c1'));
    await s.state.start();
    expect(s.state.route, AppRoute.player);
    expect(s.controller.opened, ['c1']);
    expect(s.client.restored?.email, 'a@b.pl');
  });

  test('start routes to library without last book', () async {
    final s = await Setup.create();
    await s.state.start();
    expect(s.state.route, AppRoute.library);
    expect(s.controller.opened, isEmpty);
  });

  test('rejected credentials route to login and clear store', () async {
    final s = await Setup.create();
    await s.state.start();
    s.state.authRejected();
    await Future<void>.delayed(Duration.zero);
    expect(s.state.route, AppRoute.login);
    expect(await s.creds.read(), isNull);
  });

  test('login stores credentials and opens the library', () async {
    final s = await Setup.create(withCredentials: false);
    await s.state.start();
    await s.state.login('a@b.pl', 'pw');
    expect(s.state.route, AppRoute.library);
    expect((await s.creds.read())?.email, 'a@b.pl');
  });

  test('pickBook ignores a pick while a book is opening', () async {
    final s = await Setup.create();
    await s.state.start();
    final gate = s.controller.openGate = Completer<void>();
    final first = s.state.pickBook(shelfBook('c1'));
    await s.state.pickBook(shelfBook('c2'));
    gate.complete();
    await first;
    expect(s.controller.opened, ['c1']);
    expect(s.controller.maxConcurrentOpens, 1);
    expect(s.state.route, AppRoute.player);
  });

  test('failed open drops the book and falls back to the library', () async {
    final s = await Setup.create();
    await s.state.start();
    s.controller.openError = Exception('offline');
    await s.state.pickBook(shelfBook('c1'));
    expect(s.state.route, AppRoute.library);
    expect(s.controller.stops, 1);
    expect(s.controller.book, isNull);
    s.state.closeLibrary();
    expect(s.state.route, AppRoute.library);
  });

  test('closeLibrary only returns to the player with a book', () async {
    final s = await Setup.create();
    await s.state.start();
    s.state.closeLibrary();
    expect(s.state.route, AppRoute.library);
    await s.state.pickBook(shelfBook('c1'));
    s.state.openLibrary();
    expect(s.state.route, AppRoute.library);
    s.state.closeLibrary();
    expect(s.state.route, AppRoute.player);
  });

  test('logout stops playback, clears credentials, routes to login', () async {
    final s = await Setup.create();
    await s.state.start();
    await s.state.logout();
    expect(s.state.route, AppRoute.login);
    expect(s.controller.stops, greaterThan(0));
    expect(await s.creds.read(), isNull);
  });

  test('resume on the player without a book reopens the last book', () async {
    final s = await Setup.create(lastBook: shelfBook('c1'));
    await s.state.start();
    // The book was dropped while the app was in the background.
    await s.controller.stop();
    await s.state.resumed();
    expect(s.controller.opened, ['c1', 'c1']);
    expect(s.controller.book?.consumableId, 'c1');
    expect(s.state.route, AppRoute.player);
  });

  test('resume with a book loaded reopens nothing', () async {
    final s = await Setup.create(lastBook: shelfBook('c1'));
    await s.state.start();
    await s.state.resumed();
    s.state.openLibrary();
    await s.controller.stop();
    await s.state.resumed();
    expect(s.controller.opened, ['c1']);
  });

  test('start keeps the player and retries the last book while offline', () {
    late Setup s;
    fakeAsync((async) {
      Setup.create(lastBook: shelfBook('c1')).then((v) => s = v);
      async.flushMicrotasks();
      s.controller.openError = Exception('offline');
      s.state.start();
      async.flushMicrotasks();
      expect(s.state.route, AppRoute.player);
      expect(s.state.offline, isTrue);
      expect(s.controller.opened, ['c1']);
      s.controller.openError = Exception('still offline');
      final gate = s.controller.openGate = Completer<void>();
      async.elapse(const Duration(seconds: 10));
      expect(s.controller.opened, ['c1', 'c1']);
      // The no-connection state stays while the retry runs.
      expect(s.state.offline, isTrue);
      gate.complete();
      async.flushMicrotasks();
      expect(s.state.route, AppRoute.player);
      expect(s.state.offline, isTrue);
      async.elapse(const Duration(seconds: 10));
      expect(s.controller.opened, ['c1', 'c1', 'c1']);
      expect(s.state.route, AppRoute.player);
      expect(s.state.offline, isFalse);
      expect(s.controller.book?.consumableId, 'c1');
      async.elapse(const Duration(seconds: 30));
      expect(s.controller.opened, hasLength(3));
    });
  });

  test('opening the library cancels the offline retry', () {
    late Setup s;
    fakeAsync((async) {
      Setup.create(lastBook: shelfBook('c1')).then((v) => s = v);
      async.flushMicrotasks();
      s.controller.openError = Exception('offline');
      s.state.start();
      async.flushMicrotasks();
      s.state.openLibrary();
      expect(s.state.offline, isFalse);
      async.elapse(const Duration(seconds: 30));
      expect(s.controller.opened, ['c1']);
      expect(s.state.route, AppRoute.library);
    });
  });

  test('dispose cancels the offline retry', () {
    late Setup s;
    fakeAsync((async) {
      Setup.create(lastBook: shelfBook('c1')).then((v) => s = v);
      async.flushMicrotasks();
      s.controller.openError = Exception('offline');
      s.state.start();
      async.flushMicrotasks();
      s.state.dispose();
      async.elapse(const Duration(seconds: 30));
      expect(s.controller.opened, ['c1']);
    });
  });

  test(
    'picking the book already loaded returns to it without reopening',
    () async {
      final s = await Setup.create(lastBook: shelfBook('c1'));
      await s.state.start();
      s.state.openLibrary();
      await s.state.pickBook(shelfBook('c1'));
      expect(s.controller.opened, ['c1']);
      expect(s.controller.stops, 0);
      expect(s.state.route, AppRoute.player);
    },
  );
}
