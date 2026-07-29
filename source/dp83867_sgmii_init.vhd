library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dp83867_pkg.all;

-- Initializes the KCU116 or VCU118 on-board TI DP83867 for six-wire SGMII.
--
-- The register sequence follows AMD Answer Record 69494.  Clause-22 indirect
-- addressing through REGCR/ADDAR is used for the DP83867 extended registers.
-- After configuration the controller continuously reads BMSR twice, because
-- its link-status bit is latched low.
entity dp83867_sgmii_init is
    generic (
        CLK_FREQ_HZ : positive := 125_000_000;
        MDC_FREQ_HZ : positive := 2_500_000;
        PHY_ADDR    : std_logic_vector(4 downto 0) := "00011"
    );
    port (
        clk         : in    std_logic;
        rst         : in    std_logic;
        phy_rst_n   : out   std_logic;
        mdc         : out   std_logic;
        mdio        : inout std_logic;
        config_done : out   std_logic;
        link_up     : out   std_logic;
        diagnostics : out   phy_diagnostics_t;
        error       : out   std_logic
    );
end entity dp83867_sgmii_init;

architecture rtl of dp83867_sgmii_init is
    constant PHY_RESET_CYCLES : positive := CLK_FREQ_HZ / 100_000; -- 10 us
    constant POST_RESET_CYCLES : positive := CLK_FREQ_HZ / 1_000;   -- 1 ms
    constant POLL_CYCLES       : positive := CLK_FREQ_HZ / 100;     -- 10 ms
    constant RESET_READ_LIMIT : positive := 2048;

    type capture_target_t is (
        CAP_NONE, CAP_BMSR, CAP_PHYSTS, CAP_PHYCR, CAP_CFG1,
        CAP_BMCR, CAP_ANAR, CAP_ANLPAR, CAP_ANER, CAP_STS1,
        CAP_RECR, CAP_MSE_A, CAP_MSE_B, CAP_MSE_C, CAP_MSE_D,
        CAP_CFG4, CAP_STRAP2, CAP_ANA_LD
    );
    type command_kind_t is (COMMAND_WRITE, COMMAND_READ);
    type command_t is record
        kind       : command_kind_t;
        reg        : mdio_register_address_t;
        data       : mdio_word_t;
        target     : capture_target_t;
        clear_mask : mdio_word_t;
    end record;
    type command_array_t is array (natural range <>) of command_t;

    function write_command (
        reg_value  : mdio_register_address_t;
        data_value : mdio_word_t
    ) return command_t is
    begin
        return (COMMAND_WRITE, reg_value, data_value, CAP_NONE, x"0000");
    end function;

    function read_command (
        reg_value    : mdio_register_address_t;
        target_value : capture_target_t := CAP_NONE;
        clear_mask   : mdio_word_t := x"0000"
    ) return command_t is
    begin
        return (
            COMMAND_READ, reg_value, x"0000", target_value, clear_mask);
    end function;

    function extended_address_command (
        address_value : mdio_word_t
    ) return command_t is
    begin
        return write_command(DP83867_REG_ADDAR, address_value);
    end function;

    function extended_data_write (
        data_value : mdio_word_t
    ) return command_t is
    begin
        return write_command(DP83867_REG_ADDAR, data_value);
    end function;

    function extended_data_read (
        target_value : capture_target_t
    ) return command_t is
    begin
        return read_command(DP83867_REG_ADDAR, target_value);
    end function;

    constant INIT_COMMANDS : command_array_t(0 to 22) := (
        -- Hardware reset is followed by the standard software reset.
        write_command(DP83867_REG_BMCR, x"8000"),
        read_command(DP83867_REG_BMCR, clear_mask => x"8000"),

        -- Establish the board-independent copper settings before starting
        -- Auto-Negotiation.  FORCE_LINK_GOOD must be clear in PHYCR, while
        -- SGMII and automatic MDI/MDIX remain enabled.  CFG1 uses automatic
        -- leader/follower resolution and advertises both 1000BASE-T modes.
        write_command(DP83867_REG_PHYCR, x"5848"),
        write_command(DP83867_REG_CFG1, x"0300"),

        -- SGMIICTL1 0x00D3: six-wire mode and 625 MHz clock output.
        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_SGMIICTL1),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_write(x"4000"),

        -- CFG2 0x0014: interrupt polarity, SGMII AN, speed optimization.
        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_CFG2),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_write(x"2BC0"),

        -- RGMIICTL 0x0032: disable the unused RGMII interface.
        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_RGMIICTL),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_write(x"0053"),

        -- CFG4 0x0031: KCU116/VCU118 RX_CTRL strap workaround.
        -- Clear INT_TST_MODE_1 (bit 7); keep the documented default values
        -- for the SGMII AN timer and reserved fields.
        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_CFG4),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_write(x"1030"),

        -- Apply the extended-register settings.  CTRL.SW_RESTART preserves
        -- the register file but restarts the PHY state machines.
        write_command(DP83867_REG_CTRL, x"4000"),
        read_command(DP83867_REG_CTRL, clear_mask => x"C000"),

        -- Start copper auto-negotiation only after the final restart has
        -- completed.
        write_command(DP83867_REG_BMCR, x"1340")
    );

    constant POLL_COMMANDS : command_array_t(0 to 38) := (
        -- BMSR link status is latched low, so discard the first read.
        read_command(DP83867_REG_BMSR),
        read_command(DP83867_REG_BMSR, CAP_BMSR),
        read_command(DP83867_REG_PHYSTS, CAP_PHYSTS),
        read_command(DP83867_REG_PHYCR, CAP_PHYCR),
        read_command(DP83867_REG_CFG1, CAP_CFG1),
        read_command(DP83867_REG_BMCR, CAP_BMCR),
        read_command(DP83867_REG_ANAR, CAP_ANAR),
        read_command(DP83867_REG_ANLPAR, CAP_ANLPAR),
        read_command(DP83867_REG_ANER, CAP_ANER),
        read_command(DP83867_REG_STS1, CAP_STS1),
        read_command(DP83867_REG_RECR, CAP_RECR),

        -- Indirect reads of the four copper-channel link-quality values.
        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_MSE_A),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_read(CAP_MSE_A),

        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_MSE_B),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_read(CAP_MSE_B),

        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_MSE_C),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_read(CAP_MSE_C),

        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_MSE_D),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_read(CAP_MSE_D),

        -- Indirect read of CFG4, extended address 0x0031.
        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_CFG4),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_read(CAP_CFG4),

        -- Indirect read of STRAP_STS2, extended address 0x006F.
        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_STRAP_STS2),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_read(CAP_STRAP2),

        -- Indirect read of the MDI transmitter control register.  Its normal
        -- value is 0x0200; 0x000F indicates disabled copper transmitters.
        write_command(DP83867_REG_REGCR, x"001F"),
        extended_address_command(DP83867_EXT_ANA_LD_DATA_CTRL),
        write_command(DP83867_REG_REGCR, x"401F"),
        extended_data_read(CAP_ANA_LD)
    );

    type phase_t is (INITIALIZATION, POLLING);
    type state_t is (
        RESET_HOLD, POST_RESET_WAIT, COMMAND_ISSUE, COMMAND_WAIT, POLL_DELAY
    );
    signal state : state_t := RESET_HOLD;
    signal phase : phase_t := INITIALIZATION;

    signal delay_count   : natural range 0 to POST_RESET_CYCLES - 1 := 0;
    signal poll_count    : natural range 0 to POLL_CYCLES - 1 := 0;
    signal command_index : natural range 0 to POLL_COMMANDS'high :=
        INIT_COMMANDS'low;
    signal current_command : command_t := INIT_COMMANDS(INIT_COMMANDS'low);

    signal cmd_reg       : std_logic_vector(4 downto 0) := DP83867_REG_BMCR;
    signal cmd_data      : std_logic_vector(15 downto 0) := (others => '0');
    signal cmd_opcode    : std_logic_vector(1 downto 0) := "01";
    signal cmd_valid     : std_logic := '0';
    signal cmd_ready     : std_logic;
    signal read_data     : std_logic_vector(15 downto 0);
    signal read_valid    : std_logic;
    signal mdio_out      : std_logic;
    signal mdio_tri      : std_logic;
    signal master_busy   : std_logic;
    signal reset_count   : natural range 0 to PHY_RESET_CYCLES - 1 := 0;
    signal reset_reads   : natural range 0 to RESET_READ_LIMIT - 1 := 0;
    signal config_done_i : std_logic := '0';
    signal link_up_i     : std_logic := '0';
    signal diagnostics_i : phy_diagnostics_t := PHY_DIAGNOSTICS_RESET;
    signal mse_a_pending : mdio_word_t := (others => '0');
    signal mse_b_pending : mdio_word_t := (others => '0');
    signal mse_c_pending : mdio_word_t := (others => '0');
    signal sticky_error  : std_logic := '0';
begin
    assert CLK_FREQ_HZ >= 1_000_000
        report "CLK_FREQ_HZ is too low" severity failure;
    assert MDC_FREQ_HZ <= 2_500_000
        report "Clause-22 MDC must not exceed 2.5 MHz" severity failure;
    assert CLK_FREQ_HZ >= 2 * MDC_FREQ_HZ
        report "CLK_FREQ_HZ must be at least twice MDC_FREQ_HZ"
        severity failure;
    assert ((CLK_FREQ_HZ + 2 * MDC_FREQ_HZ - 1) /
            (2 * MDC_FREQ_HZ)) - 1 <= 255
        report "MDC prescaler does not fit in eight bits" severity failure;

    mdio <= mdio_out when mdio_tri = '0' else 'Z';

    config_done <= config_done_i;
    link_up     <= link_up_i;
    diagnostics <= diagnostics_i;
    error       <= sticky_error;
    phy_rst_n   <= '0' when state = RESET_HOLD else '1';

    current_command <= INIT_COMMANDS(command_index)
        when phase = INITIALIZATION else POLL_COMMANDS(command_index);

    command_mux : process(all)
    begin
        cmd_reg    <= current_command.reg;
        cmd_data   <= (others => '0');
        cmd_opcode <= MDIO_OP_READ;
        cmd_valid  <= '1' when state = COMMAND_ISSUE else '0';
        if current_command.kind = COMMAND_WRITE then
            cmd_data   <= current_command.data;
            cmd_opcode <= MDIO_OP_WRITE;
        end if;
    end process command_mux;

    mdio_master_i : entity work.mdio_master
        port map (
            clk            => clk,
            rst            => rst,
            cmd_phy_addr   => PHY_ADDR,
            cmd_reg_addr   => cmd_reg,
            cmd_data       => cmd_data,
            cmd_opcode     => cmd_opcode,
            cmd_valid      => cmd_valid,
            cmd_ready      => cmd_ready,
            data_out       => read_data,
            data_out_valid => read_valid,
            data_out_ready => '1',
            mdc_o          => mdc,
            mdio_i         => mdio,
            mdio_o         => mdio_out,
            mdio_t         => mdio_tri,
            busy           => master_busy,
            prescale       =>
                ((CLK_FREQ_HZ + 2 * MDC_FREQ_HZ - 1) /
                 (2 * MDC_FREQ_HZ)) - 1
        );

    controller : process(clk)
        procedure advance_command is
        begin
            reset_reads <= 0;
            if phase = INITIALIZATION then
                if command_index = INIT_COMMANDS'high then
                    config_done_i <= '1';
                    poll_count    <= 0;
                    phase         <= POLLING;
                    state         <= POLL_DELAY;
                else
                    command_index <= command_index + 1;
                    state         <= COMMAND_ISSUE;
                end if;
            elsif command_index = POLL_COMMANDS'high then
                state <= POLL_DELAY;
            else
                command_index <= command_index + 1;
                state         <= COMMAND_ISSUE;
            end if;
        end procedure;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state          <= RESET_HOLD;
                phase          <= INITIALIZATION;
                reset_count    <= 0;
                reset_reads    <= 0;
                delay_count    <= 0;
                poll_count     <= 0;
                command_index  <= INIT_COMMANDS'low;
                config_done_i  <= '0';
                link_up_i      <= '0';
                diagnostics_i  <= PHY_DIAGNOSTICS_RESET;
                mse_a_pending  <= (others => '0');
                mse_b_pending  <= (others => '0');
                mse_c_pending  <= (others => '0');
                sticky_error   <= '0';
            else
                case state is
                    when RESET_HOLD =>
                        config_done_i <= '0';
                        link_up_i     <= '0';
                        phase         <= INITIALIZATION;
                        if reset_count = PHY_RESET_CYCLES - 1 then
                            reset_count <= 0;
                            delay_count <= 0;
                            state       <= POST_RESET_WAIT;
                        else
                            reset_count <= reset_count + 1;
                        end if;

                    when POST_RESET_WAIT =>
                        if delay_count = POST_RESET_CYCLES - 1 then
                            delay_count   <= 0;
                            command_index <= INIT_COMMANDS'low;
                            state         <= COMMAND_ISSUE;
                        else
                            delay_count <= delay_count + 1;
                        end if;

                    when COMMAND_ISSUE =>
                        if cmd_ready = '1' then
                            state <= COMMAND_WAIT;
                        end if;

                    when COMMAND_WAIT =>
                        if current_command.kind = COMMAND_WRITE then
                            if cmd_ready = '1' and master_busy = '0' then
                                advance_command;
                            end if;
                        elsif read_valid = '1' then
                            if current_command.clear_mask /= x"0000" and
                               (read_data and current_command.clear_mask) /=
                               x"0000" then
                                if reset_reads = RESET_READ_LIMIT - 1 then
                                    sticky_error  <= '1';
                                    reset_count   <= 0;
                                    reset_reads   <= 0;
                                    command_index <= INIT_COMMANDS'low;
                                    state         <= RESET_HOLD;
                                else
                                    reset_reads <= reset_reads + 1;
                                    state       <= COMMAND_ISSUE;
                                end if;
                            else
                                case current_command.target is
                                    when CAP_NONE =>
                                        null;
                                    when CAP_BMSR =>
                                        diagnostics_i.bmsr <= read_data;
                                        link_up_i <= read_data(2);
                                    when CAP_PHYSTS =>
                                        diagnostics_i.physts <= read_data;
                                    when CAP_PHYCR =>
                                        diagnostics_i.phycr <= read_data;
                                    when CAP_CFG1 =>
                                        diagnostics_i.cfg1 <= read_data;
                                    when CAP_BMCR =>
                                        diagnostics_i.bmcr <= read_data;
                                    when CAP_ANAR =>
                                        diagnostics_i.anar <= read_data;
                                    when CAP_ANLPAR =>
                                        diagnostics_i.anlpar <= read_data;
                                    when CAP_ANER =>
                                        diagnostics_i.aner <= read_data;
                                    when CAP_STS1 =>
                                        diagnostics_i.sts1 <= read_data;
                                    when CAP_RECR =>
                                        diagnostics_i.recr <= read_data;
                                    when CAP_MSE_A =>
                                        mse_a_pending <= read_data;
                                    when CAP_MSE_B =>
                                        mse_b_pending <= read_data;
                                    when CAP_MSE_C =>
                                        mse_c_pending <= read_data;
                                    when CAP_MSE_D =>
                                        -- Publish the quartet together so a
                                        -- UART snapshot cannot mix cycles.
                                        diagnostics_i.mse_a <= mse_a_pending;
                                        diagnostics_i.mse_b <= mse_b_pending;
                                        diagnostics_i.mse_c <= mse_c_pending;
                                        diagnostics_i.mse_d <= read_data;
                                    when CAP_CFG4 =>
                                        diagnostics_i.cfg4 <= read_data;
                                    when CAP_STRAP2 =>
                                        diagnostics_i.strap_sts2 <= read_data;
                                    when CAP_ANA_LD =>
                                        diagnostics_i.ana_ld_data_ctrl <=
                                            read_data;
                                end case;
                                advance_command;
                            end if;
                        end if;

                    when POLL_DELAY =>
                        if poll_count = POLL_CYCLES - 1 then
                            poll_count    <= 0;
                            command_index <= POLL_COMMANDS'low;
                            phase         <= POLLING;
                            state         <= COMMAND_ISSUE;
                        else
                            poll_count <= poll_count + 1;
                        end if;
                end case;
            end if;
        end if;
    end process controller;
end architecture rtl;
