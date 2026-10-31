import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'playback/player_controller.dart';
import 'storage/credentials_store.dart';
import 'storage/local_store.dart';
import 'storytel/models.dart';
import 'storytel/storytel_client.dart';
import 'storytel/storytel_http.dart';

enum AppRoute { login, library, player }

/// Startup routing and the few user actions that move between screens.
class AppState extends ChangeNotifier {
  AppState({
    required this.client,
    required this._credentials,
    required this._store,
    required this.controller,
  });

  final StorytelClient client;
  final PlayerController controller;
  final CredentialsStore _credentials;
  final LocalStore _store;

  static const _retryInterval = Duration(seconds: 10);

  AppRoute _route = AppRoute.login;
  bool _started = false;
  Future<void>? _opening;
  bool _offline = false;
  Timer? _retry;

  AppRoute get route => _route;

  /// The last book could not be opened at launch (no network): the player
  /// shows a no-connection state and the book is retried every 10 s.
  bool get offline => _offline;

  /// False until [start] has decided the first route.
  bool get started => _started;

  Future<List<ShelfBook>> loadShelf() => client.bookshelf();

  Future<void> start() async {
    final creds = await _credentials.read();
    if (creds == null) {
      _setRoute(AppRoute.login);
      _started = true;
      notifyListeners();
      return;
    }
    client.restore(creds);
    final last = _store.lastBook();
    _started = true;
    if (last == null) {
      _setRoute(AppRoute.library);
      return;
    }
    await _open(last, retryOffline: true);
  }

  /// The app came back to the foreground. The player must never sit there
  /// without a book (e.g. the engine dropped it): reopen the last one.
  Future<void> resumed() async {
    if (_route != AppRoute.player ||
        controller.book != null ||
        _opening != null) {
      return;
    }
    final last = _store.lastBook();
    if (last != null) await _open(last, retryOffline: true);
  }

  /// Throws what the client throws; the login screen turns it into a message.
  Future<void> login(String email, String password) async {
    final creds = await client.login(email, password);
    await _credentials.write(creds);
    _setRoute(AppRoute.library);
  }

  /// Opens [b] and shows the player. A pick while another book is still
  /// opening is ignored: the controller does not serialise `open` calls.
  Future<void> pickBook(ShelfBook b) async {
    if (_opening != null) return;
    // The book already loaded keeps its place: just return to it.
    if (b.consumableId == controller.book?.consumableId) return closeLibrary();
    await _open(b);
  }

  void openLibrary() {
    _cancelRetry();
    _setRoute(AppRoute.library);
  }

  void closeLibrary() {
    if (controller.book != null) _setRoute(AppRoute.player);
  }

  Future<void> logout() async {
    _cancelRetry();
    await controller.stop();
    await _credentials.clear();
    _setRoute(AppRoute.login);
  }

  /// Storytel no longer accepts the stored login: forget it and ask again.
  void authRejected() {
    _cancelRetry();
    unawaited(controller.stop());
    unawaited(_credentials.clear());
    _setRoute(AppRoute.login);
  }

  /// Opens [b] on the player. When that fails, a user pick falls back to the
  /// library; with [retryOffline] (the last book at launch or on resume) a
  /// transient failure keeps the player, shows no connection and tries again
  /// every 10 s, any other failure falls back to the library.
  Future<void> _open(ShelfBook b, {bool retryOffline = false}) {
    _retry?.cancel();
    _retry = null;
    // A retry keeps the no-connection state until it succeeds.
    if (!retryOffline) _offline = false;
    _setRoute(AppRoute.player);
    final run = () async {
      try {
        await controller.open(b);
        if (_offline) {
          _offline = false;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Opening a book failed: ${e.runtimeType}');
        // Drop the half-opened book so Back cannot lead to a dead player;
        // the last-book record stays.
        try {
          await controller.stop();
        } catch (_) {}
        // A rejected login already routed to the login screen, and a parent
        // who opened the library meanwhile stays there.
        if (_route != AppRoute.player) return;
        // Only a transient failure is worth retrying; a book that can no
        // longer be opened (left the shelf or subscription) goes to the
        // library, where another one can be picked.
        if (!retryOffline || !_isTransient(e)) {
          return _setRoute(AppRoute.library);
        }
        _offline = true;
        notifyListeners();
        _retry = Timer(_retryInterval, () {
          _retry = null;
          unawaited(_open(b, retryOffline: true));
        });
      }
    }();
    _opening = run;
    return run.whenComplete(() => _opening = null);
  }

  /// Network trouble or a server error: the same book may open later. A
  /// missing stream location carries the 2xx/3xx status, so it is permanent.
  static bool _isTransient(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException ||
      (e is StorytelHttpException && e.status >= 500);

  void _cancelRetry() {
    _retry?.cancel();
    _retry = null;
    _offline = false;
  }

  @override
  void dispose() {
    _retry?.cancel();
    _retry = null;
    super.dispose();
  }

  void _setRoute(AppRoute r) {
    _route = r;
    notifyListeners();
  }
}
