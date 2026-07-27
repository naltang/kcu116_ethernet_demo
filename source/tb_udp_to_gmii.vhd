library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_udp_to_gmii is
end entity tb_udp_to_gmii;

architecture sim of tb_udp_to_gmii is
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal clk_enable   : std_logic := '0';
    signal udp_valid    : std_logic := '0';
    signal udp_ready    : std_logic;
    signal frame_sent   : std_logic;
    signal gmii_tx_en   : std_logic;
    signal gmii_txd     : std_logic_vector(7 downto 0);
    signal gmii_tx_er   : std_logic;
    signal enable_count : natural range 0 to 9 := 0;

    constant TEST_SOURCE_MAC     : std_logic_vector(47 downto 0) :=
        x"0A0B0C0D0E0F";
    constant TEST_SOURCE_IP      : std_logic_vector(31 downto 0) :=
        x"C0A8010A";
    constant TEST_DESTINATION_IP : std_logic_vector(31 downto 0) :=
        x"C0A80114";
    constant TEST_SOURCE_PORT       : natural := 10000;
    constant TEST_DESTINATION_PORT  : natural := 20000;
    constant TEST_PAYLOAD           : std_logic_vector(39 downto 0) :=
        x"DEADBEEF01";
    constant REPLACEMENT_PAYLOAD : std_logic_vector(39 downto 0) :=
        x"1122334455";

    signal udp_payload : std_logic_vector(TEST_PAYLOAD'range) :=
        TEST_PAYLOAD;

    constant PAYLOAD_BYTE_COUNT : positive := TEST_PAYLOAD'length / 8;
    constant UDP_LENGTH          : positive := 8 + PAYLOAD_BYTE_COUNT;
    constant FRAME_DATA_LENGTH   : positive := 60;
    constant PREAMBLE_LENGTH     : positive := 8;
    constant TX_BYTE_COUNT       : positive :=
        PREAMBLE_LENGTH + FRAME_DATA_LENGTH + 4;

    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
begin
    clk <= not clk after 4 ns;

    dut : entity work.udp_to_gmii
        generic map (
            UDP_PAYLOAD_BYTE_COUNT => PAYLOAD_BYTE_COUNT,
            SOURCE_MAC_ADDRESS     => TEST_SOURCE_MAC,
            SOURCE_IP_ADDRESS      => TEST_SOURCE_IP,
            DESTINATION_IP_ADDRESS => TEST_DESTINATION_IP,
            SOURCE_UDP_PORT        => TEST_SOURCE_PORT,
            DESTINATION_UDP_PORT   => TEST_DESTINATION_PORT
        )
        port map (
            clk          => clk,
            rst          => rst,
            clk_enable   => clk_enable,
            udp_valid    => udp_valid,
            udp_payload  => udp_payload,
            udp_ready    => udp_ready,
            frame_sent   => frame_sent,
            gmii_tx_en   => gmii_tx_en,
            gmii_txd     => gmii_txd,
            gmii_tx_er   => gmii_tx_er
        );

    -- Model the client clock enable used at 100 Mb/s: one enabled GMII
    -- transfer every ten 125-MHz cycles.
    enable_generator : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                enable_count <= 0;
                clk_enable   <= '0';
            elsif enable_count = 9 then
                enable_count <= 0;
                clk_enable   <= '1';
            else
                enable_count <= enable_count + 1;
                clk_enable   <= '0';
            end if;
        end if;
    end process enable_generator;

    stimulus : process
    begin
        wait for 100 ns;
        wait until rising_edge(clk);
        rst <= '0';

        -- Hold VALID until the handshake, then immediately replace the input
        -- payload.  The transmitted datagram must use the accepted snapshot.
        wait for 24 ns;
        wait until rising_edge(clk);
        udp_valid <= '1';
        wait until rising_edge(clk) and udp_ready = '1';
        udp_valid   <= '0';
        udp_payload <= REPLACEMENT_PAYLOAD;

        wait until frame_sent = '1';
        wait for 20 ns;
        stop;
        wait;
    end process stimulus;

    monitor : process(clk)
        variable captured     : byte_array_t(0 to TX_BYTE_COUNT - 1);
        variable index        : natural := 0;
        variable byte_index   : natural;
        variable checksum_sum : natural;
        variable word_value   : unsigned(15 downto 0);
        variable crc          : std_logic_vector(31 downto 0);
        variable crc_byte     : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            assert gmii_tx_er = '0'
                report "Unexpected GMII transmit error" severity failure;
            if clk_enable = '1' and gmii_tx_en = '1' then
                assert index < TX_BYTE_COUNT
                    report "Transmitted too many bytes" severity failure;
                captured(index) := gmii_txd;
                index := index + 1;
            end if;

            if frame_sent = '1' then
                assert index = TX_BYTE_COUNT
                    report "Incorrect transmitted byte count" severity failure;

                for current_byte in 0 to 6 loop
                    assert captured(current_byte) = x"55"
                        report "Incorrect Ethernet preamble" severity failure;
                end loop;
                assert captured(7) = x"D5"
                    report "Incorrect Ethernet SFD" severity failure;

                -- Destination MAC is left at its broadcast default.
                for current_byte in 8 to 13 loop
                    assert captured(current_byte) = x"FF"
                        report "Incorrect destination MAC address"
                        severity failure;
                end loop;
                for current_byte in 0 to 5 loop
                    assert captured(14 + current_byte) =
                        TEST_SOURCE_MAC(47 - current_byte * 8 downto
                                        40 - current_byte * 8)
                        report "Incorrect source MAC address" severity failure;
                end loop;
                for current_byte in 0 to 3 loop
                    assert captured(34 + current_byte) =
                        TEST_SOURCE_IP(31 - current_byte * 8 downto
                                       24 - current_byte * 8)
                        report "Incorrect source IPv4 address" severity failure;
                    assert captured(38 + current_byte) =
                        TEST_DESTINATION_IP(31 - current_byte * 8 downto
                                            24 - current_byte * 8)
                        report "Incorrect destination IPv4 address"
                        severity failure;
                end loop;
                assert captured(42) = x"27" and captured(43) = x"10"
                    report "Incorrect UDP source port" severity failure;
                assert captured(44) = x"4E" and captured(45) = x"20"
                    report "Incorrect UDP destination port" severity failure;
                assert captured(46) = x"00" and captured(47) = x"0D"
                    report "Incorrect UDP length" severity failure;

                for current_byte in 0 to PAYLOAD_BYTE_COUNT - 1 loop
                    assert captured(50 + current_byte) =
                        TEST_PAYLOAD(
                            TEST_PAYLOAD'high - current_byte * 8 downto
                            TEST_PAYLOAD'high - current_byte * 8 - 7)
                        report "Incorrect UDP payload byte" severity failure;
                end loop;
                for current_byte in
                    50 + PAYLOAD_BYTE_COUNT to PREAMBLE_LENGTH +
                    FRAME_DATA_LENGTH - 1
                loop
                    assert captured(current_byte) = x"00"
                        report "Incorrect Ethernet padding" severity failure;
                end loop;

                -- A valid one's-complement checksum folds to all ones when its
                -- checksum field is included in the sum.
                checksum_sum := 0;
                for current_byte in 22 to 40 loop
                    if current_byte mod 2 = 0 then
                        word_value(15 downto 8) :=
                            unsigned(captured(current_byte));
                        word_value(7 downto 0) :=
                            unsigned(captured(current_byte + 1));
                        checksum_sum := checksum_sum + to_integer(word_value);
                    end if;
                end loop;
                while checksum_sum > 65535 loop
                    checksum_sum := checksum_sum mod 65536 +
                                    checksum_sum / 65536;
                end loop;
                assert checksum_sum = 65535
                    report "Incorrect IPv4 header checksum" severity failure;

                checksum_sum := 17;
                for current_byte in 34 to 40 loop
                    if current_byte mod 2 = 0 then
                        word_value(15 downto 8) :=
                            unsigned(captured(current_byte));
                        word_value(7 downto 0) :=
                            unsigned(captured(current_byte + 1));
                        checksum_sum := checksum_sum + to_integer(word_value);
                    end if;
                end loop;
                word_value(15 downto 8) := unsigned(captured(46));
                word_value(7 downto 0) := unsigned(captured(47));
                checksum_sum := checksum_sum + to_integer(word_value);

                for word_index in 0 to (UDP_LENGTH + 1) / 2 - 1 loop
                    byte_index := 42 + word_index * 2;
                    word_value(15 downto 8) := unsigned(captured(byte_index));
                    if byte_index + 1 < 42 + UDP_LENGTH then
                        word_value(7 downto 0) :=
                            unsigned(captured(byte_index + 1));
                    else
                        word_value(7 downto 0) := (others => '0');
                    end if;
                    checksum_sum := checksum_sum + to_integer(word_value);
                end loop;
                while checksum_sum > 65535 loop
                    checksum_sum := checksum_sum mod 65536 +
                                    checksum_sum / 65536;
                end loop;
                assert checksum_sum = 65535
                    report "Incorrect UDP checksum" severity failure;

                crc := (others => '1');
                for current_byte in
                    PREAMBLE_LENGTH to PREAMBLE_LENGTH +
                    FRAME_DATA_LENGTH - 1
                loop
                    crc_byte := captured(current_byte);
                    for bit_index in 0 to 7 loop
                        if (crc(0) xor crc_byte(bit_index)) = '1' then
                            crc := ('0' & crc(31 downto 1)) xor x"EDB88320";
                        else
                            crc := '0' & crc(31 downto 1);
                        end if;
                    end loop;
                end loop;
                crc := not crc;
                assert captured(TX_BYTE_COUNT - 4) = crc(7 downto 0) and
                       captured(TX_BYTE_COUNT - 3) = crc(15 downto 8) and
                       captured(TX_BYTE_COUNT - 2) = crc(23 downto 16) and
                       captured(TX_BYTE_COUNT - 1) = crc(31 downto 24)
                    report "Incorrect Ethernet FCS" severity failure;

                report "Latched UDP payload-to-GMII frame verified"
                    severity note;
            end if;
        end if;
    end process monitor;
end architecture sim;
