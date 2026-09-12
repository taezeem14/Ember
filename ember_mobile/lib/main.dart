import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/player_provider.dart';
import 'screens/queue_discovery_screen.dart';
import 'services/audio_handler.dart';
import 'services/storage_service.dart';
import 'theme/ember_theme.dart';

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

  final audioHandler = await initAudioHandler();
  final storageService = await StorageService.init();

  runApp(
    EmberMobileApp(
      audioHandler: audioHandler as EmberAudioHandler,
      storageService: storageService,
    ),
  );
}

class EmberMobileApp extends StatelessWidget {
  final EmberAudioHandler audioHandler;
  final StorageService storageService;

  const EmberMobileApp({
    super.key,
    required this.audioHandler,
    required this.storageService,
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
        home: const QueueDiscoveryScreen(),
      ),
    );
  }
}
