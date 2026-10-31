import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'app_state.dart';
import 'playback/just_audio_engine.dart';
import 'playback/media_session_handler.dart';
import 'playback/player_controller.dart';
import 'storage/credentials_store.dart';
import 'storage/local_store.dart';
import 'storytel/storytel_client.dart';
import 'storytel/storytel_http.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await LocalStore.open();
  final credentials = CredentialsStore(const FlutterSecureStorage());
  // Both callbacks fire before the state exists only if a call is made
  // before runApp, which never happens.
  late final AppState state;
  final client = StorytelClient(
    StorytelHttp(http.Client()),
    onCredentialsRejected: () => state.authRejected(),
  );
  final controller = PlayerController(
    engine: JustAudioEngine(),
    client: client,
    store: store,
    onAuthFailure: () => state.authRejected(),
  );
  state = AppState(
    client: client,
    credentials: credentials,
    store: store,
    controller: controller,
  );

  await AudioService.init(
    builder: () => MediaSessionHandler(controller),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.sz3ry.bookwavetv.playback',
      androidNotificationChannelName: 'Bookwave TV',
      androidStopForegroundOnPause: false,
    ),
  );

  AppLifecycleListener(onDetach: controller.stop);

  runApp(BookwaveTvApp(state));
  await state.start();
}
