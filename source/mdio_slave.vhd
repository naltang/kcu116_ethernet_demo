library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mdio_slave is
    generic (
        PHY_ADDR : std_logic_vector(4 downto 0) := "00011"
    );
    port (
        -- Global Signals
        clk          : in    std_logic; -- High-speed system clock
        rst_n        : in    std_logic; -- Active-low synchronous reset

        -- MDIO Interface Physical Pins
        mdc          : in    std_logic; -- Management Data Clock (from Master)
        mdio         : inout std_logic  -- Bidirectional MDIO data line
    );
end entity mdio_slave;

architecture rtl of mdio_slave is
    -- FSM state definitions
    type state_t is (
        IDLE, PREAMBLE, START, OP_CODE, PHY_ADDRESS, REG_ADDRESS, TA, DATA,
        WRITE_REG
    );
    signal state : state_t := IDLE;

    -- MDC edge-detection registers
    signal mdc_d1, mdc_d2 : std_logic := '0';
    signal mdc_rising     : std_logic;
    signal mdc_falling    : std_logic;

    -- Internal signals split from the inout port
    signal mdio_in  : std_logic := '1';
    signal mdio_out : std_logic := '1';
    signal mdio_oe  : std_logic := '0'; -- 1 drives MDIO; 0 selects high-Z.

    -- Internal shift and counter registers
    signal bit_cnt   : integer range 0 to 32 := 0;
    signal shift_reg : std_logic_vector(15 downto 0) := (others => '0');

    -- Captured frame fields
    signal op_code_reg   : std_logic_vector(1 downto 0) := (others => '0');
    signal phy_addr_reg  : std_logic_vector(4 downto 0) := (others => '0');
    signal reg_addr_reg  : std_logic_vector(4 downto 0) := (others => '0');
    signal read_data_reg : std_logic_vector(15 downto 0) := (others => '0');

    -- Internal register interface signals
    signal reg_addr     : std_logic_vector(4 downto 0);
    signal reg_data_out : std_logic_vector(15 downto 0);
    signal reg_data_in  : std_logic_vector(15 downto 0);
    signal reg_we       : std_logic;

    -- Internal storage array (32 registers x 16 bits)
    type reg_array_t is array (0 to 31) of std_logic_vector(15 downto 0);
    signal reg_file : reg_array_t := (
        0 => x"1100", -- Control Register default (e.g., BMCR)
        1 => x"782F", -- Status Register default (e.g., BMSR)
        2 => x"0022", -- PHY Identifier 1
        3 => x"1611", -- PHY Identifier 2
        4 => x"01E1", -- Local 10/100 auto-negotiation advertisement
        5 => x"CDE1", -- Link partner ability with ACK set
        6 => x"0067", -- Link partner AN capable and page received
        -- Model the problematic KCU116 strap-derived values so the
        -- initialization regression verifies that they are corrected.
        9 => x"1300", -- manual 1000BASE-T leader/follower configuration
        10 => x"6000", -- resolved leader/follower and receiver status
        16 => x"5C48", -- SGMII enabled, but force-link-good set
        17 => x"BF02", -- DP83867 PHYSTS: linked at 1 Gb/s, full duplex
        21 => x"0005", -- DP83867 RECR: model a nonzero receive-error count
        others => x"0000"
    );

    type extended_reg_array_t is
        array (0 to 255) of std_logic_vector(15 downto 0);
    signal extended_reg_file : extended_reg_array_t := (
        16#31# => x"11F0", -- CFG4 before the RX_CTRL strap workaround
        16#6F# => x"0100", -- STRAP_STS2: normal operation
        16#DD# => x"0200", -- MDI transmitters enabled
        others => x"0000"
    );
    signal extended_address : std_logic_vector(15 downto 0) :=
        (others => '0');

    signal count_clear_reset   : integer range 0 to 20000 := 0;
    signal count_clear_restart : integer range 0 to 20000 := 0;
begin
    -- Tri-state buffer logic for the inout port.
    mdio    <= mdio_out when mdio_oe = '1' else 'Z';
    mdio_in <= mdio;

    -- MDC edge detection.
    mdc_edge_detector : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                mdc_d1    <= '0';
                mdc_d2    <= '0';
            else
                mdc_d1    <= mdc;
                mdc_d2    <= mdc_d1;
            end if;
        end if;
    end process mdc_edge_detector;

    mdc_rising  <= mdc_d1 and (not mdc_d2);
    mdc_falling <= (not mdc_d1) and mdc_d2;

    -- Internal combinational memory read path.
    reg_data_in <= extended_reg_file(to_integer(unsigned(
                       extended_address(7 downto 0))))
        when reg_addr_reg = "01110" and
             reg_file(13)(15 downto 14) = "01"
        else reg_file(to_integer(unsigned(reg_addr_reg)));

    -- Internal memory write path.
    register_writer : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                -- Reset registers to default values if required by hardware
                reg_file(0)         <= x"1100";
                extended_address    <= (others => '0');
                count_clear_reset   <= 0;
                count_clear_restart <= 0;
            elsif reg_we = '1' then
                if reg_addr = "01110" and
                   reg_file(13)(15 downto 14) = "00" then
                    -- REGCR selects address mode: ADDAR holds the extended
                    -- register address.
                    extended_address <= reg_data_out;
                    reg_file(14)      <= reg_data_out;
                elsif reg_addr = "01110" and
                      reg_file(13)(15 downto 14) = "01" then
                    -- REGCR selects data mode: ADDAR accesses the selected
                    -- extended register.
                    extended_reg_file(to_integer(unsigned(
                        extended_address(7 downto 0)))) <= reg_data_out;
                    reg_file(14) <= reg_data_out;
                else
                    reg_file(to_integer(unsigned(reg_addr))) <= reg_data_out;
                end if;

                if reg_addr = "00000" then
                    count_clear_reset <= 10000;
                elsif reg_addr = "11111" and reg_data_out(14) = '1' then
                    count_clear_restart <= 10000;
                end if;
            elsif reg_file(0)(15) = '1' then
                -- BMCR software reset is self-clearing.
                if count_clear_reset = 0 then
                    reg_file(0)(15) <= '0';
                    report "BMCR software reset self-cleared" severity note;
                else
                    count_clear_reset <= count_clear_reset - 1;
                end if;
            elsif reg_file(31)(14) = '1' then
                -- CTRL software restart is also self-clearing and preserves
                -- the programmed register values.
                if count_clear_restart = 0 then
                    reg_file(31)(14) <= '0';
                    report "CTRL software restart self-cleared" severity note;
                else
                    count_clear_restart <= count_clear_restart - 1;
                end if;
            end if;
        end if;
    end process register_writer;

    -- MDIO slave protocol state machine.
    protocol_controller : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state         <= IDLE;
                bit_cnt       <= 0;
                shift_reg     <= (others => '0');
                op_code_reg   <= (others => '0');
                phy_addr_reg  <= (others => '0');
                reg_addr_reg  <= (others => '0');
                read_data_reg <= (others => '0');
                mdio_out      <= '1';
                mdio_oe       <= '0';
                reg_we        <= '0';
                reg_addr      <= (others => '0');
                reg_data_out  <= (others => '0');
            else
                reg_we <= '0';

                -- Sample input data on the rising edge of MDC.
                if mdc_rising = '1' then
                    case state is
                        when IDLE =>
                            if mdio_in = '1' then
                                bit_cnt <= 1;
                                state   <= PREAMBLE;
                            end if;

                        when PREAMBLE =>
                            shift_reg(1 downto 0) <= shift_reg(0) & mdio_in;
                            if mdio_in = '1' then
                                if bit_cnt = 32 then
                                    bit_cnt <= 32;
                                else
                                    bit_cnt <= bit_cnt + 1;
                                end if;
                            else
                                if bit_cnt = 32 then
                                    state   <= START;
                                    bit_cnt <= 0;
                                else
                                    -- Premature end of preamble.
                                    state   <= IDLE;
                                    bit_cnt <= 0;
                                end if;
                            end if;

                        when START =>
                            shift_reg(1 downto 0) <= shift_reg(0) & mdio_in;
                            bit_cnt <= 0;
                            if shift_reg(0) = '0' and mdio_in = '1' then
                                state <= OP_CODE;
                            else
                                state <= IDLE;
                            end if;

                        when OP_CODE =>
                            shift_reg(1 downto 0) <= shift_reg(0) & mdio_in;
                            if bit_cnt = 1 then
                                bit_cnt     <= 0;
                                op_code_reg <= shift_reg(0) & mdio_in;
                                state       <= PHY_ADDRESS;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;

                        when PHY_ADDRESS =>
                            shift_reg(4 downto 0) <= shift_reg(3 downto 0) & mdio_in;
                            if bit_cnt = 4 then
                                bit_cnt      <= 0;
                                phy_addr_reg <= shift_reg(3 downto 0) & mdio_in;
                                state        <= REG_ADDRESS;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;

                        when REG_ADDRESS =>
                            shift_reg(4 downto 0) <= shift_reg(3 downto 0) & mdio_in;
                            if bit_cnt = 4 then
                                bit_cnt      <= 0;
                                reg_addr_reg <= shift_reg(3 downto 0) & mdio_in;
                                state        <= TA;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;

                        when TA =>
                            if bit_cnt = 1 then
                                bit_cnt <= 0;
                                if phy_addr_reg = PHY_ADDR then
                                    state <= DATA;
                                else
                                    state <= IDLE;
                                end if;
                            else
                                if op_code_reg = "10" then
                                    read_data_reg <= reg_data_in;
                                    report "READ reg=" &
                                        to_hstring(reg_addr_reg) & ", data=" &
                                        to_hstring(reg_data_in)
                                        severity note;
                                end if;
                                bit_cnt <= bit_cnt + 1;
                            end if;

                        when DATA =>
                            if op_code_reg = "01" then
                                shift_reg <= shift_reg(14 downto 0) & mdio_in;
                            end if;

                            if bit_cnt = 15 then
                                bit_cnt <= 0;
                                if op_code_reg = "01" then
                                    reg_addr     <= reg_addr_reg;
                                    reg_data_out <=
                                        shift_reg(14 downto 0) & mdio_in;
                                    reg_we       <= '1';
                                    report "WRITE reg=" &
                                        to_hstring(reg_addr_reg) & ", data=" &
                                        to_hstring(
                                            shift_reg(14 downto 0) & mdio_in)
                                        severity note;
                                end if;
                                state <= IDLE;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;

                        when others =>
                            state <= IDLE;
                    end case;
                end if;

                -- Drive output data on the falling edge of MDC.
                if mdc_falling = '1' then
                    if state = TA and phy_addr_reg = PHY_ADDR and
                       op_code_reg = "10" and bit_cnt = 1 then
                        mdio_oe       <= '1';
                        mdio_out      <= read_data_reg(15);
                        read_data_reg <= read_data_reg(14 downto 0) & '0';
                    elsif state = DATA and op_code_reg = "10" then
                        mdio_oe       <= '1';
                        mdio_out      <= read_data_reg(15);
                        read_data_reg <= read_data_reg(14 downto 0) & '0';
                    else
                        mdio_oe  <= '0';
                        mdio_out <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process protocol_controller;
end architecture rtl;
