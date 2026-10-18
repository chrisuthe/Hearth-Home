import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/android_app_config.dart';

/// Stands in for the platform check in tests.
@visibleForTesting
bool? debugAndroidAppsSupportedOverride;

/// Whether this build can list and launch other Android apps. Android only.
///
/// `dart:io`, not `defaultTargetPlatform`: the latter reports Android under
/// `flutter test`.
bool get androidAppsSupported =>
    debugAndroidAppsSupportedOverride ?? (!kIsWeb && Platform.isAndroid);

/// An app installed on the tablet that has a launcher entry.
class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});

  final String packageName;
  final String label;
}

/// Dart side of `com.hearth/apps`. Every call degrades to an empty or false
/// result, so a missing channel (non-Android) never throws.
class AndroidAppsBridge {
  static const _channel = MethodChannel('com.hearth/apps');

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('apps.$method failed: $e');
    } on MissingPluginException catch (e) {
      debugPrint('apps.$method unavailable: $e');
    }
    return null;
  }

  /// Launchable apps sorted by label, Hearth excluded.
  Future<List<InstalledApp>> listApps() async {
    final raw = await _call<List<Object?>>('listApps');
    if (raw == null) return const [];
    return [
      for (final e in raw)
        if (e is Map)
          InstalledApp(
            packageName: e['packageName'] as String? ?? '',
            label: e['label'] as String? ?? '',
          ),
    ];
  }

  /// PNG bytes of the app's icon, or null.
  Future<Uint8List?> icon(String packageName) =>
      _call<Uint8List>('icon', {'packageName': packageName});

  /// False when the package is not installed or the call failed.
  Future<bool> launch(String packageName, AndroidAppLayout layout) async =>
      await _call<bool>(
          'launch', {'packageName': packageName, 'layout': layout.name}) ??
      false;

  /// Whether "Display over other apps" is granted.
  Future<bool> overlayGranted() async =>
      await _call<bool>('overlayGranted') ?? false;

  Future<void> openOverlaySettings() => _call<void>('openOverlaySettings');

  /// Brings Hearth forward over a running app.
  Future<void> bringToFront() => _call<void>('bringToFront');
}

final androidAppsBridgeProvider =
    Provider<AndroidAppsBridge>((ref) => AndroidAppsBridge());

/// App icon PNG, cached per package.
final androidAppIconProvider =
    FutureProvider.family<Uint8List?, String>(
        (ref, pkg) => ref.watch(androidAppsBridgeProvider).icon(pkg));
