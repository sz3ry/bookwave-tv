import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../playback/position_rules.dart';
import '../storytel/models.dart';

/// Non-secret local state: device id, last chosen book, per-book positions.
class LocalStore {
  LocalStore._(this._prefs, this._deviceId);

  static const _deviceIdKey = 'device_id';
  static const _lastBookKey = 'last_book';
  static String _positionKey(String consumableId) => 'pos:$consumableId';

  final SharedPreferences _prefs;
  final String _deviceId;

  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = const Uuid().v4().toUpperCase();
      await prefs.setString(_deviceIdKey, id);
    }
    return LocalStore._(prefs, id);
  }

  String deviceId() => _deviceId;

  ShelfBook? lastBook() => _readJson(_lastBookKey, ShelfBook.fromJson);

  Future<void> setLastBook(ShelfBook b) =>
      _prefs.setString(_lastBookKey, jsonEncode(b.toJson()));

  StoredPosition? position(String consumableId) =>
      _readJson(_positionKey(consumableId), StoredPosition.fromJson);

  Future<void> setPosition(String consumableId, StoredPosition p) =>
      _prefs.setString(_positionKey(consumableId), jsonEncode(p.toJson()));

  /// Decodes a stored JSON object; corrupt or mistyped data yields null.
  T? _readJson<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
