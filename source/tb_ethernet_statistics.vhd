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
    signal gmii_rxd          : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_dv            : std_logic := '0';
    signal rx_er            : std_logic := '0';
    signal recv_started     : std_logic;
    signal recv_error_event : std_logic;
    signal frame_sent_count : unsigned(3 downto 0);
    signal recv_count       : unsigned(3 downto 0);
    signal recv_fcs_error_count : unsigned(3 downto 0);
    signal recv_error_count : unsigned(3 downto 0);
begin
    clk <= not clk after 4 ns;

    dut : entity work.ethernet_statistics
        generic map (
            COUNTER_WIDTH => 4
        )
        port map (
            clk              => clk,
            rst              => rst,
            active           => active,
            clk_enable       => clk_enable,
            frame_sent       => frame_sent,
            gmii_rxd          => gmii_rxd,
            rx_dv            => rx_dv,
            rx_er             => rx_er,
            recv_started      => recv_started,
            recv_error_event  => recv_error_event,
            frame_sent_count => frame_sent_count,
            recv_count       => recv_count,
            recv_fcs_error_count => recv_fcs_error_count,
            recv_error_count => recv_error_count
        );

    stimulus : process
        procedure enabled_cycle (
            constant dv_value    : in std_logic;
            constant error_value : in std_logic;
            constant data_value  : in std_logic_vector(7 downto 0) := x"00"
        ) is
        begin
            clk_enable <= '1';
            rx_dv      <= dv_value;
            rx_er      <= error_value;
            gmii_rxd   <= data_value;
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;

        procedure frame_byte (
            constant data_value      : in std_logic_vector(7 downto 0);
            constant disabled_cycles : in natural := 0
        ) is
        begin
            enabled_cycle('1', '0', data_value);
            for repeat_index in 1 to disabled_cycles loop
                clk_enable <= '0';
                wait until rising_edge(clk);
                wait for 1 ns;
            end loop;
        end procedure;

        procedure send_known_frame (
            constant corrupt_fcs     : in boolean;
            constant disabled_cycles : in natural := 0
        ) is
        begin
            -- CRC-32 of 01 02 03 04 is 0xB63CFBCD. Ethernet sends the
            -- complemented CRC least-significant byte first.
            enabled_cycle('1', '0', x"55");
            assert recv_started = '1'
                report "Receive-start event was not asserted"
                severity failure;
            for repeat_index in 1 to disabled_cycles loop
                clk_enable <= '0';
                wait until rising_edge(clk);
                wait for 1 ns;
            end loop;
            for preamble_index in 2 to 7 loop
                frame_byte(x"55", disabled_cycles);
            end loop;
            frame_byte(x"D5", disabled_cycles);
            frame_byte(x"01", disabled_cycles);
            frame_byte(x"02", disabled_cycles);
            frame_byte(x"03", disabled_cycles);
            frame_byte(x"04", disabled_cycles);
            frame_byte(x"CD", disabled_cycles);
            frame_byte(x"FB", disabled_cycles);
            frame_byte(x"3C", disabled_cycles);
            if corrupt_fcs then
                frame_byte(x"B7", disabled_cycles);
            else
                frame_byte(x"B6", disabled_cycles);
            end if;
            enabled_cycle('0', '0');
        end procedure;

        procedure sent_pulse is
        begin
            frame_sent <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            frame_sent <= '0';
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst    <= '0';
        active <= '1';

        sent_pulse;
        assert frame_sent_count = 1
            report "Transmit frame count did not increment" severity failure;

        -- A receive interval with a correct FCS increments R but not F.
        send_known_frame(false);
        assert recv_count = 1 and recv_fcs_error_count = 0 and
               recv_error_count = 0
            report "FCS-good receive frame was counted incorrectly"
            severity failure;

        -- A completed frame with no RX_ER still increments R when its FCS is
        -- bad; F is a subset of R and records the additional integrity check.
        send_known_frame(true);
        assert recv_count = 2 and recv_fcs_error_count = 1 and
               recv_error_count = 0
            report "FCS-bad receive frame was counted incorrectly"
            severity failure;

        -- An RX_ERROR anywhere within the interval makes it one errored frame.
        enabled_cycle('1', '0');
        enabled_cycle('1', '1');
        enabled_cycle('1', '0');
        enabled_cycle('0', '0');
        assert recv_count = 2 and recv_fcs_error_count = 1 and
               recv_error_count = 1
            report "Errored receive frame was counted incorrectly"
            severity failure;

        -- A standalone error indication is one event even if held high.
        enabled_cycle('0', '1');
        assert recv_error_event = '1'
            report "Standalone error event was not asserted" severity failure;
        enabled_cycle('0', '1');
        enabled_cycle('0', '0');
        assert recv_error_count = 2
            report "Standalone receive error was counted incorrectly"
            severity failure;

        -- Normal 1000BASE-X carrier extension is not an error.
        enabled_cycle('0', '1', x"0F");
        enabled_cycle('0', '1', x"0F");
        enabled_cycle('0', '0');
        assert recv_error_count = 2
            report "Carrier extension was counted as an error"
            severity failure;

        -- Disabled client cycles do not change receive state or statistics.
        clk_enable <= '0';
        rx_dv      <= '1';
        rx_er      <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        rx_dv      <= '0';
        rx_er      <= '0';
        assert recv_count = 2 and recv_fcs_error_count = 1 and
               recv_error_count = 2
            report "Disabled receive cycle changed a statistic"
            severity failure;

        -- An error asserted as RX_DV closes the frame is attributed to it.
        enabled_cycle('1', '0');
        enabled_cycle('0', '1');
        assert recv_error_count = 3 and recv_error_event = '1'
            report "Closing-edge receive error was counted incorrectly"
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
               recv_fcs_error_count = 1 and recv_error_count = 3
            report "Inactive client handling changed a statistic"
            severity failure;

        -- Repeated bytes on disabled 100/10-Mb/s client cycles must not be
        -- included more than once in the CRC.
        send_known_frame(false, 2);
        assert recv_count = 3 and recv_fcs_error_count = 1
            report "Clock-enable-aware FCS checking failed" severity failure;

        -- Exercise modulo rollover with realistic event pulses.
        for rollover_index in 1 to 15 loop
            sent_pulse;
        end loop;
        assert frame_sent_count = 0
            report "Transmit frame counter did not roll over"
            severity failure;

        for rollover_index in 1 to 15 loop
            send_known_frame(true);
        end loop;
        assert recv_fcs_error_count = 0
            report "FCS-error counter did not roll over" severity failure;

        report "Ethernet statistics and receive FCS checking verified"
            severity note;
        stop;
        wait;
    end process stimulus;
end architecture sim;
