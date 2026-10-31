import 'dart:async';

import 'package:bookwave_tv/playback/player_controller.dart';
import 'package:bookwave_tv/storytel/models.dart';
import 'package:bookwave_tv/storytel/storytel_client.dart';
import 'package:flutter/foundation.dart';

ShelfBook shelfBook(
  String id, {
  bool kids = true,
  DateTime? positionUpdated,
  DateTime? stateUpdated,
}) => ShelfBook(
  consumableId: id,
  title: 'Book $id',
  authors: 'Author',
  kidsBook: kids,
  durationMs: 3600000,
  positionUpdatedTime: positionUpdated,
  stateUpdateTime: stateUpdated,
);

class FakeClient implements StorytelClient {
  List<ShelfBook> shelf = [];
  final List<Object> shelfErrors = [];
  Object? loginError;
  int shelfCalls = 0;
  StorytelCredentials? restored;

  @override
  Future<StorytelCredentials> login(String email, String password) async {
    final e = loginError;
    if (e != null) throw e;
    return StorytelCredentials(email: email, encryptedPassword: 'enc');
  }

  @override
  void restore(StorytelCredentials c) => restored = c;

  @override
  Future<List<ShelfBook>> bookshelf() async {
    shelfCalls++;
    if (shelfErrors.isNotEmpty) throw shelfErrors.removeAt(0);
    return shelf;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeController extends ChangeNotifier implements PlayerController {
  final opened = <String>[];
  int stops = 0;
  int maxConcurrentOpens = 0;
  int _running = 0;
  Completer<void>? openGate;
  Object? openError;

  @override
  ShelfBook? book;

  @override
  Future<void> open(ShelfBook b) async {
    _running++;
    if (_running > maxConcurrentOpens) maxConcurrentOpens = _running;
    opened.add(b.consumableId);
    book = b;
    notifyListeners();
    final gate = openGate;
    openGate = null;
    if (gate != null) await gate.future;
    _running--;
    final e = openError;
    openError = null;
    if (e != null) throw e;
  }

  @override
  Future<void> stop() async {
    stops++;
    book = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
