import 'package:bookwave_tv/playback/position_rules.dart';
import 'package:bookwave_tv/storage/local_store.dart';
import 'package:bookwave_tv/storytel/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('deviceId is stable and upper-case UUID', () async {
    final store = await LocalStore.open();
    final id = store.deviceId();
    expect(id, matches(RegExp(r'^[0-9A-F-]{36}$')));
    expect(store.deviceId(), id);
    expect((await LocalStore.open()).deviceId(), id);
  });

  test('lastBook round-trips', () async {
    final store = await LocalStore.open();
    expect(store.lastBook(), isNull);
    await store.setLastBook(
      ShelfBook(
        consumableId: 'c1',
        title: 'T',
        authors: 'A, B',
        kidsBook: false,
        durationMs: 1000,
        positionMs: 5,
      ),
    );
    final book = (await LocalStore.open()).lastBook();
    expect(book?.consumableId, 'c1');
    expect(book?.title, 'T');
    expect(book?.authors, 'A, B');
    expect(book?.durationMs, 1000);
    expect(book?.positionMs, 5);
  });

  test('position round-trips including remoteSeen', () async {
    final store = await LocalStore.open();
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
    await store.setPosition(
      'c1',
      StoredPosition(positionMs: 1234, updatedAt: at, remoteSeen: 999),
    );
    final p = (await LocalStore.open()).position('c1');
    expect(p?.positionMs, 1234);
    expect(p?.remoteSeen, 999);
    expect(p?.updatedAt.toUtc(), at);
  });

  test('missing position is null', () async {
    expect((await LocalStore.open()).position('nope'), isNull);
  });

  test('corrupt stored values return null', () async {
    SharedPreferences.setMockInitialValues({
      'last_book': '{not json',
      'pos:c1': 'garbage',
    });
    final store = await LocalStore.open();
    expect(store.lastBook(), isNull);
    expect(store.position('c1'), isNull);
  });
}
