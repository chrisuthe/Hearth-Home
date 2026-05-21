import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../config/webview_config.dart';
import 'webview_session.dart';
import 'webview_session_pool.dart';

/// Renders a single configured webview into HubShell's PageView.
///
/// Resolves a [WebviewSession] from the pool (warm-cache), renders the
/// underlying video texture, and shows Hearth-styled LOADING / ERROR
/// placeholders during transitions.
///
/// Touch input and idle-suspend wiring are added in later tasks
/// (Task 14: Touch input mapping, Task 16: Idle-suspend wiring).
class WebviewScreen extends ConsumerStatefulWidget {
  final WebviewConfig config;

  const WebviewScreen({super.key, required this.config});

  @override
  ConsumerState<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends ConsumerState<WebviewScreen> {
  WebviewSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSession());
  }

  void _ensureSession() {
    final pool = ref.read(webviewSessionPoolProvider);
    final session = pool.getOrCreate(widget.config.url);
    setState(() => _session = session);
    session.addListener(_onSessionChange);
  }

  void _onSessionChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        return LayoutBuilder(builder: (context, constraints) {
          return _TouchableWebviewView(
            session: session,
            controller: controller,
            size: Size(constraints.maxWidth, constraints.maxHeight),
          );
        });
    }
  }
}

class _Placeholder extends StatelessWidget {
  final WebviewConfig config;
  final bool isError;
  final String? message;
  final VoidCallback? onRetry;

  const _Placeholder.loading({required this.config})
      : isError = false,
        message = null,
        onRetry = null;

  const _Placeholder.error({
    required this.config,
    required String this.message,
    required VoidCallback this.onRetry,
  }) : isError = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : config.icon,
            color: isError ? Colors.redAccent : Colors.white70,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            isError ? 'Reconnecting to ${config.name}…' : config.name,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          if (isError && message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const CircularProgressIndicator(color: Color(0xFF646CFF)),
          ],
        ],
      ),
    );
  }
}

class _TouchableWebviewView extends StatefulWidget {
  final WebviewSession session;
  final VideoPlayerController controller;
  final Size size;

  const _TouchableWebviewView({
    required this.session,
    required this.controller,
    required this.size,
  });

  @override
  State<_TouchableWebviewView> createState() => _TouchableWebviewViewState();
}

class _TouchableWebviewViewState extends State<_TouchableWebviewView> {
  Offset? _longPressOrigin;

  // Maps local Flutter pixel to wpesrc viewport coordinates.
  // VideoPlayer renders via BoxFit.contain inside [size]; map back to native.
  Offset _toViewport(Offset local) {
    final renderSize = widget.controller.value.size;
    if (renderSize.width == 0 || renderSize.height == 0) return local;
    final scaleX = renderSize.width / widget.size.width;
    final scaleY = renderSize.height / widget.size.height;
    // BoxFit.contain uses the LARGER scale factor so source fits inside box.
    final scale = scaleX > scaleY ? scaleX : scaleY;
    return Offset(local.dx * scale, local.dy * scale);
  }

  void _resumeIfNeeded() {
    if (widget.session.state == WebviewSessionState.paused) {
      widget.session.setPaused(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        _resumeIfNeeded();
        widget.session.sendPointerDown(_toViewport(d.localPosition));
      },
      onTapUp: (d) {
        widget.session.sendPointerUp(_toViewport(d.localPosition));
      },
      onTapCancel: () {
        if (_longPressOrigin != null) {
          widget.session.sendPointerUp(_toViewport(_longPressOrigin!));
        }
      },
      onLongPressStart: (d) {
        _resumeIfNeeded();
        _longPressOrigin = d.localPosition;
        widget.session.sendLongPressStart(_toViewport(d.localPosition));
      },
      onLongPressEnd: (d) {
        widget.session.sendLongPressEnd(_toViewport(d.localPosition));
        _longPressOrigin = null;
      },
      onVerticalDragUpdate: (d) {
        _resumeIfNeeded();
        widget.session.sendScroll(
          _toViewport(d.localPosition),
          0,
          -d.delta.dy, // negate: drag down means scroll up the page
        );
      },
      onHorizontalDragUpdate: (d) {
        _resumeIfNeeded();
        widget.session.sendScroll(
          _toViewport(d.localPosition),
          -d.delta.dx,
          0,
        );
      },
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: widget.controller.value.size.width,
          height: widget.controller.value.size.height,
          child: VideoPlayer(widget.controller),
        ),
      ),
    );
  }
}
