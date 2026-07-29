library ieee;
use ieee.std_logic_1164.all;

-- Transfer a coherent, slowly changing status vector using a toggle handshake.
-- The source holds the data stable until the destination acknowledges it.
entity status_snapshot_cdc is
    generic (
        WIDTH : positive := 16
    );
    port (
        source_clk  : in  std_logic;
        source_rst  : in  std_logic;
        source_data : in  std_logic_vector(WIDTH - 1 downto 0);
        dest_clk    : in  std_logic;
        dest_rst    : in  std_logic;
        dest_data   : out std_logic_vector(WIDTH - 1 downto 0)
    );
end entity status_snapshot_cdc;

architecture rtl of status_snapshot_cdc is
    signal data_hold   : std_logic_vector(WIDTH - 1 downto 0) :=
        (others => '0');
    signal request_src : std_logic := '0';
    signal request_meta, request_sync : std_logic := '0';
    signal acknowledge_dest : std_logic := '0';
    signal acknowledge_meta, acknowledge_sync : std_logic := '0';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of request_meta : signal is "TRUE";
    attribute ASYNC_REG of request_sync : signal is "TRUE";
    attribute ASYNC_REG of acknowledge_meta : signal is "TRUE";
    attribute ASYNC_REG of acknowledge_sync : signal is "TRUE";
begin
    source_controller : process(source_clk)
    begin
        if rising_edge(source_clk) then
            if source_rst = '1' then
                data_hold        <= (others => '0');
                request_src      <= '0';
                acknowledge_meta <= '0';
                acknowledge_sync <= '0';
            else
                acknowledge_meta <= acknowledge_dest;
                acknowledge_sync <= acknowledge_meta;

                if request_src = acknowledge_sync and
                   source_data /= data_hold then
                    data_hold   <= source_data;
                    request_src <= not request_src;
                end if;
            end if;
        end if;
    end process source_controller;

    destination_controller : process(dest_clk)
    begin
        if rising_edge(dest_clk) then
            if dest_rst = '1' then
                request_meta     <= '0';
                request_sync     <= '0';
                acknowledge_dest <= '0';
                dest_data        <= (others => '0');
            else
                request_meta <= request_src;
                request_sync <= request_meta;

                if request_sync /= acknowledge_dest then
                    dest_data        <= data_hold;
                    acknowledge_dest <= request_sync;
                end if;
            end if;
        end if;
    end process destination_controller;
end architecture rtl;
