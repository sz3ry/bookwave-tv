import 'dart:async';

import 'package:flutter/foundation.dart';

import 'playback/player_controller.dart';
import 'storage/credentials_store.dart';
import 'storage/local_store.dart';
import 'storytel/models.dart';
import 'storytel/storytel_client.dart';

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

  AppRoute _route = AppRoute.login;
  bool _started = false;
  Future<void>? _opening;

  AppRoute get route => _route;

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
    await _open(last, fallback: AppRoute.library);
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
    await _open(b, fallback: AppRoute.library);
  }

  void openLibrary() => _setRoute(AppRoute.library);

  void closeLibrary() {
    if (controller.book != null) _setRoute(AppRoute.player);
  }

  Future<void> logout() async {
    await controller.stop();
    await _credentials.clear();
    _setRoute(AppRoute.login);
  }

  /// Storytel no longer accepts the stored login: forget it and ask again.
  void authRejected() {
    unawaited(controller.stop());
    unawaited(_credentials.clear());
    _setRoute(AppRoute.login);
  }

  Future<void> _open(ShelfBook b, {required AppRoute fallback}) {
    _setRoute(AppRoute.player);
    final run = () async {
      try {
        await controller.open(b);
      } catch (e) {
        debugPrint('Opening a book failed: ${e.runtimeType}');
        // A rejected login already routed to the login screen.
        if (_route == AppRoute.player) _setRoute(fallback);
      }
    }();
    _opening = run;
    return run.whenComplete(() => _opening = null);
  }

  void _setRoute(AppRoute r) {
    _route = r;
    notifyListeners();
  }
}
