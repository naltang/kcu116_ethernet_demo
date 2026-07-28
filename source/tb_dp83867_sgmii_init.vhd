library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

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
    signal phy_status  : std_logic_vector(15 downto 0);
    signal phy_control : std_logic_vector(15 downto 0);
    signal phy_cfg1    : std_logic_vector(15 downto 0);
    signal phy_bmcr    : std_logic_vector(15 downto 0);
    signal phy_bmsr    : std_logic_vector(15 downto 0);
    signal phy_anar    : std_logic_vector(15 downto 0);
    signal phy_anlpar  : std_logic_vector(15 downto 0);
    signal phy_aner    : std_logic_vector(15 downto 0);
    signal phy_sts1    : std_logic_vector(15 downto 0);
    signal phy_recr    : std_logic_vector(15 downto 0);
    signal phy_cfg4    : std_logic_vector(15 downto 0);
    signal phy_strap2  : std_logic_vector(15 downto 0);
    signal phy_ana_ld  : std_logic_vector(15 downto 0);
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
            phy_status  => phy_status,
            phy_control => phy_control,
            phy_cfg1    => phy_cfg1,
            phy_bmcr    => phy_bmcr,
            phy_bmsr    => phy_bmsr,
            phy_anar    => phy_anar,
            phy_anlpar  => phy_anlpar,
            phy_aner    => phy_aner,
            phy_sts1    => phy_sts1,
            phy_recr    => phy_recr,
            phy_cfg4    => phy_cfg4,
            phy_strap2  => phy_strap2,
            phy_ana_ld  => phy_ana_ld,
            error       => error
        );

    phy_model : entity work.mdio_slave
        generic map (
            PHY_ADDR => "00011"
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

        wait until config_done = '1' for 10 ms;
        assert config_done = '1'
            report "DP83867 configuration timed out" severity failure;
        assert error = '0'
            report "DP83867 controller reported an error" severity failure;
        report "DP83867 configuration sequence verified" severity note;

        wait until link_up = '1' for 20 ms;
        assert link_up = '1'
            report "DP83867 link polling timed out" severity failure;
        report "DP83867 double-read link polling verified" severity note;

        wait until phy_status = x"BF02" for 1 ms;
        assert phy_status = x"BF02"
            report "DP83867 PHYSTS register polling timed out" severity failure;
        report "DP83867 PHYSTS register polling verified" severity note;

        wait until phy_control = x"5848" for 1 ms;
        assert phy_control = x"5848"
            report "DP83867 PHYCR register polling timed out" severity failure;
        report "DP83867 PHYCR register polling verified" severity note;

        wait until phy_cfg1 = x"0300" for 1 ms;
        assert phy_cfg1 = x"0300"
            report "DP83867 CFG1 register polling timed out" severity failure;
        report "DP83867 CFG1 register polling verified" severity note;

        wait until phy_ana_ld = x"0200" for 3 ms;
        assert phy_ana_ld = x"0200"
            report "DP83867 ANA_LD_DATA_CTRL indirect polling timed out"
            severity failure;
        assert phy_strap2 = x"0100"
            report "DP83867 STRAP_STS2 indirect polling timed out"
            severity failure;
        assert phy_bmcr = x"1340"
            report "DP83867 BMCR register polling timed out" severity failure;
        assert phy_bmsr = x"782F"
            report "DP83867 BMSR register polling timed out" severity failure;
        assert phy_anar = x"01E1"
            report "DP83867 ANAR register polling timed out" severity failure;
        assert phy_anlpar = x"CDE1"
            report "DP83867 ANLPAR register polling timed out" severity failure;
        assert phy_aner = x"0067"
            report "DP83867 ANER register polling timed out" severity failure;
        assert phy_sts1 = x"6000"
            report "DP83867 STS1 register polling timed out" severity failure;
        assert phy_recr = x"0005"
            report "DP83867 RECR register polling timed out" severity failure;
        report "DP83867 RECR register polling verified" severity note;
        assert phy_cfg4 = x"1030"
            report "DP83867 CFG4 indirect polling timed out" severity failure;
        report "DP83867 diagnostic-register polling verified" severity note;
        stop;
        wait;
    end process stimulus;
end architecture sim;
