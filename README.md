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

From the repository root:

```sh
vivado -mode batch -source create_project.tcl
```

The resulting programming file is:

```text
build/kcu116_ethernet_demo/kcu116_ethernet_demo.runs/impl_1/kcu116_ethernet_demo.bit
```

After the command-line build completes successfully, the newly created Vivado
project can be opened in the Vivado GUI. From the repository root, open:

```text
build/kcu116_ethernet_demo.xpr
```

The Tcl script creates a new project and regenerates the PCS/PMA IP. Generated
IP files are intentionally not stored here.

## Run

1. Connect the KCU116 RJ45 port to a host or switch.
2. Program the generated bitstream.
3. Assign the receiving host an address in `1.2.3.0/24`, for example
   `1.2.3.4`. Subnet mask should be `255.255.255.0`. No gateway is required.
4. Start the console UDP receiver.

   On Windows:

   ```powershell
   py recv_udp.py
   ```

   If the Python launcher is not installed, use
   `python recv_udp.py`.

   On Linux:

   ```sh
   python3 recv_udp.py
   ```

   The receiver uses only the Python standard library, binds all IPv4
   interfaces on UDP port 5678, and runs until Ctrl+C is pressed. Each packet
   is printed as text and hexadecimal bytes:

   ```text
   Receiving UDP packets on 0.0.0.0:5678 (press Ctrl+C to stop)
   [2026-07-25T12:34:56+09:00] 1.2.3.116:1234 - 26 bytes
     text: 'Hello world! --from KCU116'
     hex : 48 65 6C 6C 6F 20 77 6F 72 6C 64 21 20 2D 2D 66 72 6F 6D 20 4B 43 55 31 31 36
   ```

   Use `--bind ADDRESS` or `--port PORT` to override the defaults:

   ```sh
   python3 recv_udp.py --bind 1.2.3.4 --port 5678
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

> **Important:** This demonstration is transmit-only and does not implement an
> ARP or ICMP responder. The board will not answer ARP requests or ping, even
> when its copper and SGMII links are working correctly. The source address
> `1.2.3.116` identifies transmitted packets; it does not provide a complete
> network stack at that address. Do not use ARP or ping to check board status,
> because those checks will always fail by design. Use the LEDs and/or the UART
> status report instead.

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
PCS_STATUS=0xXXXX PHY_STATUS=0xXXXX PHYCR=0xXXXX CFG1=0xXXXX BMCR=0xXXXX BMSR=0xXXXX ANAR=0xXXXX ANLPAR=0xXXXX ANER=0xXXXX STS1=0xXXXX RECR=0xXXXX CFG4=0xXXXX STRAP_STS2=0xXXXX ANA_LD_DATA_CTRL=0xXXXX
```

A typical report after successful 1-Gb/s Auto-Negotiation is:

```text
PCS_STATUS=0x388B PHY_STATUS=0xAC02 PHYCR=0x5848 CFG1=0x0300 BMCR=0x1140 BMSR=0x796D ANAR=0x01E1 ANLPAR=0xC1E1 ANER=0x006D STS1=0x7800 RECR=0x0000 CFG4=0x1030 STRAP_STS2=0x0150 ANA_LD_DATA_CTRL=0x0200
```

`PCS_STATUS` is the 16-bit status vector from the PCS/PMA IP.
`PHY_STATUS` is the DP83867 Clause-22 `PHYSTS` register at address `0x11`,
polled over MDIO after the double read of BMSR. For example, `0xAC02` is a
typical value after a 1-Gb/s full-duplex copper link is established. `PHYCR`
is Clause-22 register `0x10`; its force-link-good bit 10 should be clear and
SGMII-enable bit 11 should be set. `CFG1` is Clause-22 register `0x09`; a
normal automatic leader/follower 1000BASE-T advertisement commonly reads
`0x0300`.
`BMCR`, `BMSR`, `ANAR`, `ANLPAR`, `ANER`, and `STS1` expose the copper
Auto-Negotiation progress. `RECR` is the Clause-22 receiver error counter at
address `0x15`; it saturates at `0xFFFF`, and an MDIO write clears it. The
normal polling read does not clear the counter. `CFG4` and `STRAP_STS2` verify
the KCU116 RX_CTRL strap workaround. Extended register `ANA_LD_DATA_CTRL` at
`0x00DD` normally reads `0x0200`; `0x000F` indicates that the MDI transmitters
are disabled.

## Troubleshooting

If the system reports that `vivado` cannot be found or is not recognized,
initialize the Vivado command environment before running the build. Locate the
appropriate setup script under the Vivado installation directory and run it in
the same terminal.

On Windows Command Prompt:

```bat
call C:\path\to\Vivado\2026.1\settings64.bat
vivado -mode batch -source create_project.tcl
```

On Linux:

```sh
source /path/to/Vivado/2026.1/settings64.sh
vivado -mode batch -source create_project.tcl
```

The installation path and version may differ. Use the `settings64.bat` or
`settings64.sh` supplied with the installed Vivado version.

Check the UART status report before changing the PCS/PMA configuration, pin
constraints, or network software. Open the KCU116 USB-UART port at 9600 baud,
8-N-1, wait for PHY initialization to finish, and save several complete status
lines. Stable register values make it possible to distinguish a copper-link
problem from an SGMII or host-network problem.

For the reference 1-Gb/s setup, the important values are:

| Field | Healthy indication |
|---|---|
| `PCS_STATUS` | Typically `0x388B`; bit 0 set and bits 11:10 are `10` |
| `PHY_STATUS` | Typically `0xAC02` for a 1-Gb/s full-duplex link |
| `PHYCR` | `0x5848` |
| `CFG1` | `0x0300` |
| `BMCR` | Typically `0x1140` after the restart bit from `0x1340` self-clears |
| `BMSR` | Typically `0x796D`; bit 2 set after the controller's double read |
| `ANAR` | Typically `0x01E1` |
| `ANLPAR` | Typically `0xC1E1`, depending on the link partner |
| `ANER` | Typically `0x006D`, depending on the link partner |
| `STS1` | Typically `0x7800` |
| `RECR` | Normally `0x0000`; a rising value indicates receive errors detected by the PHY |
| `CFG4` | `0x1030` |
| `STRAP_STS2` | Typically `0x0150` on the reference board |
| `ANA_LD_DATA_CTRL` | `0x0200` |

`ANLPAR`, `ANER`, and some status bits depend on the connected link partner, so
do not reject a link merely because their complete hexadecimal values differ
from a previous run. Interpret them together with `BMSR`, `PHY_STATUS`, and
the PCS status.

Use the observed failure pattern to choose the next action:

| UART or LED observation | Likely area | Action |
|---|---|---|
| No UART text | Programming, USB-UART, clock, or reset | Confirm that the bitstream is loaded, select the correct serial port, use 9600 8-N-1, and verify that `cpu_reset` is released. |
| PHY registers remain `0xFFFF` | MDIO is undriven or the PHY is not responding | Check PHY power and reset, PHY address `00011`, MDC, the bidirectional MDIO pin, and its pull-up. Probe MDC/MDIO if LED 6 is on. |
| PHY registers remain `0x0000` | PHY held in reset, unpowered, or MDIO stuck low | Check `phy1_reset_b`, the power-down pin, PHY supplies, and MDIO for a short to ground. |
| LED 0 stays off or LED 6 turns on | PHY initialization did not complete | Do not debug UDP yet. Reprogram the FPGA, ensure reset is stable, then verify the MDIO reset, extended-register writes, and software restart sequence. |
| `PHYCR`, `CFG1`, or `CFG4` differs from the configured value | Configuration was not applied or was overwritten | Check the MDIO transaction sequence and reset history. Confirm `PHYCR=0x5848`, `CFG1=0x0300`, and `CFG4=0x1030` before continuing. |
| `ANA_LD_DATA_CTRL=0x000F` | Copper MDI transmitters are disabled | Check the PHY strap state and the indirect extended-register access. Confirm that the initialization restart completes and the value returns to `0x0200`. |
| `BMSR` link bit is clear and `PHY_STATUS` does not show link | Copper Auto-Negotiation or cabling | Try a known-good cable and 1-Gb/s switch port, allow negotiation to restart, and compare `ANAR` with `ANLPAR`. |
| Copper link is up, but `PCS_STATUS` bit 0 and LED 2 stay low | SGMII-over-LVDS path | Verify the 625-MHz clock, SGMII RX/TX pin assignments, `PHYCR` SGMII enable, PCS reset, and any Vivado bitslice or LOC warnings. |
| LEDs 0, 1, and 2 are on and LED 3 toggles, but no packet is received | Host capture or network configuration | Capture on the correct interface, verify address `1.2.3.4/24` and UDP port 5678, and check the host firewall. |
| ARP lookup or ping fails | Expected transmit-only behavior | Do not change PHY or PCS settings based on this result. The design never responds to ARP or ICMP; check board status through the LEDs and/or UART. |
| LEDs 0, 1, and 2 are on, but LED 3 does not toggle | PCS client clock or transmit control | Check `clk125_out`, `sgmii_clk_en`, client reset, and `PCS_STATUS` speed bits before inspecting the UDP generator. |
| LED 5 is on and `RECR` increases | Copper-side receive errors | Try a known-good cable and switch port, then compare `RECR` before and after controlled traffic. |
| LED 5 is on but `RECR` remains unchanged | SGMII/PCS error or an earlier sticky event | Reset or reprogram to clear LED 5, then probe `gmii_rx_er`, `gmii_rx_dv`, and `PCS_STATUS[6:4]`; check SGMII signal integrity and the 625-MHz reference clock if the error repeats. |

After taking corrective action, reset or reprogram the board and compare a new
UART report with the previous one. Change one subsystem at a time; otherwise a
new PCS, PHY, and host configuration can hide the original fault.

## Vivado simulation

The project-generation script adds the following files to the Vivado `sim_1`
fileset as VHDL-2008 simulation-only sources:

- `source/tb_udp_to_gmii.vhd`
- `source/tb_dp83867_sgmii_init.vhd`
- `source/mdio_slave.vhd`, the PHY model used by the MDIO testbench

These files are available under **Simulation Sources** in the generated Vivado
project and are excluded from synthesis and implementation. The default
simulation top is `tb_udp_to_gmii`.

To run the UDP/GMII test in the Vivado GUI:

1. Open `build/kcu116_ethernet_demo.xpr`.
2. In **Sources**, select **Simulation Sources**.
3. Right-click `tb_udp_to_gmii` and select **Set as Top**.
4. Select **Flow Navigator > Simulation > Run Behavioral Simulation**.
5. In the simulator, select **Run All**. The testbench stops itself after
   completing its checks.

The Tcl console output should include:

```text
Latched UDP payload-to-GMII frame verified
```

This test verifies the complete GMII byte stream, IPv4 and UDP checksums,
Ethernet FCS, payload latching, and operation with the client clock enable
pulsed as it is at 100 Mb/s.

To run the PHY initialization and link-polling test, close the current
simulation, set `tb_dp83867_sgmii_init` as the simulation top, and run
Behavioral Simulation again. Select **Run All** so the simulation can progress
through the complete MDIO sequence.

Expected output includes:

```text
DP83867 configuration sequence verified
DP83867 double-read link polling verified
DP83867 PHYSTS register polling verified
DP83867 PHYCR register polling verified
DP83867 CFG1 register polling verified
DP83867 RECR register polling verified
DP83867 diagnostic-register polling verified
```

The simulation sources can also be selected and launched from the Vivado Tcl
console:

```tcl
set_property top tb_udp_to_gmii [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

set_property top tb_dp83867_sgmii_init [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
```

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
activity and errors, but received frames are not parsed or answered. In
particular, the design has no ARP or ICMP responder and therefore cannot be
discovered with ARP or tested with ping.

## References

- AMD PG047, *1G/2.5G Ethernet PCS/PMA or SGMII LogiCORE IP Product Guide*:
  <https://docs.amd.com/r/en-US/pg047-gig-eth-pcs-pma>
- TI DP83867 datasheet:
  <https://www.ti.com/lit/ds/symlink/dp83867e.pdf>
- AMD Answer Record 69494, KCU116/VCU118 DP83867 SGMII bring-up
