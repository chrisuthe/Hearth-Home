import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sendspin_dart/sendspin_dart.dart';

import '../../../app/media_tokens.dart';
import '../../../app/tokens/tokens.dart';
import '../../../models/music_state.dart';
import '../../../services/sendspin/sendspin_service.dart';

/// Hero mini-stats row: provider chip · format · year · sendspin sync.
///
/// Each item renders only when its data source is populated. The row
/// hides entirely when nothing is available (e.g., radio streams with
/// no provider/format/year and no Sendspin connection).
class MiniStatsRow extends ConsumerWidget {
  final MusicTrack track;

  const MiniStatsRow({super.key, required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ssAsync = ref.watch(sendspinStateProvider);
    final sendspin = ssAsync.valueOrNull;

    final children = <Widget>[];
    void addSeparator() {
      if (children.isNotEmpty) {
        children.add(const _Dot());
      }
    }

    final provider = track.provider;
    if (provider != null && provider.isNotEmpty) {
      children.add(_ProviderChip(provider: provider));
    }
    if (track.format != null) {
      addSeparator();
      children.add(_StatText(track.format!));
    }
    if (track.year != null) {
      addSeparator();
      children.add(_StatText(track.year!.toString()));
    }
    if (sendspin != null && sendspin.isActive) {
      addSeparator();
      children.add(_SendspinBadge(state: sendspin));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: HearthSpacing.x2,
        children: children,
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  final String provider;

  const _ProviderChip({required this.provider});

  @override
  Widget build(BuildContext context) {
    final color = MediaColors.providerColors[provider] ??
        const Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary);
    final label = _humanise(provider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: HearthSpacing.x1),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.08),
        borderRadius: BorderRadius.circular(MediaRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: HearthSpacing.x2),
          Text(
            label,
            style: const TextStyle(
              fontSize: HearthFont.caption,
              fontWeight: FontWeight.w400,
              color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.tertiary),
            ),
          ),
        ],
      ),
    );
  }

  static String _humanise(String provider) {
    switch (provider) {
      case 'spotify':
        return 'Spotify';
      case 'tidal':
        return 'Tidal';
      case 'apple_music':
        return 'Apple Music';
      case 'ytmusic':
        return 'YT Music';
      case 'soundcloud':
        return 'SoundCloud';
      case 'filesystem_local':
        return 'Local Library';
      default:
        return provider
            .split('_')
            .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
            .join(' ');
    }
  }
}

class _StatText extends StatelessWidget {
  final String text;
  const _StatText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MediaTextStyles.tabular(
        HearthFont.caption,
        weight: FontWeight.w400,
        color: const Color.fromRGBO(
          255,
          255,
          255,
          MediaTextOpacity.tertiary,
        ),
      ),
    );
  }
}

/// "·" separator between mini-stat items. Static muted dot.
class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '·',
      style: TextStyle(
        fontSize: HearthFont.caption,
        color: Color.fromRGBO(255, 255, 255, MediaTextOpacity.section),
      ),
    );
  }
}

/// Sendspin sync indicator — uses the same `clockOffsetMs < 0` =
/// "syncing" sentinel as the existing media screen indicator.
class _SendspinBadge extends StatelessWidget {
  final SendspinPlayerState state;
  const _SendspinBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final precisionMs = state.clockOffsetMs;
    final String label;
    if (state.connectionState != SendspinConnectionState.streaming ||
        precisionMs < 0) {
      label = 'Syncing';
    } else {
      final precisionStr = precisionMs < 1 ? '<1' : '$precisionMs';
      label = 'Sendspin ±${precisionStr}ms';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.graphic_eq,
          size: 12,
          color: MediaColors.sendspinGreen,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: MediaTextStyles.tabular(
            HearthFont.caption,
            weight: FontWeight.w500,
            color: MediaColors.sendspinGreen,
          ),
        ),
      ],
    );
  }
}
