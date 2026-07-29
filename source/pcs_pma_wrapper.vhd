library ieee;
use ieee.std_logic_1164.all;

-- Isolate the generated AMD PCS/PMA port list from the application top level.
entity pcs_pma_wrapper is
    port (
        reset           : in  std_logic;
        refclk625_p     : in  std_logic;
        refclk625_n     : in  std_logic;
        speed_is_10_100 : in  std_logic;
        speed_is_100    : in  std_logic;
        sgmii_rx_p      : in  std_logic;
        sgmii_rx_n      : in  std_logic;
        sgmii_tx_p      : out std_logic;
        sgmii_tx_n      : out std_logic;
        client_clk      : out std_logic;
        client_rst      : out std_logic;
        client_enable   : out std_logic;
        gmii_txd        : in  std_logic_vector(7 downto 0);
        gmii_tx_en      : in  std_logic;
        gmii_tx_er      : in  std_logic;
        gmii_rxd        : out std_logic_vector(7 downto 0);
        gmii_rx_dv      : out std_logic;
        gmii_rx_er      : out std_logic;
        status          : out std_logic_vector(15 downto 0)
    );
end entity pcs_pma_wrapper;

architecture rtl of pcs_pma_wrapper is
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
            tx_dly_rdy_1           : in  std_logic;
            rx_dly_rdy_1           : in  std_logic;
            tx_vtc_rdy_1           : in  std_logic;
            rx_vtc_rdy_1           : in  std_logic;
            tx_dly_rdy_2           : in  std_logic;
            rx_dly_rdy_2           : in  std_logic;
            tx_vtc_rdy_2           : in  std_logic;
            rx_vtc_rdy_2           : in  std_logic;
            tx_dly_rdy_3           : in  std_logic;
            rx_dly_rdy_3           : in  std_logic;
            tx_vtc_rdy_3           : in  std_logic;
            rx_vtc_rdy_3           : in  std_logic;
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
            rx_btval_1              : out std_logic_vector(8 downto 0);
            rx_btval_2              : out std_logic_vector(8 downto 0);
            rx_btval_3              : out std_logic_vector(8 downto 0);
            riu_valid_3             : in  std_logic;
            riu_valid_2             : in  std_logic;
            riu_valid_1             : in  std_logic;
            riu_prsnt_1             : in  std_logic;
            riu_prsnt_2             : in  std_logic;
            riu_prsnt_3             : in  std_logic;
            riu_rddata_3            : in  std_logic_vector(15 downto 0);
            riu_rddata_1            : in  std_logic_vector(15 downto 0);
            riu_rddata_2            : in  std_logic_vector(15 downto 0)
        );
    end component;
begin
    core : gig_ethernet_pcs_pma_0
        port map (
            sgmii_clk_r_0          => open,
            sgmii_clk_f_0          => open,
            sgmii_clk_en_0         => client_enable,
            clk125_out             => client_clk,
            clk312_out             => open,
            rst_125_out            => client_rst,
            refclk625_n            => refclk625_n,
            refclk625_p            => refclk625_p,
            speed_is_10_100_0      => speed_is_10_100,
            speed_is_100_0         => speed_is_100,
            reset                  => reset,
            txn_0                  => sgmii_tx_n,
            rxn_0                  => sgmii_rx_n,
            gmii_txd_0             => gmii_txd,
            gmii_rxd_0             => gmii_rxd,
            txp_0                  => sgmii_tx_p,
            gmii_rx_dv_0           => gmii_rx_dv,
            gmii_rx_er_0           => gmii_rx_er,
            gmii_isolate_0         => open,
            rxp_0                  => sgmii_rx_p,
            signal_detect_0        => '1',
            gmii_tx_en_0           => gmii_tx_en,
            gmii_tx_er_0           => gmii_tx_er,
            configuration_vector_0 => "10000",
            status_vector_0        => status,
            an_adv_config_vector_0 => x"0001",
            an_restart_config_0    => '0',
            an_interrupt_0         => open,
            tx_dly_rdy_1           => '1',
            rx_dly_rdy_1           => '1',
            tx_vtc_rdy_1           => '1',
            rx_vtc_rdy_1           => '1',
            tx_dly_rdy_2           => '1',
            rx_dly_rdy_2           => '1',
            tx_vtc_rdy_2           => '1',
            rx_vtc_rdy_2           => '1',
            tx_dly_rdy_3           => '1',
            rx_dly_rdy_3           => '1',
            tx_vtc_rdy_3           => '1',
            rx_vtc_rdy_3           => '1',
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
            rx_btval_1              => open,
            rx_btval_2              => open,
            rx_btval_3              => open,
            riu_valid_3             => '0',
            riu_valid_2             => '0',
            riu_valid_1             => '0',
            riu_prsnt_1             => '0',
            riu_prsnt_2             => '0',
            riu_prsnt_3             => '0',
            riu_rddata_3            => (others => '0'),
            riu_rddata_1            => (others => '0'),
            riu_rddata_2            => (others => '0')
        );
end architecture rtl;
