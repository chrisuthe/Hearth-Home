import 'dart:async';

import 'package:flutter/material.dart';

import '../services/dlna/dlna_renderer.dart';
import '../services/dlna/soap_handler.dart';
import '../services/video/hearth_video_player.dart';

/// Full-screen or PiP overlay that plays media for DLNA cast sessions.
class CastOverlay extends StatefulWidget {
  final DlnaCastState castState;
  final DlnaRenderer renderer;
  final VoidCallback onStopped;

  const CastOverlay({
    super.key,
    required this.castState,
    required this.renderer,
    required this.onStopped,
  });

  @override
  State<CastOverlay> createState() => _CastOverlayState();
}

class _CastOverlayState extends State<CastOverlay> {
  HearthVideoPlayer? _player;
  String? _currentUrl;
  bool _isPip = false;
  bool _showControls = false;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _syncPlayback(widget.castState);
  }

  @override
  void didUpdateWidget(covariant CastOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.castState.transportState != widget.castState.transportState ||
        oldWidget.castState.mediaUrl != widget.castState.mediaUrl) {
      _syncPlayback(widget.castState);
    }
  }

  void _syncPlayback(DlnaCastState state) {
    switch (state.transportState) {
      case DlnaTransportState.playing:
        final url = state.mediaUrl;
        if (url != null && url != _currentUrl) {
          _player?.dispose();
          _player = HearthVideoPlayer.create();
          _currentUrl = url;
          _player!.play(url);
        }
      case DlnaTransportState.paused:
        // Keep player alive — no action needed.
        break;
      case DlnaTransportState.stopped:
        _player?.dispose();
        _player = null;
        _currentUrl = null;
        widget.onStopped();
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Transport commands
  // ---------------------------------------------------------------------------

  static const _avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';

  void _sendPlay() {
    widget.renderer.handleSoapAction(
      SoapAction(_avTransport, 'Play', {'InstanceID': '0', 'Speed': '1'}),
    );
  }

  void _sendPause() {
    widget.renderer.handleSoapAction(
      SoapAction(_avTransport, 'Pause', {'InstanceID': '0', 'Speed': '1'}),
    );
  }

  void _sendStop() {
    widget.renderer.handleSoapAction(
      SoapAction(_avTransport, 'Stop', {'InstanceID': '0'}),
    );
  }

  // ---------------------------------------------------------------------------
  // Controls visibility
  // ---------------------------------------------------------------------------

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    _resetControlsTimer();
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (_showControls) {
      _controlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isPip) {
      return _buildPip();
    }
    return _buildFullScreen();
  }

  Widget _buildFullScreen() {
    return GestureDetector(
      onTap: _toggleControls,
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // Video layer
            if (_player != null)
              Center(child: _player!.buildView(fit: BoxFit.contain)),

            // Transport controls overlay
            if (_showControls) _buildControlsOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Column(
        children: [
          // Top bar: title + PiP toggle
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.castState.mediaTitle ?? 'Cast',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.picture_in_picture_alt,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() => _isPip = true);
                      _showControls = false;
                      _controlsTimer?.cancel();
                    },
                    tooltip: 'Picture-in-Picture',
                  ),
                ],
              ),
            ),
          ),

          // Center: play/pause
          const Spacer(),
          IconButton(
            iconSize: 64,
            icon: Icon(
              widget.castState.transportState == DlnaTransportState.playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: Colors.white,
              size: 64,
            ),
            onPressed: () {
              if (widget.castState.transportState ==
                  DlnaTransportState.playing) {
                _sendPause();
              } else {
                _sendPlay();
              }
              _resetControlsTimer();
            },
          ),
          const Spacer(),

          // Bottom: stop
          Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: IconButton(
              icon: const Icon(
                Icons.stop_circle,
                color: Colors.white,
                size: 48,
              ),
              onPressed: _sendStop,
              tooltip: 'Stop',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPip() {
    final screenSize = MediaQuery.sizeOf(context);
    final pipWidth = screenSize.width * 0.3;
    final pipHeight = pipWidth * 9 / 16;

    return Stack(
      children: [
        Positioned(
          right: 16,
          bottom: 16,
          width: pipWidth,
          height: pipHeight,
          child: GestureDetector(
            onTap: () {
              setState(() => _isPip = false);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _player != null
                  ? _player!.buildView(fit: BoxFit.contain)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
