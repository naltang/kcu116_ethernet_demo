## VCU118 Rev 2.0+ fixed 125-MHz clock
set_property PACKAGE_PIN AY24 [get_ports clk_125_p]
set_property PACKAGE_PIN AY23 [get_ports clk_125_n]
set_property IOSTANDARD LVDS [get_ports {clk_125_p clk_125_n}]
create_clock -name board_clk125 -period 8.000 [get_ports clk_125_p]

## CPU_RESET push button, active high
set_property PACKAGE_PIN L19 [get_ports cpu_reset]
set_property IOSTANDARD LVCMOS12 [get_ports cpu_reset]

## FPGA transmit side of the VCU118 USB-UART bridge
set_property PACKAGE_PIN BB21 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS18 [get_ports uart_tx]

## On-board TI DP83867 management and control
set_property PACKAGE_PIN AR24 [get_ports phy1_pdwn_b_i_int_b_o]
set_property PACKAGE_PIN BA21 [get_ports phy1_reset_b]
set_property PACKAGE_PIN AV23 [get_ports phy1_mdc]
set_property PACKAGE_PIN AR23 [get_ports phy1_mdio]
set_property IOSTANDARD LVCMOS18 \
    [get_ports {phy1_pdwn_b_i_int_b_o phy1_reset_b phy1_mdc phy1_mdio}]
set_property PULLUP true [get_ports phy1_mdio]

## Six-wire SGMII-over-LVDS interface in bank 64.
## The top-level names use FPGA directions: IN is PHY-to-FPGA and OUT is
## FPGA-to-PHY. The VCU118 master-XDC net names use the PHY directions.
set_property PACKAGE_PIN AU24 [get_ports phy1_sgmii_in_p]
set_property PACKAGE_PIN AV24 [get_ports phy1_sgmii_in_n]
set_property PACKAGE_PIN AU21 [get_ports phy1_sgmii_out_p]
set_property PACKAGE_PIN AV21 [get_ports phy1_sgmii_out_n]
set_property PACKAGE_PIN AT22 [get_ports phy1_sgmii_clk_p]
set_property PACKAGE_PIN AU22 [get_ports phy1_sgmii_clk_n]
set_property IOSTANDARD LVDS [get_ports {
    phy1_sgmii_in_p phy1_sgmii_in_n
    phy1_sgmii_out_p phy1_sgmii_out_n
    phy1_sgmii_clk_p phy1_sgmii_clk_n
}]

## User LEDs
set_property PACKAGE_PIN AT32 [get_ports gpio_led_0]
set_property PACKAGE_PIN AV34 [get_ports gpio_led_1]
set_property PACKAGE_PIN AY30 [get_ports gpio_led_2]
set_property PACKAGE_PIN BB32 [get_ports gpio_led_3]
set_property PACKAGE_PIN BF32 [get_ports gpio_led_4]
set_property PACKAGE_PIN AU37 [get_ports gpio_led_5]
set_property PACKAGE_PIN AV36 [get_ports gpio_led_6]
set_property PACKAGE_PIN BA37 [get_ports gpio_led_7]
set_property IOSTANDARD LVCMOS12 [get_ports {
    gpio_led_0 gpio_led_1 gpio_led_2 gpio_led_3
    gpio_led_4 gpio_led_5 gpio_led_6 gpio_led_7
}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
