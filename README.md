# KCU116 VHDL Ethernet demonstration

This example sends a valid UDP broadcast once per second through the KCU116
on-board DP83867 PHY. It does not use the AXI Ethernet Subsystem or a processor.
The only Ethernet IP is AMD's licensed **1G/2.5G Ethernet PCS/PMA or SGMII**
core, configured as:

- SGMII, MAC mode
- synchronous SGMII over LVDS
- 625-MHz differential reference clock
- 10/100/1000 capability with auto-negotiation
- shared logic included in the core
- client interface selected for TEMAC-style rate adaptation

The small transmit MAC, UDP frame, periodic trigger, PHY initialization, and
MDIO controller are VHDL.

## Requirements

- KCU116 evaluation board
- Vivado with the `gig_ethernet_pcs_pma` IP available and licensed (usually free)
- A 1-Gb/s-capable Ethernet switch or directly connected host
- Vivado 2026.1 is the configuration used as the reference. The script uses
  the installed version of the IP rather than hard-coding an IP version.

## Build

From the `source` directory:

```sh
vivado -mode batch -source create_project.tcl
```

The resulting programming file is:

```text
build/kcu116_ethernet_demo/kcu116_ethernet_demo.runs/impl_1/kcu116_ethernet_demo.bit
```

The Tcl script creates a new project and regenerates the PCS/PMA IP. Generated
IP files are intentionally not stored here.

## Run

1. Connect the KCU116 RJ45 port to a host or switch.
2. Program the generated bitstream.
3. Assign the receiving host an address in `1.2.3.0/24`, for example
   `1.2.3.4`. Subnet mask should be `255.255.255.0`. No gateway is required.
4. Start the console UDP listener.

   On Windows:

   ```powershell
   py listen_udp.py
   ```

   If the Python launcher is not installed, use
   `python listen_udp.py`.

   On Linux:

   ```sh
   python3 listen_udp.py
   ```

   The listener uses only the Python standard library, binds all IPv4
   interfaces on UDP port 5678, and runs until Ctrl+C is pressed. Each packet
   is printed as text and hexadecimal bytes:

   ```text
   Listening for UDP packets on 0.0.0.0:5678 (press Ctrl+C to stop)
   [2026-07-25T12:34:56+09:00] 1.2.3.116:1234 - 26 bytes
     text: 'Hello world! --from KCU116'
     hex : 48 65 6C 6C 6F 20 77 6F 72 6C 64 21 20 2D 2D 66 72 6F 6D 20 4B 43 55 31 31 36
   ```

   Use `--bind ADDRESS` or `--port PORT` to override the defaults:

   ```sh
   python3 listen_udp.py --bind 1.2.3.4 --port 5678
   ```

   On Windows, allow Python to receive traffic on the private network if
   Windows Firewall prompts. On Linux, ensure the local firewall allows
   incoming UDP port 5678.

5. Alternatively, capture UDP destination port 5678:

   ```sh
   sudo tcpdump -ni any 'udp port 5678' -XX
   ```

   Wireshark filter:

   ```text
   udp.dstport == 5678
   ```

The transmitted packet has:

| Field | Value |
|---|---|
| Destination MAC | `ff:ff:ff:ff:ff:ff` |
| Source MAC | `02:00:00:00:00:01` |
| Source IPv4 | `1.2.3.116` |
| Destination IPv4 | `1.2.3.4` |
| UDP ports | 1234 to 5678 |
| Payload | `Hello world! --from KCU116` |

`udp_to_gmii` provides these VHDL generics; the address and port generics are
also exposed by `kcu116_ethernet_demo`:

| Generic | Default |
|---|---|
| `UDP_PAYLOAD_BYTE_COUNT` | `26` (maximum `1472`) |
| `SOURCE_MAC_ADDRESS` | `x"020000000001"` |
| `DESTINATION_MAC_ADDRESS` | `x"FFFFFFFFFFFF"` |
| `SOURCE_IP_ADDRESS` | `x"01020374"` |
| `DESTINATION_IP_ADDRESS` | `x"01020304"` |
| `SOURCE_UDP_PORT` | `1234` |
| `DESTINATION_UDP_PORT` | `5678` |

The `UDP_PAYLOAD_BYTE_COUNT` generic sets the width of `udp_payload` to eight
times that many bits. The maximum UDP payload is 1472 bytes so the 20-byte IPv4
header, 8-byte UDP header, and payload fit the standard 1500-byte Ethernet MTU.
The leftmost payload byte is sent first. `udp_valid` and `udp_ready` implement
a standard valid-ready handshake: the producer holds `udp_valid` and
`udp_payload` stable until a rising clock edge where `udp_ready` is high. The
transmitter latches the payload on that edge, after which the producer may
change both inputs. The demo top level connects the
`Hello world! --from KCU116` payload shown above.

IPv4/UDP lengths, checksums, minimum Ethernet padding, and the Ethernet FCS are
generated automatically.

## LEDs

| LED | Meaning |
|---|---|
| 0 | DP83867 register configuration completed |
| 1 | DP83867 copper-side link up |
| 2 | PCS SGMII synchronization and auto-negotiation complete |
| 3 | Toggles after each transmitted UDP frame |
| 4 | Toggles at the start of each received GMII frame |
| 5 | Sticky GMII receive error |
| 6 | PHY initialization error |
| 7 | Negotiated SGMII speed is 1 Gb/s |

LEDs 0, 1, 2, and 7 should be on for a normal 1-Gb/s link. LED 3 changes state
once per second.

## UART status report

The FPGA continuously sends a textual status line through the KCU116 USB-UART
bridge at 9600 baud, 8 data bits, no parity, and one stop bit:

```text
PCS_STATUS=0xXXXX PHY_STATUS=0xXXXX PHYCR=0xXXXX CFG1=0xXXXX BMCR=0xXXXX BMSR=0xXXXX ANAR=0xXXXX ANLPAR=0xXXXX ANER=0xXXXX STS1=0xXXXX CFG4=0xXXXX STRAP_STS2=0xXXXX ANA_LD_DATA_CTRL=0xXXXX
```

`PCS_STATUS` is the 16-bit status vector from the PCS/PMA IP.
`PHY_STATUS` is the DP83867 Clause-22 `PHYSTS` register at address `0x11`,
polled over MDIO after the double read of BMSR. For example, `0xBF02` normally
indicates a 1-Gb/s full-duplex copper link. `PHYCR` is Clause-22 register
`0x10`; its force-link-good bit 10 should be clear and SGMII-enable bit 11
should be set. `CFG1` is Clause-22 register `0x09`; a normal automatic
leader/follower 1000BASE-T advertisement commonly reads `0x0300`.
`BMCR`, `BMSR`, `ANAR`, `ANLPAR`, `ANER`, and `STS1` expose the copper
Auto-Negotiation progress. `CFG4` and `STRAP_STS2` verify the KCU116 RX_CTRL
strap workaround. Extended register `ANA_LD_DATA_CTRL` at `0x00DD` normally
reads `0x0200`; `0x000F` indicates that the MDI transmitters are disabled.

## HDL verification

GHDL can verify the complete GMII byte stream, including operation when the
client clock enable is pulsed as it is at 100 Mb/s:

```sh
mkdir -p /tmp/kcu116-ghdl
ghdl -a --std=08 --workdir=/tmp/kcu116-ghdl \
  source/udp_to_gmii.vhd source/tb_udp_to_gmii.vhd
ghdl -e --std=08 --workdir=/tmp/kcu116-ghdl tb_udp_to_gmii
ghdl -r --std=08 --workdir=/tmp/kcu116-ghdl tb_udp_to_gmii \
  --assert-level=error
```

Expected output includes `Latched UDP payload-to-GMII frame verified`.

The PHY initialization and link-polling test is:

```sh
mkdir -p /tmp/kcu116-mdio
ghdl -a --std=08 --workdir=/tmp/kcu116-mdio \
  source/mdio_master.vhd source/mdio_slave.vhd \
  source/dp83867_sgmii_init.vhd source/tb_dp83867_sgmii_init.vhd
ghdl -e --std=08 --workdir=/tmp/kcu116-mdio tb_dp83867_sgmii_init
ghdl -r --std=08 --workdir=/tmp/kcu116-mdio tb_dp83867_sgmii_init \
  --assert-level=error --stop-time=31ms
```

Expected output includes `DP83867 configuration sequence verified`,
`DP83867 double-read link polling verified`, and
`DP83867 PHYSTS register polling verified`, followed by verification of
the remaining direct and extended diagnostic-register reads.

## Design notes

- The fixed board 125-MHz clock runs MDIO so the PHY can be configured before
  its 625-MHz SGMII clock exists.
- After reset, initialization writes `PHYCR=0x5848` to clear force-link-good
  while retaining SGMII and Auto-MDIX, and writes `CFG1=0x0300` to select
  automatic 1000BASE-T leader/follower resolution before restarting
  Auto-Negotiation.
- The PCS is held in reset until the MDIO sequence enables six-wire SGMII.
- Client logic is clocked by `clk125_out` from the PCS, not the unrelated board
  oscillator.
- `status_vector(11 downto 10)` controls PCS rate adaptation.
- `sgmii_clk_en` advances the GMII transmitter at the negotiated byte rate.
- `signal_detect` is tied high because the on-board LVDS connection has no
  separate loss-of-signal input.
- `status_vector(0)` gates frame transmission until SGMII auto-negotiation is
  complete.

This is deliberately a transmit demonstration rather than a complete
general-purpose Ethernet MAC. The receive GMII interface is monitored for
activity and errors but received frames are not parsed or answered.

## References

- AMD PG047, *1G/2.5G Ethernet PCS/PMA or SGMII LogiCORE IP Product Guide*:
  <https://docs.amd.com/r/en-US/pg047-gig-eth-pcs-pma>
- TI DP83867 datasheet:
  <https://www.ti.com/lit/ds/symlink/dp83867e.pdf>
- AMD Answer Record 69494, KCU116/VCU118 DP83867 SGMII bring-up
