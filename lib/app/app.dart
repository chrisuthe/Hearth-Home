import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hub_shell.dart';

/// Root widget for the Home Hub application.
///
/// Uses a dark theme optimized for an always-on AMOLED display — true black
/// background saves power and looks great on the 11" panel. Material 3 with
/// a subtle indigo accent keeps the UI modern without being distracting.
class HomeHubApp extends ConsumerWidget {
  const HomeHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Home Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorSchemeSeed: const Color(0xFF646CFF),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const Scaffold(
        body: HubShell(),
      ),
    );
  }
}
