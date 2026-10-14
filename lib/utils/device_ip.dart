import 'dart:io';

/// The device's first non-loopback IPv4 address, or null when none resolves.
Future<String?> lookupDeviceIp() async {
  try {
    final interfaces = await NetworkInterface.list();
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
  } catch (_) {}
  return null;
}
