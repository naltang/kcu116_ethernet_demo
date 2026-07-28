library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Initializes the KCU116 on-board TI DP83867 for six-wire SGMII.
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
        phy_status  : out   std_logic_vector(15 downto 0);
        phy_control : out   std_logic_vector(15 downto 0);
        phy_cfg1    : out   std_logic_vector(15 downto 0);
        phy_bmcr    : out   std_logic_vector(15 downto 0);
        phy_bmsr    : out   std_logic_vector(15 downto 0);
        phy_anar    : out   std_logic_vector(15 downto 0);
        phy_anlpar  : out   std_logic_vector(15 downto 0);
        phy_aner    : out   std_logic_vector(15 downto 0);
        phy_sts1    : out   std_logic_vector(15 downto 0);
        phy_recr    : out   std_logic_vector(15 downto 0);
        phy_cfg4    : out   std_logic_vector(15 downto 0);
        phy_strap2  : out   std_logic_vector(15 downto 0);
        phy_ana_ld  : out   std_logic_vector(15 downto 0);
        error       : out   std_logic
    );
end entity dp83867_sgmii_init;

architecture rtl of dp83867_sgmii_init is
    constant PHY_RESET_CYCLES : positive := CLK_FREQ_HZ / 100_000; -- 10 us
    constant POST_RESET_CYCLES : positive := CLK_FREQ_HZ / 1_000;   -- 1 ms
    constant POLL_CYCLES       : positive := CLK_FREQ_HZ / 100;     -- 10 ms
    constant RESET_READ_LIMIT : positive := 2048;

    type op_kind_t is (
        OP_WRITE, OP_READ, OP_READ_RESET, OP_READ_RESTART
    );
    type command_t is record
        kind : op_kind_t;
        reg  : std_logic_vector(4 downto 0);
        data : std_logic_vector(15 downto 0);
    end record;
    type command_array_t is array (natural range <>) of command_t;

    type poll_target_t is (
        CAP_NONE, CAP_BMSR, CAP_PHYSTS, CAP_PHYCR, CAP_CFG1,
        CAP_BMCR, CAP_ANAR, CAP_ANLPAR, CAP_ANER, CAP_STS1,
        CAP_RECR, CAP_CFG4, CAP_STRAP2, CAP_ANA_LD
    );
    type poll_command_t is record
        kind   : op_kind_t;
        reg    : std_logic_vector(4 downto 0);
        data   : std_logic_vector(15 downto 0);
        target : poll_target_t;
    end record;
    type poll_command_array_t is array (natural range <>) of poll_command_t;

    constant REG_BMCR   : std_logic_vector(4 downto 0) := "00000";
    constant REG_BMSR   : std_logic_vector(4 downto 0) := "00001";
    constant REG_ANAR   : std_logic_vector(4 downto 0) := "00100";
    constant REG_ANLPAR : std_logic_vector(4 downto 0) := "00101";
    constant REG_ANER   : std_logic_vector(4 downto 0) := "00110";
    constant REG_CFG1   : std_logic_vector(4 downto 0) := "01001";
    constant REG_STS1   : std_logic_vector(4 downto 0) := "01010";
    constant REG_REGCR  : std_logic_vector(4 downto 0) := "01101";
    constant REG_ADDAR  : std_logic_vector(4 downto 0) := "01110";
    constant REG_PHYCR  : std_logic_vector(4 downto 0) := "10000";
    constant REG_PHYSTS : std_logic_vector(4 downto 0) := "10001";
    constant REG_RECR   : std_logic_vector(4 downto 0) := "10101";
    constant REG_CTRL   : std_logic_vector(4 downto 0) := "11111";

    constant INIT_COMMANDS : command_array_t(0 to 22) := (
        -- Hardware reset is followed by the standard software reset.
        (OP_WRITE,      REG_BMCR,  x"8000"),
        (OP_READ_RESET, REG_BMCR,  x"0000"),

        -- Correct the KCU116 strap-derived copper settings before starting
        -- Auto-Negotiation.  FORCE_LINK_GOOD must be clear in PHYCR, while
        -- SGMII and automatic MDI/MDIX remain enabled.  CFG1 uses automatic
        -- leader/follower resolution and advertises both 1000BASE-T modes.
        (OP_WRITE, REG_PHYCR, x"5848"),
        (OP_WRITE, REG_CFG1,  x"0300"),

        -- SGMIICTL1 0x00D3: six-wire mode and 625 MHz clock output.
        (OP_WRITE, REG_REGCR, x"001F"),
        (OP_WRITE, REG_ADDAR, x"00D3"),
        (OP_WRITE, REG_REGCR, x"401F"),
        (OP_WRITE, REG_ADDAR, x"4000"),

        -- CFG2 0x0014: interrupt polarity, SGMII AN, speed optimization.
        (OP_WRITE, REG_REGCR, x"001F"),
        (OP_WRITE, REG_ADDAR, x"0014"),
        (OP_WRITE, REG_REGCR, x"401F"),
        (OP_WRITE, REG_ADDAR, x"2BC0"),

        -- RGMIICTL 0x0032: disable the unused RGMII interface.
        (OP_WRITE, REG_REGCR, x"001F"),
        (OP_WRITE, REG_ADDAR, x"0032"),
        (OP_WRITE, REG_REGCR, x"401F"),
        (OP_WRITE, REG_ADDAR, x"0053"),

        -- CFG4 0x0031: KCU116 RX_CTRL strap workaround.
        -- Clear INT_TST_MODE_1 (bit 7); keep the documented default values
        -- for the SGMII AN timer and reserved fields.
        (OP_WRITE, REG_REGCR, x"001F"),
        (OP_WRITE, REG_ADDAR, x"0031"),
        (OP_WRITE, REG_REGCR, x"401F"),
        (OP_WRITE, REG_ADDAR, x"1030"),

        -- Apply the extended-register settings.  CTRL.SW_RESTART preserves
        -- the register file but restarts the PHY state machines.
        (OP_WRITE,        REG_CTRL, x"4000"),
        (OP_READ_RESTART, REG_CTRL, x"0000"),

        -- Start copper auto-negotiation only after the final restart has
        -- completed.
        (OP_WRITE, REG_BMCR, x"1340")
    );

    constant POLL_COMMANDS : poll_command_array_t(0 to 22) := (
        -- BMSR link status is latched low, so discard the first read.
        (OP_READ,  REG_BMSR,   x"0000", CAP_NONE),
        (OP_READ,  REG_BMSR,   x"0000", CAP_BMSR),
        (OP_READ,  REG_PHYSTS, x"0000", CAP_PHYSTS),
        (OP_READ,  REG_PHYCR,  x"0000", CAP_PHYCR),
        (OP_READ,  REG_CFG1,   x"0000", CAP_CFG1),
        (OP_READ,  REG_BMCR,   x"0000", CAP_BMCR),
        (OP_READ,  REG_ANAR,   x"0000", CAP_ANAR),
        (OP_READ,  REG_ANLPAR, x"0000", CAP_ANLPAR),
        (OP_READ,  REG_ANER,   x"0000", CAP_ANER),
        (OP_READ,  REG_STS1,   x"0000", CAP_STS1),
        (OP_READ,  REG_RECR,   x"0000", CAP_RECR),

        -- Indirect read of CFG4, extended address 0x0031.
        (OP_WRITE, REG_REGCR,  x"001F", CAP_NONE),
        (OP_WRITE, REG_ADDAR,  x"0031", CAP_NONE),
        (OP_WRITE, REG_REGCR,  x"401F", CAP_NONE),
        (OP_READ,  REG_ADDAR,  x"0000", CAP_CFG4),

        -- Indirect read of STRAP_STS2, extended address 0x006F.
        (OP_WRITE, REG_REGCR,  x"001F", CAP_NONE),
        (OP_WRITE, REG_ADDAR,  x"006F", CAP_NONE),
        (OP_WRITE, REG_REGCR,  x"401F", CAP_NONE),
        (OP_READ,  REG_ADDAR,  x"0000", CAP_STRAP2),

        -- Indirect read of the MDI transmitter control register.  Its normal
        -- value is 0x0200; 0x000F indicates disabled copper transmitters.
        (OP_WRITE, REG_REGCR,  x"001F", CAP_NONE),
        (OP_WRITE, REG_ADDAR,  x"00DD", CAP_NONE),
        (OP_WRITE, REG_REGCR,  x"401F", CAP_NONE),
        (OP_READ,  REG_ADDAR,  x"0000", CAP_ANA_LD)
    );

    type state_t is (
        RESET_HOLD, POST_RESET_WAIT, INIT_ISSUE, INIT_WAIT,
        POLL_DELAY, POLL_ISSUE, POLL_WAIT
    );
    signal state : state_t := RESET_HOLD;

    signal delay_count   : natural range 0 to POST_RESET_CYCLES - 1 := 0;
    signal poll_count    : natural range 0 to POLL_CYCLES - 1 := 0;
    signal command_index : natural range INIT_COMMANDS'range :=
        INIT_COMMANDS'low;
    signal poll_index    : natural range POLL_COMMANDS'range :=
        POLL_COMMANDS'low;

    signal cmd_reg       : std_logic_vector(4 downto 0) := REG_BMCR;
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
    signal phy_status_i  : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_control_i : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_cfg1_i    : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_bmcr_i    : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_bmsr_i    : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_anar_i    : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_anlpar_i  : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_aner_i    : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_sts1_i    : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_recr_i    : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_cfg4_i    : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_strap2_i  : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_ana_ld_i  : std_logic_vector(15 downto 0) := (others => '0');
    signal error_i       : std_logic := '0';
begin
    assert CLK_FREQ_HZ >= 1_000_000
        report "CLK_FREQ_HZ is too low" severity failure;
    assert MDC_FREQ_HZ <= 2_500_000
        report "Clause-22 MDC must not exceed 2.5 MHz" severity failure;

    mdio <= mdio_out when mdio_tri = '0' else 'Z';

    config_done <= config_done_i;
    link_up     <= link_up_i;
    phy_status  <= phy_status_i;
    phy_control <= phy_control_i;
    phy_cfg1    <= phy_cfg1_i;
    phy_bmcr    <= phy_bmcr_i;
    phy_bmsr    <= phy_bmsr_i;
    phy_anar    <= phy_anar_i;
    phy_anlpar  <= phy_anlpar_i;
    phy_aner    <= phy_aner_i;
    phy_sts1    <= phy_sts1_i;
    phy_recr    <= phy_recr_i;
    phy_cfg4    <= phy_cfg4_i;
    phy_strap2  <= phy_strap2_i;
    phy_ana_ld  <= phy_ana_ld_i;
    error       <= error_i;
    phy_rst_n   <= '0' when state = RESET_HOLD else '1';

    -- Select the command presented to the common MDIO master.
    command_mux : process(all)
    begin
        cmd_reg    <= REG_BMSR;
        cmd_data   <= (others => '0');
        cmd_opcode <= "10"; -- Clause-22 read
        cmd_valid  <= '0';

        case state is
            when INIT_ISSUE =>
                cmd_reg  <= INIT_COMMANDS(command_index).reg;
                cmd_data <= INIT_COMMANDS(command_index).data;
                if INIT_COMMANDS(command_index).kind = OP_WRITE then
                    cmd_opcode <= "01";
                end if;
                cmd_valid <= '1';

            when POLL_ISSUE =>
                cmd_reg  <= POLL_COMMANDS(poll_index).reg;
                cmd_data <= POLL_COMMANDS(poll_index).data;
                if POLL_COMMANDS(poll_index).kind = OP_WRITE then
                    cmd_opcode <= "01";
                end if;
                cmd_valid <= '1';

            when others =>
                null;
        end case;
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
            prescale       => std_logic_vector(to_unsigned(
                ((CLK_FREQ_HZ + 2 * MDC_FREQ_HZ - 1) /
                 (2 * MDC_FREQ_HZ)) - 1, 8))
        );

    controller : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state          <= RESET_HOLD;
                reset_count    <= 0;
                reset_reads    <= 0;
                delay_count    <= 0;
                poll_count     <= 0;
                command_index  <= INIT_COMMANDS'low;
                poll_index     <= POLL_COMMANDS'low;
                config_done_i  <= '0';
                link_up_i      <= '0';
                phy_status_i   <= (others => '0');
                phy_control_i  <= (others => '0');
                phy_cfg1_i     <= (others => '0');
                phy_bmcr_i     <= (others => '0');
                phy_bmsr_i     <= (others => '0');
                phy_anar_i     <= (others => '0');
                phy_anlpar_i   <= (others => '0');
                phy_aner_i     <= (others => '0');
                phy_sts1_i     <= (others => '0');
                phy_recr_i     <= (others => '0');
                phy_cfg4_i     <= (others => '0');
                phy_strap2_i   <= (others => '0');
                phy_ana_ld_i   <= (others => '0');
                error_i        <= '0';
            else
                case state is
                    when RESET_HOLD =>
                        config_done_i <= '0';
                        link_up_i     <= '0';
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
                            state         <= INIT_ISSUE;
                        else
                            delay_count <= delay_count + 1;
                        end if;

                    when INIT_ISSUE =>
                        if cmd_ready = '1' then
                            state <= INIT_WAIT;
                        end if;

                    when INIT_WAIT =>
                        if INIT_COMMANDS(command_index).kind = OP_WRITE then
                            if cmd_ready = '1' and master_busy = '0' then
                                if command_index = INIT_COMMANDS'high then
                                    config_done_i <= '1';
                                    poll_count    <= 0;
                                    state         <= POLL_DELAY;
                                else
                                    command_index <= command_index + 1;
                                    state         <= INIT_ISSUE;
                                end if;
                            end if;
                        elsif read_valid = '1' then
                            if read_data(15) = '0' then
                                if INIT_COMMANDS(command_index).kind =
                                   OP_READ_RESET then
                                    command_index <= command_index + 1;
                                    reset_reads   <= 0;
                                    state         <= INIT_ISSUE;
                                elsif read_data(14) = '0' then
                                    command_index <= command_index + 1;
                                    reset_reads   <= 0;
                                    state         <= INIT_ISSUE;
                                elsif reset_reads = RESET_READ_LIMIT - 1 then
                                    error_i       <= '1';
                                    reset_count   <= 0;
                                    reset_reads   <= 0;
                                    command_index <= INIT_COMMANDS'low;
                                    state         <= RESET_HOLD;
                                else
                                    reset_reads <= reset_reads + 1;
                                    state       <= INIT_ISSUE;
                                end if;
                            elsif reset_reads = RESET_READ_LIMIT - 1 then
                                -- A missing/unresponsive PHY also reaches this
                                -- path because MDIO reads back as non-zero.
                                error_i       <= '1';
                                reset_count   <= 0;
                                reset_reads   <= 0;
                                command_index <= INIT_COMMANDS'low;
                                state         <= RESET_HOLD;
                            else
                                reset_reads <= reset_reads + 1;
                                -- Repeat the reset-register read until reset
                                -- clears.
                                state <= INIT_ISSUE;
                            end if;
                        end if;

                    when POLL_DELAY =>
                        if poll_count = POLL_CYCLES - 1 then
                            poll_count <= 0;
                            poll_index <= POLL_COMMANDS'low;
                            state      <= POLL_ISSUE;
                        else
                            poll_count <= poll_count + 1;
                        end if;

                    when POLL_ISSUE =>
                        if cmd_ready = '1' then
                            state <= POLL_WAIT;
                        end if;

                    when POLL_WAIT =>
                        if POLL_COMMANDS(poll_index).kind = OP_WRITE then
                            if cmd_ready = '1' and master_busy = '0' then
                                if poll_index = POLL_COMMANDS'high then
                                    state <= POLL_DELAY;
                                else
                                    poll_index <= poll_index + 1;
                                    state      <= POLL_ISSUE;
                                end if;
                            end if;
                        elsif read_valid = '1' then
                            case POLL_COMMANDS(poll_index).target is
                                when CAP_NONE =>
                                    null;
                                when CAP_BMSR =>
                                    phy_bmsr_i <= read_data;
                                    link_up_i  <= read_data(2);
                                when CAP_PHYSTS =>
                                    phy_status_i <= read_data;
                                when CAP_PHYCR =>
                                    phy_control_i <= read_data;
                                when CAP_CFG1 =>
                                    phy_cfg1_i <= read_data;
                                when CAP_BMCR =>
                                    phy_bmcr_i <= read_data;
                                when CAP_ANAR =>
                                    phy_anar_i <= read_data;
                                when CAP_ANLPAR =>
                                    phy_anlpar_i <= read_data;
                                when CAP_ANER =>
                                    phy_aner_i <= read_data;
                                when CAP_STS1 =>
                                    phy_sts1_i <= read_data;
                                when CAP_RECR =>
                                    phy_recr_i <= read_data;
                                when CAP_CFG4 =>
                                    phy_cfg4_i <= read_data;
                                when CAP_STRAP2 =>
                                    phy_strap2_i <= read_data;
                                when CAP_ANA_LD =>
                                    phy_ana_ld_i <= read_data;
                            end case;

                            if poll_index = POLL_COMMANDS'high then
                                state <= POLL_DELAY;
                            else
                                poll_index <= poll_index + 1;
                                state      <= POLL_ISSUE;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process controller;
end architecture rtl;
