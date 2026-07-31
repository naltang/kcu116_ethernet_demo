# KCU116/VCU118 VHDL Ethernet demonstration

This FPGA-only demonstration transmits one valid UDP broadcast per second
through the on-board DP83867 PHY on either a KCU116 or a VCU118 Rev 2.0+
evaluation board. The VHDL sources are shared; the project script selects the
FPGA part and board constraints. The design also monitors received Ethernet
frames, but it does not implement receive protocol processing.

> **Important:** The design does not contain an ARP, ICMP, or UDP responder.
> The board therefore does not answer ARP requests or ping, even when both the
> copper and SGMII links are healthy. The source address `1.2.3.100` identifies
> transmitted IPv4 datagrams; it is not a complete network stack. Use the LEDs,
> UART status report, or packet capture to check the board.

The design does not use the AXI Ethernet Subsystem or a processor. Its only
Ethernet IP is AMD's licensed **1G/2.5G Ethernet PCS/PMA or SGMII** core,
configured for:

- SGMII MAC mode
- synchronous SGMII over LVDS
- a 625-MHz differential reference clock
- 10/100/1000 operation with auto-negotiation
- shared logic included in the core
- TEMAC-style client rate adaptation

The transmit MAC, UDP frame generator, periodic trigger, PHY initialization,
MDIO controller, receive statistics, and UART formatter are VHDL.

## Requirements

- KCU116 evaluation board or VCU118 Rev 2.0+ evaluation board
- Vivado with a license covering the selected FPGA device
- The `gig_ethernet_pcs_pma` IP installed and licensed for synthesis
- A 1-Gb/s-capable Ethernet switch or a directly connected host
- Python 3 for the optional host utilities

Vivado 2026.1 is the reference configuration. The project script uses the
installed PCS/PMA IP version rather than hard-coding a version number.

## Build

### Configure the Vivado environment

If `vivado` is not already available on the command line, initialize the
environment using the setup script supplied with the installed version.

On Windows Command Prompt:

```bat
call C:\path\to\Vivado\2026.1\settings64.bat
```

On Linux:

```sh
source /path/to/Vivado/2026.1/settings64.sh
```

The installation path and version may differ.

### Generate the project and bitstream

The board argument is mandatory. From the repository root, build exactly one
target:

```sh
vivado -mode batch -source create_project.tcl -tclargs kcu116
vivado -mode batch -source create_project.tcl -tclargs vcu118
```

The resulting projects and programming files are:

```text
build_kcu116/kcu116_ethernet_demo.xpr
build_kcu116/kcu116_ethernet_demo.runs/impl_1/ethernet_demo.bit

build_vcu118/vcu118_ethernet_demo.xpr
build_vcu118/vcu118_ethernet_demo.runs/impl_1/ethernet_demo.bit
```

`create_project.tcl` recreates the project and regenerates the PCS/PMA IP.
Generated project and IP files are intentionally not stored in the repository.
Running the script without a board argument, with more than one argument, or
with an unsupported board name prints the usage message and exits without
creating a project.

Both targets synthesize the same `source/ethernet_demo.vhd` top level and
supporting VHDL. Board selection changes only the generated project:

| Target | FPGA part | Constraints | Build directory |
|---|---|---|---|
| `kcu116` | `xcku5p-ffvb676-2-e` | `constraints/kcu116.xdc` | `build_kcu116/` |
| `vcu118` | `xcvu9p-flga2104-2L-e` | `constraints/vcu118.xdc` | `build_vcu118/` |

The VCU118 constraints target Rev 2.0 and later boards. Pin assignments and
I/O standards were taken from AMD's official VCU118 Rev 2.0 master XDC.
Both targets intentionally use the same MAC and IPv4 addresses. Do not connect
a KCU116 and VCU118 running this design to the same network at the same time.

## Quick start

1. Build the target selected above.
2. Connect that board's RJ45 port to a host or a 1-Gb/s-capable switch.
3. Program the matching bitstream. A KCU116 bitstream cannot be used on a
   VCU118, or vice versa. The Center PHY profile is selected automatically.
4. Assign the receiving host an address in `1.2.3.0/24`, such as `1.2.3.4`,
   with subnet mask `255.255.255.0`. No gateway is required.
5. Start the UDP receiver:

   ```sh
   python3 recv_udp.py
   ```

   On Windows, `py recv_udp.py` can be used instead.
6. Confirm that LEDs 0, 1, 2, and 7 are on. LED 3 should change state once per
   second.
7. Wait for the transmitted payload to appear:

   ```text
   [2026-07-25T12:34:56+09:00] 1.2.3.100:1234 - 34 bytes
     text: 'Hello world! -- from an FPGA board'
     hex : 48 65 6C 6C 6F 20 77 6F 72 6C 64 21 20 2D 2D 20 66 72 6F 6D 20 61 6E 20 46 50 47 41 20 62 6F 61 72 64
   ```

If no datagram appears, check the [troubleshooting](#troubleshooting) section
before modifying the PCS/PMA configuration.

## Host utilities

Both utilities use only the Python standard library.

### Receive board traffic

`recv_udp.py` listens continuously on UDP port 5678 and prints each datagram as
text and hexadecimal bytes.

On Windows:

```powershell
py recv_udp.py
```

If the Python launcher is unavailable:

```powershell
python recv_udp.py
```

On Linux:

```sh
python3 recv_udp.py
```

The default bind address is `0.0.0.0`, so all local IPv4 interfaces are
monitored. Override the bind address or port when required:

```sh
python3 recv_udp.py --bind 1.2.3.4 --port 5678
```

On Windows, allow Python to receive traffic on the private network if Windows
Firewall prompts. On Linux, ensure that the local firewall allows incoming UDP
port 5678.

### Generate test traffic

`send_udp.py` generates directed-broadcast UDP traffic. To send ten test
datagrams to a `recv_udp.py` instance using its default port:

```sh
python3 send_udp.py "interface test" --destination 1.2.3.4 --port 5678 --count 10
```

To exercise the FPGA receive counter instead, the UDP port is unimportant
because the FPGA counts Ethernet frames without parsing their contents:

```sh
python3 send_udp.py "counter test" --destination 1.2.3.100 --port 1234 --count 100
```

Use `--interval SECONDS` to pace the datagrams. The value accepts fractional
seconds; for example, this sends ten datagrams with 50 ms between consecutive
transmissions:

```sh
python3 send_udp.py "paced test" --destination 1.2.3.100 --count 10 --interval 0.05
```

`--destination` is a subnet selector, not the transmitted destination address.
The script finds the local IPv4 interface whose subnet contains the supplied
address, binds to that interface, and sends to the subnet's directed-broadcast
address. The resulting Ethernet destination is `ff:ff:ff:ff:ff:ff`.

If several interfaces match, the one with the longest subnet prefix is used.
The script reports an error rather than silently using a default interface
when no subnet matches. `--count COUNT` defaults to one and sends the requested
number of datagrams through the same socket. `--interval SECONDS` defaults to
zero, which sends them back-to-back as a burst. A positive, finite value inserts
that delay between consecutive datagrams; no delay is added after the final
datagram. UDP does not guarantee that every sent datagram will be delivered.

### Capture traffic

To capture UDP destination port 5678 on Linux:

```sh
sudo tcpdump -ni any 'udp port 5678' -XX
```

Equivalent Wireshark display filter:

```text
udp.dstport == 5678
```

## Default frame and VHDL configuration

The top-level demonstration transmits:

| Field | Default value |
|---|---|
| Destination MAC | `ff:ff:ff:ff:ff:ff` |
| Source MAC | `02:00:00:00:00:01` |
| Source IPv4 | `1.2.3.100` |
| Destination IPv4 | `1.2.3.4` |
| UDP source port | `1234` |
| UDP destination port | `5678` |
| Payload | `Hello world! -- from an FPGA board` |

`udp_to_gmii` provides the following generics. The address and port generics
are also exposed by the board-neutral `ethernet_demo` top level. The module's
generic payload default remains 26 bytes; the demonstration top level supplies
the 34-byte text shown above.

| Generic | Default |
|---|---|
| `UDP_PAYLOAD_BYTE_COUNT` | `26` (maximum `1472`) |
| `SOURCE_MAC_ADDRESS` | `x"020000000001"` |
| `DESTINATION_MAC_ADDRESS` | `x"FFFFFFFFFFFF"` |
| `SOURCE_IP_ADDRESS` | `x"01020364"` |
| `DESTINATION_IP_ADDRESS` | `x"01020304"` |
| `SOURCE_UDP_PORT` | `1234` |
| `DESTINATION_UDP_PORT` | `5678` |

`UDP_PAYLOAD_BYTE_COUNT` sets the width of `udp_payload` to eight times the
specified number of bytes. Its maximum is 1472 so the 20-byte IPv4 header,
8-byte UDP header, and payload fit the standard 1500-byte Ethernet MTU.

The leftmost payload byte is sent first. `udp_valid` and `udp_ready` implement
a standard valid-ready handshake: the producer holds `udp_valid` and
`udp_payload` stable until a rising clock edge on which `udp_ready` is high.
The transmitter latches the payload on that edge, after which the producer may
change both inputs. The demonstration top level connects the default payload
shown above.

IPv4 and UDP lengths, IPv4 and UDP checksums, minimum Ethernet padding, and the
transmitted Ethernet FCS are generated automatically. Received Ethernet FCS
values are checked by the statistics monitor.

## PHY configuration profiles

The five active-high directional pushbuttons select complete DP83867
initialization profiles. They are separate from the CPU reset pushbutton and
have the same logical names on both supported boards. At FPGA startup, the
Center profile is selected automatically.

| Button and UART prefix | Profile | PHY-specific change |
|---|---|---|
| Center (`C`) | Baseline | Existing six-wire SGMII, copper auto-negotiation, speed-optimization, and board-strap settings |
| North (`N`) | Inter-channel margin | Extended register `0x0102=0x7477` to increase AGC convergence time and `0x00E4=0x0080` to disable AGC retraining |
| East (`E`) | Normal MDI amplitude | Extended register `0x01D5=0xF508`, the TI unstable-1-Gb/s setting that changes the PHY from low-power to normal operational mode |
| South (`S`) | Short-cable DSP margin | Complete TI short-cable convergence and timing-bandwidth sequence |
| West (`W`) | No-downshift diagnostic | Baseline with `CFG2.SPEED_OPT_EN` cleared (`CFG2=0x29C0`) so failed 1-Gb/s establishment does not invoke speed optimization |

The South profile writes the following extended-register values:

```text
0053=2054 00EF=3840 0102=7477 0103=7777 0104=4577
010C=7777 01C2=7FDE 0115=5555 0118=0771 011D=6DB2
011E=3FFB 01C3=FFC6 01C4=0FC2 01C5=0FF0 012C=0E81
```

Press and release exactly one directional button after LED 0 is on. The
buttons are synchronized and debounced; a held button produces only one
request, and simultaneous presses are ignored. Selecting any profile,
including the one already active, performs a complete PHY reset before writing
the profile and common SGMII settings. LED 0 turns off, the Ethernet link drops
temporarily, and UART reporting pauses until initialization finishes.

The frame counters and sticky receive-error indication are cleared by a profile
change so measurements for the new configuration start from zero. Save the
preceding UART line before pressing a button. CPU reset restores the Center
profile.

North and South are TI troubleshooting configurations, not general cable
repairs. East is intended for the condition described by TI's unstable
1-Gb/s procedure and can increase PHY power consumption. West is diagnostic:
with a marginal four-pair path it can remain down instead of falling back to a
lower speed. Press Center to restore the normal configuration.

## LED status

| LED | Meaning |
|---|---|
| 0 | DP83867 register configuration completed |
| 1 | DP83867 copper-side link up |
| 2 | PCS SGMII synchronization and auto-negotiation complete |
| 3 | Toggles after each transmitted Ethernet frame |
| 4 | Toggles at the start of each received GMII frame |
| 5 | Sticky GMII receive error |
| 6 | PHY initialization error |
| 7 | Negotiated SGMII speed is 1 Gb/s |

For a normal 1-Gb/s link, LEDs 0, 1, 2, and 7 should be on. LED 3 changes state
once per second. LED 5 excludes the normal `RX_DV=0`, `RX_ER=1`, `RXD=0x0F`
carrier-extension indication.

## UART status

The FPGA continuously transmits a textual status line through the selected
board's USB-UART bridge at 9600 baud, 8 data bits, no parity, and one stop bit:

```text
C FRAME(S=0xXXXX R=0xXXXX F=0xXXXX E=0xXXXX) PCS=0xXXXX PHYSTS=0xXXXX BMCR=0xXXXX BMSR=0xXXXX STS1=0xXXXX RECR=0xXXXX ISR=0xXXXX MSE(A=0xXXXX B=0xXXXX C=0xXXXX D=0xXXXX) ANAR=0xXXXX ANLPAR=0xXXXX ANER=0xXXXX PHYCR=0xXXXX CFG1=0xXXXX CFG4=0xXXXX STRAP2=0xXXXX ANA_LD=0xXXXX
```

An illustrative report after successful 1-Gb/s auto-negotiation is:

```text
C FRAME(S=0x000C R=0x0003 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xAC02 BMCR=0x1140 BMSR=0x796D STS1=0x7800 RECR=0x0000 ISR=0x0000 MSE(A=0x0123 B=0x0145 C=0x0167 D=0x0189) ANAR=0x01E1 ANLPAR=0xC1E1 ANER=0x006D PHYCR=0x5848 CFG1=0x0300 CFG4=0x1030 STRAP2=0x0150 ANA_LD=0x0200
```

The first character is always `C`, `N`, `E`, `S`, or `W` and identifies the
PHY profile that completed initialization. The fields remain on one physical
line. `FRAME(...)` groups the Ethernet statistics and `MSE(...)` groups the
four copper-channel measurements. All other fields are printed without an
enclosing group.

### Frame counters

The `FRAME` group contains four 16-bit unsigned counters. They are printed as
fixed-width hexadecimal values, cleared by `cpu_reset` or a PHY profile change,
and wrap from `0xFFFF` to `0x0000`.

| Field | Meaning |
|---|---|
| `S` | Increments after a complete transmitted frame |
| `R` | Increments after a complete GMII `RX_DV` interval containing no `RX_ER`; FCS is not part of this decision |
| `F` | Increments when a frame counted by `R` has an invalid Ethernet FCS |
| `E` | Increments once for a receive interval containing `RX_ER`, or for a standalone non-carrier receive-error event |

`F` is a subset of `R`, while frames counted by `E` do not also increment `R`
or `F`. Therefore, the modulo-16-bit number of received frames with a valid FCS
is:

```text
FCS-good receive count = (R - F) mod 65536
```

The FCS calculation starts after the start-of-frame delimiter, covers the
Ethernet header, data, padding, and received FCS, and checks the standard CRC-32
residue. It advances only on `sgmii_clk_en`, so repeated GMII values at 10 or
100 Mb/s are included once. `E` excludes the normal `RX_DV=0`, `RX_ER=1`,
`RXD=0x0F` carrier-extension indication.

#### Relating `send_udp.py --count` to `R`

Each small datagram generated by `send_udp.py` normally produces one Ethernet
frame counted by `R`. For example:

```sh
python3 send_udp.py "test" --destination 1.2.3.100 --count 100
```

Normally, the modulo-16-bit increase should be at least 100:

```text
R increase = (R_after - R_before) mod 65536
```

The increase need not equal 100 because `R` counts every complete Ethernet
frame seen on GMII without `RX_ER`, not only traffic generated by
`send_udp.py`.
Background ARP, DHCP, IPv6, multicast, and discovery traffic can increase `R`
automatically. A large UDP datagram can be fragmented into multiple Ethernet
frames.

Conversely, UDP provides no delivery guarantee. Host, switch, or link drops
can make the increase less than 100, and receive events reported with `RX_ER`
increment `E` instead of `R`. A corrupted frame that reaches GMII without
`RX_ER` increments both `R` and `F`; in a normal controlled test, `F` should
remain unchanged.

### PCS and PHY fields

This table is the canonical reference for the remaining UART fields:

| Field | Source and meaning | Healthy reference indication |
|---|---|---|
| `PCS` | 16-bit PCS/PMA status vector | Typically `0x388B`; bit 0 set and bits 11:10 equal `10` |
| `PHYSTS` | DP83867 Clause-22 register `0x11` | Typically `0xAC02` for a 1-Gb/s full-duplex link |
| `BMCR` | Basic mode control register | Typically `0x1140` after restart bit 9 from `0x1340` self-clears |
| `BMSR` | Basic mode status register, read twice to expose current link state | Typically `0x796D`; link-status bit 2 set |
| `STS1` | DP83867 status register 1 | Typically `0x7800` |
| `RECR` | DP83867 Clause-22 receiver error counter at `0x15` | Normally `0x0000` |
| `ISR` | Accumulated DP83867 interrupt-status events from Clause-22 register `0x13` since the preceding UART report | Often `0x0000` on a stable link; link or auto-negotiation events can make it nonzero |
| `MSE(A/B/C/D)` | DP83867 extended mean-square-error registers `0x0225`, `0x0265`, `0x02A5`, and `0x02E5` | At 1 Gb/s, values below `0x020A` indicate excellent link quality |
| `ANAR` | Auto-negotiation advertisement | Typically `0x01E1` |
| `ANLPAR` | Link-partner auto-negotiation ability | Commonly `0xC1E1`; depends on the link partner |
| `ANER` | Auto-negotiation expansion | Commonly `0x006D`; depends on the link partner |
| `PHYCR` | Clause-22 register `0x10`; includes SGMII enable and force-link-good controls | `0x5848`; bit 11 set and force-link-good bit 10 clear |
| `CFG1` | Clause-22 register `0x09`; 1000BASE-T advertisement | `0x0300` |
| `CFG4` | DP83867 configuration register 4 | `0x1030` |
| `STRAP2` | DP83867 strap status register 2 | Board strap status; `0x0150` is typical on the KCU116 |
| `ANA_LD` | DP83867 extended analog load-data control register `0x00DD` | `0x0200`; `0x000F` indicates disabled MDI transmitters |

`PHYSTS` is polled after the double read of `BMSR`. Partner-dependent fields
such as `ANLPAR`, `ANER`, and some status bits need not exactly match the
example. Interpret them together with `BMSR`, `PHYSTS`, and `PCS`.

The DP83867 `ISR` event bits are latched high and clear when register `0x13`
is read. Polling therefore ORs each read into an FPGA accumulator. The UART
formatter snapshots that accumulator with the other fields, then clears it
for the next report. A displayed bit means that the corresponding event was
observed at least once since the preceding line; it is not a live level and
does not count how many times the event occurred.

The four `MSE` values measure copper-channel link quality; lower is better.
TI classifies a value less than 522 (less than `0x020A`) as excellent, 522
through 827 (`0x020A` through `0x033B`) as good, and greater than 827 (greater
than `0x033B`) as poor. The values depend on the cable, board layout, noise,
and link partner, so the example values above are not expected constants.
All four channels are applicable at 1 Gb/s. At 100 Mb/s only channel A is
applicable, and at 10 Mb/s none of the four values is applicable. Interpret
the values only while the copper link is up. The reported quartet is updated
together after channel D is read, so one UART line cannot combine MSE values
from two polling cycles. An inapplicable or unstable channel can report
`0x7FFF`; do not classify that value by itself as a poor cable.

`RECR` saturates at `0xFFFF`; an MDIO write clears it, while normal polling
does not. The `FRAME` group's `E` counter and `RECR` measure errors at different
points and are not expected to match exactly. `E` observes the FPGA GMII
interface after the SGMII/PCS path and wraps at `0xFFFF`. `RECR` records
receive errors detected by the DP83867 on its copper side and saturates at
`0xFFFF`. An SGMII/PCS-path error can therefore increment `E` without changing
`RECR`.

## Troubleshooting

Before changing the PCS/PMA configuration, constraints, or host software:

1. Open the selected board's FPGA USB-UART port at 9600 baud, 8-N-1.
2. Wait for PHY initialization to finish.
3. Save several complete UART status lines.
4. Compare the observed LEDs and fields with the table below.

Restarting the PHY while recording the UART output is a useful way to narrow
the fault to a network layer. First save the current lines, then press and
release the button whose letter already appears at the start of the UART line;
this reapplies the same profile, so the configuration under test does not
change. The link drop, UART pause, and counter reset are expected. Record the
complete sequence from down/training through link establishment or speed
fallback, and repeat it when the behavior is intermittent.

- If `BMSR`, `PHYSTS`, `ISR`, `STS1`, and `MSE` show failed negotiation before
  `R` can increase, investigate the cable, RJ45 contacts, switch port, and
  other copper-path components.
- If the copper link becomes active but `PCS` and LED 2 do not, investigate
  the SGMII connection and PCS configuration.
- If both the copper link and PCS are active but the expected traffic is
  absent from `R`, investigate the host interface, addressing, firewall,
  switch path, and offered traffic.

This procedure narrows the likely fault domain; the UART values alone cannot
distinguish, for example, a defective cable from an intermittent plug-to-jack
contact.

Stable register values help distinguish copper-link, SGMII, and host-network
problems.

| UART or LED observation | Likely area | Action |
|---|---|---|
| No UART text | Programming, USB-UART, clock, or reset | Confirm that the bitstream is loaded, select the correct serial port, use 9600 8-N-1, and verify that `cpu_reset` is released. |
| PHY registers remain `0xFFFF` | MDIO is undriven or the PHY is not responding | Check PHY power and reset, PHY address `00011`, MDC, the bidirectional MDIO pin, and its pull-up. Probe MDC and MDIO if LED 6 is on. |
| PHY registers remain `0x0000` | PHY is held in reset, unpowered, or MDIO is stuck low | Check `phy1_reset_b`, the power-down pin, PHY supplies, and MDIO for a short to ground. |
| LED 0 stays off or LED 6 turns on | PHY initialization did not complete | Reprogram the FPGA, ensure reset is stable, then verify the MDIO reset, extended-register writes, and software restart sequence before debugging UDP. |
| `PHYCR`, `CFG1`, or `CFG4` differs from its configured value | Configuration was not applied or was overwritten | Check the MDIO transaction sequence and reset history. Confirm `PHYCR=0x5848`, `CFG1=0x0300`, and `CFG4=0x1030`. |
| `ANA_LD=0x000F` | Copper MDI transmitters are disabled | Check the PHY strap state and indirect extended-register access. Confirm that initialization completes and the value returns to `0x0200`. |
| `BMSR` link bit is clear and `PHYSTS` does not show link | Copper auto-negotiation or cabling | Try a known-good cable and 1-Gb/s switch port, allow negotiation to restart, and compare `ANAR` with `ANLPAR`. |
| Link repeatedly changes between 1 Gb/s, 100 Mb/s, and down; an applicable `MSE` value repeatedly exceeds `0x033B`; or `ISR` includes auto-negotiation error bit `0x8000` during failed 1-Gb/s attempts | UTP cable, intermittent RJ45 contact, or another part of the copper path | Replace the UTP cable with a known-good Cat 5e or better cable first. Unplug and firmly reseat both RJ45 plugs, confirm that their latches hold, and inspect the plug and jack contacts. If the problem remains, try another switch port and inspect the other copper-side components. |
| Copper link is up, but `PCS` bit 0 and LED 2 stay low | SGMII-over-LVDS path | Verify the 625-MHz clock, SGMII RX/TX pin assignments, `PHYCR` SGMII enable, PCS reset, and any Vivado bitslice or location warnings. |
| LEDs 0, 1, and 2 are on and LED 3 toggles, but no datagram is received | Host capture or network configuration | Capture on the correct interface, verify host address `1.2.3.4/24` and UDP port 5678, and check the host firewall. |
| ARP lookup or ping fails | Expected transmit-only behavior | Do not change PHY or PCS settings. The design never responds to ARP or ICMP; use the LEDs and UART report instead. |
| LEDs 0, 1, and 2 are on, but LED 3 does not toggle | PCS client clock or transmit control | Check `clk125_out`, `sgmii_clk_en`, client reset, and the `PCS` speed bits before inspecting the UDP generator. |
| `R` increases by less than `send_udp.py --count` | Host, switch, or link loss | Verify the selected interface and broadcast address, capture the traffic at the sender, and remember that UDP does not guarantee delivery. |
| `F` increases | A complete frame reached GMII without `RX_ER`, but its Ethernet FCS was invalid | Compare `F`, `E`, and `RECR`. If only `F` changes, inspect SGMII/GMII sampling and the sender as well as the cable; if the physical-error indicators also change, try a known-good cable and switch port first. |
| LED 5 is on and `RECR` increases | Copper-side receive errors | Try a known-good cable and switch port, then compare `RECR` before and after controlled traffic. |
| LED 5 is on but `RECR` remains unchanged | SGMII/PCS receive error | Reset or reprogram to clear LED 5, then probe `gmii_rx_er`, `gmii_rx_dv`, `gmii_rxd`, and `PCS[6:4]`. Normal carrier extension is filtered; check SGMII signal integrity and the 625-MHz reference clock if another error pattern repeats. |

### Bad UTP cable or intermittent RJ45 contact

An updated capture made with the same known-bad UTP cable used for the earlier
test repeatedly followed this shortened sequence:

```text
Down/training:      PCS=0x220B PHYSTS=0x0002 BMSR=0x7949 ISR=0x0040 MSE(A=0x0030 B=0x7FFF C=0x7FFF D=0x7FFF)
AN page received:   PCS=0x220B PHYSTS=0x0002 BMSR=0x7949 ISR=0x1000 ANLPAR=0xC1E1
1-Gb/s attempt:     PCS=0x3A0B PHYSTS=0xA002 BMSR=0x7949 ISR=0x1000 MSE(A=0x0116 B=0x00CE C=0x029F D=0x03CF)
Attempt fails:      PCS=0x220B PHYSTS=0x0002 BMSR=0x7949 ISR=0x8040 MSE(A=0x002A B=0x7FFF C=0x7FFF D=0x7FFF)
Another 1-Gb/s try: PCS=0x3A0B PHYSTS=0xA302 BMSR=0x7949 ISR=0x0000 MSE(A=0x0186 B=0x00F9 C=0x033E D=0x0151)
Attempt fails:      PCS=0x220B PHYSTS=0x0302 BMSR=0x7949 ISR=0x8000 MSE(A=0x000A B=0x7FFF C=0x7FFF D=0x7FFF)
100-Mb/s link:      PCS=0x348B PHYSTS=0x6C02 BMSR=0x796D ISR=0x1C00 MSE(A=0x0024 B=0x7FFF C=0x7FFF D=0x7FFF)
Stable 100 Mb/s:    PCS=0x348B PHYSTS=0x6C02 BMSR=0x796D ISR=0x0000 R=0x000E
```

This capture predates the `F` counter, so it contains no receive-FCS result.
With the current design, record `F` along with `R`, `E`, and `RECR` when
repeating the experiment.

The relevant accumulated `ISR` values decode as follows:

| Value | Events observed since the preceding UART line |
|---|---|
| `0x0002` | Polarity changed |
| `0x0040` | MDI crossover changed |
| `0x0042` | MDI crossover and polarity changed |
| `0x0080` | Reserved bit 7 was observed; the DP83867 datasheet defines no event for this bit |
| `0x0100` | False carrier |
| `0x0104` | False carrier and xGMII error |
| `0x0400` | Link status changed |
| `0x0440` | Link status and MDI crossover changed |
| `0x0500` | Link status changed and false carrier |
| `0x0504` | Link status changed, false carrier, and xGMII error |
| `0x0800` | Auto-negotiation completed |
| `0x0C00` | Auto-negotiation completed and link status changed |
| `0x0D04` | Auto-negotiation completed, link status changed, false carrier, and xGMII error |
| `0x1000` | An auto-negotiation page was received |
| `0x1002` | An auto-negotiation page was received and polarity changed |
| `0x1040` | An auto-negotiation page was received and MDI crossover changed |
| `0x1042` | An auto-negotiation page was received, and MDI crossover and polarity changed |
| `0x1800` | A page was received and auto-negotiation completed |
| `0x1C00` | Page received, auto-negotiation completed, and link status changed |
| `0x4C00` | Speed changed, auto-negotiation completed, and link status changed |
| `0x5C00` | Speed changed, a page was received, auto-negotiation completed, and link status changed |
| `0x8000` | Auto-negotiation error |
| `0x8040` | Auto-negotiation error and MDI crossover change |
| `0x8042` | Auto-negotiation error, MDI crossover change, and polarity change |

During each 1-Gb/s attempt, all four MSE channels were applicable.
`MSE(D)=0x03CF` and, on a later attempt, `MSE(C)=0x033E` exceeded the poor-link
threshold of `0x033B`. The link-status bit in `BMSR=0x7949` remained clear,
and the attempts ended with the auto-negotiation error bit in `ISR=0x8040` or
`ISR=0x8000`. The PHY eventually completed auto-negotiation at 100 Mb/s,
reported `ISR=0x1C00`, and then received frames as `R` increased.

The recurring `0x7FFF` values on channels B through D occurred while the link
was down, training, or operating at 100 Mb/s. Those channels are inapplicable
at 100 Mb/s, so `0x7FFF` alone is not evidence of a bad cable.

In this example, `E` and `RECR` remained zero even though the cable was bad;
the PHY was failing during negotiation rather than reporting received-frame
errors. An auto-negotiation error bit confirms that negotiation failed, but
does not identify whether the physical cause is the cable, an intermittent
connector, the link partner, or another copper-path component. If a UART log
shows the same repeated 1-Gb/s attempts, `ISR` auto-negotiation errors, link
loss, and excessive applicable MSE values, replace the UTP cable and reseat
the RJ45 connections before changing the VHDL, PHY configuration, or SGMII
constraints.

#### Complementary capture with the FCS counter

A later capture from the same bad-link test was not a duplicate of the
preceding capture, although it followed the same overall pattern. Its most
informative lines can be shortened as follows:

```text
1-Gb/s attempt: C FRAME(R=0x0000 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xA802 BMSR=0x7969 STS1=0x2800 ISR=0x1800
False carrier:  C FRAME(R=0x0000 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xA802 BMSR=0x7969 STS1=0x2800 ISR=0x0100
Idle errors:    C FRAME(R=0x0000 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xA802 BMSR=0x7969 STS1=0x08FF RECR=0x0000 ISR=0x0104 MSE(A=0x003F B=0x0033 C=0x003F D=0x0013)
Attempt fails: C FRAME(R=0x0000 F=0x0000 E=0x0000) PCS=0x220B PHYSTS=0x0002 BMSR=0x7949
100-Mb/s link: C FRAME(R=0x0000 F=0x0000 E=0x0000) PCS=0x348B PHYSTS=0x6C02 BMSR=0x796D ISR=0x1C00
Valid receive: C FRAME(R=0x0005 F=0x0000 E=0x0000) PCS=0x348B PHYSTS=0x6C02 BMSR=0x796D RECR=0x0000 ISR=0x0000
```

`STS1=0x08FF` reports `0xFF` (255) in the 8-bit 1000BASE-T idle-error
counter, while both the local- and remote-receiver-status bits are clear.
At the same time, `ISR=0x0104` records false-carrier and xGMII-error events.
The next report shows that the 1-Gb/s attempt has dropped. This is direct
evidence of a failure during 1000BASE-T reception or training, before useful
Ethernet frames reach the FPGA.

Unlike the preceding capture, the applicable MSE values during this attempt
are below the excellent-link threshold of `0x020A`. An instantaneous set of
low MSE samples therefore does not, by itself, prove that link establishment
is stable. Interpret MSE together with `STS1`, `ISR`, `BMSR`, and repeated
link behavior.

`F=0` does not clear the cable or connector in this capture. While 1-Gb/s
establishment is failing, `R` is also zero, so there are no completed received
frames for the FCS checker to classify. After the PHY falls back to a stable
100-Mb/s link, `R` reaches five while `F` remains zero; those five frames
reached GMII with valid FCS values. `E=0` and `RECR=0` likewise show that the
observed failure was not counted as a completed GMII receive-error interval or
as a copper-side receiver error.

The `S` counter continued to increase while the link was down. `S` confirms
that the FPGA completed frames on its transmit interface; it does not confirm
that those frames were delivered through the cable.

#### Paced traffic through the bad cable

Another test ran `send_udp.py` with `--interval 0.1`, limiting the offered
traffic to approximately ten datagrams per second. The relevant progression
was:

```text
Stable 100 Mb/s: R=0x02AD -> R=0x0301, F=0x0000 E=0x0000 RECR=0x0000
Link drops:      R=0x0301 PCS=0x220B PHYSTS=0x0002 BMSR=0x7949 ISR=0x0440
1-Gb/s attempt: R=0x0301 PCS=0x3A0B PHYSTS=0xA302 BMSR=0x7949 MSE(A=0x01ED B=0x0D4D C=0x1E03 D=0x0B92)
Attempt fails:  R=0x0301 PCS=0x220B PHYSTS=0x0002 BMSR=0x7949 ISR=0x8040
Another attempt: R=0x0301 PCS=0x3A0B PHYSTS=0xA002 BMSR=0x7949 MSE(A=0x013E B=0x0103 C=0x09D8 D=0x188F)
Attempt fails:  R=0x0301 PCS=0x220B PHYSTS=0x0302 BMSR=0x7949 ISR=0x8040
Worst attempt:  R=0x0301 PCS=0x3A0B PHYSTS=0xA302 BMSR=0x7949 ISR=0x0080 MSE(A=0x002C B=0x382C C=0x3392 D=0x2732)
100 Mb/s returns: R=0x0301 PCS=0x348B PHYSTS=0x6C02 BMSR=0x796D ISR=0x1C00
Receive resumes:   R=0x0308 -> R=0x034C, F=0x0000 E=0x0000 RECR=0x0000
```

At 9600 baud, each 274-byte UART report and its inter-line pause take about
0.286 seconds. During the initial stable interval, `R` increased by 84 over
about 8.2 seconds, closely matching the expected 10-datagram/s rate after
allowing for unrelated background frames. `R` then remained fixed at
`0x0301` for roughly 12 seconds while the link was down or repeatedly trying
1 Gb/s, and resumed only after the 100-Mb/s link returned. Because `F`, `E`,
and `RECR` stayed zero, the missing test traffic did not arrive as completed
bad-FCS or receive-error frames; it was lost before reaching the FPGA's GMII
receive interface. Reproducing the failure at this low rate also rules out
burst transmission as its cause.

The maximum finite MSE values observed during the failed 1-Gb/s attempts were:

| Channel | Maximum observed MSE |
|---|---:|
| A | `0x01F0` |
| B | `0x382C` |
| C | `0x3392` |
| D | `0x2732` |

Channel A remained below the excellent threshold of `0x020A`, while channels
C and D were repeatedly far above the poor threshold of `0x033B`; channel B
was also extremely poor during two attempts. These are training samples rather
than measurements from a stable linked state, so their exact quality classes
are not a link signoff. Their repeated, pair-specific pattern nevertheless
strongly points to intermittent or defective copper-pair or connector paths
needed for 1000BASE-T. That diagnosis is consistent with the same cable
operating at 100 Mb/s but failing when all four pairs are required.

The two reports containing `ISR=0x0080` coincide with the worst 1-Gb/s
attempt. Bit 7 of DP83867 register `0x0013` is documented as reserved, so the
value must not be given a defined event meaning. If it matters during further
debugging, compare raw MDIO reads with a known-good cable and the exact PHY
silicon revision.

After recovery, some `R` increments were greater than the approximately two
or three paced datagrams expected per UART line. `R` counts every received
Ethernet frame, so background traffic or frames released after link recovery
can account for the difference. Use a simultaneous host packet capture, and
prefer sequence-numbered payloads, when an exact delivery ratio is required.

#### Repeatable restart and speed-fallback test

A later test held the same bad cable in a condition where 1000BASE-T could not
establish a stable link. The Center and North buttons were alternated only to
restart the PHY and mark the restart boundaries in the UART log; this capture
is not a comparison of those two profiles.

Four complete post-restart sequences produced nearly identical timing:

| Restart marker | First post-restart line | First 100-Mb/s linked line | Visible 1-Gb/s attempts | Approximate time to 100 Mb/s |
|---|---:|---:|---:|---:|
| `N` | 79 | 119 | 3 | 11.4 seconds |
| `C` | 161 | 201 | 3 | 11.4 seconds |
| `N` | 247 | 287 | 3 | 11.4 seconds |
| `C` | 319 | 358 | 3 | 11.2 seconds |

The time is estimated from the approximately 0.286-second UART reporting
period and begins at the first visible line after each restart. Initialization
occurs before that line and is not included.

During every visible 1-Gb/s attempt, `PCS` progressed through `0x3A0B` or
`0x388B`, but the copper link never became active: `BMSR` remained `0x7949` or
`0x7969`, the link-status bit in `PHYSTS` remained clear, and `R` stayed zero.
The attempts produced auto-negotiation errors such as `ISR=0x8000`,
`ISR=0x8040`, or `ISR=0x8042`. Some attempts also ended with
`STS1=0x08FF`, false-carrier or xGMII events, and loss of the local and remote
1000BASE-T receiver-status indications.

The largest finite MSE values from the four complete restart sequences were:

| Restart marker | MSE A | MSE B | MSE C | MSE D |
|---|---:|---:|---:|---:|
| `N` | `0x01A0` | `0x021F` | `0x01E1` | `0x2ABF` |
| `C` | `0x009C` | `0x0097` | `0x0098` | `0x347D` |
| `N` | `0x0351` | `0x012D` | `0x1B13` | `0x03DC` |
| `C` | `0x009A` | `0x0097` | `0x00CC` | `0x1657` |

These measurements were taken during failed training attempts rather than
from a stable linked state, so their exact quality classes are not link
signoff results. Their repeated channel asymmetry is nevertheless useful:
channel D exceeded `0x033B` in every complete sequence, channel C was also
extremely poor during one sequence, while A and B were usually much lower.
Together with reliable 100-Mb/s operation after fallback, this strongly points
to an impaired cable, plug, jack, or other copper path needed when all four
1000BASE-T channels are active.

After speed fallback, each sequence settled at `PCS=0x348B`,
`BMSR=0x796D`, and `PHYSTS=0x6C02` or `0x6F02`; `R` then increased while
`F`, `E`, and `RECR` remained zero. The difference between `PHYSTS=0x6C02`
and `0x6F02` is the Auto-MDIX resolution for the A/B and C/D pair groups, not
a difference in the negotiated 100-Mb/s full-duplex link state.

Polarity-change events also appeared as `ISR=0x0002` and in the combined
values `0x1002`, `0x1042`, and `0x8042`. Polarity and MDI/MDIX resolution can
change while a restarted PHY is training, so these events are supporting
observations rather than independent proof of a wiring fault.

The repeatable delay and fallback show that speed optimization is operating
predictably despite the defective path. The absence of `F`, `E`, and `RECR`
errors does not clear the cable: the 1-Gb/s failures occur before completed
Ethernet frames reach the FPGA, and reception is clean after the PHY selects
100 Mb/s.

#### Cable-movement test at 1 Gb/s

In another test, the known-bad cable was intentionally moved and shaken while
the UART report was being recorded. Unlike the preceding captures, this test
began with an operating 1-Gb/s link and then showed rapid link flapping:

```text
Initially linked: C FRAME(R=0x3B23 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xAF02 BMSR=0x796D STS1=0x3800 RECR=0x0000 ISR=0x0000
Movement event:   C FRAME(R=0x3B25 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xAB02 BMSR=0x7969 STS1=0x2800 RECR=0x0000 ISR=0x0504
Linked again:     C FRAME(R=0x3B29 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xAF02 BMSR=0x796D STS1=0x3800 RECR=0x0000 ISR=0x0400
Idle errors:      C FRAME(R=0x3B38 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xAB02 BMSR=0x7969 STS1=0x08FF RECR=0x0000 ISR=0x0100
Fully down:       C FRAME(R=0x3B38 F=0x0000 E=0x0000) PCS=0x220B PHYSTS=0x0002 BMSR=0x7949 STS1=0x0000 RECR=0x0000 ISR=0x0040
1-Gb/s returns:   C FRAME(R=0x3B3C F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xAC02 BMSR=0x796D STS1=0x3800 RECR=0x0000 ISR=0x0504
Later traffic:    C FRAME(R=0x3B93 F=0x0000 E=0x0000) PCS=0x388B PHYSTS=0xAC02 BMSR=0x796D STS1=0x3800 RECR=0x0000 ISR=0x0400
```

The direct correlation between mechanical movement and link-state changes is
strong evidence of an intermittent physical connection. It does not, by
itself, identify whether the defect is inside the cable, at either RJ45 plug,
between a plug and jack, in a jack, or in another mechanically disturbed
copper-path connection. Repeat the movement separately near each plug and
along the cable, then substitute a known-good cable, to narrow the location
without changing the FPGA design.

This capture also identifies the first receiver-status change. `STS1=0x3800`
reports both the local and remote 1000BASE-T receivers as OK. During the first
link loss, `STS1=0x2800` still reports the local receiver as OK but reports the
remote receiver as not OK. This suggests that the link partner first lost the
signal transmitted from the board-side PHY. Later `STS1=0x08FF` and
`STS1=0x48FF` report neither receiver as OK and contain `0xFF` in the
1000BASE-T idle-error counter.

`ISR=0x0504` occurred repeatedly and records a link-status change, false
carrier, and xGMII error. `ISR=0x0D04` adds an auto-negotiation-complete event.
No auto-negotiation-error bit `0x8000` appeared: 1-Gb/s negotiation could
complete, but mechanical disturbance made the established link unstable.

All four MSE values nevertheless remained in the excellent range. Their
maximum values were `A=0x010E`, `B=0x019B`, `C=0x01B2`, and `D=0x0199`, all
below `0x020A`. Periodic MSE samples can therefore miss a brief contact
interruption; low MSE must not override observed link flapping, receiver-status
failures, or mechanically repeatable behavior.

Across the capture, `R` increased by 112 while `F`, `E`, and `RECR` remained
zero. Frames that reached GMII were intact, while traffic sent during complete
link-down intervals did not reach the FPGA. Brief changes can occur between
the sequential PHY-register polls and UART snapshots, so an `R` increment on
a line whose current `BMSR` link bit is clear is not necessarily a counter
error.

The same UART pattern can occur when the electrical contact between an RJ45
plug and jack is intermittent, even if the UTP cable itself is undamaged.
The UART report cannot distinguish these two causes because either one can
disrupt one or more copper pairs. Unplug and firmly reseat both ends, check
that each latch holds the plug securely, and try a known-good cable. If moving
or lightly touching a connector changes the link behavior, inspect that plug,
jack, and its board connection before changing the FPGA design.

After taking corrective action, reset or reprogram the board and compare a new
UART report with the previous one. Change one subsystem at a time so a new PCS,
PHY, or host configuration does not hide the original fault.

## Simulation

`create_project.tcl` adds these VHDL-2008 simulation sources to the Vivado
`sim_1` fileset:

| Simulation top | Purpose | Expected note |
|---|---|---|
| `tb_udp_to_gmii` | Two complete GMII frames, IPv4/UDP checksums, padding, Ethernet FCS, payload latching, and 100-Mb/s-style client clock enable | `Two deterministic UDP-to-GMII frames verified` |
| `tb_udp_to_gmii_no_padding` | Continuous 1-Gb/s-style enable, an exactly minimum-size unpadded frame, and reset during transmission | `Continuous-enable, no-padding, and reset behavior verified` |
| `tb_ethernet_statistics` | Sent, FCS-good, FCS-bad, and errored receive frames; clock-enable handling; carrier-extension filtering; inactive clients; and rollover behavior | `Ethernet statistics and receive FCS checking verified` |
| `tb_phy_profile_buttons` | Pushbutton synchronization, debounce, profile selection, repeated selection, disabled input, and simultaneous-press rejection | `PHY profile pushbutton synchronization and debounce verified` |
| `tb_dp83867_sgmii_init` | All five DP83867 profiles, reset isolation between profiles, link polling, and diagnostic-register polling | `DP83867 profile reinitialization verified` |
| `tb_mdio_master` | Clause-22 read/write transactions and response backpressure | `MDIO master read, write, and backpressure verified` |
| `tb_uart_status` | UART bit timing, the complete fixed status format, and coherent line snapshots | `UART byte timing, fixed line format, and snapshot verified` |

`source/mdio_slave_bfm.vhd` implements the generic Clause-22 wire protocol.
`source/mdio_slave.vhd` adds the DP83867 register behavior used by the PHY and
MDIO-master tests. Simulation-only sources are excluded from synthesis and
implementation. The default simulation top is `tb_udp_to_gmii`.

### Vivado GUI

1. Open `build_kcu116/kcu116_ethernet_demo.xpr` or
   `build_vcu118/vcu118_ethernet_demo.xpr`.
2. Under **Simulation Sources**, right-click the desired testbench and select
   **Set as Top**.
3. Select **Flow Navigator > Simulation > Run Behavioral Simulation**.
4. Select **Run All**. Every testbench stops after its checks pass and contains
   a watchdog that fails a stalled simulation.

### Vivado Tcl console

Run all testbenches:

```tcl
foreach simulation_top {
    tb_udp_to_gmii
    tb_udp_to_gmii_no_padding
    tb_ethernet_statistics
    tb_phy_profile_buttons
    tb_dp83867_sgmii_init
    tb_mdio_master
    tb_uart_status
} {
    set_property top $simulation_top [get_filesets sim_1]
    launch_simulation -simset sim_1 -mode behavioral
    run all
    close_sim
}
```

The DP83867 test additionally reports:

```text
DP83867 Center profile verified
DP83867 North profile verified
DP83867 East profile verified
DP83867 South profile verified
DP83867 West profile verified
DP83867 profile reinitialization verified
DP83867 double-read link polling verified
DP83867 PHYSTS register polling verified
DP83867 PHYCR register polling verified
DP83867 CFG1 register polling verified
DP83867 RECR register polling verified
DP83867 clear-on-read ISR accumulation verified
DP83867 MSE register polling verified
DP83867 diagnostic-register polling verified
```

## Design notes

- The fixed board 125-MHz clock runs MDIO so the PHY can be configured before
  its 625-MHz SGMII clock exists.
- Initialization writes `PHYCR=0x5848` to clear force-link-good while retaining
  SGMII and Auto-MDIX.
- Initialization writes `CFG1=0x0300` to select automatic 1000BASE-T
  leader/follower resolution before restarting auto-negotiation.
- A profile request resets the PHY before applying profile-specific writes and
  then the shared SGMII sequence, preventing hidden registers from retaining
  the preceding profile.
- Directional pushbuttons are synchronized into the 125-MHz board-clock domain,
  debounced for 10 ms, and ignored while PHY initialization is active.
- The PCS is held in reset until the MDIO sequence enables six-wire SGMII.
- Client logic is clocked by `clk125_out` from the PCS, not the unrelated board
  oscillator.
- `status_vector(11 downto 10)` controls PCS rate adaptation.
- `sgmii_clk_en` advances the GMII transmitter at the negotiated byte rate.
- `ethernet_statistics` filters the normal carrier-extension indication
  (`RX_DV=0`, `RX_ER=1`, `RXD=0x0F`) before counting errors or driving the
  sticky error LED event.
- `ethernet_statistics` checks the received Ethernet CRC-32 only on enabled
  client byte cycles. `F` counts FCS failures that were not already reported
  through `RX_ER`.
- The 16-bit Ethernet statistics use modulo arithmetic and cross into the UART
  clock domain in Gray code.
- The multi-bit PCS status uses a request/acknowledge snapshot handshake so one
  UART line cannot contain a mixture of two PCS status updates.
- The UART formatter snapshots all fields once per line and streams individual
  bytes to the transmitter instead of latching a 274-byte vector.
- The UDP transmitter stores one accepted payload snapshot and addresses it by
  byte or word index for checksum and serialization.
- The generated PCS/PMA core is isolated behind `pcs_pma_wrapper`, keeping its
  vendor-specific port list out of the application top level.
- `signal_detect` is tied high because the on-board LVDS connection has no
  separate loss-of-signal input.
- `status_vector(0)` gates frame transmission until SGMII auto-negotiation is
  complete.
- The receive GMII interface is monitored for activity and errors, but received
  frames are not parsed or answered.

## References

- AMD PG047, *1G/2.5G Ethernet PCS/PMA or SGMII LogiCORE IP Product Guide*:
  <https://docs.amd.com/r/en-US/pg047-gig-eth-pcs-pma>
- AMD UG1239, *KCU116 Board User Guide*:
  <https://docs.amd.com/v/u/en-US/ug1239-kcu116-eval-bd>
- AMD UG1224, *VCU118 Evaluation Board User Guide*:
  <https://docs.amd.com/v/u/en-US/ug1224-vcu118-eval-bd>
- AMD RDF0400, *VCU118 Master XDC* (in the XTP450 board archive):
  <https://docs.amd.com/v/u/en-US/VCU118-Schematics-XTP450>
- TI DP83867 datasheet:
  <https://www.ti.com/lit/ds/symlink/dp83867cr.pdf>
- TI SNLA246, *DP83867 Troubleshooting Guide*:
  <https://www.ti.com/lit/an/snla246d/snla246d.pdf>
- AMD Answer Record 69494, KCU116/VCU118 DP83867 SGMII bring-up
