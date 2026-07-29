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
    signal phy_rst_n   : std_logic;
    signal mdc         : std_logic;
    signal mdio        : std_logic := 'H';
    signal config_done : std_logic;
    signal link_up     : std_logic;
    signal diagnostics : phy_diagnostics_t;
    signal error       : std_logic;
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
            phy_rst_n   => phy_rst_n,
            mdc         => mdc,
            mdio        => mdio,
            config_done => config_done,
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
            mdio  => mdio
        );

    stimulus : process
    begin
        wait for 1 us;
        wait until rising_edge(clk);
        rst <= '0';

        wait until config_done = '1';
        assert error = '0'
            report "DP83867 controller reported an error" severity failure;
        report "DP83867 configuration sequence verified" severity note;

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
        wait for 25 ms;
        assert false report "DP83867 test timed out" severity failure;
        wait;
    end process watchdog;
end architecture sim;
