library ieee;
use ieee.std_logic_1164.all;

-- Assert reset asynchronously and release it synchronously in the destination
-- clock domain.
entity reset_synchronizer is
    generic (
        STAGES : positive range 2 to 8 := 2
    );
    port (
        clk       : in  std_logic;
        async_rst : in  std_logic;
        sync_rst  : out std_logic
    );
end entity reset_synchronizer;

architecture rtl of reset_synchronizer is
    signal reset_pipe : std_logic_vector(STAGES - 1 downto 0) :=
        (others => '1');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of reset_pipe : signal is "TRUE";
begin
    synchronize : process(clk, async_rst)
    begin
        if async_rst = '1' then
            reset_pipe <= (others => '1');
        elsif rising_edge(clk) then
            reset_pipe <= reset_pipe(reset_pipe'high - 1 downto 0) & '0';
        end if;
    end process synchronize;

    sync_rst <= reset_pipe(reset_pipe'high);
end architecture rtl;
