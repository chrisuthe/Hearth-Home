#!/usr/bin/env python3
"""Minimal SSDP responder for Hearth DLNA Media Renderer.

Listens for UPnP M-SEARCH multicast requests and responds with the
device location. Run as a subprocess from the Hearth app.

Usage: ssdp-responder.py <uuid> <friendly_name> <http_port> [local_ip]
"""

import socket
import struct
import sys
import time

MCAST_ADDR = "239.255.255.250"
MCAST_PORT = 1900

def get_local_ip():
    """Get the first non-loopback IPv4 address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def main():
    if len(sys.argv) < 4:
        print("Usage: ssdp-responder.py <uuid> <friendly_name> <http_port> [local_ip]")
        sys.exit(1)

    uuid = sys.argv[1]
    friendly_name = sys.argv[2]
    http_port = int(sys.argv[3])
    local_ip = sys.argv[4] if len(sys.argv) > 4 else get_local_ip()

    location = f"http://{local_ip}:{http_port}/dlna/device.xml"

    # Create multicast listener
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    sock.bind(("", MCAST_PORT))

    # Join multicast group on the local interface
    mreq = struct.pack("4s4s",
        socket.inet_aton(MCAST_ADDR),
        socket.inet_aton(local_ip))
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    print(f"SSDP responder started: {friendly_name} (uuid:{uuid})", flush=True)
    print(f"Location: {location}", flush=True)

    # Send initial alive
    nt = "urn:schemas-upnp-org:device:MediaRenderer:1"
    alive = (
        f"NOTIFY * HTTP/1.1\r\n"
        f"HOST: {MCAST_ADDR}:{MCAST_PORT}\r\n"
        f"CACHE-CONTROL: max-age=1800\r\n"
        f"LOCATION: {location}\r\n"
        f"NT: {nt}\r\n"
        f"NTS: ssdp:alive\r\n"
        f"SERVER: Hearth/1.0 UPnP/1.0\r\n"
        f"USN: uuid:{uuid}::{nt}\r\n"
        f"\r\n"
    )
    sock.sendto(alive.encode(), (MCAST_ADDR, MCAST_PORT))

    last_alive = time.time()
    sock.settimeout(30)  # wake up every 30s to resend alive

    while True:
        try:
            data, addr = sock.recvfrom(4096)
            message = data.decode("utf-8", errors="ignore")

            if not message.startswith("M-SEARCH"):
                continue

            # Extract ST header
            st = None
            for line in message.split("\r\n"):
                if line.upper().startswith("ST:"):
                    st = line.split(":", 1)[1].strip()
                    break

            if st is None:
                continue

            # Check if search is relevant
            relevant = (
                st == "ssdp:all"
                or st == "upnp:rootdevice"
                or "MediaRenderer" in st
                or "AVTransport" in st
                or "RenderingControl" in st
                or "ConnectionManager" in st
            )
            if not relevant:
                continue

            response = (
                f"HTTP/1.1 200 OK\r\n"
                f"CACHE-CONTROL: max-age=1800\r\n"
                f"LOCATION: {location}\r\n"
                f"SERVER: Hearth/1.0 UPnP/1.0\r\n"
                f"ST: {st}\r\n"
                f"USN: uuid:{uuid}::{st}\r\n"
                f"EXT:\r\n"
                f"\r\n"
            )
            sock.sendto(response.encode(), addr)

        except socket.timeout:
            pass

        # Resend alive every 60 seconds
        now = time.time()
        if now - last_alive >= 60:
            sock.sendto(alive.encode(), (MCAST_ADDR, MCAST_PORT))
            last_alive = now


if __name__ == "__main__":
    main()
