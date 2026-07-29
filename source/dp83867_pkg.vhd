library ieee;
use ieee.std_logic_1164.all;

package dp83867_pkg is
    subtype mdio_register_address_t is std_logic_vector(4 downto 0);
    subtype mdio_word_t is std_logic_vector(15 downto 0);

    constant MDIO_OP_WRITE : std_logic_vector(1 downto 0) := "01";
    constant MDIO_OP_READ  : std_logic_vector(1 downto 0) := "10";

    constant DP83867_REG_BMCR   : mdio_register_address_t := "00000";
    constant DP83867_REG_BMSR   : mdio_register_address_t := "00001";
    constant DP83867_REG_ANAR   : mdio_register_address_t := "00100";
    constant DP83867_REG_ANLPAR : mdio_register_address_t := "00101";
    constant DP83867_REG_ANER   : mdio_register_address_t := "00110";
    constant DP83867_REG_CFG1   : mdio_register_address_t := "01001";
    constant DP83867_REG_STS1   : mdio_register_address_t := "01010";
    constant DP83867_REG_REGCR  : mdio_register_address_t := "01101";
    constant DP83867_REG_ADDAR  : mdio_register_address_t := "01110";
    constant DP83867_REG_PHYCR  : mdio_register_address_t := "10000";
    constant DP83867_REG_PHYSTS : mdio_register_address_t := "10001";
    constant DP83867_REG_RECR   : mdio_register_address_t := "10101";
    constant DP83867_REG_CTRL   : mdio_register_address_t := "11111";

    constant DP83867_EXT_CFG2             : mdio_word_t := x"0014";
    constant DP83867_EXT_CFG4             : mdio_word_t := x"0031";
    constant DP83867_EXT_RGMIICTL         : mdio_word_t := x"0032";
    constant DP83867_EXT_STRAP_STS2       : mdio_word_t := x"006F";
    constant DP83867_EXT_SGMIICTL1        : mdio_word_t := x"00D3";
    constant DP83867_EXT_ANA_LD_DATA_CTRL : mdio_word_t := x"00DD";
    constant DP83867_EXT_MSE_A            : mdio_word_t := x"0225";
    constant DP83867_EXT_MSE_B            : mdio_word_t := x"0265";
    constant DP83867_EXT_MSE_C            : mdio_word_t := x"02A5";
    constant DP83867_EXT_MSE_D            : mdio_word_t := x"02E5";

    type phy_diagnostics_t is record
        physts           : mdio_word_t;
        phycr            : mdio_word_t;
        cfg1             : mdio_word_t;
        bmcr             : mdio_word_t;
        bmsr             : mdio_word_t;
        anar             : mdio_word_t;
        anlpar           : mdio_word_t;
        aner             : mdio_word_t;
        sts1             : mdio_word_t;
        recr             : mdio_word_t;
        mse_a            : mdio_word_t;
        mse_b            : mdio_word_t;
        mse_c            : mdio_word_t;
        mse_d            : mdio_word_t;
        cfg4             : mdio_word_t;
        strap_sts2       : mdio_word_t;
        ana_ld_data_ctrl : mdio_word_t;
    end record;

    constant PHY_DIAGNOSTICS_RESET : phy_diagnostics_t := (
        physts           => (others => '0'),
        phycr            => (others => '0'),
        cfg1             => (others => '0'),
        bmcr             => (others => '0'),
        bmsr             => (others => '0'),
        anar             => (others => '0'),
        anlpar           => (others => '0'),
        aner             => (others => '0'),
        sts1             => (others => '0'),
        recr             => (others => '0'),
        mse_a            => (others => '0'),
        mse_b            => (others => '0'),
        mse_c            => (others => '0'),
        mse_d            => (others => '0'),
        cfg4             => (others => '0'),
        strap_sts2       => (others => '0'),
        ana_ld_data_ctrl => (others => '0')
    );
end package dp83867_pkg;
