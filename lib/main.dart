import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/assistant_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load API keys from .env
  await dotenv.load(fileName: ".env");

  // Lock to portrait (simpler UX for visually impaired users)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Keep screen on so hotword engine stays active
  WakelockPlus.enable();

  runApp(const VisualAssistantApp());
}

class VisualAssistantApp extends StatelessWidget {
  const VisualAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AssistantScreen(),
    );
  }
}