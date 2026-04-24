import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/logger.dart';

/// Manages system timezone on Linux (Buildroot / Raspberry Pi).
///
/// On Linux, applies the configured IANA timezone via timedatectl or by
/// writing /etc/localtime directly (Buildroot fallback). On Windows and
/// web, timezone operations are no-ops — Flutter uses the OS timezone.
class TimezoneService {
  static const _tag = 'Timezone';

  /// Common timezones shown at the top of the picker for convenience.
  static const commonTimezones = [
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Anchorage',
    'Pacific/Honolulu',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Europe/Moscow',
    'Asia/Tokyo',
    'Asia/Shanghai',
    'Asia/Kolkata',
    'Asia/Dubai',
    'Australia/Sydney',
    'Pacific/Auckland',
  ];

  /// Apply the given IANA timezone to the system.
  ///
  /// Tries timedatectl first, then falls back to writing /etc/localtime
  /// directly (for Buildroot images without systemd-timedated).
  Future<bool> applyTimezone(String timezone) async {
    if (kIsWeb || !Platform.isLinux || timezone.isEmpty) return false;

    try {
      // Hearth runs as a non-root user; timedatectl set-timezone requires
      // privilege. setup-pi.sh provisions a NOPASSWD sudoers entry for this
      // exact command — see /etc/sudoers.d/hearth-timezone. The -n flag
      // fails fast if the rule isn't in place instead of blocking on a
      // password prompt that would never be answered.
      final result = await Process.run(
        'sudo',
        ['-n', 'timedatectl', 'set-timezone', timezone],
      );
      if (result.exitCode == 0) {
        Log.i(_tag, 'Set timezone to $timezone via timedatectl');
        return true;
      }
      Log.w(_tag,
          'sudo timedatectl failed (exit ${result.exitCode}): ${result.stderr}. Falling back to /etc/localtime.');
    } catch (e) {
      Log.w(_tag, 'timedatectl not available: $e');
    }

    // Fallback: symlink /etc/localtime to the zoneinfo file.
    try {
      final zonePath = '/usr/share/zoneinfo/$timezone';
      if (!await File(zonePath).exists()) {
        Log.e(_tag, 'Zoneinfo file not found: $zonePath');
        return false;
      }

      // Remove existing /etc/localtime and create symlink.
      final localtime = File('/etc/localtime');
      if (await localtime.exists()) {
        await localtime.delete();
      }
      await Link('/etc/localtime').create(zonePath);

      // Also write /etc/timezone for tools that read it.
      await File('/etc/timezone').writeAsString('$timezone\n');

      Log.i(_tag, 'Set timezone to $timezone via /etc/localtime symlink');
      return true;
    } catch (e) {
      Log.e(_tag, 'Failed to set timezone via /etc/localtime: $e');
      return false;
    }
  }

  /// Get the current system timezone.
  Future<String> getCurrentTimezone() async {
    if (kIsWeb || !Platform.isLinux) return '';

    try {
      // Try timedatectl first.
      final result = await Process.run(
        'timedatectl',
        ['show', '--property=Timezone', '--value'],
      );
      if (result.exitCode == 0) {
        final tz = (result.stdout as String).trim();
        if (tz.isNotEmpty) return tz;
      }
    } catch (_) {}

    // Fallback: read /etc/timezone.
    try {
      final file = File('/etc/timezone');
      if (await file.exists()) {
        return (await file.readAsString()).trim();
      }
    } catch (_) {}

    return '';
  }

  /// List all available IANA timezones from the system.
  Future<List<String>> listTimezones() async {
    if (kIsWeb || !Platform.isLinux) return _fallbackTimezones;

    try {
      final result = await Process.run('timedatectl', ['list-timezones']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) return lines;
      }
    } catch (_) {}

    // Fallback: scan /usr/share/zoneinfo.
    try {
      final baseDir = Directory('/usr/share/zoneinfo');
      if (await baseDir.exists()) {
        final zones = <String>[];
        await for (final entity in baseDir.list(recursive: true)) {
          if (entity is File) {
            final relative = entity.path.substring(baseDir.path.length + 1);
            // Filter to valid IANA zones (contain a slash, no dots).
            if (relative.contains('/') && !relative.contains('.') && !relative.startsWith('posix/') && !relative.startsWith('right/')) {
              zones.add(relative);
            }
          }
        }
        zones.sort();
        if (zones.isNotEmpty) return zones;
      }
    } catch (_) {}

    return _fallbackTimezones;
  }

  /// Hardcoded timezone list for Windows dev and when system lists fail.
  static const _fallbackTimezones = [
    'Africa/Cairo',
    'Africa/Johannesburg',
    'Africa/Lagos',
    'Africa/Nairobi',
    'America/Anchorage',
    'America/Argentina/Buenos_Aires',
    'America/Bogota',
    'America/Chicago',
    'America/Denver',
    'America/Halifax',
    'America/Los_Angeles',
    'America/Mexico_City',
    'America/New_York',
    'America/Phoenix',
    'America/Sao_Paulo',
    'America/St_Johns',
    'America/Toronto',
    'America/Vancouver',
    'Asia/Bangkok',
    'Asia/Colombo',
    'Asia/Dubai',
    'Asia/Hong_Kong',
    'Asia/Jakarta',
    'Asia/Karachi',
    'Asia/Kolkata',
    'Asia/Seoul',
    'Asia/Shanghai',
    'Asia/Singapore',
    'Asia/Taipei',
    'Asia/Tehran',
    'Asia/Tokyo',
    'Atlantic/Reykjavik',
    'Australia/Adelaide',
    'Australia/Brisbane',
    'Australia/Melbourne',
    'Australia/Perth',
    'Australia/Sydney',
    'Europe/Amsterdam',
    'Europe/Athens',
    'Europe/Berlin',
    'Europe/Brussels',
    'Europe/Dublin',
    'Europe/Helsinki',
    'Europe/Istanbul',
    'Europe/Lisbon',
    'Europe/London',
    'Europe/Madrid',
    'Europe/Moscow',
    'Europe/Oslo',
    'Europe/Paris',
    'Europe/Rome',
    'Europe/Stockholm',
    'Europe/Vienna',
    'Europe/Warsaw',
    'Europe/Zurich',
    'Pacific/Auckland',
    'Pacific/Fiji',
    'Pacific/Guam',
    'Pacific/Honolulu',
    'UTC',
  ];
}

final timezoneServiceProvider = Provider<TimezoneService>((ref) {
  return TimezoneService();
});
