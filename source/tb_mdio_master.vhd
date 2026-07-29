library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.dp83867_pkg.all;

entity tb_mdio_master is
end entity tb_mdio_master;

architecture sim of tb_mdio_master is
    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal cmd_phy_addr   : std_logic_vector(4 downto 0) := "00011";
    signal cmd_reg_addr   : std_logic_vector(4 downto 0) := (others => '0');
    signal cmd_data       : std_logic_vector(15 downto 0) := (others => '0');
    signal cmd_opcode     : std_logic_vector(1 downto 0) := MDIO_OP_READ;
    signal cmd_valid      : std_logic := '0';
    signal cmd_ready      : std_logic;
    signal data_out       : std_logic_vector(15 downto 0);
    signal data_out_valid : std_logic;
    signal data_out_ready : std_logic := '1';
    signal mdc            : std_logic;
    signal mdio           : std_logic := 'H';
    signal mdio_o         : std_logic;
    signal mdio_t         : std_logic;
    signal busy           : std_logic;
begin
    clk <= not clk after 50 ns;
    mdio <= mdio_o when mdio_t = '0' else 'Z';
    mdio <= 'H';

    dut : entity work.mdio_master
        port map (
            clk            => clk,
            rst            => rst,
            cmd_phy_addr   => cmd_phy_addr,
            cmd_reg_addr   => cmd_reg_addr,
            cmd_data       => cmd_data,
            cmd_opcode     => cmd_opcode,
            cmd_valid      => cmd_valid,
            cmd_ready      => cmd_ready,
            data_out       => data_out,
            data_out_valid => data_out_valid,
            data_out_ready => data_out_ready,
            mdc_o          => mdc,
            mdio_i         => mdio,
            mdio_o         => mdio_o,
            mdio_t         => mdio_t,
            busy           => busy,
            prescale       => 1
        );

    phy : entity work.mdio_slave
        generic map (
            PHY_ADDR          => "00011",
            SELF_CLEAR_CYCLES => 10
        )
        port map (
            clk   => clk,
            rst_n => not rst,
            mdc   => mdc,
            mdio  => mdio
        );

    stimulus : process
        procedure issue_command (
            constant opcode_value : in std_logic_vector(1 downto 0);
            constant address_value : in std_logic_vector(4 downto 0);
            constant data_value    : in std_logic_vector(15 downto 0)
        ) is
        begin
            cmd_opcode   <= opcode_value;
            cmd_reg_addr <= address_value;
            cmd_data     <= data_value;
            cmd_valid    <= '1';
            wait until rising_edge(clk) and cmd_ready = '1';
            cmd_valid <= '0';
        end procedure;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';

        issue_command(MDIO_OP_WRITE, DP83867_REG_ANAR, x"A55A");
        wait until busy = '1';
        wait until busy = '0';

        data_out_ready <= '0';
        issue_command(MDIO_OP_READ, DP83867_REG_ANAR, x"0000");
        wait until data_out_valid = '1';
        assert data_out = x"A55A"
            report "MDIO read did not return the preceding write"
            severity failure;

        -- Read data must remain stable while the consumer applies backpressure.
        for hold_index in 1 to 3 loop
            wait until rising_edge(clk);
            assert data_out_valid = '1' and data_out = x"A55A"
                report "MDIO read response did not honor backpressure"
                severity failure;
        end loop;
        data_out_ready <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        assert data_out_valid = '0'
            report "MDIO read response did not complete" severity failure;

        report "MDIO master read, write, and backpressure verified"
            severity note;
        stop;
        wait;
    end process stimulus;

    watchdog : process
    begin
        wait for 2 ms;
        assert false report "MDIO master test timed out" severity failure;
        wait;
    end process watchdog;
end architecture sim;
