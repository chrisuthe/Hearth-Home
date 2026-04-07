import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app.dart' show kDialogBackground;
import '../../config/hub_config.dart';
import '../../services/wifi_service.dart';

/// Multi-step first-boot setup wizard.
///
/// Walks the user through WiFi → Services → Display → Done.
/// All config changes persist immediately via [HubConfigNotifier.update].
/// After completion, the parent (HearthApp) detects haUrl is set and
/// switches to the main HubShell.
class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  int _step = 0;

  void _nextStep() => setState(() => _step++);
  void _prevStep() => setState(() => _step--);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProgressBar(currentStep: _step, totalSteps: 4),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: switch (_step) {
              0 => _WifiStep(key: const ValueKey(0), onNext: _nextStep),
              1 => _ServicesStep(
                  key: const ValueKey(1),
                  onNext: _nextStep,
                  onBack: _prevStep,
                ),
              2 => _DisplayStep(
                  key: const ValueKey(2),
                  onNext: _nextStep,
                  onBack: _prevStep,
                ),
              _ => const _DoneStep(key: ValueKey(3)),
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Progress bar
// ---------------------------------------------------------------------------

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  static const _accent = Color(0xFF646CFF);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: List.generate(totalSteps, (i) {
          final isComplete = i <= currentStep;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < totalSteps - 1 ? 6 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: isComplete ? _accent : Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 0 — WiFi
// ---------------------------------------------------------------------------

class _WifiStep extends ConsumerStatefulWidget {
  const _WifiStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<_WifiStep> createState() => _WifiStepState();
}

class _WifiStepState extends ConsumerState<_WifiStep> {
  static const _accent = Color(0xFF646CFF);

  List<WifiNetwork> _networks = [];
  bool _scanning = false;
  String? _connectedSsid;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _errorMessage = null;
    });
    final service = ref.read(wifiServiceProvider);
    final results = await Future.wait([
      service.scan(),
      service.activeConnection(),
    ]);
    if (!mounted) return;
    setState(() {
      _networks = results[0] as List<WifiNetwork>;
      _connectedSsid = results[1] as String?;
      _scanning = false;
    });
  }

  Future<void> _connectToNetwork(WifiNetwork network) async {
    if (network.isSecured) {
      await _showPasswordDialog(network);
    } else {
      await _connectOpen(network.ssid);
    }
  }

  Future<void> _connectOpen(String ssid) async {
    setState(() => _errorMessage = null);
    final ok = await ref.read(wifiServiceProvider).connectOpen(ssid);
    if (!mounted) return;
    if (ok) {
      setState(() => _connectedSsid = ssid);
    } else {
      setState(() => _errorMessage = 'Failed to connect to $ssid');
    }
  }

  Future<void> _showPasswordDialog(WifiNetwork network) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogBackground,
        title: Text('Connect to ${network.ssid}'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Password',
            border: OutlineInputBorder(),
          ),
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
    if (confirmed == null || !mounted) return;
    setState(() => _errorMessage = null);
    final ok =
        await ref.read(wifiServiceProvider).connect(network.ssid, confirmed);
    if (!mounted) return;
    if (ok) {
      setState(() => _connectedSsid = network.ssid);
    } else {
      setState(() => _errorMessage = 'Failed to connect to ${network.ssid}');
    }
  }

  IconData _signalIcon(int strength) {
    if (strength >= 75) return Icons.signal_wifi_4_bar;
    if (strength >= 50) return Icons.network_wifi_3_bar;
    if (strength >= 25) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _connectedSsid != null
        ? _connectedSsid!
        : 'Select your WiFi network';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Connect to WiFi',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          Expanded(
            child: _scanning
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _networks.length,
                    itemBuilder: (ctx, i) {
                      final network = _networks[i];
                      final isConnected = network.ssid == _connectedSsid;
                      return ListTile(
                        leading: Icon(
                          _signalIcon(network.signalStrength),
                          color: isConnected ? _accent : Colors.white54,
                        ),
                        title: Text(network.ssid),
                        subtitle: network.isSecured
                            ? Text(
                                network.security,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              )
                            : Text(
                                'Open',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                        trailing: isConnected
                            ? const Icon(Icons.check_circle,
                                color: Color(0xFF646CFF))
                            : network.isSecured
                                ? const Icon(Icons.lock,
                                    size: 16, color: Colors.white38)
                                : null,
                        onTap: () => _connectToNetwork(network),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: widget.onNext,
                child: const Text('Skip (Using Ethernet)'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _scanning ? null : _startScan,
                child: const Text('Rescan'),
              ),
              const SizedBox(width: 8),
              if (_connectedSsid != null)
                FilledButton(
                  onPressed: widget.onNext,
                  child: const Text('Next'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — Services
// ---------------------------------------------------------------------------

class _ServicesStep extends ConsumerStatefulWidget {
  const _ServicesStep({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  ConsumerState<_ServicesStep> createState() => _ServicesStepState();
}

class _ServicesStepState extends ConsumerState<_ServicesStep> {
  late final TextEditingController _haUrlCtrl;
  late final TextEditingController _haTokenCtrl;
  late final TextEditingController _immichUrlCtrl;
  late final TextEditingController _immichKeyCtrl;
  late final TextEditingController _frigateUrlCtrl;

  @override
  void initState() {
    super.initState();
    final config = ref.read(hubConfigProvider);
    _haUrlCtrl = TextEditingController(text: config.haUrl);
    _haTokenCtrl = TextEditingController(text: config.haToken);
    _immichUrlCtrl = TextEditingController(text: config.immichUrl);
    _immichKeyCtrl = TextEditingController(text: config.immichApiKey);
    _frigateUrlCtrl = TextEditingController(text: config.frigateUrl);

    _haUrlCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _haUrlCtrl.dispose();
    _haTokenCtrl.dispose();
    _immichUrlCtrl.dispose();
    _immichKeyCtrl.dispose();
    _frigateUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(hubConfigProvider.notifier).update(
          (c) => c.copyWith(
            haUrl: _haUrlCtrl.text.trim(),
            haToken: _haTokenCtrl.text.trim(),
            immichUrl: _immichUrlCtrl.text.trim(),
            immichApiKey: _immichKeyCtrl.text.trim(),
            frigateUrl: _frigateUrlCtrl.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final canNext = _haUrlCtrl.text.trim().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Connect Services',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Home Assistant is required. Others are optional.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 32),
          _ServiceField(
            label: 'Home Assistant URL',
            hint: 'http://192.168.1.x:8123',
            controller: _haUrlCtrl,
          ),
          const SizedBox(height: 16),
          _ServiceField(
            label: 'Home Assistant Token',
            hint: 'Long-lived access token',
            controller: _haTokenCtrl,
            obscure: true,
          ),
          const SizedBox(height: 24),
          _ServiceField(
            label: 'Immich URL',
            hint: 'http://192.168.1.x:2283',
            controller: _immichUrlCtrl,
          ),
          const SizedBox(height: 16),
          _ServiceField(
            label: 'Immich API Key',
            hint: 'Paste your Immich API key',
            controller: _immichKeyCtrl,
            obscure: true,
          ),
          const SizedBox(height: 24),
          _ServiceField(
            label: 'Frigate URL',
            hint: 'http://192.168.1.x:5000',
            controller: _frigateUrlCtrl,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: canNext
                    ? () async {
                        await _save();
                        widget.onNext();
                      }
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServiceField extends StatelessWidget {
  const _ServiceField({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Display
// ---------------------------------------------------------------------------

class _DisplayStep extends ConsumerStatefulWidget {
  const _DisplayStep({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  ConsumerState<_DisplayStep> createState() => _DisplayStepState();
}

class _DisplayStepState extends ConsumerState<_DisplayStep> {
  static const _profiles = {
    'auto': ('Auto-detect', 'Let Hearth detect your display'),
    'amoled-11': ('11" AMOLED', '1184x864 (half of 2368x1728)'),
    'rpi-7': ('RPi 7" Touchscreen', '800x480'),
    'hdmi': ('HDMI Monitor', 'Uses native resolution'),
  };

  static const _accent = Color(0xFF646CFF);

  late String _selectedProfile;

  @override
  void initState() {
    super.initState();
    _selectedProfile = ref.read(hubConfigProvider).displayProfile;
  }

  Future<void> _saveAndNext() async {
    await ref.read(hubConfigProvider.notifier).update(
          (c) => c.copyWith(displayProfile: _selectedProfile),
        );
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Choose Display',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Select the display connected to your Pi',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: _profiles.entries.map((entry) {
                final key = entry.key;
                final (title, subtitle) = entry.value;
                final isSelected = key == _selectedProfile;
                return ListTile(
                  leading: Icon(
                    Icons.monitor,
                    color: isSelected ? _accent : Colors.white54,
                  ),
                  title: Text(title),
                  subtitle: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: _accent)
                      : null,
                  onTap: () => setState(() => _selectedProfile = key),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saveAndNext,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Done
// ---------------------------------------------------------------------------

class _DoneStep extends ConsumerWidget {
  const _DoneStep({super.key});

  static const _accent = Color(0xFF646CFF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 80,
              color: _accent,
            ),
            const SizedBox(height: 24),
            const Text(
              'All Set!',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'You can change these settings anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 40),
            FilledButton.icon(
              icon: const Icon(Icons.home),
              label: const Text('Start Hearth'),
              onPressed: () {
                // Parent (HearthApp) watches haUrl and auto-transitions
                // when it becomes non-empty. Nothing to do here unless
                // the user somehow reached Done without setting haUrl.
              },
            ),
          ],
        ),
      ),
    );
  }
}
