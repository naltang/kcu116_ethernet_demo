library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dp83867_pkg.all;
use work.debug_status_pkg.all;

library unisim;
use unisim.vcomponents.all;

entity ethernet_demo is
    generic (
        CLOCK_FREQ_HZ            : positive := 125_000_000;
        FRAME_PERIOD_CYCLES      : positive := 125_000_000;
        SOURCE_MAC_ADDRESS       : std_logic_vector(47 downto 0) := x"020000000001";
        DESTINATION_MAC_ADDRESS  : std_logic_vector(47 downto 0) := x"FFFFFFFFFFFF";
        SOURCE_IP_ADDRESS        : std_logic_vector(31 downto 0) := x"01020364";
        DESTINATION_IP_ADDRESS   : std_logic_vector(31 downto 0) := x"01020304";
        SOURCE_UDP_PORT          : natural range 0 to 65535 := 1234;
        DESTINATION_UDP_PORT     : natural range 0 to 65535 := 5678
    );
    port (
        clk_125_p : in  std_logic;
        clk_125_n : in  std_logic;
        cpu_reset : in  std_logic;

        uart_tx : out std_logic;

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
end entity ethernet_demo;

architecture rtl of ethernet_demo is
    constant UDP_PAYLOAD : std_logic_vector(34 * 8 - 1 downto 0) :=
        x"48656C6C6F20776F726C6421202D2D2066726F6D20616E204650474120626F617264";
		-- This is a hex string of "Hello world! -- from an FPGA board"

    signal board_clk125 : std_logic;
    signal board_reset  : std_logic;

    signal phy_config_done : std_logic;
    signal phy_link_up     : std_logic;
    signal phy_diagnostics : phy_diagnostics_t := PHY_DIAGNOSTICS_RESET;
    signal phy_init_error  : std_logic;

    signal pcs_reset        : std_logic;
    signal pcs_clk125       : std_logic;
    signal pcs_rst125       : std_logic;
    signal pcs_clk_enable   : std_logic;
    signal pcs_status       : std_logic_vector(15 downto 0);
    signal pcs_status_uart  : std_logic_vector(15 downto 0);
    signal pcs_link_up      : std_logic;
    signal client_async_rst : std_logic;
    signal client_reset     : std_logic;
    signal statistics_reset : std_logic;
    signal speed_is_10_100  : std_logic;
    signal speed_is_100     : std_logic;

    signal gmii_txd   : std_logic_vector(7 downto 0);
    signal gmii_tx_en : std_logic;
    signal gmii_tx_er : std_logic;
    signal gmii_rxd   : std_logic_vector(7 downto 0);
    signal gmii_rx_dv : std_logic;
    signal gmii_rx_er : std_logic;

    signal udp_valid    : std_logic := '0';
    signal udp_ready    : std_logic;
    signal frame_sent   : std_logic;
    signal second_count : natural range 0 to FRAME_PERIOD_CYCLES - 1 := 0;

    signal frame_sent_count_pcs : unsigned(15 downto 0);
    signal recv_count_pcs       : unsigned(15 downto 0);
    signal recv_fcs_error_count_pcs : unsigned(15 downto 0);
    signal recv_error_count_pcs : unsigned(15 downto 0);
    signal frame_sent_count_uart : unsigned(15 downto 0);
    signal recv_count_uart       : unsigned(15 downto 0);
    signal recv_fcs_error_count_uart : unsigned(15 downto 0);
    signal recv_error_count_uart : unsigned(15 downto 0);
    signal recv_started          : std_logic;
    signal recv_error_event      : std_logic;

    signal debug_status : debug_status_t := DEBUG_STATUS_RESET;
    signal uart_data    : std_logic_vector(7 downto 0);
    signal uart_valid   : std_logic;
    signal uart_ready   : std_logic;
    signal uart_snapshot : std_logic;

    signal tx_activity  : std_logic := '0';
    signal rx_activity  : std_logic := '0';
    signal rx_error_seen : std_logic := '0';
begin
    phy1_pdwn_b_i_int_b_o <= '1';

    board_clock_buffer : IBUFGDS
        port map (
            I  => clk_125_p,
            IB => clk_125_n,
            O  => board_clk125
        );

    board_reset_i : entity work.reset_synchronizer
        port map (
            clk       => board_clk125,
            async_rst => cpu_reset,
            sync_rst  => board_reset
        );

    phy_init_i : entity work.dp83867_sgmii_init
        generic map (
            CLK_FREQ_HZ => CLOCK_FREQ_HZ,
            MDC_FREQ_HZ => 2_500_000,
            PHY_ADDR    => "00011"
        )
        port map (
            clk         => board_clk125,
            rst         => board_reset,
            clear_isr   => uart_snapshot,
            phy_rst_n   => phy1_reset_b,
            mdc         => phy1_mdc,
            mdio        => phy1_mdio,
            config_done => phy_config_done,
            link_up     => phy_link_up,
            diagnostics => phy_diagnostics,
            error       => phy_init_error
        );

    pcs_reset        <= board_reset or not phy_config_done;
    pcs_link_up      <= pcs_status(0);
    client_async_rst <= cpu_reset or pcs_rst125 or not pcs_link_up;
    speed_is_10_100  <= not pcs_status(11);
    speed_is_100     <= pcs_status(10);

    client_reset_i : entity work.reset_synchronizer
        port map (
            clk       => pcs_clk125,
            async_rst => client_async_rst,
            sync_rst  => client_reset
        );

    statistics_reset_i : entity work.reset_synchronizer
        port map (
            clk       => pcs_clk125,
            async_rst => cpu_reset,
            sync_rst  => statistics_reset
        );

    pcs_i : entity work.pcs_pma_wrapper
        port map (
            reset           => pcs_reset,
            refclk625_p     => phy1_sgmii_clk_p,
            refclk625_n     => phy1_sgmii_clk_n,
            speed_is_10_100 => speed_is_10_100,
            speed_is_100    => speed_is_100,
            sgmii_rx_p      => phy1_sgmii_in_p,
            sgmii_rx_n      => phy1_sgmii_in_n,
            sgmii_tx_p      => phy1_sgmii_out_p,
            sgmii_tx_n      => phy1_sgmii_out_n,
            client_clk      => pcs_clk125,
            client_rst      => pcs_rst125,
            client_enable   => pcs_clk_enable,
            gmii_txd        => gmii_txd,
            gmii_tx_en      => gmii_tx_en,
            gmii_tx_er      => gmii_tx_er,
            gmii_rxd        => gmii_rxd,
            gmii_rx_dv      => gmii_rx_dv,
            gmii_rx_er      => gmii_rx_er,
            status          => pcs_status
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

    statistics_i : entity work.ethernet_statistics
        port map (
            clk              => pcs_clk125,
            rst              => statistics_reset,
            active           => not client_reset,
            clk_enable       => pcs_clk_enable,
            frame_sent       => frame_sent,
            gmii_rxd         => gmii_rxd,
            rx_dv            => gmii_rx_dv,
            rx_er            => gmii_rx_er,
            recv_started     => recv_started,
            recv_error_event => recv_error_event,
            frame_sent_count => frame_sent_count_pcs,
            recv_count       => recv_count_pcs,
            recv_fcs_error_count => recv_fcs_error_count_pcs,
            recv_error_count => recv_error_count_pcs
        );

    frame_count_cdc_i : entity work.gray_counter_cdc
        port map (
            source_count => frame_sent_count_pcs,
            dest_clk     => board_clk125,
            dest_rst     => board_reset,
            dest_count   => frame_sent_count_uart
        );

    recv_count_cdc_i : entity work.gray_counter_cdc
        port map (
            source_count => recv_count_pcs,
            dest_clk     => board_clk125,
            dest_rst     => board_reset,
            dest_count   => recv_count_uart
        );

    recv_fcs_error_count_cdc_i : entity work.gray_counter_cdc
        port map (
            source_count => recv_fcs_error_count_pcs,
            dest_clk     => board_clk125,
            dest_rst     => board_reset,
            dest_count   => recv_fcs_error_count_uart
        );

    recv_error_count_cdc_i : entity work.gray_counter_cdc
        port map (
            source_count => recv_error_count_pcs,
            dest_clk     => board_clk125,
            dest_rst     => board_reset,
            dest_count   => recv_error_count_uart
        );

    pcs_status_cdc_i : entity work.status_snapshot_cdc
        port map (
            source_clk  => pcs_clk125,
            source_rst  => client_reset,
            source_data => pcs_status,
            dest_clk    => board_clk125,
            dest_rst    => board_reset,
            dest_data   => pcs_status_uart
        );

    debug_status.frame_sent_count <=
        std_logic_vector(frame_sent_count_uart);
    debug_status.recv_count       <= std_logic_vector(recv_count_uart);
    debug_status.recv_fcs_error_count <=
        std_logic_vector(recv_fcs_error_count_uart);
    debug_status.recv_error_count <=
        std_logic_vector(recv_error_count_uart);
    debug_status.pcs_status <= pcs_status_uart;
    debug_status.phy        <= phy_diagnostics;

    uart_report_i : entity work.uart_status_report
        generic map (
            CLOCK_FREQ_HZ   => CLOCK_FREQ_HZ,
            BAUD_RATE       => 9600,
            PAUSE_BIT_TIMES => 5
        )
        port map (
            clk        => board_clk125,
            rst        => board_reset,
            status     => debug_status,
            snapshot_taken => uart_snapshot,
            data_out   => uart_data,
            data_valid => uart_valid,
            data_ready => uart_ready
        );

    uart_tx_i : entity work.uart_tx
        generic map (
            CLOCK_FREQ_HZ => CLOCK_FREQ_HZ,
            BAUD_RATE     => 9600
        )
        port map (
            clk        => board_clk125,
            rst        => board_reset,
            data_in    => uart_data,
            data_valid => uart_valid,
            data_ready => uart_ready,
            tx_out     => uart_tx
        );

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

                if second_count = FRAME_PERIOD_CYCLES - 1 then
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
                tx_activity   <= '0';
                rx_activity   <= '0';
                rx_error_seen <= '0';
            else
                if frame_sent = '1' then
                    tx_activity <= not tx_activity;
                end if;
                if recv_started = '1' then
                    rx_activity <= not rx_activity;
                end if;
                if recv_error_event = '1' then
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
    gpio_led_7 <= pcs_status(11);
end architecture rtl;
