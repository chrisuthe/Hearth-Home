import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hub_shell.dart';

/// Root widget for the Hearth application.
///
/// Uses a dark theme optimized for an always-on AMOLED display — true black
/// background saves power and looks great on the 11" panel. Material 3 with
/// a subtle indigo accent keeps the UI modern without being distracting.
/// Dialog/sheet background — slightly lighter than true black for visual
/// separation from the AMOLED background.
const kDialogBackground = Color(0xFF1E1E1E);

class HearthApp extends ConsumerWidget {
  const HearthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Hearth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorSchemeSeed: const Color(0xFF646CFF),
        useMaterial3: true,
        fontFamily: 'Roboto',
        dialogTheme: const DialogThemeData(backgroundColor: kDialogBackground),
      ),
      home: const Scaffold(
        body: HubShell(),
      ),
    );
  }
}
