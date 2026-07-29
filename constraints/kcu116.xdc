## KCU116 fixed 125-MHz system clock
set_property PACKAGE_PIN G12 [get_ports clk_125_p]
set_property PACKAGE_PIN F12 [get_ports clk_125_n]
set_property IOSTANDARD LVDS_25 [get_ports {clk_125_p clk_125_n}]
create_clock -name board_clk125 -period 8.000 [get_ports clk_125_p]

## CPU_RESET push button, active high
set_property PACKAGE_PIN B9 [get_ports cpu_reset]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_reset]

## FPGA transmit side of the KCU116 USB-UART bridge
set_property PACKAGE_PIN W13 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS18 [get_ports uart_tx]

## On-board TI DP83867 management and control
set_property PACKAGE_PIN R25 [get_ports phy1_pdwn_b_i_int_b_o]
set_property PACKAGE_PIN AA23 [get_ports phy1_reset_b]
set_property PACKAGE_PIN U25 [get_ports phy1_mdc]
set_property PACKAGE_PIN P25 [get_ports phy1_mdio]
set_property IOSTANDARD LVCMOS18 \
    [get_ports {phy1_pdwn_b_i_int_b_o phy1_reset_b phy1_mdc phy1_mdio}]
set_property PULLUP true [get_ports phy1_mdio]

## Six-wire SGMII-over-LVDS interface in bank 65
set_property PACKAGE_PIN U26 [get_ports phy1_sgmii_in_p]
set_property PACKAGE_PIN V26 [get_ports phy1_sgmii_in_n]
set_property PACKAGE_PIN N24 [get_ports phy1_sgmii_out_p]
set_property PACKAGE_PIN P24 [get_ports phy1_sgmii_out_n]
set_property PACKAGE_PIN T24 [get_ports phy1_sgmii_clk_p]
set_property PACKAGE_PIN U24 [get_ports phy1_sgmii_clk_n]
set_property IOSTANDARD LVDS [get_ports {
    phy1_sgmii_in_p phy1_sgmii_in_n
    phy1_sgmii_out_p phy1_sgmii_out_n
    phy1_sgmii_clk_p phy1_sgmii_clk_n
}]

## User LEDs
set_property PACKAGE_PIN C9  [get_ports gpio_led_0]
set_property PACKAGE_PIN D9  [get_ports gpio_led_1]
set_property PACKAGE_PIN E10 [get_ports gpio_led_2]
set_property PACKAGE_PIN E11 [get_ports gpio_led_3]
set_property PACKAGE_PIN F9  [get_ports gpio_led_4]
set_property PACKAGE_PIN F10 [get_ports gpio_led_5]
set_property PACKAGE_PIN G9  [get_ports gpio_led_6]
set_property PACKAGE_PIN G10 [get_ports gpio_led_7]
set_property IOSTANDARD LVCMOS33 [get_ports {
    gpio_led_0 gpio_led_1 gpio_led_2 gpio_led_3
    gpio_led_4 gpio_led_5 gpio_led_6 gpio_led_7
}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
