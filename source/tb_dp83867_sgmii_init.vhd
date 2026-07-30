library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.dp83867_pkg.all;

entity tb_dp83867_sgmii_init is
end entity tb_dp83867_sgmii_init;

architecture sim of tb_dp83867_sgmii_init is
    constant CLK_PERIOD : time := 100 ns;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal profile_select : phy_profile_t := PHY_PROFILE_CENTER;
    signal reinitialize : std_logic := '0';
    signal clear_isr   : std_logic := '0';
    signal phy_rst_n   : std_logic;
    signal mdc         : std_logic;
    signal mdio        : std_logic := 'H';
    signal config_done : std_logic;
    signal active_profile : phy_profile_t;
    signal link_up     : std_logic;
    signal diagnostics : phy_diagnostics_t;
    signal error       : std_logic;
    signal debug_extended_address : mdio_word_t := (others => '0');
    signal debug_extended_data    : mdio_word_t;
begin
    clk <= not clk after CLK_PERIOD / 2;
    mdio <= 'H';

    dut : entity work.dp83867_sgmii_init
        generic map (
            CLK_FREQ_HZ => 10_000_000,
            MDC_FREQ_HZ => 1_000_000,
            PHY_ADDR    => "00011"
        )
        port map (
            clk         => clk,
            rst         => rst,
            profile_select => profile_select,
            reinitialize => reinitialize,
            clear_isr   => clear_isr,
            phy_rst_n   => phy_rst_n,
            mdc         => mdc,
            mdio        => mdio,
            config_done => config_done,
            active_profile => active_profile,
            link_up     => link_up,
            diagnostics => diagnostics,
            error       => error
        );

    phy_model : entity work.mdio_slave
        generic map (
            PHY_ADDR          => "00011",
            SELF_CLEAR_CYCLES => 100
        )
        port map (
            clk   => clk,
            rst_n => phy_rst_n,
            mdc   => mdc,
            mdio  => mdio,
            debug_extended_address => debug_extended_address,
            debug_extended_data    => debug_extended_data
        );

    stimulus : process
        procedure check_extended (
            constant address_value  : in mdio_word_t;
            constant expected_value : in mdio_word_t;
            constant description    : in string
        ) is
        begin
            debug_extended_address <= address_value;
            wait for 1 ns;
            assert debug_extended_data = expected_value
                report description & ": expected " &
                    to_hstring(expected_value) & ", received " &
                    to_hstring(debug_extended_data)
                severity failure;
        end procedure;

        procedure apply_profile (
            constant profile_value : in phy_profile_t
        ) is
        begin
            profile_select <= profile_value;
            reinitialize   <= '1';
            wait until rising_edge(clk);
            reinitialize <= '0';
            wait until rising_edge(clk);
            assert config_done = '0'
                report "Profile reinitialization did not clear config_done"
                severity failure;
            wait until config_done = '1';
            assert active_profile = profile_value
                report "Active PHY profile was not updated"
                severity failure;
        end procedure;
    begin
        wait for 1 us;
        wait until rising_edge(clk);
        rst <= '0';

        wait until config_done = '1';
        assert error = '0'
            report "DP83867 controller reported an error" severity failure;
        assert active_profile = PHY_PROFILE_CENTER
            report "Initial PHY profile was not Center" severity failure;
        check_extended(DP83867_EXT_CFG2, x"2BC0",
            "Center CFG2");
        check_extended(DP83867_EXT_TRAINING_0102, x"0000",
            "Center AGC timer");
        report "DP83867 Center profile verified" severity note;

        apply_profile(PHY_PROFILE_NORTH);
        check_extended(DP83867_EXT_TRAINING_0102, x"7477",
            "North AGC timer");
        check_extended(DP83867_EXT_AGC_RETRAIN, x"0080",
            "North AGC retrain");
        report "DP83867 North profile verified" severity note;

        apply_profile(PHY_PROFILE_EAST);
        check_extended(DP83867_EXT_MDI_AMPLITUDE, x"F508",
            "East MDI amplitude");
        check_extended(DP83867_EXT_TRAINING_0102, x"0000",
            "East reset of preceding North profile");
        report "DP83867 East profile verified" severity note;

        apply_profile(PHY_PROFILE_SOUTH);
        check_extended(DP83867_EXT_VITERBI_IDLE_CTRL, x"2054",
            "South Viterbi idle control");
        check_extended(DP83867_EXT_CAGC_DC_COMP, x"3840",
            "South CAGC DC compensation");
        check_extended(DP83867_EXT_TRAINING_0102, x"7477",
            "South training timer 0102");
        check_extended(DP83867_EXT_TRAINING_0103, x"7777",
            "South training timer 0103");
        check_extended(DP83867_EXT_TRAINING_0104, x"4577",
            "South training timer 0104");
        check_extended(DP83867_EXT_TIMING_010C, x"7777",
            "South timing bandwidth 010C");
        check_extended(DP83867_EXT_TIMING_01C2, x"7FDE",
            "South timing bandwidth 01C2");
        check_extended(DP83867_EXT_TRAINING_0115, x"5555",
            "South training timer 0115");
        check_extended(DP83867_EXT_TRAINING_0118, x"0771",
            "South training timer 0118");
        check_extended(DP83867_EXT_TIMING_011D, x"6DB2",
            "South timing bandwidth 011D");
        check_extended(DP83867_EXT_TIMING_011E, x"3FFB",
            "South timing bandwidth 011E");
        check_extended(DP83867_EXT_TIMING_01C3, x"FFC6",
            "South timing bandwidth 01C3");
        check_extended(DP83867_EXT_TIMING_01C4, x"0FC2",
            "South timing bandwidth 01C4");
        check_extended(DP83867_EXT_TIMING_01C5, x"0FF0",
            "South timing bandwidth 01C5");
        check_extended(DP83867_EXT_FFE_CFG, x"0E81",
            "South FFE configuration");
        report "DP83867 South profile verified" severity note;

        apply_profile(PHY_PROFILE_WEST);
        check_extended(DP83867_EXT_CFG2, x"29C0",
            "West no-downshift CFG2");
        check_extended(DP83867_EXT_FFE_CFG, x"0000",
            "West reset of preceding South profile");
        report "DP83867 West profile verified" severity note;

        apply_profile(PHY_PROFILE_CENTER);
        check_extended(DP83867_EXT_CFG2, x"2BC0",
            "Restored Center CFG2");
        check_extended(DP83867_EXT_MDI_AMPLITUDE, x"0000",
            "Center reset of profile tuning");
        report "DP83867 profile reinitialization verified" severity note;

        wait until link_up = '1';
        report "DP83867 double-read link polling verified" severity note;

        wait until diagnostics.physts = x"BF02";
        report "DP83867 PHYSTS register polling verified" severity note;

        wait until diagnostics.phycr = x"5848";
        report "DP83867 PHYCR register polling verified" severity note;

        wait until diagnostics.cfg1 = x"0300";
        report "DP83867 CFG1 register polling verified" severity note;

        wait until diagnostics.ana_ld_data_ctrl = x"0200";
        assert diagnostics.ana_ld_data_ctrl = x"0200"
            report "DP83867 ANA_LD_DATA_CTRL indirect polling timed out"
            severity failure;
        assert diagnostics.strap_sts2 = x"0100"
            report "DP83867 STRAP_STS2 indirect polling timed out"
            severity failure;
        assert diagnostics.bmcr = x"1340"
            report "DP83867 BMCR register polling timed out" severity failure;
        assert diagnostics.bmsr = x"782F"
            report "DP83867 BMSR register polling timed out" severity failure;
        assert diagnostics.anar = x"01E1"
            report "DP83867 ANAR register polling timed out" severity failure;
        assert diagnostics.anlpar = x"CDE1"
            report "DP83867 ANLPAR register polling timed out" severity failure;
        assert diagnostics.aner = x"0067"
            report "DP83867 ANER register polling timed out" severity failure;
        assert diagnostics.sts1 = x"6000"
            report "DP83867 STS1 register polling timed out" severity failure;
        assert diagnostics.recr = x"0005"
            report "DP83867 RECR register polling timed out" severity failure;
        report "DP83867 RECR register polling verified" severity note;
        assert diagnostics.isr = x"5400"
            report "DP83867 ISR accumulation timed out" severity failure;
        clear_isr <= '1';
        wait until rising_edge(clk);
        clear_isr <= '0';
        wait until rising_edge(clk);
        assert diagnostics.isr = x"0000"
            report "DP83867 ISR report-clear failed" severity failure;
        report "DP83867 clear-on-read ISR accumulation verified"
            severity note;
        assert diagnostics.mse_a = x"0123"
            report "DP83867 MSE_A indirect polling timed out"
            severity failure;
        assert diagnostics.mse_b = x"0145"
            report "DP83867 MSE_B indirect polling timed out"
            severity failure;
        assert diagnostics.mse_c = x"0167"
            report "DP83867 MSE_C indirect polling timed out"
            severity failure;
        assert diagnostics.mse_d = x"0189"
            report "DP83867 MSE_D indirect polling timed out"
            severity failure;
        report "DP83867 MSE register polling verified" severity note;
        assert diagnostics.cfg4 = x"1030"
            report "DP83867 CFG4 indirect polling timed out" severity failure;
        report "DP83867 diagnostic-register polling verified" severity note;
        stop;
        wait;
    end process stimulus;

    watchdog : process
    begin
        wait for 50 ms;
        assert false report "DP83867 test timed out" severity failure;
        wait;
    end process watchdog;
end architecture sim;
