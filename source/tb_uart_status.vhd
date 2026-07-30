library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.debug_status_pkg.all;

entity tb_uart_status is
end entity tb_uart_status;

architecture sim of tb_uart_status is
    constant CLOCK_FREQ_HZ : positive := 10_000_000;
    constant BAUD_RATE     : positive := 1_000_000;
    constant BIT_PERIOD    : time := 1 sec / BAUD_RATE;
    constant EXPECTED_LINE : string :=
        "FRAME(S=0x0001 R=0x0002 E=0x0003) PCS=0x0004" &
        " PHYSTS=0x0005 BMCR=0x0006 BMSR=0x0007 STS1=0x0008" &
        " RECR=0x0009 ISR=0x000A" &
        " MSE(A=0x000B B=0x000C C=0x000D D=0x000E)" &
        " ANAR=0x000F ANLPAR=0x0010 ANER=0x0011" &
        " PHYCR=0x0012 CFG1=0x0013 CFG4=0x0014" &
        " STRAP2=0x0015 ANA_LD=0x0016" & CR & LF;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal status     : debug_status_t := DEBUG_STATUS_RESET;
    signal data_out   : std_logic_vector(7 downto 0);
    signal data_valid : std_logic;
    signal data_ready : std_logic;
    signal snapshot_taken : std_logic;
    signal tx         : std_logic;
begin
    clk <= not clk after 50 ns;

    report_i : entity work.uart_status_report
        generic map (
            CLOCK_FREQ_HZ   => CLOCK_FREQ_HZ,
            BAUD_RATE       => BAUD_RATE,
            PAUSE_BIT_TIMES => 1
        )
        port map (
            clk        => clk,
            rst        => rst,
            status     => status,
            snapshot_taken => snapshot_taken,
            data_out   => data_out,
            data_valid => data_valid,
            data_ready => data_ready
        );

    uart_i : entity work.uart_tx
        generic map (
            CLOCK_FREQ_HZ => CLOCK_FREQ_HZ,
            BAUD_RATE     => BAUD_RATE
        )
        port map (
            clk        => clk,
            rst        => rst,
            data_in    => data_out,
            data_valid => data_valid,
            data_ready => data_ready,
            tx_out     => tx
        );

    reset_and_status : process
    begin
        status.frame_sent_count       <= x"0001";
        status.recv_count             <= x"0002";
        status.recv_error_count       <= x"0003";
        status.pcs_status             <= x"0004";
        status.phy.physts             <= x"0005";
        status.phy.bmcr               <= x"0006";
        status.phy.bmsr               <= x"0007";
        status.phy.sts1               <= x"0008";
        status.phy.recr               <= x"0009";
        status.phy.isr                <= x"000A";
        status.phy.mse_a              <= x"000B";
        status.phy.mse_b              <= x"000C";
        status.phy.mse_c              <= x"000D";
        status.phy.mse_d              <= x"000E";
        status.phy.anar               <= x"000F";
        status.phy.anlpar             <= x"0010";
        status.phy.aner               <= x"0011";
        status.phy.phycr              <= x"0012";
        status.phy.cfg1               <= x"0013";
        status.phy.cfg4               <= x"0014";
        status.phy.strap_sts2         <= x"0015";
        status.phy.ana_ld_data_ctrl   <= x"0016";
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        -- Change live inputs during transmission; the current line must retain
        -- the snapshot captured before its first byte.
        wait until falling_edge(tx);
        wait for 5 * BIT_PERIOD;
        status.frame_sent_count <= x"FFFF";
        status.phy.physts       <= x"FFFF";
        wait;
    end process reset_and_status;

    receiver : process
        variable expected_byte : std_logic_vector(7 downto 0);
        variable received_byte : std_logic_vector(7 downto 0);
    begin
        wait until rst = '0';
        for character_index in EXPECTED_LINE'range loop
            wait until falling_edge(tx);
            wait for BIT_PERIOD + BIT_PERIOD / 2;
            expected_byte := std_logic_vector(to_unsigned(
                character'pos(EXPECTED_LINE(character_index)), 8));
            for bit_index in 0 to 7 loop
                received_byte(bit_index) := tx;
                wait for BIT_PERIOD;
            end loop;
            assert received_byte = expected_byte
                report "UART status mismatch at character " &
                    integer'image(character_index) & ": expected " &
                    to_hstring(expected_byte) & ", received " &
                    to_hstring(received_byte)
                severity failure;
            assert tx = '1'
                report "UART stop bit was not high" severity failure;
        end loop;

        report "UART byte timing, fixed line format, and snapshot verified"
            severity note;
        stop;
        wait;
    end process receiver;

    watchdog : process
    begin
        wait for 5 ms;
        assert false report "UART status test timed out" severity failure;
        wait;
    end process watchdog;
end architecture sim;
