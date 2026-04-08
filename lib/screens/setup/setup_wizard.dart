import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app.dart' show kDialogBackground;
import '../../config/hub_config.dart';
import '../../services/wifi_service.dart';

/// First-boot setup wizard — WiFi connection only.
///
/// After connecting to WiFi (or skipping), marks setup complete and
/// transitions to the main app. Service configuration (HA, Immich, etc.)
/// is done via the web portal at hearth.local:8090.
class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});

  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  List<WifiNetwork> _networks = [];
  bool _scanning = false;
  String? _connectedSsid;
  String? _error;
  String? _ipAddress;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _resolveIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (mounted) setState(() => _ipAddress = addr.address);
            return;
          }
        }
      }
    } catch (_) {}
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
      if (connected != null) _resolveIp();
    }
  }

  Future<void> _connect(WifiNetwork network) async {
    if (network.isOpen) {
      final wifi = ref.read(wifiServiceProvider);
      final success = await wifi.connectOpen(network.ssid);
      if (mounted) {
        if (success) {
          setState(() => _connectedSsid = network.ssid);
          _resolveIp();
        } else {
          setState(() => _error = 'Failed to connect to ${network.ssid}');
        }
      }
      return;
    }
    final password = await _showPasswordDialog(network.ssid);
    if (password == null) return;
    setState(() => _error = null);
    final wifi = ref.read(wifiServiceProvider);
    final success = await wifi.connect(network.ssid, password);
    if (mounted) {
      if (success) {
        setState(() => _connectedSsid = network.ssid);
        _resolveIp();
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

  Future<void> _finishSetup() async {
    // Mark setup complete so the wizard doesn't show again.
    // Setting a placeholder haUrl triggers HearthApp to show HubShell.
    await ref.read(hubConfigProvider.notifier).update(
          (c) => c.copyWith(haUrl: 'pending-setup'),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Text(
                'Welcome to Hearth',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 8),
              Text(
                _connectedSsid != null
                    ? 'Connected to $_connectedSsid'
                    : 'Connect to WiFi to get started',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
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
                          color: isConnected
                              ? const Color(0xFF646CFF)
                              : Colors.white54,
                        ),
                        title: Text(network.ssid),
                        subtitle: Text(
                          network.isOpen ? 'Open' : network.security,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        trailing: isConnected
                            ? const Icon(Icons.check_circle,
                                color: Color(0xFF646CFF))
                            : network.isSecured
                                ? const Icon(Icons.lock,
                                    color: Colors.white24, size: 18)
                                : null,
                        onTap:
                            isConnected ? null : () => _connect(network),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              if (_connectedSsid != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Continue setup from a browser:',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _ipAddress != null
                            ? 'http://$_ipAddress:8090'
                            : 'http://hearth.local:8090',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF646CFF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _finishSetup,
                    child: const Text('Skip'),
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
                          onPressed: _finishSetup,
                          child: const Text('Continue'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
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
