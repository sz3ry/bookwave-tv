import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'composition.dart';
import 'playback/just_audio_engine.dart';
import 'playback/media_session_handler.dart';
import 'storage/credentials_store.dart';
import 'storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final state = buildAppState(
    httpClient: http.Client(),
    engine: JustAudioEngine(),
    store: await LocalStore.open(),
    credentials: CredentialsStore(const FlutterSecureStorage()),
  );
  final controller = state.controller;

  await AudioService.init(
    builder: () => MediaSessionHandler(controller),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.sz3ry.bookwavetv.playback',
      androidNotificationChannelName: 'Bookwave TV',
      androidStopForegroundOnPause: false,
    ),
  );

  // Back at the root only moves the app to the background (MainActivity), so
  // the book keeps playing. If the activity is torn down anyway, save the
  // place without dropping the book: the cached engine may keep playing.
  AppLifecycleListener(
    onDetach: () => unawaited(controller.flush()),
    onResume: () => unawaited(state.resumed()),
  );

  runApp(BookwaveTvApp(state));
  await state.start();
}
