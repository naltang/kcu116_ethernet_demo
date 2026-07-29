library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_udp_to_gmii_no_padding is
end entity tb_udp_to_gmii_no_padding;

architecture sim of tb_udp_to_gmii_no_padding is
    constant PAYLOAD : std_logic_vector(18 * 8 - 1 downto 0) :=
        x"000102030405060708090A0B0C0D0E0F1011";
    constant TX_BYTE_COUNT : positive := 8 + 60 + 4;

    type byte_array_t is array (natural range <>)
        of std_logic_vector(7 downto 0);

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal udp_valid   : std_logic := '0';
    signal udp_ready   : std_logic;
    signal frame_sent  : std_logic;
    signal gmii_tx_en  : std_logic;
    signal gmii_txd    : std_logic_vector(7 downto 0);
    signal gmii_tx_er  : std_logic;
    signal frame_verified : std_logic := '0';
begin
    clk <= not clk after 4 ns;

    dut : entity work.udp_to_gmii
        generic map (
            UDP_PAYLOAD_BYTE_COUNT => PAYLOAD'length / 8
        )
        port map (
            clk         => clk,
            rst         => rst,
            clk_enable  => '1',
            udp_valid   => udp_valid,
            udp_payload => PAYLOAD,
            udp_ready   => udp_ready,
            frame_sent  => frame_sent,
            gmii_tx_en  => gmii_tx_en,
            gmii_txd    => gmii_txd,
            gmii_tx_er  => gmii_tx_er
        );

    stimulus : process
        procedure send_payload is
        begin
            udp_valid <= '1';
            wait until rising_edge(clk) and udp_ready = '1';
            udp_valid <= '0';
        end procedure;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';

        -- Abort one frame to verify that reset clears an in-progress transfer.
        send_payload;
        wait until gmii_tx_en = '1';
        rst <= '1';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';

        send_payload;
        wait until frame_verified = '1';
        report "Continuous-enable, no-padding, and reset behavior verified"
            severity note;
        stop;
        wait;
    end process stimulus;

    monitor : process(clk)
        variable captured : byte_array_t(0 to TX_BYTE_COUNT - 1);
        variable index    : natural range 0 to TX_BYTE_COUNT := 0;
    begin
        if rising_edge(clk) then
            assert gmii_tx_er = '0'
                report "Unexpected GMII transmit error" severity failure;
            if rst = '1' then
                index := 0;
            else
                if gmii_tx_en = '1' then
                    assert index < TX_BYTE_COUNT
                        report "No-padding frame was too long" severity failure;
                    captured(index) := gmii_txd;
                    index := index + 1;
                end if;

                if frame_sent = '1' then
                    assert index = TX_BYTE_COUNT
                        report "No-padding frame length was incorrect"
                        severity failure;
                    for payload_index in 0 to PAYLOAD'length / 8 - 1 loop
                        assert captured(50 + payload_index) = PAYLOAD(
                            PAYLOAD'high - payload_index * 8 downto
                            PAYLOAD'high - payload_index * 8 - 7)
                            report "No-padding payload byte was incorrect"
                            severity failure;
                    end loop;
                    frame_verified <= '1';
                    index := 0;
                end if;
            end if;
        end if;
    end process monitor;

    watchdog : process
    begin
        wait for 20 us;
        assert false report "No-padding UDP test timed out" severity failure;
        wait;
    end process watchdog;
end architecture sim;
