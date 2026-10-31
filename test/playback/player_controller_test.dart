import 'dart:async';

import 'package:bookwave_tv/playback/audio_engine.dart';
import 'package:bookwave_tv/playback/player_controller.dart';
import 'package:bookwave_tv/storage/local_store.dart';
import 'package:bookwave_tv/storytel/models.dart';
import 'package:bookwave_tv/storytel/storytel_client.dart';
import 'package:bookwave_tv/storytel/storytel_http.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAudioEngine implements AudioEngine {
  final loads = <String>[];
  final seeks = <Duration>[];
  int plays = 0;
  int pauses = 0;
  bool failNextPlay = false;
  bool idleNextPlay = false;
  final _states = StreamController<EnginePlayerState>.broadcast();

  @override
  Duration position = Duration.zero;

  void emit(EnginePlayerState s) => _states.add(s);

  @override
  Stream<EnginePlayerState> get states => _states.stream;

  @override
  Future<void> load(String url) async {
    loads.add(url);
    position = Duration.zero;
    emit(EnginePlayerState.ready);
  }

  @override
  Future<void> seek(Duration p) async {
    seeks.add(p);
    position = p;
  }

  @override
  Future<void> play() async {
    plays++;
    if (failNextPlay) {
      failNextPlay = false;
      emit(EnginePlayerState.error);
      return;
    }
    if (idleNextPlay) {
      idleNextPlay = false;
      emit(EnginePlayerState.idle);
      return;
    }
    emit(EnginePlayerState.playing);
  }

  @override
  Future<void> pause() async {
    pauses++;
    emit(EnginePlayerState.paused);
  }

  @override
  Future<void> dispose() => _states.close();
}

class FakeStorytelClient implements StorytelClient {
  /// Remote positions per consumable id.
  final remotes = <String, RemotePosition?>{};
  RemotePosition? get remote => remotes['c1'];
  set remote(RemotePosition? p) => remotes['c1'] = p;
  Object? writeError;

  /// One-shot hooks: the next call waits on the gate or throws the error.
  Completer<void>? writeGate;
  Completer<void>? readGate;
  Completer<void>? streamUrlGate;
  Object? streamUrlError;
  int streamUrlCalls = 0;
  int readCalls = 0;
  final writes = <int>[];

  @override
  Future<String> streamUrl(String consumableId) async {
    streamUrlCalls++;
    final gate = streamUrlGate;
    streamUrlGate = null;
    if (gate != null) await gate.future;
    final error = streamUrlError;
    streamUrlError = null;
    if (error != null) throw error;
    return 'https://cdn.example/$consumableId/$streamUrlCalls.mp3';
  }

  @override
  Future<RemotePosition?> readPosition(String consumableId) async {
    readCalls++;
    final gate = readGate;
    readGate = null;
    if (gate != null) await gate.future;
    return remotes[consumableId];
  }

  @override
  Future<void> writePosition(
    String consumableId,
    int positionMs,
    String deviceId,
  ) async {
    final gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    if (writeError != null) throw writeError!;
    writes.add(positionMs);
    remotes[consumableId] = RemotePosition(positionMs, null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ShelfBook book([String id = 'c1']) => ShelfBook(
  consumableId: id,
  title: 'Book $id',
  authors: 'Author',
  kidsBook: true,
  durationMs: 3600000,
);

final t0 = DateTime.utc(2026, 10, 31, 20);

class Harness {
  Harness(this.async, this.store)
    : engine = FakeAudioEngine(),
      client = FakeStorytelClient() {
    controller = PlayerController(
      engine: engine,
      client: client,
      store: store,
      clock: () => t0.add(async.elapsed),
    );
  }

  final FakeAsync async;
  final LocalStore store;
  final FakeAudioEngine engine;
  final FakeStorytelClient client;
  late final PlayerController controller;

  /// Starts [f] without waiting for it (it may be blocked on a gate).
  void start(Future<void> Function() f) {
    unawaited(f());
    async.flushMicrotasks();
  }

  /// Runs [f] and drains its microtasks.
  T run<T>(Future<T> Function() f) {
    late T result;
    Object? error;
    f().then<void>((v) => result = v, onError: (Object e) => error = e);
    async.flushMicrotasks();
    if (error != null) throw error!;
    return result;
  }
}

/// Runs [body] in fake time with a real [LocalStore] on mock prefs.
void withHarness(Map<String, Object> prefs, void Function(Harness h) body) {
  SharedPreferences.setMockInitialValues(prefs);
  late LocalStore store;
  fakeAsync((async) {
    LocalStore.open().then((s) => store = s);
    async.flushMicrotasks();
    final h = Harness(async, store);
    body(h);
    h.controller.dispose();
  });
}

Map<String, Object> localPos(String id, int ms, {int? remoteSeen}) => {
  'pos:$id':
      '{"positionMs":$ms,"updatedAt":"2026-10-31T19:00:00.000Z"'
      '${remoteSeen == null ? '' : ',"remoteSeen":$remoteSeen'}}',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('open seeks to resolved start and does not play', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      expect(h.engine.loads, ['https://cdn.example/c1/1.mp3']);
      expect(h.engine.seeks, [const Duration(milliseconds: 60000)]);
      expect(h.engine.plays, 0);
      expect(h.controller.isPlaying, isFalse);
      expect(h.controller.book?.consumableId, 'c1');
      expect(h.store.lastBook()?.consumableId, 'c1');
    });
  });

  test('no write before start applied', () {
    withHarness({}, (h) {
      h.run(() => h.controller.open(book()));
      h.async.elapse(const Duration(seconds: 60));
      expect(h.client.writes, isEmpty);
      expect(h.store.position('c1'), isNull);
      expect(h.engine.seeks, [Duration.zero]);
    });
  });

  test('tick saves local every 15 s and writes remote when moved', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      expect(h.controller.isPlaying, isTrue);
      h.engine.position = const Duration(milliseconds: 75000);
      h.async.elapse(const Duration(seconds: 15));
      expect(h.store.position('c1')?.positionMs, 75000);
      expect(h.client.writes, [75000]);
      expect(h.store.position('c1')?.remoteSeen, 75000);
      h.engine.position = const Duration(milliseconds: 90000);
      h.async.elapse(const Duration(seconds: 15));
      expect(h.store.position('c1')?.positionMs, 90000);
      expect(h.client.writes, [75000, 90000]);
    });
  });

  test('tick does not write remote when unmoved', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 60500);
      h.async.elapse(const Duration(seconds: 15));
      expect(h.store.position('c1')?.positionMs, 60500);
      expect(h.client.writes, isEmpty);
    });
  });

  test('pause writes remote', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 65000);
      h.async.elapse(const Duration(seconds: 5));
      h.run(() => h.controller.togglePlayPause());
      expect(h.controller.isPlaying, isFalse);
      expect(h.engine.pauses, 1);
      expect(h.store.position('c1')?.positionMs, 65000);
      expect(h.client.writes, [65000]);
      expect(h.store.position('c1')?.remoteSeen, 65000);
    });
  });

  test('resume follows remote moved by another device', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 70000);
      h.async.elapse(const Duration(seconds: 5));
      h.run(() => h.controller.togglePlayPause());
      h.async.elapse(const Duration(minutes: 10));
      h.client.remote = RemotePosition(
        500000,
        t0.add(const Duration(minutes: 9)),
      );
      final reads = h.client.readCalls;
      h.run(() => h.controller.togglePlayPause());
      expect(h.client.readCalls, reads + 1);
      expect(h.engine.seeks.last, const Duration(milliseconds: 500000));
      expect(h.controller.isPlaying, isTrue);
      expect(h.store.position('c1')?.positionMs, 500000);
      expect(h.store.position('c1')?.remoteSeen, 500000);
    });
  });

  test('resume after URL expiry re-resolves and seeks', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 75000);
      h.async.elapse(const Duration(seconds: 5));
      h.run(() => h.controller.togglePlayPause());
      h.async.elapse(const Duration(hours: 3));
      h.engine.failNextPlay = true;
      h.run(() => h.controller.togglePlayPause());
      expect(h.client.streamUrlCalls, 2);
      expect(h.engine.loads.last, 'https://cdn.example/c1/2.mp3');
      expect(h.engine.seeks.last, const Duration(milliseconds: 75000));
      expect(h.engine.plays, 3);
      expect(h.controller.isPlaying, isTrue);
    });
  });

  test('guarded write skipped when remote moved', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 65000);
      h.async.elapse(const Duration(seconds: 5));
      h.client.remote = RemotePosition(300000, null);
      h.run(() => h.controller.stop());
      expect(h.client.writes, isEmpty);
      expect(h.store.position('c1')?.positionMs, 65000);
      expect(h.controller.isPlaying, isFalse);
    });
  });

  test('guarded write sent when remote unmoved', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 65000);
      h.async.elapse(const Duration(seconds: 5));
      h.run(() => h.controller.stop());
      expect(h.client.writes, [65000]);
    });
  });

  test('remote write failure keeps local position', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 80000);
      h.client.writeError = StorytelHttpException(503, null);
      h.run(() => h.controller.togglePlayPause());
      expect(h.controller.isPlaying, isFalse);
      expect(h.store.position('c1')?.positionMs, 80000);
      expect(h.store.position('c1')?.remoteSeen, 60000);
    });
  });

  test('remote auth failure reports it and keeps playing', () {
    SharedPreferences.setMockInitialValues({});
    fakeAsync((async) {
      late LocalStore store;
      LocalStore.open().then((s) => store = s);
      async.flushMicrotasks();
      var authFailures = 0;
      final engine = FakeAudioEngine();
      final client = FakeStorytelClient()
        ..writeError = StorytelAuthException(null, isLoginFailure: true);
      final c = PlayerController(
        engine: engine,
        client: client,
        store: store,
        clock: () => t0.add(async.elapsed),
        onAuthFailure: () => authFailures++,
      );
      c.open(book());
      async.flushMicrotasks();
      c.togglePlayPause();
      async.flushMicrotasks();
      engine.position = const Duration(milliseconds: 20000);
      async.elapse(const Duration(seconds: 15));
      expect(authFailures, 1);
      expect(c.isPlaying, isTrue);
      expect(store.position('c1')?.positionMs, 20000);
      c.dispose();
    });
  });

  test('completed then toggle restarts from 0', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 3600000);
      h.engine.emit(EnginePlayerState.completed);
      h.async.flushMicrotasks();
      expect(h.controller.isFinished, isTrue);
      expect(h.controller.isPlaying, isFalse);
      h.run(() => h.controller.togglePlayPause());
      expect(h.engine.seeks.last, Duration.zero);
      expect(h.controller.isFinished, isFalse);
      expect(h.controller.isPlaying, isTrue);
    });
  });

  /// Opens c1 at 60000, plays, ticks at 75000, then the stream breaks with
  /// the engine at 0 and a recovery blocked on `streamUrl`.
  Completer<void> breakStreamDuringPlay(Harness h) {
    h.client.remote = RemotePosition(60000, null);
    h.run(() => h.controller.open(book()));
    h.run(() => h.controller.togglePlayPause());
    h.engine.position = const Duration(milliseconds: 75000);
    h.async.elapse(const Duration(seconds: 15));
    expect(h.client.writes, [75000]);
    final gate = h.client.streamUrlGate = Completer<void>();
    h.engine.position = Duration.zero;
    h.engine.emit(EnginePlayerState.error);
    h.async.flushMicrotasks();
    expect(h.client.streamUrlCalls, 2);
    return gate;
  }

  test('pause during recovery does not write 0', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      final gate = breakStreamDuringPlay(h);
      h.run(() => h.controller.togglePlayPause());
      expect(h.controller.isPlaying, isFalse);
      expect(h.store.position('c1')?.positionMs, 75000);
      expect(h.client.writes, [75000]);
      final plays = h.engine.plays;
      gate.complete();
      h.async.flushMicrotasks();
      expect(h.engine.plays, plays);
      expect(h.controller.isPlaying, isFalse);
      expect(h.engine.seeks.last, const Duration(milliseconds: 75000));
      h.async.elapse(const Duration(seconds: 60));
      expect(h.store.position('c1')?.positionMs, 75000);
      expect(h.client.writes, [75000]);
    });
  });

  test('stop during recovery does not write 0 and does not play', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      final gate = breakStreamDuringPlay(h);
      h.run(() => h.controller.stop());
      expect(h.controller.book, isNull);
      expect(h.store.position('c1')?.positionMs, 75000);
      final plays = h.engine.plays;
      final loads = h.engine.loads.length;
      gate.complete();
      h.async.flushMicrotasks();
      expect(h.engine.plays, plays);
      expect(h.engine.loads.length, loads);
      expect(h.controller.isPlaying, isFalse);
      expect(h.client.writes, [75000]);
    });
  });

  test('failed recovery keeps last known position', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 75000);
      h.async.elapse(const Duration(seconds: 15));
      h.client.streamUrlError = StorytelHttpException(503, null);
      h.engine.position = Duration.zero;
      h.engine.emit(EnginePlayerState.error);
      h.async.flushMicrotasks();
      expect(h.controller.isPlaying, isFalse);
      expect(h.controller.position, const Duration(milliseconds: 75000));
      h.async.elapse(const Duration(seconds: 30));
      h.run(() => h.controller.togglePlayPause());
      expect(h.engine.loads.last, 'https://cdn.example/c1/3.mp3');
      expect(h.engine.seeks.last, const Duration(milliseconds: 75000));
      expect(h.controller.isPlaying, isTrue);
      expect(h.store.position('c1')?.positionMs, 75000);
      expect(h.client.writes, [75000]);
    });
  });

  test('book switch during in-flight tick keeps new book bookkeeping', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 75000);
      final gate = h.client.writeGate = Completer<void>();
      h.async.elapse(const Duration(seconds: 15));
      h.start(() => h.controller.open(book('c2')));
      gate.complete();
      h.async.flushMicrotasks();
      expect(h.controller.book?.consumableId, 'c2');
      expect(h.client.writes, [75000]);
      expect(h.store.position('c1')?.remoteSeen, 75000);
      // c2 has no remote: its remoteSeen must stay unknown, not c1's.
      h.client.writeError = StorytelHttpException(503, null);
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 20000);
      h.async.elapse(const Duration(seconds: 15));
      expect(h.store.position('c2')?.positionMs, 20000);
      expect(h.store.position('c2')?.remoteSeen, isNull);
    });
  });

  test('book switch during resume recheck does not autoplay', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.async.elapse(const Duration(minutes: 1));
      final gate = h.client.readGate = Completer<void>();
      h.start(() => h.controller.togglePlayPause());
      h.start(() => h.controller.open(book('c2')));
      gate.complete();
      h.async.flushMicrotasks();
      expect(h.controller.book?.consumableId, 'c2');
      expect(h.engine.plays, 0);
      expect(h.controller.isPlaying, isFalse);
    });
  });

  test('idle after play request triggers recovery', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.engine.idleNextPlay = true;
      h.run(() => h.controller.togglePlayPause());
      expect(h.client.streamUrlCalls, 2);
      expect(h.engine.seeks.last, const Duration(milliseconds: 60000));
      expect(h.engine.plays, 2);
      expect(h.controller.isPlaying, isTrue);
    });
  });

  test('local save on pause does not wait on an in-flight remote write', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 75000);
      h.client.writeGate = Completer<void>(); // never completes
      h.async.elapse(const Duration(seconds: 15));
      h.engine.position = const Duration(milliseconds: 80000);
      h.start(() => h.controller.togglePlayPause());
      expect(h.controller.isPlaying, isFalse);
      expect(h.store.position('c1')?.positionMs, 80000);
    });
  });

  test('local save on stop does not wait on an in-flight remote write', () {
    withHarness(localPos('c1', 60000, remoteSeen: 60000), (h) {
      h.client.remote = RemotePosition(60000, null);
      h.run(() => h.controller.open(book()));
      h.run(() => h.controller.togglePlayPause());
      h.engine.position = const Duration(milliseconds: 75000);
      h.client.writeGate = Completer<void>(); // never completes
      h.async.elapse(const Duration(seconds: 15));
      h.engine.position = const Duration(milliseconds: 80000);
      h.start(() => h.controller.stop());
      expect(h.controller.book, isNull);
      expect(h.store.position('c1')?.positionMs, 80000);
    });
  });
}
