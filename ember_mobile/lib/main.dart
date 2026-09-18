import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/player_provider.dart';
import 'screens/spotify_shell_screen.dart';
import 'services/audio_handler.dart';
import 'services/storage_service.dart';
import 'theme/ember_theme.dart';

import 'services/passkey_service.dart';
import 'screens/passkey_gate_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system navigation & status bar transparent for edge-to-edge obsidian immersion
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: EmberColors.obsidianBase,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Ember Flutter Error: ${details.exception}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Ember Global Async Error: $error');
    return true;
  };

  EmberAudioHandler audioHandler;
  try {
    final rawHandler = await initAudioHandler();
    audioHandler = rawHandler is EmberAudioHandler ? rawHandler : EmberAudioHandler();
  } catch (e) {
    debugPrint('AudioHandler init fallback: $e');
    audioHandler = EmberAudioHandler();
  }

  StorageService storageService;
  try {
    storageService = await StorageService.init();
  } catch (e) {
    debugPrint('StorageService init fallback: $e');
    storageService = StorageService(null);
  }

  bool isActivated = false;
  try {
    isActivated = await PasskeyService.isActivated();
  } catch (e) {
    debugPrint('Passkey check error: $e');
  }

  runApp(
    EmberMobileApp(
      audioHandler: audioHandler,
      storageService: storageService,
      initialActivated: isActivated,
    ),
  );
}

class EmberMobileApp extends StatelessWidget {
  final EmberAudioHandler audioHandler;
  final StorageService storageService;
  final bool initialActivated;

  const EmberMobileApp({
    super.key,
    required this.audioHandler,
    required this.storageService,
    this.initialActivated = false,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PlayerProvider(audioHandler, storageService),
        ),
      ],
      child: MaterialApp(
        title: 'Ember',
        debugShowCheckedModeBanner: false,
        theme: EmberTheme.darkTheme,
        home: initialActivated
            ? const SpotifyShellScreen()
            : const PasskeyGateScreen(),
      ),
    );
  }
}
