# Recreate and build the KCU116/VCU118 VHDL SGMII/UDP demonstration.
#
# Run from any directory:
#   vivado -mode batch -source create_project.tcl -tclargs kcu116
#   vivado -mode batch -source create_project.tcl -tclargs vcu118
#
# The board argument is mandatory. The script creates build_<board>, generates
# the licensed Gigabit Ethernet PCS/PMA IP for that FPGA, and builds a
# programming bitstream.

set script_dir [file normalize [file dirname [info script]]]
set source_dir [file normalize [file join $script_dir source]]

proc print_usage {} {
    puts stderr "Usage:"
    puts stderr "  vivado -mode batch -source create_project.tcl -tclargs kcu116"
    puts stderr "  vivado -mode batch -source create_project.tcl -tclargs vcu118"
}

if {$argc != 1} {
    puts stderr "ERROR: Select exactly one target board."
    print_usage
    exit 2
}

set board_name [string tolower [lindex $argv 0]]
switch -- $board_name {
    kcu116 {
        set project_name kcu116_ethernet_demo
        set part_name xcku5p-ffvb676-2-e
        set board_part_pattern xilinx.com:kcu116:part0:*
        set constraint_file [file join $script_dir constraints kcu116.xdc]
    }
    vcu118 {
        set project_name vcu118_ethernet_demo
        set part_name xcvu9p-flga2104-2L-e
        set board_part_pattern xilinx.com:vcu118:part0:*
        set constraint_file [file join $script_dir constraints vcu118.xdc]
    }
    default {
        puts stderr "ERROR: Unsupported target board '$board_name'."
        print_usage
        exit 2
    }
}

set build_dir [file normalize [file join $script_dir build_$board_name]]

file mkdir $build_dir
create_project -force $project_name $build_dir -part $part_name
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

# Explicit package pins make a board-part installation optional. Set the
# matching board part when available to improve board-aware IP validation.
set matching_board_parts [get_board_parts -quiet $board_part_pattern]
if {[llength $matching_board_parts] > 0} {
    set_property board_part [lindex $matching_board_parts end] [current_project]
}

add_files -norecurse [list \
    [file join $source_dir dp83867_pkg.vhd] \
    [file join $source_dir debug_status_pkg.vhd] \
    [file join $source_dir mdio_master.vhd] \
    [file join $source_dir reset_synchronizer.vhd] \
    [file join $source_dir gray_counter_cdc.vhd] \
    [file join $source_dir status_snapshot_cdc.vhd] \
    [file join $source_dir uart_tx.vhd] \
    [file join $source_dir uart_status_report.vhd] \
    [file join $source_dir dp83867_sgmii_init.vhd] \
    [file join $source_dir udp_to_gmii.vhd] \
    [file join $source_dir ethernet_statistics.vhd] \
    [file join $source_dir pcs_pma_wrapper.vhd] \
    [file join $source_dir ethernet_demo.vhd]]
set_property file_type {VHDL 2008} [get_files *.vhd]

set simulation_files [list \
    [file join $source_dir mdio_slave_bfm.vhd] \
    [file join $source_dir mdio_slave.vhd] \
    [file join $source_dir tb_udp_to_gmii.vhd] \
    [file join $source_dir tb_udp_to_gmii_no_padding.vhd] \
    [file join $source_dir tb_ethernet_statistics.vhd] \
    [file join $source_dir tb_dp83867_sgmii_init.vhd] \
    [file join $source_dir tb_mdio_master.vhd] \
    [file join $source_dir tb_uart_status.vhd]]
add_files -fileset sim_1 -norecurse $simulation_files
set simulation_sources [get_files -of_objects [get_filesets sim_1]]
set_property file_type {VHDL 2008} $simulation_sources
set_property used_in {simulation} $simulation_sources

add_files -fileset constrs_1 -norecurse $constraint_file

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
    CONFIG.EnableAsyncSGMII {true} \
    CONFIG.ClockSelection {Sync} \
    CONFIG.Tx_In_Upper_Nibble {0} \
    CONFIG.TxLane0_Placement {DIFF_PAIR_2} \
    CONFIG.RxLane0_Placement {DIFF_PAIR_0} \
] [get_ips gig_ethernet_pcs_pma_0]

generate_target all [get_ips gig_ethernet_pcs_pma_0]
set_property top ethernet_demo [get_filesets sources_1]
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
    ethernet_demo.bit]
puts "BOARD: $board_name"
puts "BITSTREAM: $bit_file"
