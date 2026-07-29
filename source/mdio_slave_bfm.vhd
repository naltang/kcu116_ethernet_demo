library ieee;
use ieee.std_logic_1164.all;

-- Generic Clause-22 MDIO slave bus-functional model. Register behavior is
-- supplied by a separate model through the simple read/write interface.
entity mdio_slave_bfm is
    generic (
        PHY_ADDR : std_logic_vector(4 downto 0) := "00011";
        VERBOSE  : boolean := false
    );
    port (
        clk             : in    std_logic;
        rst_n           : in    std_logic;
        mdc             : in    std_logic;
        mdio            : inout std_logic;
        reg_read_addr   : out   std_logic_vector(4 downto 0);
        reg_read_data   : in    std_logic_vector(15 downto 0);
        reg_write_valid : out   std_logic;
        reg_write_addr  : out   std_logic_vector(4 downto 0);
        reg_write_data  : out   std_logic_vector(15 downto 0)
    );
end entity mdio_slave_bfm;

architecture sim of mdio_slave_bfm is
    constant OP_WRITE : std_logic_vector(1 downto 0) := "01";
    constant OP_READ  : std_logic_vector(1 downto 0) := "10";

    type state_t is (
        IDLE, PREAMBLE, START, OP_CODE, PHY_ADDRESS, REG_ADDRESS, TA, DATA
    );
    signal state : state_t := IDLE;

    signal mdc_d1, mdc_d2 : std_logic := '0';
    signal mdc_rising, mdc_falling : std_logic;
    signal mdio_in  : std_logic := '1';
    signal mdio_out : std_logic := '1';
    signal mdio_oe  : std_logic := '0';

    signal bit_count      : natural range 0 to 32 := 0;
    signal shift_reg      : std_logic_vector(15 downto 0) := (others => '0');
    signal opcode_latched : std_logic_vector(1 downto 0) := (others => '0');
    signal phy_latched    : std_logic_vector(4 downto 0) := (others => '0');
    signal reg_latched    : std_logic_vector(4 downto 0) := (others => '0');
    signal read_latched   : std_logic_vector(15 downto 0) := (others => '0');
begin
    mdio    <= mdio_out when mdio_oe = '1' else 'Z';
    mdio_in <= to_x01(mdio);
    reg_read_addr <= reg_latched;

    edge_detector : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                mdc_d1 <= '0';
                mdc_d2 <= '0';
            else
                mdc_d1 <= mdc;
                mdc_d2 <= mdc_d1;
            end if;
        end if;
    end process edge_detector;

    mdc_rising  <= mdc_d1 and not mdc_d2;
    mdc_falling <= not mdc_d1 and mdc_d2;

    protocol_controller : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state           <= IDLE;
                bit_count       <= 0;
                shift_reg       <= (others => '0');
                opcode_latched  <= (others => '0');
                phy_latched     <= (others => '0');
                reg_latched     <= (others => '0');
                read_latched    <= (others => '0');
                mdio_out        <= '1';
                mdio_oe         <= '0';
                reg_write_valid <= '0';
                reg_write_addr  <= (others => '0');
                reg_write_data  <= (others => '0');
            else
                reg_write_valid <= '0';

                if mdc_rising = '1' then
                    case state is
                        when IDLE =>
                            if mdio_in = '1' then
                                bit_count <= 1;
                                state     <= PREAMBLE;
                            end if;

                        when PREAMBLE =>
                            if mdio_in = '1' then
                                if bit_count < 32 then
                                    bit_count <= bit_count + 1;
                                end if;
                            elsif bit_count = 32 then
                                bit_count <= 0;
                                state     <= START;
                            else
                                bit_count <= 0;
                                state     <= IDLE;
                            end if;

                        when START =>
                            bit_count <= 0;
                            if mdio_in = '1' then
                                state <= OP_CODE;
                            else
                                state <= IDLE;
                            end if;

                        when OP_CODE =>
                            shift_reg(1 downto 0) <=
                                shift_reg(0) & mdio_in;
                            if bit_count = 1 then
                                bit_count      <= 0;
                                opcode_latched <= shift_reg(0) & mdio_in;
                                state          <= PHY_ADDRESS;
                            else
                                bit_count <= bit_count + 1;
                            end if;

                        when PHY_ADDRESS =>
                            shift_reg(4 downto 0) <=
                                shift_reg(3 downto 0) & mdio_in;
                            if bit_count = 4 then
                                bit_count   <= 0;
                                phy_latched <=
                                    shift_reg(3 downto 0) & mdio_in;
                                state <= REG_ADDRESS;
                            else
                                bit_count <= bit_count + 1;
                            end if;

                        when REG_ADDRESS =>
                            shift_reg(4 downto 0) <=
                                shift_reg(3 downto 0) & mdio_in;
                            if bit_count = 4 then
                                bit_count   <= 0;
                                reg_latched <=
                                    shift_reg(3 downto 0) & mdio_in;
                                state <= TA;
                            else
                                bit_count <= bit_count + 1;
                            end if;

                        when TA =>
                            if bit_count = 0 and
                               opcode_latched = OP_READ then
                                read_latched <= reg_read_data;
                                if VERBOSE then
                                    report "READ reg=" &
                                        to_hstring(reg_latched) & ", data=" &
                                        to_hstring(reg_read_data)
                                        severity note;
                                end if;
                            end if;

                            if bit_count = 1 then
                                bit_count <= 0;
                                if phy_latched = PHY_ADDR then
                                    state <= DATA;
                                else
                                    state <= IDLE;
                                end if;
                            else
                                bit_count <= bit_count + 1;
                            end if;

                        when DATA =>
                            if opcode_latched = OP_WRITE then
                                shift_reg <=
                                    shift_reg(14 downto 0) & mdio_in;
                            end if;

                            if bit_count = 15 then
                                bit_count <= 0;
                                if opcode_latched = OP_WRITE then
                                    reg_write_addr <= reg_latched;
                                    reg_write_data <=
                                        shift_reg(14 downto 0) & mdio_in;
                                    reg_write_valid <= '1';
                                    if VERBOSE then
                                        report "WRITE reg=" &
                                            to_hstring(reg_latched) &
                                            ", data=" & to_hstring(
                                                shift_reg(14 downto 0) &
                                                mdio_in)
                                            severity note;
                                    end if;
                                end if;
                                state <= IDLE;
                            else
                                bit_count <= bit_count + 1;
                            end if;
                    end case;
                end if;

                if mdc_falling = '1' then
                    if state = TA and phy_latched = PHY_ADDR and
                       opcode_latched = OP_READ and bit_count = 1 then
                        mdio_oe      <= '1';
                        mdio_out     <= read_latched(15);
                        read_latched <= read_latched(14 downto 0) & '0';
                    elsif state = DATA and opcode_latched = OP_READ then
                        mdio_oe      <= '1';
                        mdio_out     <= read_latched(15);
                        read_latched <= read_latched(14 downto 0) & '0';
                    else
                        mdio_oe  <= '0';
                        mdio_out <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process protocol_controller;
end architecture sim;
