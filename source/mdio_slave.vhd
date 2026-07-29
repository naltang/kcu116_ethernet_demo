library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dp83867_pkg.all;

-- DP83867 register model used with the generic Clause-22 MDIO slave BFM.
entity mdio_slave is
    generic (
        PHY_ADDR              : std_logic_vector(4 downto 0) := "00011";
        SELF_CLEAR_CYCLES     : positive := 10_000;
        EXTENDED_ADDRESS_BITS : positive range 1 to 16 := 10;
        VERBOSE               : boolean := false
    );
    port (
        clk   : in    std_logic;
        rst_n : in    std_logic;
        mdc   : in    std_logic;
        mdio  : inout std_logic
    );
end entity mdio_slave;

architecture sim of mdio_slave is
    type register_array_t is
        array (0 to 31) of std_logic_vector(15 downto 0);
    constant DEFAULT_REGISTERS : register_array_t := (
        0  => x"1100",
        1  => x"782F",
        2  => x"0022",
        3  => x"1611",
        4  => x"01E1",
        5  => x"CDE1",
        6  => x"0067",
        9  => x"1300",
        10 => x"6000",
        16 => x"5C48",
        17 => x"BF02",
        21 => x"0005",
        others => x"0000"
    );
    signal registers : register_array_t := DEFAULT_REGISTERS;

    type extended_register_array_t is array (
        0 to 2 ** EXTENDED_ADDRESS_BITS - 1
    ) of std_logic_vector(15 downto 0);

    function build_default_extended_registers
        return extended_register_array_t is
        variable result : extended_register_array_t := (others => x"0000");
    begin
        result(to_integer(unsigned(
            DP83867_EXT_CFG4(EXTENDED_ADDRESS_BITS - 1 downto 0)))) :=
            x"11F0";
        result(to_integer(unsigned(
            DP83867_EXT_STRAP_STS2(
                EXTENDED_ADDRESS_BITS - 1 downto 0)))) := x"0100";
        result(to_integer(unsigned(
            DP83867_EXT_ANA_LD_DATA_CTRL(
                EXTENDED_ADDRESS_BITS - 1 downto 0)))) := x"0200";
        result(to_integer(unsigned(
            DP83867_EXT_MSE_A(
                EXTENDED_ADDRESS_BITS - 1 downto 0)))) := x"0123";
        result(to_integer(unsigned(
            DP83867_EXT_MSE_B(
                EXTENDED_ADDRESS_BITS - 1 downto 0)))) := x"0145";
        result(to_integer(unsigned(
            DP83867_EXT_MSE_C(
                EXTENDED_ADDRESS_BITS - 1 downto 0)))) := x"0167";
        result(to_integer(unsigned(
            DP83867_EXT_MSE_D(
                EXTENDED_ADDRESS_BITS - 1 downto 0)))) := x"0189";
        return result;
    end function build_default_extended_registers;

    constant DEFAULT_EXTENDED_REGISTERS : extended_register_array_t :=
        build_default_extended_registers;
    signal extended_registers : extended_register_array_t :=
        DEFAULT_EXTENDED_REGISTERS;
    signal extended_address : std_logic_vector(15 downto 0) :=
        (others => '0');

    signal read_addr   : std_logic_vector(4 downto 0) := (others => '0');
    signal read_data   : std_logic_vector(15 downto 0);
    signal write_valid : std_logic := '0';
    signal write_addr  : std_logic_vector(4 downto 0) := (others => '0');
    signal write_data  : std_logic_vector(15 downto 0) := (others => '0');
    signal reset_clear_count   : natural range 0 to SELF_CLEAR_CYCLES := 0;
    signal restart_clear_count : natural range 0 to SELF_CLEAR_CYCLES := 0;

    function extended_index(
        address_value : std_logic_vector(15 downto 0)
    ) return natural is
    begin
        return to_integer(unsigned(
            address_value(EXTENDED_ADDRESS_BITS - 1 downto 0)));
    end function;
begin
    assert EXTENDED_ADDRESS_BITS >= 10
        report "The DP83867 model requires at least ten address bits"
        severity failure;

    bfm : entity work.mdio_slave_bfm
        generic map (
            PHY_ADDR => PHY_ADDR,
            VERBOSE  => VERBOSE
        )
        port map (
            clk             => clk,
            rst_n           => rst_n,
            mdc             => mdc,
            mdio            => mdio,
            reg_read_addr   => read_addr,
            reg_read_data   => read_data,
            reg_write_valid => write_valid,
            reg_write_addr  => write_addr,
            reg_write_data  => write_data
        );

    read_mux : process(all)
    begin
        if is_x(read_addr) then
            read_data <= (others => '0');
        elsif read_addr = DP83867_REG_ADDAR and
              registers(to_integer(unsigned(DP83867_REG_REGCR)))(
                  15 downto 14) = "01" then
            read_data <= extended_registers(
                extended_index(extended_address));
        else
            read_data <= registers(to_integer(unsigned(read_addr)));
        end if;
    end process read_mux;

    register_model : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                registers          <= DEFAULT_REGISTERS;
                extended_registers <= DEFAULT_EXTENDED_REGISTERS;
                extended_address   <= (others => '0');
                reset_clear_count   <= 0;
                restart_clear_count <= 0;
            elsif write_valid = '1' then
                if write_addr = DP83867_REG_ADDAR and
                   registers(to_integer(unsigned(DP83867_REG_REGCR)))(
                       15 downto 14) = "00" then
                    extended_address <= write_data;
                    registers(to_integer(unsigned(DP83867_REG_ADDAR))) <=
                        write_data;
                elsif write_addr = DP83867_REG_ADDAR and
                      registers(to_integer(unsigned(DP83867_REG_REGCR)))(
                          15 downto 14) = "01" then
                    extended_registers(extended_index(extended_address)) <=
                        write_data;
                    registers(to_integer(unsigned(DP83867_REG_ADDAR))) <=
                        write_data;
                else
                    registers(to_integer(unsigned(write_addr))) <=
                        write_data;
                end if;

                if write_addr = DP83867_REG_BMCR and
                   write_data(15) = '1' then
                    reset_clear_count <= SELF_CLEAR_CYCLES;
                elsif write_addr = DP83867_REG_CTRL and
                      write_data(14) = '1' then
                    restart_clear_count <= SELF_CLEAR_CYCLES;
                end if;
            elsif registers(to_integer(unsigned(DP83867_REG_BMCR)))(15) =
                  '1' then
                if reset_clear_count = 0 then
                    registers(to_integer(unsigned(DP83867_REG_BMCR)))(15) <=
                        '0';
                else
                    reset_clear_count <= reset_clear_count - 1;
                end if;
            elsif registers(to_integer(unsigned(DP83867_REG_CTRL)))(14) =
                  '1' then
                if restart_clear_count = 0 then
                    registers(to_integer(unsigned(DP83867_REG_CTRL)))(14) <=
                        '0';
                else
                    restart_clear_count <= restart_clear_count - 1;
                end if;
            end if;
        end if;
    end process register_model;
end architecture sim;
