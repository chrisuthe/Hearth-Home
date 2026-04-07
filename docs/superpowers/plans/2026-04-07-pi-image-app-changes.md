# Pi Image — App-Level Changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add setup wizard, WiFi management, display configuration, and OTA update UI to the Hearth Flutter app so it can be the complete first-boot experience on a Pi image.

**Architecture:** The app gains a "setup mode" that activates when `hub_config.json` is missing or incomplete. Setup mode presents a multi-step wizard (WiFi → services → display) using the existing Settings screen patterns. WiFi management uses `nmcli` subprocess calls (Linux-only, stubbed on other platforms). Display config and OTA settings extend HubConfig with new fields. The existing LocalApiServer gets new endpoints for WiFi and updates.

**Tech Stack:** Flutter, Riverpod, dart:io Process (nmcli), existing HubConfig/Settings patterns

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `lib/services/wifi_service.dart` | Scan/connect WiFi via nmcli subprocess calls |
| `lib/screens/setup/setup_wizard.dart` | Multi-step first-boot wizard (WiFi → services → display) |
| `lib/screens/settings/wifi_settings.dart` | WiFi management panel for Settings screen |
| `lib/screens/settings/display_settings.dart` | Display profile picker for Settings screen |
| `lib/screens/settings/update_settings.dart` | OTA update status/controls for Settings screen |
| `lib/services/update_service.dart` | Check GitHub Releases for app updates, download bundles |
| `test/services/wifi_service_test.dart` | Unit tests for WiFi service |
| `test/services/update_service_test.dart` | Unit tests for update service |
| `test/screens/setup_wizard_test.dart` | Widget tests for setup wizard flow |
| `test/config/hub_config_test.dart` | Extended with new fields (existing file) |

### Modified Files
| File | Changes |
|------|---------|
| `lib/config/hub_config.dart` | Add `displayProfile`, `displayWidth`, `displayHeight`, `autoUpdate`, `currentVersion` fields |
| `lib/app/app.dart` | Route to setup wizard when config is incomplete |
| `lib/screens/settings/settings_screen.dart` | Add WiFi, Display, and Updates sections |
| `lib/services/local_api_server.dart` | Add `/api/wifi/scan`, `/api/wifi/connect`, `/api/update` endpoints |
| `pubspec.yaml` | No new dependencies needed — uses dart:io Process for nmcli |

---

### Task 1: Extend HubConfig with Display and Update Fields

**Files:**
- Modify: `lib/config/hub_config.dart`
- Test: `test/config/hub_config_test.dart`

- [ ] **Step 1: Write failing tests for new fields**

In `test/config/hub_config_test.dart`, add tests for the new fields:

```dart
test('new display fields have sensible defaults', () {
  const config = HubConfig();
  expect(config.displayProfile, 'auto');
  expect(config.displayWidth, 0);
  expect(config.displayHeight, 0);
  expect(config.autoUpdate, true);
  expect(config.currentVersion, '');
});

test('new fields round-trip through JSON', () {
  const config = HubConfig(
    displayProfile: 'amoled-11',
    displayWidth: 1184,
    displayHeight: 864,
    autoUpdate: false,
    currentVersion: '1.0.0',
  );
  final json = config.toJson();
  final restored = HubConfig.fromJson(json);
  expect(restored.displayProfile, 'amoled-11');
  expect(restored.displayWidth, 1184);
  expect(restored.displayHeight, 864);
  expect(restored.autoUpdate, false);
  expect(restored.currentVersion, '1.0.0');
});

test('copyWith preserves new fields when unchanged', () {
  const config = HubConfig(
    displayProfile: 'amoled-11',
    autoUpdate: false,
  );
  final updated = config.copyWith(immichUrl: 'http://test');
  expect(updated.displayProfile, 'amoled-11');
  expect(updated.autoUpdate, false);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/config/hub_config_test.dart -v`
Expected: FAIL — `displayProfile`, `displayWidth`, `displayHeight`, `autoUpdate`, `currentVersion` not defined on HubConfig.

- [ ] **Step 3: Add new fields to HubConfig**

In `lib/config/hub_config.dart`, add to the `HubConfig` class fields (after `weatherEntityId`):

```dart
final String displayProfile; // "auto" | "amoled-11" | "rpi-7" | "hdmi"
final int displayWidth;      // 0 = use profile default
final int displayHeight;     // 0 = use profile default
final bool autoUpdate;
final String currentVersion;
```

Add to the constructor with defaults:

```dart
this.displayProfile = 'auto',
this.displayWidth = 0,
this.displayHeight = 0,
this.autoUpdate = true,
this.currentVersion = '',
```

Add to `copyWith`:

```dart
String? displayProfile,
int? displayWidth,
int? displayHeight,
bool? autoUpdate,
String? currentVersion,
```

And in the return body:

```dart
displayProfile: displayProfile ?? this.displayProfile,
displayWidth: displayWidth ?? this.displayWidth,
displayHeight: displayHeight ?? this.displayHeight,
autoUpdate: autoUpdate ?? this.autoUpdate,
currentVersion: currentVersion ?? this.currentVersion,
```

Add to `toJson()`:

```dart
'displayProfile': displayProfile,
'displayWidth': displayWidth,
'displayHeight': displayHeight,
'autoUpdate': autoUpdate,
'currentVersion': currentVersion,
```

Add to `fromJson()`:

```dart
displayProfile: json['displayProfile'] as String? ?? 'auto',
displayWidth: json['displayWidth'] as int? ?? 0,
displayHeight: json['displayHeight'] as int? ?? 0,
autoUpdate: json['autoUpdate'] as bool? ?? true,
currentVersion: json['currentVersion'] as String? ?? '',
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/config/hub_config_test.dart -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat: add display profile and OTA update fields to HubConfig"
```

---

### Task 2: WiFi Service

**Files:**
- Create: `lib/services/wifi_service.dart`
- Create: `test/services/wifi_service_test.dart`

- [ ] **Step 1: Write failing tests for WiFi service**

Create `test/services/wifi_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/wifi_service.dart';

void main() {
  group('WifiNetwork', () {
    test('parses nmcli scan output line', () {
      // nmcli -t -f SSID,SIGNAL,SECURITY device wifi list
      const line = 'MyNetwork:85:WPA2';
      final network = WifiNetwork.fromNmcliLine(line);
      expect(network.ssid, 'MyNetwork');
      expect(network.signalStrength, 85);
      expect(network.security, 'WPA2');
    });

    test('parses open network (no security)', () {
      const line = 'CoffeeShop:42:';
      final network = WifiNetwork.fromNmcliLine(line);
      expect(network.ssid, 'CoffeeShop');
      expect(network.signalStrength, 42);
      expect(network.security, '');
      expect(network.isOpen, true);
    });

    test('skips blank SSID lines', () {
      const line = ':30:WPA2';
      final network = WifiNetwork.fromNmcliLine(line);
      expect(network.ssid, '');
    });
  });

  group('WifiService', () {
    test('parsesScanOutput deduplicates and sorts by signal', () {
      const output = '''MyNetwork:85:WPA2
OtherNet:60:WPA2
MyNetwork:90:WPA2
OpenNet:30:''';
      final networks = WifiService.parseScanOutput(output);
      // MyNetwork deduped to strongest signal (90), then OtherNet (60), then OpenNet (30)
      expect(networks.length, 3);
      expect(networks[0].ssid, 'MyNetwork');
      expect(networks[0].signalStrength, 90);
      expect(networks[1].ssid, 'OtherNet');
      expect(networks[2].ssid, 'OpenNet');
    });

    test('parseConnectionStatus extracts active SSID', () {
      const output = 'wlan0:MyNetwork';
      final ssid = WifiService.parseActiveConnection(output);
      expect(ssid, 'MyNetwork');
    });

    test('parseConnectionStatus returns null when disconnected', () {
      const output = 'wlan0:';
      final ssid = WifiService.parseActiveConnection(output);
      expect(ssid, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/wifi_service_test.dart -v`
Expected: FAIL — `WifiNetwork` and `WifiService` not defined.

- [ ] **Step 3: Implement WiFi service**

Create `lib/services/wifi_service.dart`:

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WifiNetwork {
  final String ssid;
  final int signalStrength;
  final String security;

  const WifiNetwork({
    required this.ssid,
    required this.signalStrength,
    required this.security,
  });

  bool get isOpen => security.isEmpty;
  bool get isSecured => security.isNotEmpty;

  factory WifiNetwork.fromNmcliLine(String line) {
    final parts = line.split(':');
    return WifiNetwork(
      ssid: parts.isNotEmpty ? parts[0] : '',
      signalStrength: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      security: parts.length > 2 ? parts[2] : '',
    );
  }
}

class WifiService {
  /// Scan for available WiFi networks.
  /// Returns empty list on non-Linux platforms or if nmcli is unavailable.
  Future<List<WifiNetwork>> scan() async {
    if (!Platform.isLinux) return [];
    try {
      final result = await Process.run(
        'nmcli',
        ['-t', '-f', 'SSID,SIGNAL,SECURITY', 'device', 'wifi', 'list', '--rescan', 'yes'],
      );
      if (result.exitCode != 0) {
        debugPrint('WiFi scan failed: ${result.stderr}');
        return [];
      }
      return parseScanOutput(result.stdout as String);
    } catch (e) {
      debugPrint('WiFi scan error: $e');
      return [];
    }
  }

  /// Connect to a WiFi network. Returns true on success.
  Future<bool> connect(String ssid, String password) async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run(
        'nmcli',
        ['device', 'wifi', 'connect', ssid, 'password', password],
      );
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('WiFi connect error: $e');
      return false;
    }
  }

  /// Connect to an open (no password) network.
  Future<bool> connectOpen(String ssid) async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run(
        'nmcli',
        ['device', 'wifi', 'connect', ssid],
      );
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('WiFi connect error: $e');
      return false;
    }
  }

  /// Get currently connected WiFi SSID, or null if disconnected.
  Future<String?> activeConnection() async {
    if (!Platform.isLinux) return null;
    try {
      final result = await Process.run(
        'nmcli',
        ['-t', '-f', 'DEVICE,CONNECTION', 'device', 'status'],
      );
      if (result.exitCode != 0) return null;
      return parseActiveConnection(result.stdout as String);
    } catch (e) {
      return null;
    }
  }

  /// Disconnect from the current WiFi network.
  Future<bool> disconnect() async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run('nmcli', ['device', 'disconnect', 'wlan0']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Parse nmcli scan output. Deduplicates by SSID (keeps strongest signal),
  /// filters blank SSIDs, sorts by signal strength descending.
  static List<WifiNetwork> parseScanOutput(String output) {
    final Map<String, WifiNetwork> best = {};
    for (final line in output.trim().split('\n')) {
      if (line.isEmpty) continue;
      final network = WifiNetwork.fromNmcliLine(line);
      if (network.ssid.isEmpty) continue;
      final existing = best[network.ssid];
      if (existing == null || network.signalStrength > existing.signalStrength) {
        best[network.ssid] = network;
      }
    }
    return best.values.toList()
      ..sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
  }

  /// Parse nmcli device status for active WiFi connection.
  /// Input format: "wlan0:MyNetwork" (device:connection)
  static String? parseActiveConnection(String output) {
    for (final line in output.trim().split('\n')) {
      if (!line.startsWith('wlan0:')) continue;
      final ssid = line.substring(6);
      return ssid.isEmpty ? null : ssid;
    }
    return null;
  }
}

final wifiServiceProvider = Provider<WifiService>((ref) => WifiService());
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/wifi_service_test.dart -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/wifi_service.dart test/services/wifi_service_test.dart
git commit -m "feat: add WiFi service with nmcli-based scan and connect"
```

---

### Task 3: Update Service

**Files:**
- Create: `lib/services/update_service.dart`
- Create: `test/services/update_service_test.dart`

- [ ] **Step 1: Write failing tests for update service**

Create `test/services/update_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test('parseLatestRelease extracts version and asset URL', () {
      final json = {
        'tag_name': 'v1.2.0',
        'prerelease': false,
        'draft': false,
        'assets': [
          {
            'name': 'hearth-bundle-1.2.0.tar.gz',
            'browser_download_url':
                'https://github.com/chrisuthe/Hearth-Home/releases/download/v1.2.0/hearth-bundle-1.2.0.tar.gz',
          },
          {
            'name': 'hearth-1.2.0-pi5.img.xz',
            'browser_download_url':
                'https://github.com/chrisuthe/Hearth-Home/releases/download/v1.2.0/hearth-1.2.0-pi5.img.xz',
          },
        ],
      };
      final release = UpdateInfo.fromGitHubRelease(json);
      expect(release, isNotNull);
      expect(release!.version, '1.2.0');
      expect(release.bundleUrl, contains('hearth-bundle-1.2.0.tar.gz'));
    });

    test('parseLatestRelease returns null for prerelease', () {
      final json = {
        'tag_name': 'v2.0.0-beta',
        'prerelease': true,
        'draft': false,
        'assets': [],
      };
      final release = UpdateInfo.fromGitHubRelease(json);
      expect(release, isNull);
    });

    test('parseLatestRelease returns null for draft', () {
      final json = {
        'tag_name': 'v2.0.0',
        'prerelease': false,
        'draft': true,
        'assets': [],
      };
      final release = UpdateInfo.fromGitHubRelease(json);
      expect(release, isNull);
    });

    test('parseLatestRelease returns null when no bundle asset exists', () {
      final json = {
        'tag_name': 'v1.0.0',
        'prerelease': false,
        'draft': false,
        'assets': [
          {
            'name': 'hearth-1.0.0-pi5.img.xz',
            'browser_download_url': 'https://example.com/image.xz',
          },
        ],
      };
      final release = UpdateInfo.fromGitHubRelease(json);
      expect(release, isNull);
    });

    test('isNewerThan compares semver correctly', () {
      final release = UpdateInfo(
        version: '1.2.0',
        bundleUrl: 'https://example.com/bundle.tar.gz',
        tagName: 'v1.2.0',
      );
      expect(release.isNewerThan('1.1.0'), true);
      expect(release.isNewerThan('1.2.0'), false);
      expect(release.isNewerThan('1.3.0'), false);
      expect(release.isNewerThan('0.9.0'), true);
      expect(release.isNewerThan(''), true);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/update_service_test.dart -v`
Expected: FAIL — `UpdateInfo` and `UpdateService` not defined.

- [ ] **Step 3: Implement update service**

Create `lib/services/update_service.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';

class UpdateInfo {
  final String version;
  final String bundleUrl;
  final String tagName;

  const UpdateInfo({
    required this.version,
    required this.bundleUrl,
    required this.tagName,
  });

  /// Parse a GitHub Release API response. Returns null for pre-releases,
  /// drafts, or releases without a bundle asset.
  static UpdateInfo? fromGitHubRelease(Map<String, dynamic> json) {
    if (json['prerelease'] == true || json['draft'] == true) return null;

    final tagName = json['tag_name'] as String? ?? '';
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;

    final assets = json['assets'] as List<dynamic>? ?? [];
    String? bundleUrl;
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      if (name.startsWith('hearth-bundle-') && name.endsWith('.tar.gz')) {
        bundleUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

    if (bundleUrl == null) return null;

    return UpdateInfo(
      version: version,
      bundleUrl: bundleUrl,
      tagName: tagName,
    );
  }

  /// Compare semver strings. Returns true if this version is newer than [other].
  bool isNewerThan(String other) {
    if (other.isEmpty) return true;
    final thisParts = version.split('.').map(int.tryParse).toList();
    final otherParts = other.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final a = i < thisParts.length ? (thisParts[i] ?? 0) : 0;
      final b = i < otherParts.length ? (otherParts[i] ?? 0) : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }
}

class UpdateService {
  static const _releaseUrl =
      'https://api.github.com/repos/chrisuthe/Hearth-Home/releases/latest';

  final Dio _dio;

  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  /// Check for the latest stable release on GitHub.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await _dio.get(
        _releaseUrl,
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return UpdateInfo.fromGitHubRelease(response.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    return null;
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

/// Holds the result of the last update check.
final latestUpdateProvider = FutureProvider<UpdateInfo?>((ref) async {
  final service = ref.read(updateServiceProvider);
  return service.checkForUpdate();
});

/// Whether an update is available compared to the current installed version.
final updateAvailableProvider = Provider<bool>((ref) {
  final current = ref.watch(hubConfigProvider).currentVersion;
  final latest = ref.watch(latestUpdateProvider).valueOrNull;
  if (latest == null) return false;
  return latest.isNewerThan(current);
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/update_service_test.dart -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/update_service.dart test/services/update_service_test.dart
git commit -m "feat: add update service for checking GitHub Releases"
```

---

### Task 4: Setup Wizard Screen

**Files:**
- Create: `lib/screens/setup/setup_wizard.dart`
- Create: `test/screens/setup_wizard_test.dart`
- Modify: `lib/app/app.dart`

- [ ] **Step 1: Write failing widget test for setup wizard**

Create `test/screens/setup_wizard_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/screens/setup/setup_wizard.dart';

void main() {
  group('SetupWizard', () {
    testWidgets('shows WiFi step first', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((ref) => HubConfigNotifier()),
          ],
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      expect(find.text('Connect to WiFi'), findsOneWidget);
    });

    testWidgets('shows skip button on WiFi step', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubConfigProvider.overrideWith((ref) => HubConfigNotifier()),
          ],
          child: const MaterialApp(home: Scaffold(body: SetupWizard())),
        ),
      );
      expect(find.text('Skip (Using Ethernet)'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/setup_wizard_test.dart -v`
Expected: FAIL — `SetupWizard` not defined.

- [ ] **Step 3: Implement setup wizard**

Create `lib/screens/setup/setup_wizard.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../services/wifi_service.dart';
import '../../app/app.dart' show kDialogBackground;

/// Multi-step first-boot wizard: WiFi → Services → Display → Done.
///
/// Shown when hub_config.json is missing or has no HA URL configured.
/// Each step persists config immediately via HubConfigNotifier.update().
/// The wizard can be re-entered from Settings if needed.
class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  int _step = 0;
  static const _stepCount = 4;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: List.generate(_stepCount, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: i <= _step
                            ? const Color(0xFF646CFF)
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Step content
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _WifiStep(
          key: const ValueKey('wifi'),
          onNext: () => setState(() => _step++),
          onSkip: () => setState(() => _step++),
        );
      case 1:
        return _ServicesStep(
          key: const ValueKey('services'),
          onNext: () => setState(() => _step++),
          onBack: () => setState(() => _step--),
        );
      case 2:
        return _DisplayStep(
          key: const ValueKey('display'),
          onNext: () => setState(() => _step++),
          onBack: () => setState(() => _step--),
        );
      case 3:
        return _DoneStep(
          key: const ValueKey('done'),
          onFinish: _finishSetup,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _finishSetup() {
    // Navigate to the main app — the parent widget watches config state
    // and will automatically switch from wizard to HubShell when haUrl is set.
  }
}

class _WifiStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;
  const _WifiStep({super.key, required this.onNext, required this.onSkip});

  @override
  ConsumerState<_WifiStep> createState() => _WifiStepState();
}

class _WifiStepState extends ConsumerState<_WifiStep> {
  List<WifiNetwork> _networks = [];
  bool _scanning = false;
  String? _connectedSsid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    final wifi = ref.read(wifiServiceProvider);
    final networks = await wifi.scan();
    final connected = await wifi.activeConnection();
    if (mounted) {
      setState(() {
        _networks = networks;
        _connectedSsid = connected;
        _scanning = false;
      });
    }
  }

  Future<void> _connect(WifiNetwork network) async {
    if (network.isOpen) {
      final wifi = ref.read(wifiServiceProvider);
      final success = await wifi.connectOpen(network.ssid);
      if (success) {
        setState(() => _connectedSsid = network.ssid);
      } else {
        setState(() => _error = 'Failed to connect to ${network.ssid}');
      }
      return;
    }
    // Show password dialog for secured networks
    final password = await _showPasswordDialog(network.ssid);
    if (password == null) return;
    setState(() => _error = null);
    final wifi = ref.read(wifiServiceProvider);
    final success = await wifi.connect(network.ssid, password);
    if (mounted) {
      if (success) {
        setState(() => _connectedSsid = network.ssid);
      } else {
        setState(() => _error = 'Wrong password or connection failed');
      }
    }
  }

  Future<String?> _showPasswordDialog(String ssid) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogBackground,
        title: Text('Enter password for $ssid'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'WiFi password'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect to WiFi',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 8),
          Text(
            _connectedSsid != null
                ? 'Connected to $_connectedSsid'
                : 'Select your WiFi network',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          if (_scanning)
            const Center(child: CircularProgressIndicator())
          else
            Expanded(
              child: ListView.builder(
                itemCount: _networks.length,
                itemBuilder: (ctx, i) {
                  final network = _networks[i];
                  final isConnected = network.ssid == _connectedSsid;
                  return ListTile(
                    leading: Icon(
                      _signalIcon(network.signalStrength),
                      color: isConnected ? const Color(0xFF646CFF) : Colors.white54,
                    ),
                    title: Text(network.ssid),
                    subtitle: Text(
                      network.isOpen ? 'Open' : network.security,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    trailing: isConnected
                        ? const Icon(Icons.check_circle, color: Color(0xFF646CFF))
                        : network.isSecured
                            ? const Icon(Icons.lock, color: Colors.white24, size: 18)
                            : null,
                    onTap: isConnected ? null : () => _connect(network),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: widget.onSkip,
                child: const Text('Skip (Using Ethernet)'),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _scanning ? null : _scan,
                    child: const Text('Rescan'),
                  ),
                  const SizedBox(width: 12),
                  if (_connectedSsid != null)
                    FilledButton(
                      onPressed: widget.onNext,
                      child: const Text('Next'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  IconData _signalIcon(int strength) {
    if (strength >= 70) return Icons.signal_wifi_4_bar;
    if (strength >= 50) return Icons.network_wifi_3_bar;
    if (strength >= 30) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }
}

class _ServicesStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _ServicesStep({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<_ServicesStep> createState() => _ServicesStepState();
}

class _ServicesStepState extends ConsumerState<_ServicesStep> {
  late final TextEditingController _haUrlController;
  late final TextEditingController _haTokenController;
  late final TextEditingController _immichUrlController;
  late final TextEditingController _immichKeyController;
  late final TextEditingController _frigateUrlController;

  @override
  void initState() {
    super.initState();
    final config = ref.read(hubConfigProvider);
    _haUrlController = TextEditingController(text: config.haUrl);
    _haTokenController = TextEditingController(text: config.haToken);
    _immichUrlController = TextEditingController(text: config.immichUrl);
    _immichKeyController = TextEditingController(text: config.immichApiKey);
    _frigateUrlController = TextEditingController(text: config.frigateUrl);
  }

  @override
  void dispose() {
    _haUrlController.dispose();
    _haTokenController.dispose();
    _immichUrlController.dispose();
    _immichKeyController.dispose();
    _frigateUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(hubConfigProvider.notifier).update((c) => c.copyWith(
          haUrl: _haUrlController.text.trim(),
          haToken: _haTokenController.text.trim(),
          immichUrl: _immichUrlController.text.trim(),
          immichApiKey: _immichKeyController.text.trim(),
          frigateUrl: _frigateUrlController.text.trim(),
        ));
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect Services',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 8),
          Text(
            'Home Assistant is required. Others are optional.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                _buildField('Home Assistant URL', _haUrlController, 'http://192.168.1.x:8123'),
                _buildField('HA Access Token', _haTokenController, 'Long-lived access token', obscure: true),
                const SizedBox(height: 16),
                _buildField('Immich URL', _immichUrlController, 'http://192.168.1.x:2283'),
                _buildField('Immich API Key', _immichKeyController, 'Paste your API key', obscure: true),
                const SizedBox(height: 16),
                _buildField('Frigate URL', _frigateUrlController, 'http://192.168.1.x:5000'),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: _haUrlController.text.trim().isNotEmpty ? _save : null,
                child: const Text('Next'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint,
      {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

class _DisplayStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _DisplayStep({super.key, required this.onNext, required this.onBack});

  @override
  ConsumerState<_DisplayStep> createState() => _DisplayStepState();
}

class _DisplayStepState extends ConsumerState<_DisplayStep> {
  late String _selectedProfile;

  static const _profiles = {
    'auto': ('Auto-detect', 'Let Hearth detect your display'),
    'amoled-11': ('11" AMOLED', '1184x864 (half of 2368x1728)'),
    'rpi-7': ('RPi 7" Touchscreen', '800x480'),
    'hdmi': ('HDMI Monitor', 'Uses native resolution'),
  };

  @override
  void initState() {
    super.initState();
    _selectedProfile = ref.read(hubConfigProvider).displayProfile;
  }

  Future<void> _save() async {
    await ref.read(hubConfigProvider.notifier).update(
          (c) => c.copyWith(displayProfile: _selectedProfile),
        );
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose Display',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 8),
          Text(
            'Select the display connected to your Pi',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: _profiles.entries.map((entry) {
                final (name, description) = entry.value;
                final isSelected = _selectedProfile == entry.key;
                return ListTile(
                  leading: Icon(
                    Icons.monitor,
                    color: isSelected ? const Color(0xFF646CFF) : Colors.white54,
                  ),
                  title: Text(name),
                  subtitle: Text(
                    description,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Color(0xFF646CFF))
                      : null,
                  onTap: () => setState(() => _selectedProfile = entry.key),
                );
              }).toList(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: _save,
                child: const Text('Next'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DoneStep extends StatelessWidget {
  final VoidCallback onFinish;
  const _DoneStep({super.key, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: Color(0xFF646CFF)),
          const SizedBox(height: 24),
          const Text(
            'All Set!',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 8),
          Text(
            'You can change these settings anytime.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 48),
          FilledButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.home),
            label: const Text('Start Hearth'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/screens/setup_wizard_test.dart -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/setup/setup_wizard.dart test/screens/setup_wizard_test.dart
git commit -m "feat: add setup wizard with WiFi, services, and display steps"
```

---

### Task 5: Route to Setup Wizard on First Boot

**Files:**
- Modify: `lib/app/app.dart`

- [ ] **Step 1: Write failing test for setup routing**

Add to `test/screens/setup_wizard_test.dart`:

```dart
testWidgets('HearthApp shows setup wizard when haUrl is empty', (tester) async {
  final notifier = HubConfigNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hubConfigProvider.overrideWith((ref) => notifier),
      ],
      child: const HearthApp(),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Connect to WiFi'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/setup_wizard_test.dart -v`
Expected: FAIL — HearthApp shows HubShell, not SetupWizard.

- [ ] **Step 3: Modify HearthApp to route based on config state**

In `lib/app/app.dart`, add the import and modify the `home` property:

```dart
import 'hub_shell.dart';
import '../config/hub_config.dart';
import '../screens/setup/setup_wizard.dart';
```

Change the `build` method's `home` parameter:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final config = ref.watch(hubConfigProvider);
  final needsSetup = config.haUrl.isEmpty;

  return MaterialApp(
    title: 'Hearth',
    debugShowCheckedModeBanner: false,
    scrollBehavior: const _TouchScrollBehavior(),
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorSchemeSeed: const Color(0xFF646CFF),
      useMaterial3: true,
      fontFamily: 'Roboto',
      dialogTheme: const DialogThemeData(backgroundColor: kDialogBackground),
    ),
    home: Scaffold(
      body: needsSetup ? const SetupWizard() : const HubShell(),
    ),
  );
}
```

Remove the `const` from `Scaffold` and `HubShell` since the body is now conditional.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/screens/setup_wizard_test.dart -v`
Expected: ALL PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `flutter test -v`
Expected: ALL PASS. Existing tests that don't mock hubConfigProvider may need an override if they relied on HubShell being shown unconditionally. If `hub_shell_test.dart` fails, add `hubConfigProvider.overrideWith` with a config that has a non-empty `haUrl`.

- [ ] **Step 6: Commit**

```bash
git add lib/app/app.dart test/screens/setup_wizard_test.dart
git commit -m "feat: route to setup wizard when config is incomplete"
```

---

### Task 6: WiFi Settings Section in Settings Screen

**Files:**
- Create: `lib/screens/settings/wifi_settings.dart`
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Create WiFi settings widget**

Create `lib/screens/settings/wifi_settings.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/wifi_service.dart';
import '../../app/app.dart' show kDialogBackground;

/// WiFi management section for the Settings screen.
/// Scans for networks and allows connecting/disconnecting.
class WifiSettingsSection extends ConsumerStatefulWidget {
  const WifiSettingsSection({super.key});

  @override
  ConsumerState<WifiSettingsSection> createState() => _WifiSettingsSectionState();
}

class _WifiSettingsSectionState extends ConsumerState<WifiSettingsSection> {
  String? _connectedSsid;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final wifi = ref.read(wifiServiceProvider);
    final ssid = await wifi.activeConnection();
    if (mounted) {
      setState(() {
        _connectedSsid = ssid;
        _loaded = true;
      });
    }
  }

  Future<void> _showWifiPicker() async {
    final wifi = ref.read(wifiServiceProvider);
    final networks = await wifi.scan();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _WifiPickerDialog(
        networks: networks,
        connectedSsid: _connectedSsid,
        wifiService: wifi,
      ),
    );
    // Refresh status after dialog closes
    _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = !_loaded
        ? 'Checking...'
        : _connectedSsid != null
            ? 'Connected to $_connectedSsid'
            : 'Not connected';

    return ListTile(
      leading: Icon(
        _connectedSsid != null ? Icons.wifi : Icons.wifi_off,
        color: Colors.white54,
        size: 22,
      ),
      title: const Text('WiFi Network', style: TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: _showWifiPicker,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

class _WifiPickerDialog extends StatefulWidget {
  final List<WifiNetwork> networks;
  final String? connectedSsid;
  final WifiService wifiService;

  const _WifiPickerDialog({
    required this.networks,
    required this.connectedSsid,
    required this.wifiService,
  });

  @override
  State<_WifiPickerDialog> createState() => _WifiPickerDialogState();
}

class _WifiPickerDialogState extends State<_WifiPickerDialog> {
  late String? _connectedSsid;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connectedSsid = widget.connectedSsid;
  }

  Future<void> _connect(WifiNetwork network) async {
    String? password;
    if (network.isSecured) {
      final controller = TextEditingController();
      password = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kDialogBackground,
          title: Text('Password for ${network.ssid}'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Connect'),
            ),
          ],
        ),
      );
      if (password == null) return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    final success = network.isOpen
        ? await widget.wifiService.connectOpen(network.ssid)
        : await widget.wifiService.connect(network.ssid, password!);

    if (mounted) {
      setState(() {
        _connecting = false;
        if (success) {
          _connectedSsid = network.ssid;
        } else {
          _error = 'Failed to connect';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kDialogBackground,
      title: const Text('WiFi Networks'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            if (_connecting)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: widget.networks.length,
                  itemBuilder: (ctx, i) {
                    final network = widget.networks[i];
                    final isConnected = network.ssid == _connectedSsid;
                    return ListTile(
                      dense: true,
                      title: Text(network.ssid),
                      subtitle: Text('${network.signalStrength}% • ${network.isOpen ? "Open" : network.security}'),
                      trailing: isConnected
                          ? const Icon(Icons.check_circle, color: Color(0xFF646CFF))
                          : null,
                      onTap: isConnected ? null : () => _connect(network),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Add WiFi section to Settings screen**

In `lib/screens/settings/settings_screen.dart`, add the import:

```dart
import 'wifi_settings.dart';
```

Add the WiFi section at the top of the `children` list, before the Connections section header:

```dart
// --- Network section ---
_SectionHeader(title: 'Network'),
const SizedBox(height: 8),
const WifiSettingsSection(),
const SizedBox(height: 24),
```

- [ ] **Step 3: Run full test suite**

Run: `flutter test -v`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings/wifi_settings.dart lib/screens/settings/settings_screen.dart
git commit -m "feat: add WiFi network management to Settings screen"
```

---

### Task 7: Display and Update Settings Sections

**Files:**
- Create: `lib/screens/settings/display_settings.dart`
- Create: `lib/screens/settings/update_settings.dart`
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Create display settings widget**

Create `lib/screens/settings/display_settings.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../app/app.dart' show kDialogBackground;

/// Display profile picker for the Settings screen.
class DisplaySettingsSection extends ConsumerWidget {
  const DisplaySettingsSection({super.key});

  static const _profiles = {
    'auto': 'Auto-detect',
    'amoled-11': '11" AMOLED (1184x864)',
    'rpi-7': 'RPi 7" Touchscreen (800x480)',
    'hdmi': 'HDMI Monitor (native)',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final label = _profiles[config.displayProfile] ?? config.displayProfile;

    return ListTile(
      leading: const Icon(Icons.monitor, color: Colors.white54, size: 22),
      title: const Text('Display Profile', style: TextStyle(fontSize: 15)),
      subtitle: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () => _showProfilePicker(context, ref, config),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Future<void> _showProfilePicker(
      BuildContext context, WidgetRef ref, HubConfig config) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: kDialogBackground,
        title: const Text('Display Profile'),
        children: _profiles.entries.map((entry) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, entry.key),
            child: Row(
              children: [
                if (entry.key == config.displayProfile)
                  const Icon(Icons.check, size: 18, color: Colors.amber)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 12),
                Text(entry.value),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (result != null) {
      ref.read(hubConfigProvider.notifier).update(
            (c) => c.copyWith(displayProfile: result),
          );
    }
  }
}
```

- [ ] **Step 2: Create update settings widget**

Create `lib/screens/settings/update_settings.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../services/update_service.dart';

/// OTA update status and controls for the Settings screen.
class UpdateSettingsSection extends ConsumerWidget {
  const UpdateSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    final latestAsync = ref.watch(latestUpdateProvider);
    final updateAvailable = ref.watch(updateAvailableProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline, color: Colors.white54, size: 22),
          title: const Text('Current Version', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            config.currentVersion.isEmpty ? 'Unknown' : 'v${config.currentVersion}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        latestAsync.when(
          data: (latest) {
            if (latest == null) {
              return const ListTile(
                leading: Icon(Icons.cloud_off, color: Colors.white54, size: 22),
                title: Text('Update Check', style: TextStyle(fontSize: 15)),
                subtitle: Text('Could not reach GitHub'),
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              );
            }
            return ListTile(
              leading: Icon(
                updateAvailable ? Icons.system_update : Icons.check_circle,
                color: updateAvailable ? Colors.amber : Colors.green,
                size: 22,
              ),
              title: Text(
                updateAvailable ? 'Update Available' : 'Up to Date',
                style: const TextStyle(fontSize: 15),
              ),
              subtitle: Text(
                'Latest: v${latest.version}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            );
          },
          loading: () => const ListTile(
            leading: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Checking for updates...', style: TextStyle(fontSize: 15)),
            contentPadding: EdgeInsets.symmetric(horizontal: 8),
          ),
          error: (_, __) => const ListTile(
            leading: Icon(Icons.error_outline, color: Colors.redAccent, size: 22),
            title: Text('Update check failed', style: TextStyle(fontSize: 15)),
            contentPadding: EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.autorenew, color: Colors.white54),
          title: const Text('Auto-Update'),
          subtitle: Text(
            config.autoUpdate ? 'Updates install automatically' : 'Manual updates only',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          ),
          value: config.autoUpdate,
          onChanged: (v) => ref
              .read(hubConfigProvider.notifier)
              .update((c) => c.copyWith(autoUpdate: v)),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Add both sections to Settings screen**

In `lib/screens/settings/settings_screen.dart`, add imports:

```dart
import 'display_settings.dart';
import 'update_settings.dart';
```

Add the Display Profile tile in the existing "Display" section, after the 24-Hour Clock toggle:

```dart
const DisplaySettingsSection(),
```

Add a new "Updates" section at the bottom of the children list (before the final `]`):

```dart
const SizedBox(height: 24),

// --- Updates section ---
_SectionHeader(title: 'Updates'),
const SizedBox(height: 8),
const UpdateSettingsSection(),
```

- [ ] **Step 4: Run full test suite**

Run: `flutter test -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings/display_settings.dart lib/screens/settings/update_settings.dart lib/screens/settings/settings_screen.dart
git commit -m "feat: add display profile and OTA update sections to Settings"
```

---

### Task 8: Extend LocalApiServer with WiFi and Update Endpoints

**Files:**
- Modify: `lib/services/local_api_server.dart`
- Modify: `test/services/local_api_server_test.dart`

- [ ] **Step 1: Write failing tests for new endpoints**

Add to `test/services/local_api_server_test.dart`:

```dart
test('GET /api/wifi/scan returns JSON array', () async {
  // On Windows/non-Linux this returns an empty list, which is fine for CI
  final response = await get('/api/wifi/scan',
      headers: {'Authorization': 'Bearer test-key'});
  expect(response.statusCode, 200);
  final body = await response.transform(utf8.decoder).join();
  final data = jsonDecode(body);
  expect(data, isA<Map>());
  expect(data['networks'], isA<List>());
});

test('GET /api/update/status returns version info', () async {
  final response = await get('/api/update/status',
      headers: {'Authorization': 'Bearer test-key'});
  expect(response.statusCode, 200);
  final body = await response.transform(utf8.decoder).join();
  final data = jsonDecode(body);
  expect(data, isA<Map>());
  expect(data.containsKey('currentVersion'), true);
  expect(data.containsKey('autoUpdate'), true);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/local_api_server_test.dart -v`
Expected: FAIL — 404 on the new endpoints.

- [ ] **Step 3: Add WiFi and update endpoints to LocalApiServer**

In `lib/services/local_api_server.dart`, add imports:

```dart
import 'wifi_service.dart';
import 'update_service.dart';
```

Add `WifiService` and `UpdateService` as constructor parameters:

```dart
final WifiService _wifiService;
final UpdateService _updateService;

LocalApiServer({
  required DisplayModeService displayModeService,
  required HubConfigNotifier configNotifier,
  WifiService? wifiService,
  UpdateService? updateService,
})  : _displayModeService = displayModeService,
      _configNotifier = configNotifier,
      _wifiService = wifiService ?? WifiService(),
      _updateService = updateService ?? UpdateService();
```

Add route handling in `_handleRequest` for the new paths:

```dart
} else if (path == '/api/wifi/scan' && request.method == 'GET') {
  await _handleWifiScan(request);
} else if (path == '/api/wifi/connect' && request.method == 'POST') {
  await _handleWifiConnect(request);
} else if (path == '/api/update/status' && request.method == 'GET') {
  await _handleUpdateStatus(request);
```

Add the handler methods:

```dart
Future<void> _handleWifiScan(HttpRequest request) async {
  final networks = await _wifiService.scan();
  final connected = await _wifiService.activeConnection();
  request.response
    ..statusCode = 200
    ..headers.contentType = ContentType.json
    ..write(jsonEncode({
      'networks': networks
          .map((n) => {
                'ssid': n.ssid,
                'signal': n.signalStrength,
                'security': n.security,
                'isOpen': n.isOpen,
              })
          .toList(),
      'connected': connected,
    }));
  await request.response.close();
}

Future<void> _handleWifiConnect(HttpRequest request) async {
  final body = await _readBody(request);
  if (body == null) return;
  final data = jsonDecode(body) as Map<String, dynamic>;
  final ssid = data['ssid'] as String? ?? '';
  final password = data['password'] as String? ?? '';

  final success = password.isEmpty
      ? await _wifiService.connectOpen(ssid)
      : await _wifiService.connect(ssid, password);

  request.response
    ..statusCode = success ? 200 : 500
    ..headers.contentType = ContentType.json
    ..write(jsonEncode({'success': success}));
  await request.response.close();
}

Future<void> _handleUpdateStatus(HttpRequest request) async {
  final config = _configNotifier.current;
  request.response
    ..statusCode = 200
    ..headers.contentType = ContentType.json
    ..write(jsonEncode({
      'currentVersion': config.currentVersion,
      'autoUpdate': config.autoUpdate,
    }));
  await request.response.close();
}
```

Update the provider to pass the new services:

```dart
final localApiServerProvider = Provider<LocalApiServer>((ref) {
  final displayService = ref.read(displayModeServiceProvider);
  final configNotifier = ref.read(hubConfigProvider.notifier);
  return LocalApiServer(
    displayModeService: displayService,
    configNotifier: configNotifier,
  );
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/local_api_server_test.dart -v`
Expected: ALL PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test -v`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/local_api_server.dart test/services/local_api_server_test.dart
git commit -m "feat: add WiFi scan/connect and update status API endpoints"
```

---

### Task 9: Final Integration Test

**Files:**
- All modified/created files

- [ ] **Step 1: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 2: Run full test suite**

Run: `flutter test -v`
Expected: ALL PASS

- [ ] **Step 3: Test on Windows desktop**

Run: `flutter run -d windows`
Expected: App launches. With empty config, shows setup wizard. WiFi step shows empty list (expected on Windows — nmcli not available). Can skip WiFi, enter service URLs, pick display, and reach main app. Settings screen shows new WiFi, Display Profile, and Updates sections.

- [ ] **Step 4: Commit any fixes**

If any issues found, fix and commit with descriptive message.
