import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';

/// A WiFi network discovered via nmcli.
class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.signalStrength,
    required this.security,
  });

  final String ssid;
  final int signalStrength;
  final String security;

  bool get isOpen => security.isEmpty;
  bool get isSecured => security.isNotEmpty;

  /// Parses a colon-separated nmcli output line: `SSID:SIGNAL:SECURITY`
  factory WifiNetwork.fromNmcliLine(String line) {
    final parts = line.split(':');
    final ssid = parts.isNotEmpty ? parts[0] : '';
    final signal =
        parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final security = parts.length > 2 ? parts[2] : '';
    return WifiNetwork(ssid: ssid, signalStrength: signal, security: security);
  }
}

/// Manages WiFi scanning and connections via nmcli (Linux only).
///
/// All methods return empty results or false on non-Linux platforms so
/// the Windows dev build works without any special-casing in UI code.
class WifiService {
  /// Scans for available WiFi networks.
  ///
  /// Runs: `nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan yes`
  /// Returns an empty list on non-Linux platforms.
  Future<List<WifiNetwork>> scan() async {
    if (!Platform.isLinux) return [];
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'SSID,SIGNAL,SECURITY',
        'device',
        'wifi',
        'list',
        '--rescan',
        'yes',
      ]);
      if (result.exitCode != 0) {
        Log.e('WiFi', 'Scan nmcli error: ${result.stderr}');
        return [];
      }
      return parseScanOutput(result.stdout as String);
    } catch (e) {
      Log.e('WiFi', 'Scan exception: $e');
      return [];
    }
  }

  /// Connects to a secured WiFi network with a password.
  ///
  /// Runs: `nmcli device wifi connect <ssid> password <password>`
  /// Returns false on non-Linux platforms.
  Future<bool> connect(String ssid, String password) async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run('nmcli', [
        'device',
        'wifi',
        'connect',
        ssid,
        'password',
        password,
      ]);
      if (result.exitCode != 0) {
        Log.e('WiFi', 'Connect nmcli error: ${result.stderr}');
        return false;
      }
      return true;
    } catch (e) {
      Log.e('WiFi', 'Connect exception: $e');
      return false;
    }
  }

  /// Connects to an open (passwordless) WiFi network.
  ///
  /// Runs: `nmcli device wifi connect <ssid>`
  /// Returns false on non-Linux platforms.
  Future<bool> connectOpen(String ssid) async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run('nmcli', [
        'device',
        'wifi',
        'connect',
        ssid,
      ]);
      if (result.exitCode != 0) {
        Log.e('WiFi', 'ConnectOpen nmcli error: ${result.stderr}');
        return false;
      }
      return true;
    } catch (e) {
      Log.e('WiFi', 'ConnectOpen exception: $e');
      return false;
    }
  }

  /// Returns the SSID of the currently active WiFi connection, or null.
  ///
  /// Runs: `nmcli -t -f DEVICE,CONNECTION device status`
  /// Returns null on non-Linux platforms.
  Future<String?> activeConnection() async {
    if (!Platform.isLinux) return null;
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'DEVICE,CONNECTION',
        'device',
        'status',
      ]);
      if (result.exitCode != 0) {
        Log.e('WiFi', 'ActiveConnection nmcli error: ${result.stderr}');
        return null;
      }
      return parseActiveConnection(result.stdout as String);
    } catch (e) {
      Log.e('WiFi', 'ActiveConnection exception: $e');
      return null;
    }
  }

  /// Disconnects the wlan0 interface.
  ///
  /// Runs: `nmcli device disconnect wlan0`
  /// Returns false on non-Linux platforms.
  Future<bool> disconnect() async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run('nmcli', [
        'device',
        'disconnect',
        'wlan0',
      ]);
      if (result.exitCode != 0) {
        Log.e('WiFi', 'Disconnect nmcli error: ${result.stderr}');
        return false;
      }
      return true;
    } catch (e) {
      Log.e('WiFi', 'Disconnect exception: $e');
      return false;
    }
  }

  /// Parses raw nmcli scan output into a deduplicated, sorted list.
  ///
  /// Deduplicates by SSID (keeps strongest signal), filters blank SSIDs,
  /// and sorts by signal strength descending.
  static List<WifiNetwork> parseScanOutput(String output) {
    final lines = output.trim().split('\n');
    final best = <String, WifiNetwork>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final network = WifiNetwork.fromNmcliLine(trimmed);
      if (network.ssid.isEmpty) continue;
      final existing = best[network.ssid];
      if (existing == null ||
          network.signalStrength > existing.signalStrength) {
        best[network.ssid] = network;
      }
    }

    final sorted = best.values.toList()
      ..sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
    return sorted;
  }

  /// Parses nmcli device status output for the wlan0 connection name.
  ///
  /// Returns the connection name (SSID) if wlan0 is active, null otherwise.
  static String? parseActiveConnection(String output) {
    final lines = output.trim().split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('wlan0:')) continue;
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex == -1) continue;
      final connection = trimmed.substring(colonIndex + 1).trim();
      return connection.isEmpty ? null : connection;
    }
    return null;
  }
}

final wifiServiceProvider = Provider<WifiService>((ref) => WifiService());
