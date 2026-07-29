library ieee;
use ieee.std_logic_1164.all;

entity uart_tx is
    generic (
        CLOCK_FREQ_HZ : positive := 125_000_000;
        BAUD_RATE     : positive := 9600
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        data_in    : in  std_logic_vector(7 downto 0);
        data_valid : in  std_logic;
        data_ready : out std_logic;
        tx_out     : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is
    constant CLKS_PER_BIT : positive := CLOCK_FREQ_HZ / BAUD_RATE;
    constant ACTUAL_BAUD  : positive := CLOCK_FREQ_HZ / CLKS_PER_BIT;

    type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state        : state_t := IDLE;
    signal clock_count  : natural range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index    : natural range 0 to 7 := 0;
    signal data_latched : std_logic_vector(7 downto 0) := (others => '0');
begin
    assert CLOCK_FREQ_HZ >= BAUD_RATE
        report "CLOCK_FREQ_HZ must be at least BAUD_RATE"
        severity failure;
    assert abs(integer(ACTUAL_BAUD) - integer(BAUD_RATE)) * 100 <=
           BAUD_RATE * 3
        report "UART baud-rate error exceeds three percent" severity failure;

    data_ready <= '1' when state = IDLE and rst = '0' else '0';
    with state select tx_out <=
        '0'                     when START_BIT,
        data_latched(bit_index) when DATA_BITS,
        '1'                     when others;

    transmit : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                clock_count  <= 0;
                bit_index    <= 0;
                data_latched <= (others => '0');
            else
                case state is
                    when IDLE =>
                        clock_count <= 0;
                        bit_index   <= 0;
                        if data_valid = '1' then
                            data_latched <= data_in;
                            state        <= START_BIT;
                        end if;

                    when START_BIT =>
                        if clock_count = CLKS_PER_BIT - 1 then
                            clock_count <= 0;
                            bit_index   <= 0;
                            state       <= DATA_BITS;
                        else
                            clock_count <= clock_count + 1;
                        end if;

                    when DATA_BITS =>
                        if clock_count = CLKS_PER_BIT - 1 then
                            clock_count <= 0;
                            if bit_index = 7 then
                                state <= STOP_BIT;
                            else
                                bit_index <= bit_index + 1;
                            end if;
                        else
                            clock_count <= clock_count + 1;
                        end if;

                    when STOP_BIT =>
                        if clock_count = CLKS_PER_BIT - 1 then
                            clock_count <= 0;
                            state       <= IDLE;
                        else
                            clock_count <= clock_count + 1;
                        end if;
                end case;
            end if;
        end if;
    end process transmit;
end architecture rtl;
