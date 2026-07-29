library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Transfer a free-running counter between unrelated clock domains.  Gray
-- coding ensures that only one source bit changes for each increment.
entity gray_counter_cdc is
    generic (
        WIDTH : positive := 16
    );
    port (
        source_count : in  unsigned(WIDTH - 1 downto 0);
        dest_clk     : in  std_logic;
        dest_rst     : in  std_logic;
        dest_count   : out unsigned(WIDTH - 1 downto 0)
    );
end entity gray_counter_cdc;

architecture rtl of gray_counter_cdc is
    signal source_gray : std_logic_vector(WIDTH - 1 downto 0);
    signal gray_meta   : std_logic_vector(WIDTH - 1 downto 0) :=
        (others => '0');
    signal gray_sync   : std_logic_vector(WIDTH - 1 downto 0) :=
        (others => '0');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of gray_meta : signal is "TRUE";
    attribute ASYNC_REG of gray_sync : signal is "TRUE";

    function gray_to_binary(value : std_logic_vector) return unsigned is
        variable result : unsigned(value'range);
    begin
        result(result'high) := value(value'high);
        for bit_index in result'high - 1 downto result'low loop
            result(bit_index) :=
                result(bit_index + 1) xor value(bit_index);
        end loop;
        return result;
    end function;
begin
    source_gray <= std_logic_vector(
        source_count xor shift_right(source_count, 1));

    synchronizer : process(dest_clk)
    begin
        if rising_edge(dest_clk) then
            if dest_rst = '1' then
                gray_meta <= (others => '0');
                gray_sync <= (others => '0');
            else
                gray_meta <= source_gray;
                gray_sync <= gray_meta;
            end if;
        end if;
    end process synchronizer;

    dest_count <= gray_to_binary(gray_sync);
end architecture rtl;
