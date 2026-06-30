# Dynamic native-resolution webview rendering — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render each webview's WPE frame at the box's true physical pixel size (derived per panel/`uiScale`), with automatic fallback to today's 1920×1080 pipeline if the sized caps fail to negotiate.

**Architecture:** A pure geometry function turns the runtime box-logical size, devicePixelRatio, and uiScale into an even-integer physical render size. `WebviewSession` pins that size on the `wpevideosrc` output via a caps filter and self-heals (rebuilds once without caps) if the sized pipeline yields no frame. The session pool keys on the requested size (2px tolerance) so a panel/scale change rebuilds; `WebviewScreen` computes the size inside its `LayoutBuilder` and feeds the pool.

**Tech Stack:** Flutter/Dart, Riverpod, flutterpi_gstreamer_video_player (GStreamer wpevideosrc), flutter_test.

## Global Constraints

- Lints enforce `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print` — use `Log.*` (never `print`).
- Tests use `flutter_test`; run with `/c/flutter/bin/flutter test <path>` (Dart/Flutter SDK is at `C:\flutter`, not on PATH).
- Pipeline contract: the wpe source element is named `websrc` and is `wpevideosrc` (owns `configure-web-view`). Do not rename or revert to `wpesrc`.
- No caps filter directly before `appsink` (breaks EGL format negotiation). The size caps go immediately after the source, on the `video/x-raw(memory:GLMemory)` caps.
- Commit messages: no AI/Claude self-reference, no `Co-Authored-By`.
- Release/rollout (Task 6 only): bump `pubspec.yaml` version, annotated tag `vX.Y.Z` (message `Hearth vX.Y.Z`), push `main` + tag to BOTH `origin` (Gitea) and `github` (GitHub). Rollback floor: app **v1.13.8**.

## File Structure

- **Create** `lib/modules/webview/webview_geometry.dart` — pure `webviewRenderPx` size math. One responsibility: resolution arithmetic, no Flutter widget deps.
- **Create** `test/modules/webview/webview_geometry_test.dart` — unit tests for the math.
- **Modify** `lib/modules/webview/webview_session.dart` — replace dead `textureWidth/textureHeight` with `renderWidth`/`renderHeight`/`useSizeCaps`; size caps in `pipelineString`; one-shot fallback in `_initController`; pure `shouldFallbackToNoCaps` predicate.
- **Modify** `test/modules/webview/webview_session_test.dart` — pipeline caps on/off + fallback predicate.
- **Modify** `lib/modules/webview/webview_session_pool.dart` — `renderSize` param on `getOrCreate`, factory typedef, size-aware identity (2px tolerance).
- **Modify** `test/modules/webview/webview_session_pool_test.dart` — size keying tests.
- **Modify** `lib/modules/webview/webview_screen.dart` — compute `renderPx` in `LayoutBuilder`, thread to pool; threshold re-resolve.

---

### Task 1: Pure render-size math (`webviewRenderPx`)

**Files:**
- Create: `lib/modules/webview/webview_geometry.dart`
- Test: `test/modules/webview/webview_geometry_test.dart`

**Interfaces:**
- Produces: `Size webviewRenderPx(Size boxLogical, double dpr, double uiScale)` — returns an even-integer-valued physical pixel `Size`, each dimension ≥ 16; degenerate (≤0 / non-finite) inputs clamp to 16.

- [ ] **Step 1: Write the failing test**

```dart
// test/modules/webview/webview_geometry_test.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/webview/webview_geometry.dart';

void main() {
  group('webviewRenderPx', () {
    test('dpr=1, scale=1 → box size unchanged', () {
      expect(webviewRenderPx(const Size(1920, 1200), 1, 1),
          const Size(1920, 1200));
    });

    test('multiplies by devicePixelRatio', () {
      expect(webviewRenderPx(const Size(600, 400), 2, 1),
          const Size(1200, 800));
    });

    test('multiplies by uiScale', () {
      expect(webviewRenderPx(const Size(800, 600), 1, 1.5),
          const Size(1200, 900));
    });

    test('rounds each dimension to an even integer', () {
      // 1921*1*1 = 1921 → nearest even 1922; 1 → clamped to 16.
      expect(webviewRenderPx(const Size(1921, 1), 1, 1),
          const Size(1922, 16));
    });

    test('clamps degenerate / non-finite inputs to 16', () {
      expect(webviewRenderPx(Size.zero, 1, 1), const Size(16, 16));
      expect(webviewRenderPx(const Size(800, 600), double.infinity, 1),
          const Size(16, 16));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/flutter/bin/flutter test test/modules/webview/webview_geometry_test.dart`
Expected: FAIL — `Error: Method not found: 'webviewRenderPx'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/modules/webview/webview_geometry.dart
import 'dart:ui';

/// Physical pixel size a webview frame should render at to be 1:1 with the
/// [boxLogical] area it occupies on screen.
///
/// `× uiScale` because `HearthScaleScope` paints the box through a
/// `Transform.scale(uiScale)`; `× dpr` converts logical→physical. Each
/// dimension is rounded to an even integer (GL/encoder friendliness) and
/// floored at 16. Degenerate or non-finite inputs collapse to 16 so a bad
/// layout pass can never produce a zero/NaN-sized pipeline.
Size webviewRenderPx(Size boxLogical, double dpr, double uiScale) {
  double dim(double logical) {
    final px = logical * uiScale * dpr;
    if (!px.isFinite || px <= 0) return 16;
    final even = (px / 2).round() * 2;
    return (even < 16 ? 16 : even).toDouble();
  }

  return Size(dim(boxLogical.width), dim(boxLogical.height));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/c/flutter/bin/flutter test test/modules/webview/webview_geometry_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/modules/webview/webview_geometry.dart test/modules/webview/webview_geometry_test.dart
git commit -m "feat(webview): pure physical render-size math for webviews"
```

---

### Task 2: Session render-size fields + size caps in the pipeline

**Files:**
- Modify: `lib/modules/webview/webview_session.dart`
- Test: `test/modules/webview/webview_session_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `WebviewSession` and `WebviewSession.testing` gain named params `int renderWidth = 1920`, `int renderHeight = 1080`, `bool useSizeCaps = false`, exposed as public final fields. `pipelineString` includes the size caps clause iff caps are active.

- [ ] **Step 1: Write the failing tests** (append inside the existing `group('WebviewSession state machine', …)` in `test/modules/webview/webview_session_test.dart`)

```dart
    test('pipeline includes size caps when useSizeCaps is set', () {
      final session = WebviewSession.testing(
        url: 'https://ha.example/lovelace',
        renderWidth: 1920,
        renderHeight: 1200,
        useSizeCaps: true,
      );
      expect(
        session.pipelineString,
        contains('video/x-raw(memory:GLMemory),width=1920,height=1200'),
      );
      expect(session.pipelineString, contains('wpevideosrc'));
      expect(session.pipelineString, contains('appsink name=sink'));
    });

    test('pipeline omits size caps when useSizeCaps is false', () {
      final session = WebviewSession.testing(url: 'https://ha.example');
      expect(session.pipelineString, isNot(contains('video/x-raw')));
      expect(session.pipelineString, contains('wpevideosrc'));
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/c/flutter/bin/flutter test test/modules/webview/webview_session_test.dart`
Expected: FAIL — `No named parameter with the name 'renderWidth'`.

- [ ] **Step 3: Replace the dead texture fields and the pipeline getter**

In `lib/modules/webview/webview_session.dart`, replace the two field declarations:

```dart
  final int textureWidth;
  final int textureHeight;
```

with:

```dart
  /// Target physical pixel size for the wpe frame. Requested by the screen
  /// from the panel geometry; used by the pool as part of session identity.
  final int renderWidth;
  final int renderHeight;

  /// Whether to pin the wpe render size with a caps filter. When the sized
  /// pipeline fails to negotiate on a panel, the session flips this off and
  /// rebuilds once (see [_initController]).
  final bool useSizeCaps;
  bool _capsActive;
  bool _sizeCapsFallbackTried = false;
```

Update the default constructor — replace:

```dart
  WebviewSession({
    required this.url,
    this.textureWidth = 1184,
    this.textureHeight = 864,
    this.initScript,
    this.initScriptAllowOrigin,
  }) : _isTesting = false {
    _initController();
  }
```

with:

```dart
  WebviewSession({
    required this.url,
    this.initScript,
    this.initScriptAllowOrigin,
    this.renderWidth = 1920,
    this.renderHeight = 1080,
    this.useSizeCaps = false,
  })  : _isTesting = false,
        _capsActive = useSizeCaps {
    _initController();
  }
```

Update the testing constructor — replace:

```dart
  @visibleForTesting
  WebviewSession.testing({
    required this.url,
    this.textureWidth = 1184,
    this.textureHeight = 864,
    this.initScript,
    this.initScriptAllowOrigin,
  }) : _isTesting = true;
```

with:

```dart
  @visibleForTesting
  WebviewSession.testing({
    required this.url,
    this.initScript,
    this.initScriptAllowOrigin,
    this.renderWidth = 1920,
    this.renderHeight = 1080,
    this.useSizeCaps = false,
  })  : _isTesting = true,
        _capsActive = useSizeCaps;
```

Replace the `pipelineString` getter:

```dart
  String get pipelineString =>
      'wpevideosrc name=$wpeSrcName location=$url draw-background=false '
      '! gldownload '
      '! videoconvert '
      '! appsink name=sink';
```

with:

```dart
  String get pipelineString {
    final caps = _capsActive
        ? ' ! video/x-raw(memory:GLMemory),width=$renderWidth,height=$renderHeight'
        : '';
    return 'wpevideosrc name=$wpeSrcName location=$url draw-background=false$caps '
        '! gldownload '
        '! videoconvert '
        '! appsink name=sink';
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/c/flutter/bin/flutter test test/modules/webview/webview_session_test.dart`
Expected: PASS (existing tests + 2 new). Note: the existing `builds correct pipeline string` test still asserts `contains('wpevideosrc')`, which remains true.

- [ ] **Step 5: Commit**

```bash
git add lib/modules/webview/webview_session.dart test/modules/webview/webview_session_test.dart
git commit -m "feat(webview): pin wpe render size via caps filter"
```

---

### Task 3: One-shot fallback when sized caps yield no frame

**Files:**
- Modify: `lib/modules/webview/webview_session.dart`
- Test: `test/modules/webview/webview_session_test.dart`

**Interfaces:**
- Produces: top-level pure predicate
  `bool shouldFallbackToNoCaps({required bool useSizeCaps, required bool alreadyTried, required bool initErrored, required Size size})`
  = `useSizeCaps && !alreadyTried && (initErrored || size == Size.zero)`.
- `_initController` uses the predicate to rebuild once with `_capsActive = false`.

- [ ] **Step 1: Write the failing test** (append to the same group)

```dart
    test('shouldFallbackToNoCaps fires on size==zero, once only', () {
      expect(
        shouldFallbackToNoCaps(
            useSizeCaps: true,
            alreadyTried: false,
            initErrored: false,
            size: Size.zero),
        isTrue,
      );
      // Already tried → never again.
      expect(
        shouldFallbackToNoCaps(
            useSizeCaps: true,
            alreadyTried: true,
            initErrored: true,
            size: Size.zero),
        isFalse,
      );
      // Caps off → nothing to fall back from.
      expect(
        shouldFallbackToNoCaps(
            useSizeCaps: false,
            alreadyTried: false,
            initErrored: true,
            size: Size.zero),
        isFalse,
      );
      // Healthy sized frame → no fallback.
      expect(
        shouldFallbackToNoCaps(
            useSizeCaps: true,
            alreadyTried: false,
            initErrored: false,
            size: const Size(1920, 1200)),
        isFalse,
      );
    });
```

Add the import at the top of the test file if not present:

```dart
import 'dart:ui';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/c/flutter/bin/flutter test test/modules/webview/webview_session_test.dart`
Expected: FAIL — `Method not found: 'shouldFallbackToNoCaps'`.

- [ ] **Step 3: Add the predicate and wire the fallback**

At the top level of `lib/modules/webview/webview_session.dart` (after the imports, before the `enum`):

```dart
/// Whether a sized (caps-pinned) webview pipeline should be rebuilt once
/// without the size caps. True only when caps were requested, we haven't
/// already retried, and the sized attempt produced no usable frame (it
/// errored or negotiated a zero size). Pure so it can be unit-tested.
bool shouldFallbackToNoCaps({
  required bool useSizeCaps,
  required bool alreadyTried,
  required bool initErrored,
  required Size size,
}) =>
    useSizeCaps && !alreadyTried && (initErrored || size == Size.zero);
```

Replace the body of `_initController` with the fallback-aware version:

```dart
  Future<void> _initController() async {
    Log.i('Webview', 'init starting for $url (caps=$_capsActive '
        '${_capsActive ? "$renderWidth x $renderHeight" : "default"})');
    var initErrored = false;
    try {
      final c = FlutterpiVideoPlayerController.withGstreamerPipeline(
        pipelineString,
        webviewInitScript: initScript,
        webviewInitScriptAllowOrigin: initScriptAllowOrigin,
      );
      _controller = c;
      _errorSub = c.errors.listen((e) {
        notifyError(e.message);
      });
      Log.i('Webview', 'awaiting controller.initialize for $url');
      await c.initialize();

      if (shouldFallbackToNoCaps(
        useSizeCaps: useSizeCaps,
        alreadyTried: _sizeCapsFallbackTried,
        initErrored: false,
        size: c.value.size,
      )) {
        Log.w('Webview', 'size caps gave Size.zero for $url; '
            'rebuilding without caps');
        await _teardownForFallback();
        return _initController();
      }

      Log.i('Webview', 'controller initialized for $url '
          '(isInitialized=${c.value.isInitialized} size=${c.value.size})');
      await c.play();
      Log.i('Webview', 'controller.play returned for $url');
      notifyFirstFrame();
      Log.i('Webview', 'state -> PLAYING for $url');
    } catch (e, st) {
      initErrored = true;
      if (shouldFallbackToNoCaps(
        useSizeCaps: useSizeCaps,
        alreadyTried: _sizeCapsFallbackTried,
        initErrored: initErrored,
        size: _controller?.value.size ?? Size.zero,
      )) {
        Log.w('Webview', 'sized pipeline failed for $url ($e); '
            'rebuilding without caps');
        await _teardownForFallback();
        return _initController();
      }
      Log.e('Webview', 'init failed for $url: $e\n$st');
      notifyError(e.toString());
    }
  }

  /// Tears down the current controller so [_initController] can retry without
  /// the size caps. Marks the one-shot so we never loop.
  Future<void> _teardownForFallback() async {
    _sizeCapsFallbackTried = true;
    _capsActive = false;
    await _controller?.dispose();
    await _errorSub?.cancel();
    _controller = null;
    _errorSub = null;
  }
```

Add `import 'dart:ui';` to the top of `webview_session.dart` if `Size` is not already imported (it is re-exported via `package:flutter/widgets.dart`, already imported — only add `dart:ui` if the analyzer flags `Size`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `/c/flutter/bin/flutter test test/modules/webview/webview_session_test.dart`
Expected: PASS (predicate test + all prior).

- [ ] **Step 5: Analyze + commit**

Run: `/c/flutter/bin/flutter analyze lib/modules/webview/webview_session.dart`
Expected: `No issues found!`

```bash
git add lib/modules/webview/webview_session.dart test/modules/webview/webview_session_test.dart
git commit -m "feat(webview): fall back to uncapped pipeline if sized render fails"
```

---

### Task 4: Pool keys on requested render size

**Files:**
- Modify: `lib/modules/webview/webview_session_pool.dart`
- Test: `test/modules/webview/webview_session_pool_test.dart`

**Interfaces:**
- Consumes: `WebviewSession` render fields from Task 2 (`renderWidth`, `renderHeight`, `useSizeCaps`).
- Produces: `getOrCreate(String url, {String? initScript, String? initScriptAllowOrigin, Size? renderSize})`. When `renderSize` is non-null the new session has `useSizeCaps == true` and `renderWidth/Height` = rounded `renderSize`. A cached session is reused only if injector matches AND (no size requested OR both dimensions within 2px). Factory typedef gains `int renderWidth`, `int renderHeight`, `bool useSizeCaps`.

- [ ] **Step 1: Write the failing tests** (append inside `group('WebviewSessionPool', …)`)

```dart
    test('stores requested render size and enables caps', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final s = pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      expect(s.renderWidth, 1920);
      expect(s.renderHeight, 1200);
      expect(s.useSizeCaps, isTrue);
    });

    test('omitting render size leaves caps off (back-compat)', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final s = pool.getOrCreate('https://a.example');
      expect(s.useSizeCaps, isFalse);
    });

    test('same render size returns the same session', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      final b = pool.getOrCreate('https://a.example',
          renderSize: const Size(1921, 1199)); // within 2px
      expect(identical(a, b), isTrue);
    });

    test('a meaningful render-size change rebuilds the session', () {
      final pool = WebviewSessionPool(sessionFactory: WebviewSession.testing);
      final a = pool.getOrCreate('https://a.example',
          renderSize: const Size(1920, 1200));
      final b = pool.getOrCreate('https://a.example',
          renderSize: const Size(1280, 800));
      expect(identical(a, b), isFalse);
      expect(b.renderWidth, 1280);
    });
```

Add to the test file imports:

```dart
import 'dart:ui';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `/c/flutter/bin/flutter test test/modules/webview/webview_session_pool_test.dart`
Expected: FAIL — `No named parameter with the name 'renderSize'`.

- [ ] **Step 3: Extend the factory typedef, default factory, and getOrCreate**

Add to the top of `lib/modules/webview/webview_session_pool.dart`:

```dart
import 'dart:ui';
```

Replace the typedef and `_defaultFactory`:

```dart
typedef WebviewSessionFactory = WebviewSession Function({
  required String url,
  String? initScript,
  String? initScriptAllowOrigin,
  int renderWidth,
  int renderHeight,
  bool useSizeCaps,
});

WebviewSession _defaultFactory({
  required String url,
  String? initScript,
  String? initScriptAllowOrigin,
  int renderWidth = 1920,
  int renderHeight = 1080,
  bool useSizeCaps = false,
}) =>
    WebviewSession(
      url: url,
      initScript: initScript,
      initScriptAllowOrigin: initScriptAllowOrigin,
      renderWidth: renderWidth,
      renderHeight: renderHeight,
      useSizeCaps: useSizeCaps,
    );
```

Replace `getOrCreate`:

```dart
  WebviewSession getOrCreate(
    String url, {
    String? initScript,
    String? initScriptAllowOrigin,
    Size? renderSize,
  }) {
    final useCaps = renderSize != null;
    final reqW = renderSize?.width.round() ?? 1920;
    final reqH = renderSize?.height.round() ?? 1080;

    final existing = _sessions[url];
    if (existing != null) {
      final sizeMatches = !useCaps ||
          (existing.useSizeCaps &&
              (existing.renderWidth - reqW).abs() <= 2 &&
              (existing.renderHeight - reqH).abs() <= 2);
      if (existing.initScript == initScript &&
          existing.initScriptAllowOrigin == initScriptAllowOrigin &&
          sizeMatches) {
        return existing;
      }
      existing.dispose();
      _sessions.remove(url);
    }

    final session = _factory(
      url: url,
      initScript: initScript,
      initScriptAllowOrigin: initScriptAllowOrigin,
      renderWidth: reqW,
      renderHeight: reqH,
      useSizeCaps: useCaps,
    );
    _sessions[url] = session;
    return session;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/c/flutter/bin/flutter test test/modules/webview/webview_session_pool_test.dart`
Expected: PASS (new size tests + all existing).

- [ ] **Step 5: Commit**

```bash
git add lib/modules/webview/webview_session_pool.dart test/modules/webview/webview_session_pool_test.dart
git commit -m "feat(webview): key session pool on requested render size"
```

---

### Task 5: Screen computes render size from panel geometry

**Files:**
- Modify: `lib/modules/webview/webview_screen.dart`

**Interfaces:**
- Consumes: `webviewRenderPx` (Task 1), `uiScaleProvider`, `pool.getOrCreate(..., renderSize:)` (Task 4).
- Produces: webview sessions resolved with the live physical render size; re-resolved only when it changes by >2px.

- [ ] **Step 1: Add imports**

At the top of `lib/modules/webview/webview_screen.dart` add:

```dart
import '../../app/scale/hearth_scale.dart';
import 'webview_geometry.dart';
```

- [ ] **Step 2: Make `_ensureSession` size-aware and store the last size**

In `_WebviewScreenState`, add a field near `_session`:

```dart
  Size? _lastRenderPx;
```

Replace `_ensureSession`'s signature and the `pool.getOrCreate` call. Change:

```dart
  void _ensureSession() {
    final config = ref.read(hubConfigProvider);
    final injector = injectorForWebview(
      widget.config,
      haUrl: config.haUrl,
      haToken: config.haToken,
    );
    final pool = ref.read(webviewSessionPoolProvider);
    final session = pool.getOrCreate(
      widget.config.url,
      initScript: injector?.script,
      initScriptAllowOrigin: injector?.allowOrigin,
    );
```

to:

```dart
  void _ensureSession(Size? renderPx) {
    final config = ref.read(hubConfigProvider);
    final injector = injectorForWebview(
      widget.config,
      haUrl: config.haUrl,
      haToken: config.haToken,
    );
    final pool = ref.read(webviewSessionPoolProvider);
    final session = pool.getOrCreate(
      widget.config.url,
      initScript: injector?.script,
      initScriptAllowOrigin: injector?.allowOrigin,
      renderSize: renderPx,
    );
```

(The rest of `_ensureSession` — the `identical` guard, listener swap, `setState` — is unchanged.)

- [ ] **Step 3: Remove the initState pre-resolve (the LayoutBuilder now drives it)**

Replace:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSession());
  }
```

with:

```dart
  @override
  void initState() {
    super.initState();
  }
```

- [ ] **Step 4: Drive resolution from the LayoutBuilder and update the config listener**

In `build`, change the config listener call:

```dart
      (_, _) => _ensureSession(),
```

to:

```dart
      (_, _) => _ensureSession(_lastRenderPx),
```

Wrap the screen body so the `LayoutBuilder` is the outermost widget and computes the size. Replace the block from `final session = _session;` through the end of the `switch` with:

```dart
    return LayoutBuilder(builder: (context, constraints) {
      final renderPx = webviewRenderPx(
        Size(constraints.maxWidth, constraints.maxHeight),
        MediaQuery.devicePixelRatioOf(context),
        ref.read(uiScaleProvider),
      );
      final last = _lastRenderPx;
      if (last == null ||
          (renderPx.width - last.width).abs() > 2 ||
          (renderPx.height - last.height).abs() > 2) {
        _lastRenderPx = renderPx;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureSession(renderPx);
        });
      }

      final session = _session;
      if (session == null) {
        return _Placeholder.loading(config: widget.config);
      }
      switch (session.state) {
        case WebviewSessionState.loading:
          return _Placeholder.loading(config: widget.config);
        case WebviewSessionState.error:
          return _Placeholder.error(
            config: widget.config,
            message: session.lastError ?? 'Unknown error',
            onRetry: () => session.reload(),
          );
        case WebviewSessionState.playing:
        case WebviewSessionState.paused:
          final controller = session.controller;
          if (controller == null || !controller.value.isInitialized) {
            return _Placeholder.loading(config: widget.config);
          }
          return _TouchableWebviewView(
            session: session,
            controller: controller,
            size: Size(constraints.maxWidth, constraints.maxHeight),
          );
      }
    });
```

Delete the now-removed inner `LayoutBuilder` that previously wrapped only the `playing/paused` case (it is replaced by the outer one above). The previous `final session = _session;` line before the switch is also removed (folded into the builder).

- [ ] **Step 5: Analyze**

Run: `/c/flutter/bin/flutter analyze lib/modules/webview/webview_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Run the full webview suite**

Run: `/c/flutter/bin/flutter test test/modules/webview/`
Expected: PASS (all geometry, session, pool, touch-mapping tests).

- [ ] **Step 7: Commit**

```bash
git add lib/modules/webview/webview_screen.dart
git commit -m "feat(webview): render webviews at the panel's native pixel size"
```

---

### Task 6: Release + on-device verification

**Files:**
- Modify: `pubspec.yaml` (version bump)

**Interfaces:** none (deployment).

- [ ] **Step 1: Full test + analyze gate**

Run: `/c/flutter/bin/flutter test` and `/c/flutter/bin/flutter analyze`
Expected: all tests pass; analyze clean.

- [ ] **Step 2: Bump version**

Edit `pubspec.yaml`: `version: 1.13.8` → `version: 1.13.9`.

- [ ] **Step 3: Commit, tag, push to both remotes**

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 1.13.9"
git tag -a v1.13.9 -m "Hearth v1.13.9"
git push origin main v1.13.9
git push github main v1.13.9
```

- [ ] **Step 4: Wait for the GitHub release bundle**

Poll: `gh release view v1.13.9 --repo chrisuthe/Hearth-Home --json assets --jq '.assets[].name'`
Expected: lists `hearth-bundle-1.13.9.tar.gz` and `.sha256`.

- [ ] **Step 5: OTA-update the device**

```bash
ssh hearthdev@10.0.1.13 'sudo systemctl start hearth-updater.service'
```
Then confirm: `ssh hearthdev@10.0.1.13 'cat /etc/hearth-version'` → `1.13.9`.

- [ ] **Step 6: Verify on the kiosk**

Have the user open the HA dashboard, then check the journal:

```bash
ssh hearthdev@10.0.1.13 'journalctl -u hearth.service --since "2 min ago" --no-pager | grep -iE "Webview|caps|size"'
```
Expected: `init starting … caps=true <W>x<H>`, a `controller initialized … size=Size(<W>, <H>)` matching the panel box (not `Size(1920.0, 1080.0)`, not `Size.zero`), **no** `rebuilding without caps`. Confirm with the user: no letterbox bars, dashboard fills the panel, taps still dead-on.

- [ ] **Step 7: Rollback path (only if broken)**

If the webview is black or the log shows repeated failures, roll back: re-point the device to the v1.13.8 bundle (publish/promote 1.13.8 as latest or manually fetch its bundle) and restart `hearth.service`. The auto-fallback should make this unnecessary, but it is the floor.

---

## Self-Review

**Spec coverage:** size math (Task 1 ✓), session caps + dead-field replacement (Task 2 ✓), auto-fallback (Task 3 ✓), pool size-keying with 2px tolerance (Task 4 ✓), screen computation from `boxLogical × dpr × uiScale` (Task 5 ✓), all-webviews scope (Task 5 passes `renderSize` for every webview ✓), release/rollback (Task 6 ✓). No spec section is unaddressed.

**Placeholder scan:** none — every code step shows complete code; commands have expected output.

**Type consistency:** `renderWidth`/`renderHeight` (int) and `useSizeCaps` (bool) are defined identically in Task 2 (session), consumed in Task 4 (factory/pool) and asserted in tests; `webviewRenderPx(Size,double,double)→Size` defined in Task 1, consumed in Task 5; `shouldFallbackToNoCaps({bool,bool,bool,Size})→bool` defined and used in Task 3. `getOrCreate(..., Size? renderSize)` defined in Task 4, called in Task 5. Consistent.
