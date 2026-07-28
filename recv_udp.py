#!/usr/bin/env python3
"""Continuously receive and print UDP datagrams from the KCU116 example."""

import argparse
import datetime
import socket
import sys


DEFAULT_BIND_ADDRESS = "0.0.0.0"
DEFAULT_PORT = 5678
MAX_DATAGRAM_BYTES = 65535


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Receive and print UDP packets from the KCU116 Ethernet demo."
        )
    )
    parser.add_argument(
        "--bind",
        default=DEFAULT_BIND_ADDRESS,
        metavar="ADDRESS",
        help=(
            "local IPv4 address on which to receive "
            "(default: all IPv4 interfaces)"
        ),
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
    return args


def format_hex(data):
    return " ".join("{:02X}".format(value) for value in data)


def main():
    args = parse_args()
    receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    try:
        receiver.bind((args.bind, args.port))
    except OSError as error:
        receiver.close()
        print(
            "Unable to receive on {}:{}: {}".format(
                args.bind, args.port, error
            ),
            file=sys.stderr,
        )
        return 1

    print(
        "Receiving UDP packets on {}:{} (press Ctrl+C to stop)".format(
            args.bind, args.port
        ),
        flush=True,
    )

    try:
        while True:
            data, sender = receiver.recvfrom(MAX_DATAGRAM_BYTES)
            timestamp = datetime.datetime.now().astimezone().isoformat(
                timespec="seconds"
            )
            text = data.decode("utf-8", errors="backslashreplace")

            print(
                "[{}] {}:{} - {} bytes".format(
                    timestamp, sender[0], sender[1], len(data)
                )
            )
            print("  text: {!r}".format(text))
            print("  hex : {}".format(format_hex(data)), flush=True)
    except KeyboardInterrupt:
        print("\nReceiver stopped.")
    finally:
        receiver.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
