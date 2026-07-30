#!/usr/bin/env python3
"""Send UDP datagrams as broadcasts on a selected local subnet."""

import argparse
import collections
import datetime
import ipaddress
import math
import socket
import struct
import sys
import time


DEFAULT_DESTINATION_ADDRESS = "127.0.0.1"
DEFAULT_PORT = 5678
MAX_DATAGRAM_BYTES = 65507
InterfaceAddress = collections.namedtuple(
    "InterfaceAddress", ["name", "address", "prefix_length"]
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Send a UDP broadcast on a local IPv4 subnet."
    )
    parser.add_argument(
        "message",
        metavar="MESSAGE",
        help="UTF-8 text to send",
    )
    parser.add_argument(
        "--destination",
        default=DEFAULT_DESTINATION_ADDRESS,
        metavar="ADDRESS",
        help=(
            "IPv4 address identifying the target local subnet "
            "(default: 127.0.0.1)"
        ),
    )
    parser.add_argument(
        "--port",
        default=DEFAULT_PORT,
        type=int,
        metavar="PORT",
        help="UDP destination port (default: 5678)",
    )
    parser.add_argument(
        "--count",
        default=1,
        type=int,
        metavar="COUNT",
        help="number of UDP datagrams to send (default: 1)",
    )
    parser.add_argument(
        "--interval",
        default=0.0,
        type=float,
        metavar="SECONDS",
        help=(
            "delay in seconds between UDP datagrams "
            "(default: 0, send as a burst)"
        ),
    )
    args = parser.parse_args()

    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    if args.count < 1:
        parser.error("--count must be at least 1")
    if not math.isfinite(args.interval) or args.interval < 0:
        parser.error("--interval must be a finite, non-negative number")

    try:
        args.destination = str(ipaddress.IPv4Address(args.destination))
    except ipaddress.AddressValueError:
        parser.error("--destination must be an IPv4 address")

    payload = args.message.encode("utf-8")
    if len(payload) > MAX_DATAGRAM_BYTES:
        parser.error(
            "MESSAGE must be at most {} UTF-8 bytes".format(
                MAX_DATAGRAM_BYTES
            )
        )

    args.payload = payload
    return args


def format_hex(data):
    return " ".join("{:02X}".format(value) for value in data)


def windows_interface_addresses():
    import ctypes
    from ctypes import wintypes

    class SocketAddress(ctypes.Structure):
        _fields_ = [
            ("sockaddr", ctypes.c_void_p),
            ("sockaddr_length", ctypes.c_int),
        ]

    class AdapterUnicastAddress(ctypes.Structure):
        pass

    AdapterUnicastAddress._fields_ = [
        ("length", wintypes.ULONG),
        ("flags", wintypes.DWORD),
        ("next", ctypes.POINTER(AdapterUnicastAddress)),
        ("address", SocketAddress),
        ("prefix_origin", ctypes.c_int),
        ("suffix_origin", ctypes.c_int),
        ("dad_state", ctypes.c_int),
        ("valid_lifetime", wintypes.ULONG),
        ("preferred_lifetime", wintypes.ULONG),
        ("lease_lifetime", wintypes.ULONG),
        ("on_link_prefix_length", ctypes.c_ubyte),
    ]

    class AdapterAddresses(ctypes.Structure):
        pass

    AdapterAddresses._fields_ = [
        ("length", wintypes.ULONG),
        ("interface_index", wintypes.DWORD),
        ("next", ctypes.POINTER(AdapterAddresses)),
        ("adapter_name", ctypes.c_char_p),
        ("first_unicast_address", ctypes.POINTER(AdapterUnicastAddress)),
        ("first_anycast_address", ctypes.c_void_p),
        ("first_multicast_address", ctypes.c_void_p),
        ("first_dns_server_address", ctypes.c_void_p),
        ("dns_suffix", ctypes.c_wchar_p),
        ("description", ctypes.c_wchar_p),
        ("friendly_name", ctypes.c_wchar_p),
        ("physical_address", ctypes.c_ubyte * 8),
        ("physical_address_length", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("mtu", wintypes.DWORD),
        ("interface_type", wintypes.DWORD),
        ("oper_status", ctypes.c_int),
    ]

    class SockaddrIn(ctypes.Structure):
        _fields_ = [
            ("family", ctypes.c_ushort),
            ("port", ctypes.c_ushort),
            ("address", ctypes.c_ubyte * 4),
            ("zero", ctypes.c_ubyte * 8),
        ]

    get_adapters_addresses = (
        ctypes.windll.iphlpapi.GetAdaptersAddresses
    )
    get_adapters_addresses.argtypes = [
        wintypes.ULONG,
        wintypes.ULONG,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.POINTER(wintypes.ULONG),
    ]
    get_adapters_addresses.restype = wintypes.ULONG

    error_buffer_overflow = 111
    buffer_size = wintypes.ULONG(15 * 1024)
    while True:
        buffer = ctypes.create_string_buffer(buffer_size.value)
        result = get_adapters_addresses(
            socket.AF_INET,
            0,
            None,
            buffer,
            ctypes.byref(buffer_size),
        )
        if result != error_buffer_overflow:
            break

    if result != 0:
        raise OSError(
            "GetAdaptersAddresses failed with error {}".format(result)
        )

    interfaces = []
    adapter_pointer = ctypes.cast(
        buffer, ctypes.POINTER(AdapterAddresses)
    )
    while adapter_pointer:
        adapter = adapter_pointer.contents
        if adapter.friendly_name:
            name = adapter.friendly_name
        elif adapter.description:
            name = adapter.description
        else:
            name = adapter.adapter_name.decode(
                "ascii", errors="replace"
            )

        unicast_pointer = adapter.first_unicast_address
        while unicast_pointer:
            unicast = unicast_pointer.contents
            address_pointer = unicast.address.sockaddr
            if address_pointer:
                sockaddr = ctypes.cast(
                    address_pointer, ctypes.POINTER(SockaddrIn)
                ).contents
                if sockaddr.family == socket.AF_INET:
                    address = socket.inet_ntoa(
                        bytes(sockaddr.address)
                    )
                    prefix_length = int(
                        unicast.on_link_prefix_length
                    )
                    if 0 <= prefix_length <= 32:
                        interfaces.append(
                            InterfaceAddress(
                                name, address, prefix_length
                            )
                        )
            unicast_pointer = unicast.next
        adapter_pointer = adapter.next

    return interfaces


def linux_interface_addresses():
    import fcntl

    interfaces = []
    request_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        for _, name in socket.if_nameindex():
            encoded_name = name.encode("utf-8")[:15]
            request = struct.pack("256s", encoded_name)
            try:
                address_data = fcntl.ioctl(
                    request_socket.fileno(), 0x8915, request
                )
                netmask_data = fcntl.ioctl(
                    request_socket.fileno(), 0x891B, request
                )
            except OSError:
                continue

            address = socket.inet_ntoa(address_data[20:24])
            netmask = socket.inet_ntoa(netmask_data[20:24])
            try:
                prefix_length = ipaddress.IPv4Network(
                    "0.0.0.0/{}".format(netmask)
                ).prefixlen
            except ipaddress.NetmaskValueError:
                continue

            interfaces.append(
                InterfaceAddress(name, address, prefix_length)
            )
    finally:
        request_socket.close()

    return interfaces


def interface_addresses():
    if sys.platform == "win32":
        return windows_interface_addresses()
    if sys.platform.startswith("linux"):
        return linux_interface_addresses()
    raise OSError(
        "automatic subnet adapter selection is supported only on "
        "Windows and Linux"
    )


def select_source_interface(destination, interfaces=None):
    destination_address = ipaddress.IPv4Address(destination)
    if interfaces is None:
        interfaces = interface_addresses()

    matches = []
    for interface in interfaces:
        network = ipaddress.IPv4Network(
            "{}/{}".format(
                interface.address, interface.prefix_length
            ),
            strict=False,
        )
        if destination_address in network:
            matches.append(interface)

    if not matches:
        available = ", ".join(
            "{}={}/{}".format(
                interface.name,
                interface.address,
                interface.prefix_length,
            )
            for interface in interfaces
        )
        if not available:
            available = "none"
        raise OSError(
            "no local IPv4 adapter has destination {} in its subnet; "
            "available adapters: {}".format(destination, available)
        )

    matches.sort(
        key=lambda interface: (
            -interface.prefix_length,
            interface.name.casefold(),
            int(ipaddress.IPv4Address(interface.address)),
        )
    )
    return matches[0]


def subnet_broadcast_address(interface):
    network = ipaddress.IPv4Network(
        "{}/{}".format(
            interface.address, interface.prefix_length
        ),
        strict=False,
    )
    if network.prefixlen >= 31:
        raise OSError(
            "adapter {} uses {}, which has no usable IPv4 broadcast "
            "address".format(interface.name, network)
        )
    return str(network.broadcast_address)


def main():
    args = parse_args()

    try:
        source_interface = select_source_interface(args.destination)
        broadcast_address = subnet_broadcast_address(source_interface)
    except OSError as error:
        print("Unable to select source adapter: {}".format(error),
              file=sys.stderr)
        return 1

    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sender.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sender.bind((source_interface.address, 0))
        total_sent_byte_count = 0
        for datagram_index in range(args.count):
            sent_byte_count = sender.sendto(
                args.payload, (broadcast_address, args.port)
            )
            if sent_byte_count != len(args.payload):
                raise OSError(
                    "only {} of {} datagram bytes were sent".format(
                        sent_byte_count, len(args.payload)
                    )
                )
            total_sent_byte_count += sent_byte_count
            if args.interval > 0 and datagram_index + 1 < args.count:
                time.sleep(args.interval)
        source_address, source_port = sender.getsockname()
    except OSError as error:
        print(
            "Unable to broadcast via {} ({}/{}) to {}:{}: {}".format(
                source_interface.name,
                source_interface.address,
                source_interface.prefix_length,
                broadcast_address,
                args.port,
                error,
            ),
            file=sys.stderr,
        )
        return 1
    finally:
        sender.close()

    timestamp = datetime.datetime.now().astimezone().isoformat(
        timespec="seconds"
    )
    datagram_word = "datagram" if args.count == 1 else "datagrams"
    print(
        "[{}] {}:{} -> {}:{} - {} {} sent "
        "({} bytes each, {} bytes total) via {}".format(
            timestamp,
            source_address,
            source_port,
            broadcast_address,
            args.port,
            args.count,
            datagram_word,
            len(args.payload),
            total_sent_byte_count,
            source_interface.name,
        )
    )
    print("  text: {!r}".format(args.message))
    print("  hex : {}".format(format_hex(args.payload)), flush=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
