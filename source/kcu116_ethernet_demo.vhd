library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity kcu116_ethernet_demo is
    generic (
        SOURCE_MAC_ADDRESS      : std_logic_vector(47 downto 0) := x"020000000001";
        DESTINATION_MAC_ADDRESS : std_logic_vector(47 downto 0) := x"FFFFFFFFFFFF";
        SOURCE_IP_ADDRESS       : std_logic_vector(31 downto 0) := x"01020374";
        DESTINATION_IP_ADDRESS  : std_logic_vector(31 downto 0) := x"01020304";
        SOURCE_UDP_PORT         : natural range 0 to 65535 := 1234;
        DESTINATION_UDP_PORT    : natural range 0 to 65535 := 5678
    );
    port (
        clk_125_p : in  std_logic;
        clk_125_n : in  std_logic;
        cpu_reset : in  std_logic;

        -- FPGA transmit side of the KCU116 USB-UART bridge.
        usb_uart_rx_fpga_tx_ls : out std_logic;

        phy1_pdwn_b_i_int_b_o : out std_logic;
        phy1_reset_b          : out std_logic;
        phy1_mdc              : out std_logic;
        phy1_mdio             : inout std_logic;

        phy1_sgmii_in_p  : in  std_logic;
        phy1_sgmii_in_n  : in  std_logic;
        phy1_sgmii_out_p : out std_logic;
        phy1_sgmii_out_n : out std_logic;
        phy1_sgmii_clk_p : in  std_logic;
        phy1_sgmii_clk_n : in  std_logic;

        gpio_led_0 : out std_logic;
        gpio_led_1 : out std_logic;
        gpio_led_2 : out std_logic;
        gpio_led_3 : out std_logic;
        gpio_led_4 : out std_logic;
        gpio_led_5 : out std_logic;
        gpio_led_6 : out std_logic;
        gpio_led_7 : out std_logic
    );
end entity kcu116_ethernet_demo;

architecture rtl of kcu116_ethernet_demo is
    constant UART_MESSAGE_BYTES : positive := 202;
    constant UDP_PAYLOAD        : std_logic_vector(26 * 8 - 1 downto 0) :=
        x"48656C6C6F20776F726C6421202D2D66726F6D204B4355313136";
    -- "Hello world! --from KCU116"

    function to_8bit_vector(char : character) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(character'pos(char), 8));
    end function;

    function to_hex_ascii(nibble : std_logic_vector(3 downto 0))
        return std_logic_vector is
    begin
        case nibble is
            when "0000" => return x"30";
            when "0001" => return x"31";
            when "0010" => return x"32";
            when "0011" => return x"33";
            when "0100" => return x"34";
            when "0101" => return x"35";
            when "0110" => return x"36";
            when "0111" => return x"37";
            when "1000" => return x"38";
            when "1001" => return x"39";
            when "1010" => return x"41";
            when "1011" => return x"42";
            when "1100" => return x"43";
            when "1101" => return x"44";
            when "1110" => return x"45";
            when "1111" => return x"46";
            when others => return x"3F"; -- '?' for an unknown simulation value
        end case;
    end function;

    procedure put_uart_char (
        variable message_value : inout std_logic_vector;
        variable byte_index    : inout natural;
        constant char_value    : in character
    ) is
    begin
        message_value(byte_index * 8 + 7 downto byte_index * 8) :=
            to_8bit_vector(char_value);
        byte_index := byte_index + 1;
    end procedure;

    procedure put_uart_text (
        variable message_value : inout std_logic_vector;
        variable byte_index    : inout natural;
        constant text_value    : in string
    ) is
    begin
        for index in text_value'range loop
            put_uart_char(message_value, byte_index, text_value(index));
        end loop;
    end procedure;

    procedure put_uart_hex_word (
        variable message_value : inout std_logic_vector;
        variable byte_index    : inout natural;
        constant word_value    : in std_logic_vector(15 downto 0)
    ) is
    begin
        put_uart_text(message_value, byte_index, "0x");
        for nibble_index in 3 downto 0 loop
            message_value(byte_index * 8 + 7 downto byte_index * 8) :=
                to_hex_ascii(word_value(
                    nibble_index * 4 + 3 downto nibble_index * 4));
            byte_index := byte_index + 1;
        end loop;
    end procedure;

    function build_uart_message (
        pcs_status_value : std_logic_vector(15 downto 0);
        phy_status_value : std_logic_vector(15 downto 0);
        phycr_value      : std_logic_vector(15 downto 0);
        cfg1_value       : std_logic_vector(15 downto 0);
        bmcr_value       : std_logic_vector(15 downto 0);
        bmsr_value       : std_logic_vector(15 downto 0);
        anar_value       : std_logic_vector(15 downto 0);
        anlpar_value     : std_logic_vector(15 downto 0);
        aner_value       : std_logic_vector(15 downto 0);
        sts1_value       : std_logic_vector(15 downto 0);
        recr_value       : std_logic_vector(15 downto 0);
        cfg4_value       : std_logic_vector(15 downto 0);
        strap2_value     : std_logic_vector(15 downto 0);
        ana_ld_value     : std_logic_vector(15 downto 0)
    ) return std_logic_vector is
        variable result_value : std_logic_vector(
            UART_MESSAGE_BYTES * 8 - 1 downto 0) := (others => '0');
        variable byte_index   : natural := 0;
    begin
        put_uart_text(result_value, byte_index, "PCS_STATUS=");
        put_uart_hex_word(result_value, byte_index, pcs_status_value);
        put_uart_text(result_value, byte_index, " PHY_STATUS=");
        put_uart_hex_word(result_value, byte_index, phy_status_value);
        put_uart_text(result_value, byte_index, " PHYCR=");
        put_uart_hex_word(result_value, byte_index, phycr_value);
        put_uart_text(result_value, byte_index, " CFG1=");
        put_uart_hex_word(result_value, byte_index, cfg1_value);
        put_uart_text(result_value, byte_index, " BMCR=");
        put_uart_hex_word(result_value, byte_index, bmcr_value);
        put_uart_text(result_value, byte_index, " BMSR=");
        put_uart_hex_word(result_value, byte_index, bmsr_value);
        put_uart_text(result_value, byte_index, " ANAR=");
        put_uart_hex_word(result_value, byte_index, anar_value);
        put_uart_text(result_value, byte_index, " ANLPAR=");
        put_uart_hex_word(result_value, byte_index, anlpar_value);
        put_uart_text(result_value, byte_index, " ANER=");
        put_uart_hex_word(result_value, byte_index, aner_value);
        put_uart_text(result_value, byte_index, " STS1=");
        put_uart_hex_word(result_value, byte_index, sts1_value);
        put_uart_text(result_value, byte_index, " RECR=");
        put_uart_hex_word(result_value, byte_index, recr_value);
        put_uart_text(result_value, byte_index, " CFG4=");
        put_uart_hex_word(result_value, byte_index, cfg4_value);
        put_uart_text(result_value, byte_index, " STRAP_STS2=");
        put_uart_hex_word(result_value, byte_index, strap2_value);
        put_uart_text(result_value, byte_index, " ANA_LD_DATA_CTRL=");
        put_uart_hex_word(result_value, byte_index, ana_ld_value);
        put_uart_char(result_value, byte_index, CR);
        put_uart_char(result_value, byte_index, LF);

        assert byte_index = UART_MESSAGE_BYTES
            report "UART_MESSAGE_BYTES does not match the formatted message"
            severity failure;
        return result_value;
    end function;

    component gig_ethernet_pcs_pma_0 is
        port (
            sgmii_clk_r_0          : out std_logic;
            sgmii_clk_f_0          : out std_logic;
            sgmii_clk_en_0         : out std_logic;
            clk125_out             : out std_logic;
            clk312_out             : out std_logic;
            rst_125_out            : out std_logic;
            refclk625_n            : in  std_logic;
            refclk625_p            : in  std_logic;
            speed_is_10_100_0      : in  std_logic;
            speed_is_100_0         : in  std_logic;
            reset                  : in  std_logic;
            txn_0                  : out std_logic;
            rxn_0                  : in  std_logic;
            gmii_txd_0             : in  std_logic_vector(7 downto 0);
            gmii_rxd_0             : out std_logic_vector(7 downto 0);
            txp_0                  : out std_logic;
            gmii_rx_dv_0           : out std_logic;
            gmii_rx_er_0           : out std_logic;
            gmii_isolate_0         : out std_logic;
            rxp_0                  : in  std_logic;
            signal_detect_0        : in  std_logic;
            gmii_tx_en_0           : in  std_logic;
            gmii_tx_er_0           : in  std_logic;
            configuration_vector_0 : in  std_logic_vector(4 downto 0);
            status_vector_0        : out std_logic_vector(15 downto 0);
            an_adv_config_vector_0 : in  std_logic_vector(15 downto 0);
            an_restart_config_0    : in  std_logic;
            an_interrupt_0         : out std_logic;
            tx_dly_rdy_1            : in  std_logic;
            rx_dly_rdy_1            : in  std_logic;
            tx_vtc_rdy_1            : in  std_logic;
            rx_vtc_rdy_1            : in  std_logic;
            tx_dly_rdy_2            : in  std_logic;
            rx_dly_rdy_2            : in  std_logic;
            tx_vtc_rdy_2            : in  std_logic;
            rx_vtc_rdy_2            : in  std_logic;
            tx_dly_rdy_3            : in  std_logic;
            rx_dly_rdy_3            : in  std_logic;
            tx_vtc_rdy_3            : in  std_logic;
            rx_vtc_rdy_3            : in  std_logic;
            tx_logic_reset          : out std_logic;
            rx_logic_reset          : out std_logic;
            rx_locked               : out std_logic;
            tx_locked               : out std_logic;
            tx_bsc_rst_out          : out std_logic;
            rx_bsc_rst_out          : out std_logic;
            tx_bs_rst_out           : out std_logic;
            rx_bs_rst_out           : out std_logic;
            tx_rst_dly_out          : out std_logic;
            rx_rst_dly_out          : out std_logic;
            tx_bsc_en_vtc_out       : out std_logic;
            rx_bsc_en_vtc_out       : out std_logic;
            tx_bs_en_vtc_out        : out std_logic;
            rx_bs_en_vtc_out        : out std_logic;
            riu_clk_out             : out std_logic;
            riu_wr_en_out           : out std_logic;
            tx_pll_clk_out          : out std_logic;
            rx_pll_clk_out          : out std_logic;
            tx_rdclk_out            : out std_logic;
            riu_addr_out            : out std_logic_vector(5 downto 0);
            riu_wr_data_out         : out std_logic_vector(15 downto 0);
            riu_nibble_sel_out      : out std_logic_vector(1 downto 0);
            rx_btval_1             : out std_logic_vector(8 downto 0);
            rx_btval_2             : out std_logic_vector(8 downto 0);
            rx_btval_3             : out std_logic_vector(8 downto 0);
            riu_valid_3            : in  std_logic;
            riu_valid_2            : in  std_logic;
            riu_valid_1            : in  std_logic;
            riu_prsnt_1            : in  std_logic;
            riu_prsnt_2            : in  std_logic;
            riu_prsnt_3            : in  std_logic;
            riu_rddata_3           : in  std_logic_vector(15 downto 0);
            riu_rddata_1           : in  std_logic_vector(15 downto 0);
            riu_rddata_2           : in  std_logic_vector(15 downto 0)
        );
    end component;

    constant ONE_SECOND_CYCLES : positive := 125_000_000;

    signal board_clk125 : std_logic;

    signal phy_config_done : std_logic;
    signal phy_link_up     : std_logic;
    signal phy_status      : std_logic_vector(15 downto 0);
    signal phy_control     : std_logic_vector(15 downto 0);
    signal phy_cfg1        : std_logic_vector(15 downto 0);
    signal phy_bmcr        : std_logic_vector(15 downto 0);
    signal phy_bmsr        : std_logic_vector(15 downto 0);
    signal phy_anar        : std_logic_vector(15 downto 0);
    signal phy_anlpar      : std_logic_vector(15 downto 0);
    signal phy_aner        : std_logic_vector(15 downto 0);
    signal phy_sts1        : std_logic_vector(15 downto 0);
    signal phy_recr        : std_logic_vector(15 downto 0);
    signal phy_cfg4        : std_logic_vector(15 downto 0);
    signal phy_strap2      : std_logic_vector(15 downto 0);
    signal phy_ana_ld      : std_logic_vector(15 downto 0);
    signal phy_init_error  : std_logic;

    signal pcs_reset       : std_logic;
    signal pcs_clk125      : std_logic;
    signal pcs_rst125      : std_logic;
    signal pcs_clk_enable  : std_logic;
    signal pcs_status      : std_logic_vector(15 downto 0);
    signal pcs_status_meta : std_logic_vector(15 downto 0) := (others => '0');
    signal pcs_status_uart : std_logic_vector(15 downto 0) := (others => '0');
    signal pcs_link_up     : std_logic;
    signal client_reset    : std_logic;
    signal speed_is_10_100 : std_logic;
    signal speed_is_100    : std_logic;

    signal gmii_txd   : std_logic_vector(7 downto 0);
    signal gmii_tx_en : std_logic;
    signal gmii_tx_er : std_logic;
    signal gmii_rxd   : std_logic_vector(7 downto 0);
    signal gmii_rx_dv : std_logic;
    signal gmii_rx_er : std_logic;

    signal udp_valid            : std_logic := '0';
    signal udp_ready            : std_logic;
    signal frame_sent           : std_logic;
    signal second_count         : natural range 0 to ONE_SECOND_CYCLES - 1 := 0;
    signal tx_activity          : std_logic := '0';
    signal rx_activity          : std_logic := '0';
    signal rx_dv_delayed        : std_logic := '0';
    signal rx_carrier_extension : std_logic;
    signal rx_error_seen        : std_logic := '0';
    signal rx_error_trigger     : std_logic;
    signal uart_vector          : std_logic_vector(
        UART_MESSAGE_BYTES * 8 - 1 downto 0) := (others => '0');
begin
    -- The active-low PDWN pin is shared with the PHY interrupt function.
    -- Driving it high releases power-down; this example does not use INT.
    phy1_pdwn_b_i_int_b_o <= '1';

    board_clock_buffer : IBUFGDS
        port map (
            I  => clk_125_p,
            IB => clk_125_n,
            O  => board_clk125
        );

    phy_init_i : entity work.dp83867_sgmii_init
        generic map (
            CLK_FREQ_HZ => 125_000_000,
            MDC_FREQ_HZ => 2_500_000,
            PHY_ADDR    => "00011"
        )
        port map (
            clk         => board_clk125,
            rst         => cpu_reset,
            phy_rst_n   => phy1_reset_b,
            mdc         => phy1_mdc,
            mdio        => phy1_mdio,
            config_done => phy_config_done,
            link_up     => phy_link_up,
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
            error       => phy_init_error
        );

    -- PCS status is generated in the PCS client clock domain.  It changes only
    -- when link state or negotiation changes, so synchronize it into the fixed
    -- board-clock domain used by the UART debug transmitter.
    pcs_status_synchronizer : process(board_clk125)
    begin
        if rising_edge(board_clk125) then
            if cpu_reset = '1' then
                pcs_status_meta <= (others => '0');
                pcs_status_uart <= (others => '0');
            else
                pcs_status_meta <= pcs_status;
                pcs_status_uart <= pcs_status_meta;
            end if;
        end if;
    end process pcs_status_synchronizer;

    uart_debug_i : entity work.uart_tx_vector
        generic map (
            CLOCK_SPEED_IN_MHZ    => 125,
            BAUD_RATE             => 9600,
            PAUSE_BEFORE          => 5,
            VECTOR_WIDTH_IN_BYTES => UART_MESSAGE_BYTES
        )
        port map (
            clk       => board_clk125,
            rst       => cpu_reset,
            tx_out    => usb_uart_rx_fpga_tx_ls,
            vector_in => uart_vector
        );

    -- Each byte is stored low byte first, as required by uart_tx_vector:
    -- "PCS_STATUS=... PHY_STATUS=... PHYCR=... CFG1=... BMCR=... BMSR=..."
    -- " ANAR=... ANLPAR=... ANER=... STS1=... RECR=... CFG4=..."
    -- " STRAP_STS2=... ANA_LD_DATA_CTRL=...\r\n"
    uart_vector <= build_uart_message(
        pcs_status_uart, phy_status, phy_control, phy_cfg1, phy_bmcr,
        phy_bmsr, phy_anar, phy_anlpar, phy_aner, phy_sts1, phy_recr,
        phy_cfg4, phy_strap2, phy_ana_ld);

    -- Hold the PCS in reset until MDIO has enabled the PHY's differential
    -- 625-MHz SGMII clock.
    pcs_reset    <= cpu_reset or not phy_config_done;
    pcs_link_up  <= pcs_status(0);
    client_reset <= pcs_rst125 or not pcs_link_up;

    -- RX_ER with RX_DV low and RXD=0x0F is the normal 1000BASE-X carrier
    -- extension indication, not a receive error.
    rx_carrier_extension <= '1' when gmii_rx_er = '1' and
                                     gmii_rx_dv = '0' and
                                     gmii_rxd = x"0F" else '0';
    rx_error_trigger <= gmii_rx_er and not rx_carrier_extension;

    -- status[11:10] is the negotiated SGMII speed:
    -- 10=1G, 01=100M, 00=10M.
    speed_is_10_100 <= not pcs_status(11);
    speed_is_100    <= pcs_status(10);

    pcs_i : gig_ethernet_pcs_pma_0
        port map (
            sgmii_clk_r_0          => open,
            sgmii_clk_f_0          => open,
            sgmii_clk_en_0         => pcs_clk_enable,
            clk125_out             => pcs_clk125,
            clk312_out             => open,
            rst_125_out            => pcs_rst125,
            refclk625_n            => phy1_sgmii_clk_n,
            refclk625_p            => phy1_sgmii_clk_p,
            speed_is_10_100_0      => speed_is_10_100,
            speed_is_100_0         => speed_is_100,
            reset                  => pcs_reset,
            txn_0                  => phy1_sgmii_out_n,
            rxn_0                  => phy1_sgmii_in_n,
            gmii_txd_0             => gmii_txd,
            gmii_rxd_0             => gmii_rxd,
            txp_0                  => phy1_sgmii_out_p,
            gmii_rx_dv_0           => gmii_rx_dv,
            gmii_rx_er_0           => gmii_rx_er,
            gmii_isolate_0         => open,
            rxp_0                  => phy1_sgmii_in_p,
            signal_detect_0        => '1',
            gmii_tx_en_0           => gmii_tx_en,
            gmii_tx_er_0           => gmii_tx_er,
            configuration_vector_0 => "10000",
            status_vector_0        => pcs_status,
            -- In SGMII MAC mode Register 4 is fixed to 0x0001 and this
            -- input is ignored, but drive the standard value explicitly.
            an_adv_config_vector_0 => x"0001",
            an_restart_config_0    => '0',
            an_interrupt_0         => open,
            tx_dly_rdy_1            => '1',
            rx_dly_rdy_1            => '1',
            tx_vtc_rdy_1            => '1',
            rx_vtc_rdy_1            => '1',
            tx_dly_rdy_2            => '1',
            rx_dly_rdy_2            => '1',
            tx_vtc_rdy_2            => '1',
            rx_vtc_rdy_2            => '1',
            tx_dly_rdy_3            => '1',
            rx_dly_rdy_3            => '1',
            tx_vtc_rdy_3            => '1',
            rx_vtc_rdy_3            => '1',
            tx_logic_reset          => open,
            rx_logic_reset          => open,
            rx_locked               => open,
            tx_locked               => open,
            tx_bsc_rst_out          => open,
            rx_bsc_rst_out          => open,
            tx_bs_rst_out           => open,
            rx_bs_rst_out           => open,
            tx_rst_dly_out          => open,
            rx_rst_dly_out          => open,
            tx_bsc_en_vtc_out       => open,
            rx_bsc_en_vtc_out       => open,
            tx_bs_en_vtc_out        => open,
            rx_bs_en_vtc_out        => open,
            riu_clk_out             => open,
            riu_wr_en_out           => open,
            tx_pll_clk_out          => open,
            rx_pll_clk_out          => open,
            tx_rdclk_out            => open,
            riu_addr_out            => open,
            riu_wr_data_out         => open,
            riu_nibble_sel_out      => open,
            rx_btval_1             => open,
            rx_btval_2             => open,
            rx_btval_3             => open,
            riu_valid_3            => '0',
            riu_valid_2            => '0',
            riu_valid_1            => '0',
            riu_prsnt_1            => '0',
            riu_prsnt_2            => '0',
            riu_prsnt_3            => '0',
            riu_rddata_3           => (others => '0'),
            riu_rddata_1           => (others => '0'),
            riu_rddata_2           => (others => '0')
        );

    udp_tx_i : entity work.udp_to_gmii
        generic map (
            UDP_PAYLOAD_BYTE_COUNT  => UDP_PAYLOAD'length / 8,
            SOURCE_MAC_ADDRESS      => SOURCE_MAC_ADDRESS,
            DESTINATION_MAC_ADDRESS => DESTINATION_MAC_ADDRESS,
            SOURCE_IP_ADDRESS       => SOURCE_IP_ADDRESS,
            DESTINATION_IP_ADDRESS  => DESTINATION_IP_ADDRESS,
            SOURCE_UDP_PORT         => SOURCE_UDP_PORT,
            DESTINATION_UDP_PORT    => DESTINATION_UDP_PORT
        )
        port map (
            clk          => pcs_clk125,
            rst          => client_reset,
            clk_enable   => pcs_clk_enable,
            udp_valid    => udp_valid,
            udp_payload  => UDP_PAYLOAD,
            udp_ready    => udp_ready,
            frame_sent   => frame_sent,
            gmii_tx_en   => gmii_tx_en,
            gmii_txd     => gmii_txd,
            gmii_tx_er   => gmii_tx_er
        );

    -- Transmit one frame per second after SGMII synchronization and
    -- auto-negotiation have completed.
    periodic_sender : process(pcs_clk125)
    begin
        if rising_edge(pcs_clk125) then
            if client_reset = '1' then
                second_count <= 0;
                udp_valid    <= '0';
            else
                if udp_valid = '1' and udp_ready = '1' then
                    udp_valid <= '0';
                end if;

                if second_count = ONE_SECOND_CYCLES - 1 then
                    second_count <= 0;
                    udp_valid    <= '1';
                else
                    second_count <= second_count + 1;
                end if;
            end if;
        end if;
    end process periodic_sender;

    activity_monitor : process(pcs_clk125)
    begin
        if rising_edge(pcs_clk125) then
            if client_reset = '1' then
                tx_activity    <= '0';
                rx_activity    <= '0';
                rx_dv_delayed  <= '0';
                rx_error_seen  <= '0';
            else
                if frame_sent = '1' then
                    tx_activity <= not tx_activity;
                end if;
                if gmii_rx_dv = '1' and rx_dv_delayed = '0' and
                   pcs_clk_enable = '1' then
                    rx_activity <= not rx_activity;
                end if;
                if pcs_clk_enable = '1' then
                    rx_dv_delayed <= gmii_rx_dv;
                end if;

                if rx_error_trigger = '1' then
                    rx_error_seen <= '1';
                end if;
            end if;
        end if;
    end process activity_monitor;

    gpio_led_0 <= phy_config_done;
    gpio_led_1 <= phy_link_up;
    gpio_led_2 <= pcs_link_up;
    gpio_led_3 <= tx_activity;
    gpio_led_4 <= rx_activity;
    gpio_led_5 <= rx_error_seen;
    gpio_led_6 <= phy_init_error;
    gpio_led_7 <= pcs_status(11); -- high for negotiated 1-Gb/s operation
end architecture rtl;
