library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx_vector is
    generic (
        CLOCK_SPEED_IN_MHZ    : integer := 125;
        BAUD_RATE             : integer := 9600;
        PAUSE_BEFORE          : integer := 5;
        VECTOR_WIDTH_IN_BYTES : integer := 100
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        tx_out    : out std_logic;
        vector_in : in  std_logic_vector(VECTOR_WIDTH_IN_BYTES * 8 - 1 downto 0)
    );
end entity uart_tx_vector;

architecture rtl of uart_tx_vector is
    -- Required baud clock divider value.
    constant CLK_DIVIDER : natural := (CLOCK_SPEED_IN_MHZ * 1000000) / BAUD_RATE;

    -- State-machine definition.
    type state_t is (IDLE, PAUSE, TRANSMIT);

    -- State and counters.
    signal current_state : state_t := IDLE;
    signal baud_counter   : integer range 0 to CLK_DIVIDER - 1 := 0;
    signal pause_counter  : integer range 0 to PAUSE_BEFORE := 0;
    signal byte_index     : integer range 0 to VECTOR_WIDTH_IN_BYTES - 1 := 0;
    -- bit_counter tracks the cycle count within a transmission (0=start, 9=stop)
    signal bit_counter    : integer range 0 to 9 := 0;

    -- Internal signal for the slow baud-rate enable pulse.
    signal baud_tick : std_logic := '0';
    -- Keep every transmitted line coherent if vector_in changes while a line
    -- is being serialized.
    signal vector_latched : std_logic_vector(
        VECTOR_WIDTH_IN_BYTES * 8 - 1 downto 0) := (others => '0');
begin
    -- Parameter validation.
    assert CLOCK_SPEED_IN_MHZ > 1 and CLOCK_SPEED_IN_MHZ < 1000
        report "CLOCK_SPEED_IN_MHZ must be greater than 1 and less than 1000."
        severity failure;

    assert PAUSE_BEFORE > 0 and PAUSE_BEFORE < 100
        report "PAUSE_BEFORE must be greater than 0 and less than 100."
        severity failure;

    assert VECTOR_WIDTH_IN_BYTES > 0 and VECTOR_WIDTH_IN_BYTES < 1000
        report "VECTOR_WIDTH_IN_BYTES must be greater than 0 and less than 1000."
        severity failure;

    -- Generate a clock-enable pulse synchronized to the baud rate.
    baud_tick_generator : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                baud_counter <= 0;
                baud_tick    <= '0';
            else
                if baud_counter < CLK_DIVIDER - 1 then
                    baud_counter <= baud_counter + 1;
                    baud_tick    <= '0';
                else
                    baud_counter <= 0;
                    baud_tick    <= '1';
                end if;
            end if;
        end if;
    end process baud_tick_generator;

    -- State and counter logic, triggered by the baud tick.
    transmit_controller : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current_state <= IDLE;
                pause_counter  <= 0;
                byte_index     <= 0;
                bit_counter    <= 0;
                vector_latched <= (others => '0');

            elsif baud_tick = '1' then
                case current_state is
                    when IDLE =>
                        pause_counter  <= 0;
                        byte_index     <= 0;
                        bit_counter    <= 0;
                        vector_latched <= vector_in;
                        current_state  <= PAUSE;

                    when PAUSE =>
                        if pause_counter < PAUSE_BEFORE then
                            pause_counter <= pause_counter + 1;
                        else
                            -- The pause is complete; start transmission.
                            current_state <= TRANSMIT;
                            pause_counter  <= 0;
                            byte_index     <= 0;
                            bit_counter    <= 0;
                        end if;

                    when TRANSMIT =>
                        if bit_counter < 9 then
                            current_state <= TRANSMIT;
                            bit_counter   <= bit_counter + 1;
                        else
                            -- Transmission of the current byte is complete.
                            if byte_index < VECTOR_WIDTH_IN_BYTES - 1 then
                                byte_index    <= byte_index + 1;
                                bit_counter   <= 0;
                            else
                                current_state <= IDLE;
                                byte_index    <= 0;
                                bit_counter   <= 0;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process transmit_controller;

    -- Decode the current state and bit index onto the serial output.
    output_decoder : process(all)
    begin
        tx_out <= '1';

        if current_state = TRANSMIT then
            case bit_counter is
                when 0 =>
                    tx_out <= '0';

                when 1 to 8 =>
                    -- UART data is transmitted least-significant bit first.
                    tx_out <= vector_latched(byte_index * 8 + (bit_counter - 1));

                when 9 =>
                    tx_out <= '1';

                when others =>
                    -- Should not happen, but safe default.
                    tx_out <= '1';
            end case;
        end if;
    end process output_decoder;
end architecture rtl;
