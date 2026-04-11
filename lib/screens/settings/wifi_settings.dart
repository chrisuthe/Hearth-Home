import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app.dart' show kDialogBackground;
import '../../services/wifi_service.dart';

/// Displays the current WiFi connection and lets the user scan and connect.
class WifiSettingsSection extends ConsumerStatefulWidget {
  const WifiSettingsSection({super.key});

  @override
  ConsumerState<WifiSettingsSection> createState() => _WifiSettingsSectionState();
}

class _WifiSettingsSectionState extends ConsumerState<WifiSettingsSection> {
  String? _connectedSsid;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshConnection();
  }

  Future<void> _refreshConnection() async {
    final service = ref.read(wifiServiceProvider);
    final ssid = await service.activeConnection();
    if (mounted) {
      setState(() {
        _connectedSsid = ssid;
        _loading = false;
      });
    }
  }

  Future<void> _openPicker() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _WifiPickerDialog(
        currentSsid: _connectedSsid,
        wifiService: ref.read(wifiServiceProvider),
      ),
    );
    // Refresh connection status after dialog closes.
    await _refreshConnection();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connectedSsid != null && _connectedSsid!.isNotEmpty;
    final subtitle = _loading
        ? 'Checking...'
        : connected
            ? _connectedSsid!
            : 'Not connected';

    return ListTile(
      leading: Icon(
        connected ? Icons.wifi : Icons.wifi_off,
        color: Colors.white54,
        size: 22,
      ),
      title: const Text('Wi-Fi', style: TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: _openPicker,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

/// Dialog that scans for networks and handles connect/disconnect flows.
class _WifiPickerDialog extends StatefulWidget {
  final String? currentSsid;
  final WifiService wifiService;

  const _WifiPickerDialog({
    required this.currentSsid,
    required this.wifiService,
  });

  @override
  State<_WifiPickerDialog> createState() => _WifiPickerDialogState();
}

class _WifiPickerDialogState extends State<_WifiPickerDialog> {
  List<WifiNetwork>? _networks;
  bool _scanning = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _networks = null;
      _statusMessage = null;
    });
    final networks = await widget.wifiService.scan();
    if (mounted) {
      setState(() {
        _networks = networks;
        _scanning = false;
      });
    }
  }

  Future<void> _connectTo(WifiNetwork network) async {
    if (network.isOpen) {
      setState(() => _statusMessage = 'Connecting to ${network.ssid}…');
      final ok = await widget.wifiService.connectOpen(network.ssid);
      if (mounted) {
        setState(() => _statusMessage =
            ok ? 'Connected to ${network.ssid}' : 'Failed to connect');
      }
      return;
    }

    // Secured network — ask for password.
    final password = await _askPassword(network.ssid);
    if (password == null) return;

    setState(() => _statusMessage = 'Connecting to ${network.ssid}…');
    final ok = await widget.wifiService.connect(network.ssid, password);
    if (mounted) {
      setState(() => _statusMessage =
          ok ? 'Connected to ${network.ssid}' : 'Failed to connect');
    }
  }

  Future<String?> _askPassword(String ssid) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogBackground,
        title: Text('Connect to $ssid'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Password'),
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
    return AlertDialog(
      backgroundColor: kDialogBackground,
      title: Row(
        children: [
          const Expanded(child: Text('Wi-Fi Networks')),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _scanning ? null : _scan,
            tooltip: 'Rescan',
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_statusMessage != null) ...[
              Text(
                _statusMessage!,
                style: const TextStyle(fontSize: 13, color: Colors.amber),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _scanning
                  ? const Center(child: CircularProgressIndicator())
                  : _networks == null || _networks!.isEmpty
                      ? Center(
                          child: Text(
                            'No networks found',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _networks!.length,
                          itemBuilder: (ctx, i) {
                            final n = _networks![i];
                            final isActive = n.ssid == widget.currentSsid;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                n.isSecured ? Icons.lock : Icons.wifi,
                                size: 18,
                                color: isActive
                                    ? const Color(0xFF646CFF)
                                    : Colors.white54,
                              ),
                              title: Text(
                                n.ssid,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isActive
                                      ? const Color(0xFF646CFF)
                                      : Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                '${n.signalStrength}%${n.isSecured ? '  \u{1F512}' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              onTap: () => _connectTo(n),
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
          child: const Text('Done'),
        ),
      ],
    );
  }
}
