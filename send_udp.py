#!/usr/bin/env python3
"""Send a UDP datagram to a UDP listener."""

import argparse
import datetime
import socket
import sys


DEFAULT_DESTINATION_ADDRESS = "127.0.0.1"
DEFAULT_PORT = 5678
MAX_DATAGRAM_BYTES = 65507


def parse_args():
    parser = argparse.ArgumentParser(
        description="Send a UDP packet to a UDP listener."
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
        help="destination IPv4 address (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--port",
        default=DEFAULT_PORT,
        type=int,
        metavar="PORT",
        help="UDP destination port (default: 5678)",
    )
    args = parser.parse_args()

    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")

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


def main():
    args = parse_args()
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    try:
        sent_byte_count = sender.sendto(
            args.payload, (args.destination, args.port)
        )
    except OSError as error:
        print(
            "Unable to send to {}:{}: {}".format(
                args.destination, args.port, error
            ),
            file=sys.stderr,
        )
        return 1
    finally:
        sender.close()

    timestamp = datetime.datetime.now().astimezone().isoformat(
        timespec="seconds"
    )
    print(
        "[{}] {}:{} - {} bytes sent".format(
            timestamp,
            args.destination,
            args.port,
            sent_byte_count,
        )
    )
    print("  text: {!r}".format(args.message))
    print("  hex : {}".format(format_hex(args.payload)), flush=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
