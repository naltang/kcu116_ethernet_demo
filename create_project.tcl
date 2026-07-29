# Recreate and build the KCU116 VHDL SGMII/UDP demonstration.
#
# Run from any directory:
#   vivado -mode batch -source create_project.tcl
#
# The script creates build/kcu116_ethernet_demo, generates the licensed
# Gigabit Ethernet PCS/PMA IP, and builds a programming bitstream.

set script_dir [file normalize [file dirname [info script]]]
set source_dir [file normalize [file join $script_dir source]]
set build_dir  [file normalize [file join $script_dir build]]
set project_name kcu116_ethernet_demo
set part_name xcku5p-ffvb676-2-e

file mkdir $build_dir
create_project -force $project_name $build_dir -part $part_name
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

# The design uses explicit package pins, so a board-part installation is not
# required.  Set it when available to improve board-aware IP validation.
set kcu116_parts [get_board_parts -quiet xilinx.com:kcu116:part0:*]
if {[llength $kcu116_parts] > 0} {
    set_property board_part [lindex $kcu116_parts end] [current_project]
}

add_files -norecurse [list \
    [file join $source_dir mdio_master.vhd] \
    [file join $source_dir uart_tx_vector.vhd] \
    [file join $source_dir dp83867_sgmii_init.vhd] \
    [file join $source_dir udp_to_gmii.vhd] \
    [file join $source_dir ethernet_statistics.vhd] \
    [file join $source_dir kcu116_ethernet_demo.vhd]]
set_property file_type {VHDL 2008} [get_files *.vhd]

set simulation_files [list \
    [file join $source_dir mdio_slave.vhd] \
    [file join $source_dir tb_udp_to_gmii.vhd] \
    [file join $source_dir tb_ethernet_statistics.vhd] \
    [file join $source_dir tb_dp83867_sgmii_init.vhd]]
add_files -fileset sim_1 -norecurse $simulation_files
set simulation_sources [get_files -of_objects [get_filesets sim_1]]
set_property file_type {VHDL 2008} $simulation_sources
set_property used_in {simulation} $simulation_sources

add_files -fileset constrs_1 -norecurse \
    [file join $script_dir kcu116_ethernet_demo.xdc]

create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip \
    -module_name gig_ethernet_pcs_pma_0

set_property -dict [list \
    CONFIG.USE_BOARD_FLOW {false} \
    CONFIG.ETHERNET_BOARD_INTERFACE {sgmii_lvds} \
    CONFIG.DIFFCLK_BOARD_INTERFACE {Custom} \
    CONFIG.Standard {SGMII} \
    CONFIG.MaxDataRate {1G} \
    CONFIG.Physical_Interface {LVDS} \
    CONFIG.Management_Interface {false} \
    CONFIG.AXILite_Interface {false} \
    CONFIG.Ext_Management_Interface {false} \
    CONFIG.Auto_Negotiation {true} \
    CONFIG.SGMII_Mode {10_100_1000} \
    CONFIG.SGMII_PHY_Mode {false} \
    CONFIG.EMAC_IF_TEMAC {TEMAC} \
    CONFIG.SupportLevel {Include_Shared_Logic_in_Core} \
    CONFIG.LvdsRefClk {625} \
    CONFIG.EnableAsyncSGMII {false} \
    CONFIG.ClockSelection {Sync} \
    CONFIG.Tx_In_Upper_Nibble {0} \
    CONFIG.TxLane0_Placement {DIFF_PAIR_2} \
    CONFIG.RxLane0_Placement {DIFF_PAIR_0} \
] [get_ips gig_ethernet_pcs_pma_0]

generate_target all [get_ips gig_ethernet_pcs_pma_0]
set_property top kcu116_ethernet_demo [get_filesets sources_1]
set_property top tb_udp_to_gmii [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "Implementation failed: $impl_status"
}

open_run impl_1
report_timing_summary -file [file join $build_dir timing_summary.rpt]
report_utilization -file [file join $build_dir utilization.rpt]

set bit_file [file join $build_dir ${project_name}.runs impl_1 \
    kcu116_ethernet_demo.bit]
puts "BITSTREAM: $bit_file"
