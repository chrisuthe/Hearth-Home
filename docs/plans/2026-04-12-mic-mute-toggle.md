# Mic Mute Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an on-screen microphone mute toggle that controls the ALSA capture device, persists across reboots, and is always visible in the HubShell overlay.

**Architecture:** New `micMuted` bool in HubConfig, a small `lib/utils/alsa_utils.dart` utility for ALSA capture mute, a mic icon button in the HubShell Stack (top-right), and startup initialization in main.dart.

**Tech Stack:** Flutter, Riverpod, dart:io Process (amixer), ALSA

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/config/hub_config.dart` | Modify | Add `micMuted` field to config model |
| `test/config/hub_config_test.dart` | Modify | Add `micMuted` to round-trip test |
| `lib/utils/alsa_utils.dart` | Create | ALSA capture mute/unmute via amixer |
| `test/utils/alsa_utils_test.dart` | Create | Unit test for ALSA util (non-Linux no-op) |
| `lib/app/hub_shell.dart` | Modify | Add mic mute icon button to Stack |
| `lib/main.dart` | Modify | Apply persisted mic mute on startup |

---

### Task 1: Add `micMuted` to HubConfig

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Add `micMuted` field to the config test's round-trip assertion**

In `test/config/hub_config_test.dart`, find the `'round-trips through JSON without data loss'` test. Add `micMuted: true` to the constructor and an assertion at the end:

```dart
const config = HubConfig(
  immichUrl: 'http://immich.local:2283',
  immichApiKey: 'test-key',
  haUrl: 'ws://ha.local:8123',
  haToken: 'ha-token',
  nightModeSource: 'ha_entity',
  nightModeHaEntity: 'light.living_room',
  idleTimeoutSeconds: 60,
  micMuted: true,
);
```

And after the existing assertions:

```dart
expect(restored.micMuted, true);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/config/hub_config_test.dart -v`
Expected: Compile error — `micMuted` is not a field on HubConfig.

- [ ] **Step 3: Add `micMuted` to HubConfig**

In `lib/config/hub_config.dart`, add the field, constructor param, copyWith param, toJson entry, and fromJson entry. Follow the exact pattern used by `showVoiceFeedback` (bool, default false):

Field declaration (after `showVoiceFeedback`):
```dart
final bool micMuted;
```

Constructor param (after `this.showVoiceFeedback = true`):
```dart
this.micMuted = false,
```

copyWith param (after `bool? showVoiceFeedback`):
```dart
bool? micMuted,
```

copyWith body (after `showVoiceFeedback: showVoiceFeedback ?? this.showVoiceFeedback`):
```dart
micMuted: micMuted ?? this.micMuted,
```

toJson (after `'showVoiceFeedback': showVoiceFeedback`):
```dart
'micMuted': micMuted,
```

fromJson (after `showVoiceFeedback: json['showVoiceFeedback'] as bool? ?? true`):
```dart
micMuted: json['micMuted'] as bool? ?? false,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/config/hub_config_test.dart -v`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat: add micMuted field to HubConfig"
```

---

### Task 2: Create ALSA capture mute utility

**Files:**
- Create: `lib/utils/alsa_utils.dart`
- Create: `test/utils/alsa_utils_test.dart`

- [ ] **Step 1: Write the test**

Create `test/utils/alsa_utils_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/utils/alsa_utils.dart';

void main() {
  group('AlsaUtils', () {
    test('setMicMuted completes without error on non-Linux', () async {
      // On Windows CI/dev, this should be a no-op that completes normally.
      if (!Platform.isLinux) {
        await setMicMuted(true);
        await setMicMuted(false);
        // No exception means success — it's a no-op on non-Linux.
      }
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/utils/alsa_utils_test.dart -v`
Expected: Compile error — `setMicMuted` not found.

- [ ] **Step 3: Implement the utility**

Create `lib/utils/alsa_utils.dart`:

```dart
import 'dart:io';
import '../utils/logger.dart';

/// Mute or unmute the ALSA capture device.
///
/// Uses `amixer set Capture nocap/cap` to control the hardware mic.
/// No-op on non-Linux platforms.
Future<void> setMicMuted(bool muted) async {
  if (!Platform.isLinux) return;
  try {
    final result = await Process.run(
      'amixer', ['set', 'Capture', muted ? 'nocap' : 'cap'],
    );
    if (result.exitCode != 0) {
      Log.w('ALSA', 'amixer set Capture ${muted ? "nocap" : "cap"} '
          'failed (exit ${result.exitCode}): ${result.stderr}');
    }
  } catch (e) {
    Log.w('ALSA', 'Failed to set mic mute: $e');
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/utils/alsa_utils_test.dart -v`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/alsa_utils.dart test/utils/alsa_utils_test.dart
git commit -m "feat: add ALSA capture mute utility"
```

---

### Task 3: Add mic mute icon button to HubShell

**Files:**
- Modify: `lib/app/hub_shell.dart`

- [ ] **Step 1: Add import**

Add at the top of `lib/app/hub_shell.dart`:

```dart
import '../utils/alsa_utils.dart';
```

- [ ] **Step 2: Add the mic mute button to the Stack**

In the `build` method of `_HubShellState`, inside the `Stack` children list, add the mic mute button after the `VoicePillOverlay` and before the edge-swipe zones:

```dart
// Mic mute toggle — always visible, top-right corner.
Positioned(
  top: 12,
  right: 12,
  child: Consumer(builder: (context, ref, _) {
    final muted = ref.watch(
      hubConfigProvider.select((c) => c.micMuted),
    );
    return IconButton(
      icon: Icon(
        muted ? Icons.mic_off : Icons.mic,
        color: muted ? Colors.red : Colors.white38,
        size: 22,
      ),
      onPressed: () {
        final newValue = !muted;
        ref.read(hubConfigProvider.notifier).update(
          (c) => c.copyWith(micMuted: newValue),
        );
        setMicMuted(newValue);
      },
    );
  }),
),
```

- [ ] **Step 3: Run analyze to verify no errors**

Run: `flutter analyze lib/app/hub_shell.dart`
Expected: No errors or warnings (info-level is OK).

- [ ] **Step 4: Commit**

```bash
git add lib/app/hub_shell.dart
git commit -m "feat: add mic mute toggle button to HubShell"
```

---

### Task 4: Apply mic mute on startup

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add import**

Add at the top of `lib/main.dart`:

```dart
import 'utils/alsa_utils.dart';
```

- [ ] **Step 2: Apply mic mute after config loads**

After the timezone block (around line 54) and before the local API server block, add:

```dart
// Apply persisted mic mute state to ALSA capture device.
if (!kIsWeb) {
  final micMuted = container.read(hubConfigProvider).micMuted;
  if (micMuted) {
    await setMicMuted(true);
  }
}
```

- [ ] **Step 3: Run analyze and all tests**

Run: `flutter analyze --no-fatal-infos && flutter test`
Expected: No errors, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: apply persisted mic mute on startup"
```

---

### Task 5: Manual verification

- [ ] **Step 1: Run on Windows**

Run: `flutter run -d windows`
Verify: Mic icon visible in top-right corner. Tapping toggles between white mic and red mic_off. No crashes (ALSA calls are no-ops on Windows).

- [ ] **Step 2: Verify persistence**

Tap to mute, close the app, relaunch. Verify the icon starts in the muted (red) state.

- [ ] **Step 3: Final commit if any tweaks needed**

If icon size/position needs adjustment, tweak and commit.
