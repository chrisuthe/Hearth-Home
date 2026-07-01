import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/hub_config.dart';
import '../../services/plex/plex_tv_auth.dart';
import '../framework/fields/bool_setting_field.dart';
import '../framework/fields/text_setting_field.dart';
import '../framework/web_context.dart';
import '../hearth_plugin.dart';

/// Plex Companion player integration.
///
/// Advertises Hearth on the LAN as a Plex player (via GDM) so Plex apps
/// (phone / web / desktop) show a native "Cast" entry for the kiosk and drive
/// full-screen video playback via the shared [HearthVideoPlayer]. See
/// `docs/specs/2026-06-30-plex-companion-client-design.md`.
///
/// Owns:
///   * `plexEnabled`  (with side-effect: seed `plexClientId` on first enable)
///   * `plexPlayerName` (the GDM `Name` / player title)
///   * `plexAuthToken` (from the on-device plex.tv PIN-link pairing flow)
///
/// `plexClientId` is internal — not surfaced as a field; app-seeded by the
/// enable toggle's [BoolSettingField.writeOverride], mirroring how [DlnaPlugin]
/// seeds `dlnaUuid`.
///
/// Web caveat (matches DLNA/Sendspin): the web portal exposes only the enable
/// toggle and player-name field. The enable checkbox posts `plexEnabled`
/// directly and does NOT seed `plexClientId`, and pairing is on-device only —
/// toggle once on-device to seed the client id and pair from the kiosk.
class PlexPlugin extends HearthPlugin {
  @override
  String get id => 'hearth.plex';

  @override
  String get name => 'Plex Cast';

  @override
  IconData get icon => Icons.play_circle_outline;

  @override
  PluginCategory get category => PluginCategory.feature;

  @override
  int get order => 86;

  @override
  bool get isCommunity => false;

  @override
  PluginConfigStatus statusFor(HubConfig config) {
    if (config.plexPlayerName.isEmpty) {
      return PluginConfigStatus.needsSetup;
    }
    // Named but unpaired: LAN casting works, but the device isn't visible to
    // the Plex account beyond the LAN until paired.
    if (config.plexAuthToken.isEmpty) {
      return PluginConfigStatus.partial;
    }
    return PluginConfigStatus.configured;
  }

  @override
  Widget buildSettingsWidget(WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BoolSettingField(
          label: 'Enable Plex Player',
          icon: Icons.play_circle_outline,
          configPath: 'plexEnabled',
          disabledReason: (c) =>
              c.plexPlayerName.isEmpty ? 'Set a player name first' : null,
          writeOverride: (ref, value) async {
            final notifier = ref.read(hubConfigProvider.notifier);
            await notifier.update((c) {
              if (value && c.plexClientId.isEmpty) {
                return c.copyWith(
                  plexEnabled: true,
                  plexClientId: HubConfig.generateUuid(),
                );
              }
              return c.copyWith(plexEnabled: value);
            });
          },
        ).buildWidget(ref),
        const TextSettingField(
          configPath: 'plexPlayerName',
          label: 'Player Name',
          hint: 'Hearth',
        ).buildWidget(ref),
        const SizedBox(height: 12),
        const PlexPairingSection(),
      ],
    );
  }

  @override
  String buildSettingsHtml(WebContext ctx) {
    final enable = BoolSettingField(
      label: 'Enable Plex Player',
      configPath: 'plexEnabled',
      disabledReason: (c) =>
          c.plexPlayerName.isEmpty ? 'Set a player name first' : null,
      // No writeOverride on the web side: the auto-save helper writes the bool
      // directly and does not seed plexClientId. Toggle once on-device to seed
      // it and pair from the kiosk.
    );
    const playerName = TextSettingField(
      configPath: 'plexPlayerName',
      label: 'Player Name',
      hint: 'Hearth',
    );
    return enable.buildHtml(ctx) + playerName.buildHtml(ctx);
  }
}

/// On-device plex.tv PIN-link pairing.
///
/// Idle → "Pair with Plex" → shows a 4-char code + `plex.tv/link` prompt →
/// polls until the user links → stores `plexAuthToken`. Paired → shows a
/// confirmation + "Unpair". Isolated state so the poll loop doesn't rebuild the
/// whole settings panel.
class PlexPairingSection extends ConsumerStatefulWidget {
  const PlexPairingSection({super.key});

  @override
  ConsumerState<PlexPairingSection> createState() => _PlexPairingSectionState();
}

class _PlexPairingSectionState extends ConsumerState<PlexPairingSection> {
  static const int _pollAttempts = 60; // ~2 min at 2s each
  bool _pairing = false;
  String? _code;
  String? _error;

  Future<void> _startPairing() async {
    final notifier = ref.read(hubConfigProvider.notifier);
    var config = ref.read(hubConfigProvider);

    // Seed the stable client id if the user paired before ever enabling.
    if (config.plexClientId.isEmpty) {
      await notifier.update(
          (c) => c.copyWith(plexClientId: HubConfig.generateUuid()));
      config = ref.read(hubConfigProvider);
    }

    final auth = PlexTvAuth(
      clientId: config.plexClientId,
      deviceName: config.plexPlayerName,
    );

    setState(() {
      _pairing = true;
      _code = null;
      _error = null;
    });

    final pin = await auth.createPin();
    if (!mounted) return;
    if (pin == null) {
      setState(() {
        _pairing = false;
        _error = 'Could not reach plex.tv. Check the connection and retry.';
      });
      return;
    }
    setState(() => _code = pin.code);

    for (var i = 0; i < _pollAttempts; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || !_pairing) return;
      final token = await auth.pollForToken(pin.id);
      if (!mounted) return;
      if (token != null) {
        await notifier.update((c) => c.copyWith(plexAuthToken: token));
        if (mounted) {
          setState(() {
            _pairing = false;
            _code = null;
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        _pairing = false;
        _code = null;
        _error = 'Pairing timed out. Please try again.';
      });
    }
  }

  Future<void> _unpair() async {
    final notifier = ref.read(hubConfigProvider.notifier);
    await notifier.update((c) => c.copyWith(plexAuthToken: ''));
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hubConfigProvider);
    final paired = config.plexAuthToken.isNotEmpty;

    if (paired) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF4CAF50)),
          const SizedBox(width: 8),
          const Expanded(child: Text('Paired with Plex')),
          TextButton(onPressed: _unpair, child: const Text('Unpair')),
        ],
      );
    }

    if (_pairing && _code != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Go to plex.tv/link and enter this code:'),
          const SizedBox(height: 8),
          Text(
            _code!,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
              color: Color(0xFF646CFF),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              const Text('Waiting for you to link…'),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  _pairing = false;
                  _code = null;
                }),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Color(0xFFE57373))),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            const Expanded(
              child: Text('Pair with your Plex account to cast beyond the LAN.'),
            ),
            FilledButton.icon(
              onPressed: config.plexPlayerName.isEmpty || _pairing
                  ? null
                  : _startPairing,
              icon: const Icon(Icons.link),
              label: const Text('Pair with Plex'),
            ),
          ],
        ),
      ],
    );
  }
}
