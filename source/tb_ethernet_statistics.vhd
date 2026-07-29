library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_ethernet_statistics is
end entity tb_ethernet_statistics;

architecture sim of tb_ethernet_statistics is
    signal clk              : std_logic := '0';
    signal rst              : std_logic := '1';
    signal active           : std_logic := '0';
    signal clk_enable       : std_logic := '1';
    signal frame_sent       : std_logic := '0';
    signal rx_dv            : std_logic := '0';
    signal rx_error         : std_logic := '0';
    signal frame_sent_count : unsigned(15 downto 0);
    signal recv_count       : unsigned(15 downto 0);
    signal recv_error_count : unsigned(15 downto 0);
begin
    clk <= not clk after 4 ns;

    dut : entity work.ethernet_statistics
        port map (
            clk              => clk,
            rst              => rst,
            active           => active,
            clk_enable       => clk_enable,
            frame_sent       => frame_sent,
            rx_dv            => rx_dv,
            rx_error         => rx_error,
            frame_sent_count => frame_sent_count,
            recv_count       => recv_count,
            recv_error_count => recv_error_count
        );

    stimulus : process
        procedure enabled_cycle (
            constant dv_value    : in std_logic;
            constant error_value : in std_logic
        ) is
        begin
            clk_enable <= '1';
            rx_dv      <= dv_value;
            rx_error   <= error_value;
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst    <= '0';
        active <= '1';

        frame_sent <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        frame_sent <= '0';
        assert frame_sent_count = 1
            report "Transmit frame count did not increment" severity failure;

        -- A receive interval without RX_ERROR is accepted without examining
        -- or calculating its FCS.
        enabled_cycle('1', '0');
        enabled_cycle('1', '0');
        enabled_cycle('1', '0');
        enabled_cycle('0', '0');
        assert recv_count = 1 and recv_error_count = 0
            report "Valid receive frame was not counted" severity failure;

        -- An RX_ERROR anywhere within the interval makes it one errored frame.
        enabled_cycle('1', '0');
        enabled_cycle('1', '1');
        enabled_cycle('1', '0');
        enabled_cycle('0', '0');
        assert recv_count = 1 and recv_error_count = 1
            report "Errored receive frame was counted incorrectly"
            severity failure;

        -- No FCS-specific input exists, so another error-free RX_DV interval
        -- is valid regardless of the values of its final four data bytes.
        enabled_cycle('1', '0');
        enabled_cycle('1', '0');
        enabled_cycle('0', '0');
        assert recv_count = 2
            report "Second valid receive frame was not counted"
            severity failure;

        -- A standalone error indication is one event even if held high.
        enabled_cycle('0', '1');
        enabled_cycle('0', '1');
        enabled_cycle('0', '0');
        assert recv_error_count = 2
            report "Standalone receive error was counted incorrectly"
            severity failure;

        -- Losing client synchronization discards, rather than counts, a
        -- partially received frame and preserves all accumulated statistics.
        enabled_cycle('1', '0');
        active <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;
        active <= '1';
        enabled_cycle('0', '0');
        assert frame_sent_count = 1 and recv_count = 2 and
               recv_error_count = 2
            report "Inactive client handling changed a statistic"
            severity failure;

        -- Exercise the specified modulo-2^16 rollover behavior.
        frame_sent <= '1';
        for rollover_index in 1 to 65_535 loop
            wait until rising_edge(clk);
        end loop;
        wait for 1 ns;
        frame_sent <= '0';
        assert frame_sent_count = 0
            report "Transmit frame counter did not roll over"
            severity failure;

        report "Ethernet statistics counters verified" severity note;
        stop;
        wait;
    end process stimulus;
end architecture sim;
