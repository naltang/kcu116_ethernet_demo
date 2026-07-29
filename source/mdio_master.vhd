-- Converted to VHDL-2008 from the Verilog source:
--
-- github.com/alexforencich/verilog-ethernet/blob/master/example/VCU118/
-- fpga_1g/rtl/mdio_master.v

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--
-- frequency(mdc) = frequency(clk) / (2 * (1 + prescale))
--
-- Example:
--     2.5 MHz    =    125 MHz     / (2 * (1 + 24))
--

entity mdio_master is
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;

        cmd_phy_addr   : in  std_logic_vector(4 downto 0);
        cmd_reg_addr   : in  std_logic_vector(4 downto 0);
        cmd_data       : in  std_logic_vector(15 downto 0);
        cmd_opcode     : in  std_logic_vector(1 downto 0);
        cmd_valid      : in  std_logic;
        cmd_ready      : out std_logic;

        data_out       : out std_logic_vector(15 downto 0);
        data_out_valid : out std_logic;
        data_out_ready : in  std_logic;

        mdc_o          : out std_logic;
        mdio_i         : in  std_logic;
        mdio_o         : out std_logic;
        mdio_t         : out std_logic;

        busy           : out std_logic;

        prescale       : in  natural range 0 to 255
    );
end entity mdio_master;

architecture rtl of mdio_master is
    type state_t is (IDLE, PREAMBLE, TRANSFER);
    constant CLAUSE22_WRITE_OPCODE : std_logic_vector(1 downto 0) := "01";
    constant CLAUSE22_READ_OPCODE  : std_logic_vector(1 downto 0) := "10";
    constant CLAUSE45_READ_OPCODE  : std_logic_vector(1 downto 0) := "11";

    signal state_reg  : state_t := IDLE;
    signal state_next : state_t := IDLE;

    signal count_reg      : natural range 0 to 255 := 0;
    signal count_next     : natural range 0 to 255 := 0;
    signal bit_count_reg  : natural range 0 to 32 := 0;
    signal bit_count_next : natural range 0 to 32 := 0;
    signal cycle_reg      : std_logic := '0';
    signal cycle_next     : std_logic := '0';

    signal data_reg  : std_logic_vector(31 downto 0) := (others => '0');
    signal data_next : std_logic_vector(31 downto 0) := (others => '0');
    signal op_reg    : std_logic_vector(1 downto 0) := "00";
    signal op_next   : std_logic_vector(1 downto 0) := "00";

    signal cmd_ready_reg       : std_logic := '0';
    signal cmd_ready_next      : std_logic := '0';
    signal data_out_reg        : std_logic_vector(15 downto 0) :=
        (others => '0');
    signal data_out_next       : std_logic_vector(15 downto 0) :=
        (others => '0');
    signal data_out_valid_reg  : std_logic := '0';
    signal data_out_valid_next : std_logic := '0';

    signal mdio_i_reg : std_logic := '1';

    signal mdc_o_reg   : std_logic := '0';
    signal mdc_o_next  : std_logic := '0';
    signal mdio_o_reg  : std_logic := '0';
    signal mdio_o_next : std_logic := '0';
    signal mdio_t_reg  : std_logic := '1';
    signal mdio_t_next : std_logic := '1';

begin
    cmd_ready      <= cmd_ready_reg;
    data_out       <= data_out_reg;
    data_out_valid <= data_out_valid_reg;
    mdc_o          <= mdc_o_reg;
    mdio_o         <= mdio_o_reg;
    mdio_t         <= mdio_t_reg;
    busy <= '1' when (
        state_reg /= IDLE or count_reg /= 0 or cycle_reg = '1' or
        mdc_o_reg = '1') else '0';

    combinational_logic : process(all)
    begin
        state_next <= IDLE;

        count_next     <= count_reg;
        bit_count_next <= bit_count_reg;
        cycle_next     <= cycle_reg;

        data_next <= data_reg;
        op_next   <= op_reg;

        cmd_ready_next <= '0';

        data_out_next       <= data_out_reg;
        data_out_valid_next <= data_out_valid_reg and not data_out_ready;

        mdc_o_next  <= mdc_o_reg;
        mdio_o_next <= mdio_o_reg;
        mdio_t_next <= mdio_t_reg;

        if count_reg > 0 then
            count_next <= count_reg - 1;
            state_next <= state_reg;
        elsif cycle_reg = '1' then
            cycle_next <= '0';
            mdc_o_next <= '1';
            count_next <= prescale;
            state_next <= state_reg;
        else
            mdc_o_next <= '0';
            case state_reg is
                when IDLE =>
                    cmd_ready_next <= not data_out_valid_reg;

                    if cmd_ready_reg = '1' and cmd_valid = '1' then
                        cmd_ready_next <= '0';
                        data_next <=
                            "01" & cmd_opcode & cmd_phy_addr & cmd_reg_addr &
                            "10" & cmd_data;
                        op_next        <= cmd_opcode;
                        mdio_t_next    <= '0';
                        mdio_o_next    <= '1';
                        bit_count_next <= 32;
                        cycle_next     <= '1';
                        count_next     <= prescale;
                        state_next     <= PREAMBLE;
                    else
                        state_next <= IDLE;
                        cycle_next <= '0';
                    end if;

                when PREAMBLE =>
                    cycle_next <= '1';
                    count_next <= prescale;
                    if bit_count_reg > 1 then
                        bit_count_next <= bit_count_reg - 1;
                        state_next     <= PREAMBLE;
                    else
                        bit_count_next <= 32;
                        mdio_o_next    <= data_reg(31);
                        data_next      <= data_reg(30 downto 0) & mdio_i_reg;
                        state_next     <= TRANSFER;
                    end if;

                when TRANSFER =>
                    cycle_next <= '1';
                    count_next <= prescale;
                    if (op_reg = CLAUSE22_READ_OPCODE or
                        op_reg = CLAUSE45_READ_OPCODE) and
                       bit_count_reg = 19 then
                        mdio_t_next <= '1';
                    end if;
                    if bit_count_reg > 1 then
                        bit_count_next <= bit_count_reg - 1;
                        mdio_o_next    <= data_reg(31);
                        data_next      <= data_reg(30 downto 0) & mdio_i_reg;
                        state_next     <= TRANSFER;
                    else
                        if op_reg = CLAUSE22_READ_OPCODE or
                           op_reg = CLAUSE45_READ_OPCODE then
                            data_out_next       <= data_reg(15 downto 0);
                            data_out_valid_next <= '1';
                        end if;
                        mdio_t_next <= '1';
                        state_next <= IDLE;
                    end if;
            end case;
        end if;
    end process combinational_logic;

    sequential_logic : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state_reg          <= IDLE;
                count_reg          <= 0;
                bit_count_reg      <= 0;
                cycle_reg          <= '0';
                data_reg           <= (others => '0');
                op_reg             <= (others => '0');
                cmd_ready_reg      <= '0';
                data_out_reg       <= (others => '0');
                data_out_valid_reg <= '0';
                mdio_i_reg         <= '1';
                mdc_o_reg          <= '0';
                mdio_o_reg         <= '0';
                mdio_t_reg         <= '1';
            else
                state_reg          <= state_next;
                count_reg          <= count_next;
                bit_count_reg      <= bit_count_next;
                cycle_reg          <= cycle_next;
                cmd_ready_reg      <= cmd_ready_next;
                data_reg           <= data_next;
                op_reg             <= op_next;
                data_out_reg       <= data_out_next;
                data_out_valid_reg <= data_out_valid_next;
                mdio_i_reg         <= mdio_i;
                mdc_o_reg          <= mdc_o_next;
                mdio_o_reg         <= mdio_o_next;
                mdio_t_reg         <= mdio_t_next;
            end if;
        end if;
    end process sequential_logic;
end architecture rtl;
