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
  /// Handles `\:` escape sequences that nmcli uses for literal colons in SSIDs.
  factory WifiNetwork.fromNmcliLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      if (line[i] == '\\' && i + 1 < line.length && line[i + 1] == ':') {
        buf.write(':');
        i++;
      } else if (line[i] == ':') {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(line[i]);
      }
    }
    fields.add(buf.toString());
    return WifiNetwork(
      ssid: fields.isNotEmpty ? fields[0] : '',
      signalStrength: fields.length > 1 ? int.tryParse(fields[1]) ?? 0 : 0,
      security: fields.length > 2 ? fields[2] : '',
    );
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
  // Note: WiFi password is passed as a CLI argument, which makes it briefly
  // visible in /proc/<pid>/cmdline. nmcli does not support reading passwords
  // from stdin in non-interactive mode. For a LAN-only kiosk this is an
  // accepted risk. See https://registry.home.chrisuthe.com/chris/Hearth/issues/13
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
  /// Runs: `nmcli -t -f active,ssid device wifi list`
  /// Returns null on non-Linux platforms.
  Future<String?> activeConnection() async {
    if (!Platform.isLinux) return null;
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'active,ssid',
        'device',
        'wifi',
        'list',
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

  /// Disconnects the active WiFi interface.
  ///
  /// Detects the WiFi device name via nmcli instead of hardcoding wlan0.
  /// Returns false on non-Linux platforms.
  Future<bool> disconnect() async {
    if (!Platform.isLinux) return false;
    try {
      final iface = await _findWifiInterface();
      final result = await Process.run('nmcli', [
        'device',
        'disconnect',
        iface,
      ]);
      if (result.exitCode != 0) {
        Log.e('WiFi', 'Disconnect nmcli error: ${result.stderr}');
        return false;
      }
      return true;
    } catch (e) {
      Log.e('WiFi', 'Disconnect error: $e');
      return false;
    }
  }

  /// Finds the first WiFi device name, falling back to wlan0.
  Future<String> _findWifiInterface() async {
    try {
      final devResult = await Process.run(
          'nmcli', ['-t', '-f', 'DEVICE,TYPE', 'device', 'status']);
      for (final line in (devResult.stdout as String).split('\n')) {
        if (line.contains(':wifi')) {
          return line.split(':').first;
        }
      }
    } catch (_) {}
    return 'wlan0';
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

  /// Parses `nmcli -t -f active,ssid device wifi list` output.
  ///
  /// Returns the SSID of the first active connection, or null.
  static String? parseActiveConnection(String output) {
    final lines = output.trim().split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('yes:')) {
        final ssid = trimmed.substring(4);
        return ssid.isEmpty ? null : ssid;
      }
    }
    return null;
  }
}

final wifiServiceProvider = Provider<WifiService>((ref) => WifiService());
