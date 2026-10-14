import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import 'android_webview_session.dart';

/// Hearth's edge-swipe zones occupy the top and bottom 80px of the display.
const double _edgeBand = 80;

/// The page claims a vertical drag only when it starts outside the edge
/// bands, so drags from the bands still reach HubShell's edge-swipe zones.
/// Pure so it can be unit-tested.
bool webviewClaimsVerticalDrag(double y, double height) =>
    y >= _edgeBand && y <= height - _edgeBand;

/// Mounts the system WebView for an [AndroidWebviewSession].
///
/// Touch goes to the WebView natively. The platform view joins Flutter's
/// gesture arena with taps, long presses and vertical drags, so horizontal
/// drags are still won by HubShell's PageView. [onActivity] fires on every
/// pointer down, before the arena decides, so any touch wakes the kiosk.
///
/// Unmounting does not destroy the WebView: it is created with the session's
/// keep-alive, survives detached while its page is offscreen, and is
/// reattached when the page is built again.
class AndroidWebviewView extends StatefulWidget {
  final AndroidWebviewSession session;
  final VoidCallback onActivity;

  const AndroidWebviewView({
    super.key,
    required this.session,
    required this.onActivity,
  });

  @override
  State<AndroidWebviewView> createState() => _AndroidWebviewViewState();
}

class _AndroidWebviewViewState extends State<AndroidWebviewView> {
  PlatformInAppWebViewWidget? _platform;
  InAppWebViewKeepAlive? _platformKeepAlive;
  PlatformInAppWebViewController? _controller;
  double _height = 0;

  /// Builds the platform widget for the session's current WebView, replacing
  /// the previous one when [AndroidWebviewSession.keepAlive] rotated (a
  /// reload or a renderer crash).
  PlatformInAppWebViewWidget _platformFor(AndroidWebviewSession session) {
    final existing = _platform;
    if (existing != null && identical(_platformKeepAlive, session.keepAlive)) {
      return existing;
    }
    _release(session);
    _platformKeepAlive = session.keepAlive;
    return _platform = PlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams(
        key: ObjectKey(session.keepAlive),
        keepAlive: session.keepAlive,
        initialUrlRequest: URLRequest(url: WebUri(session.url)),
        initialUserScripts: session.userScripts,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          // HA is often plain http; the manifest allows cleartext too.
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          transparentBackground: false,
          supportZoom: false,
          builtInZoomControls: false,
          displayZoomControls: false,
          isInspectable: kDebugMode,
        ),
        gestureRecognizers: {
          Factory<VerticalDragGestureRecognizer>(
            () => _BandedVerticalDragGestureRecognizer(
              claims: (y) => webviewClaimsVerticalDrag(y, _height),
            ),
          ),
          const Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
          const Factory<LongPressGestureRecognizer>(
              LongPressGestureRecognizer.new),
        },
        onWebViewCreated: (controller) {
          _controller = controller as PlatformInAppWebViewController;
          session.attach(controller);
        },
        onLoadStop: (_, _) => session.onLoadStop(),
        onReceivedError: (_, request, error) => session.onReceivedError(
          isForMainFrame: request.isForMainFrame ?? false,
          cancelled: error.type == WebResourceErrorType.CANCELLED,
          description: error.description,
        ),
        onReceivedHttpError: (_, request, response) =>
            session.onReceivedHttpError(
          isForMainFrame: request.isForMainFrame ?? false,
          statusCode: response.statusCode,
          reasonPhrase: response.reasonPhrase,
        ),
        onRenderProcessGone: (_, detail) =>
            session.onRenderProcessGone(didCrash: detail.didCrash),
      ),
    );
  }

  /// Detaches before disposing the platform widget: the detach pauses the
  /// WebView through the controller, whose channel the dispose closes.
  void _release(AndroidWebviewSession session) {
    final c = _controller;
    if (c != null) session.detach(c);
    _controller = null;
    _platform?.dispose();
    _platform = null;
  }

  @override
  void didUpdateWidget(AndroidWebviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _release(oldWidget.session);
    }
  }

  @override
  void dispose() {
    _release(widget.session);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = _platformFor(widget.session);
    return LayoutBuilder(builder: (context, constraints) {
      _height = constraints.maxHeight;
      return Listener(
        onPointerDown: (_) => widget.onActivity(),
        child: platform.build(context),
      );
    });
  }
}

/// A vertical drag recognizer that declines pointers landing in the edge
/// bands. Positions are local to the platform view.
class _BandedVerticalDragGestureRecognizer
    extends VerticalDragGestureRecognizer {
  final bool Function(double y) claims;

  _BandedVerticalDragGestureRecognizer({required this.claims});

  @override
  bool isPointerAllowed(PointerEvent event) =>
      claims(event.localPosition.dy) && super.isPointerAllowed(event);
}
