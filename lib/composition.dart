import 'package:http/http.dart' as http;

import 'app_state.dart';
import 'playback/audio_engine.dart';
import 'playback/player_controller.dart';
import 'storage/credentials_store.dart';
import 'storage/local_store.dart';
import 'storytel/storytel_client.dart';
import 'storytel/storytel_http.dart';

/// Builds the app's object graph. Only the client's rejected re-login logs
/// out: a 401 that survives a successful re-login is a server hiccup, and
/// the controller just keeps the local position.
AppState buildAppState({
  required http.Client httpClient,
  required AudioEngine engine,
  required LocalStore store,
  required CredentialsStore credentials,
}) {
  // The callbacks fire only from calls made after the state exists.
  late final AppState state;
  final client = StorytelClient(
    StorytelHttp(httpClient),
    onCredentialsRejected: () => state.authRejected(),
  );
  final controller = PlayerController(
    engine: engine,
    client: client,
    store: store,
  );
  state = AppState(
    client: client,
    credentials: credentials,
    store: store,
    controller: controller,
  );
  return state;
}
