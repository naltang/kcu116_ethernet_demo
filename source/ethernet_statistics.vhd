library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Count completed Ethernet transmit and receive events in the PCS client
-- clock domain.  RX_ERROR is expected to have the normal 1000BASE-X carrier
-- extension indication filtered before it reaches this entity.
entity ethernet_statistics is
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        active           : in  std_logic;
        clk_enable       : in  std_logic;
        frame_sent       : in  std_logic;
        rx_dv            : in  std_logic;
        rx_error         : in  std_logic;
        frame_sent_count : out unsigned(15 downto 0);
        recv_count       : out unsigned(15 downto 0);
        recv_error_count : out unsigned(15 downto 0)
    );
end entity ethernet_statistics;

architecture rtl of ethernet_statistics is
    signal frame_sent_count_i : unsigned(15 downto 0) := (others => '0');
    signal recv_count_i       : unsigned(15 downto 0) := (others => '0');
    signal recv_error_count_i : unsigned(15 downto 0) := (others => '0');

    signal rx_in_frame     : std_logic := '0';
    signal rx_frame_error  : std_logic := '0';
    signal rx_error_active : std_logic := '0';
begin
    frame_sent_count <= frame_sent_count_i;
    recv_count       <= recv_count_i;
    recv_error_count <= recv_error_count_i;

    count_events : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                frame_sent_count_i <= (others => '0');
                recv_count_i       <= (others => '0');
                recv_error_count_i <= (others => '0');
                rx_in_frame        <= '0';
                rx_frame_error     <= '0';
                rx_error_active    <= '0';
            else
                -- Unsigned arithmetic intentionally provides modulo-2^16
                -- rollover for all three statistics.
                if frame_sent = '1' then
                    frame_sent_count_i <= frame_sent_count_i + 1;
                end if;

                if active = '0' then
                    -- Discard an incomplete receive event when the PCS client
                    -- interface loses synchronization.  Lifetime counters are
                    -- retained until the external reset is asserted.
                    rx_in_frame     <= '0';
                    rx_frame_error  <= '0';
                    rx_error_active <= '0';
                elsif clk_enable = '1' then
                    rx_error_active <= rx_error;

                    if rx_dv = '1' then
                        if rx_in_frame = '0' then
                            rx_in_frame    <= '1';
                            rx_frame_error <= rx_error;
                        elsif rx_error = '1' then
                            rx_frame_error <= '1';
                        end if;
                    else
                        if rx_in_frame = '1' then
                            -- RX_DV framing and RX_ERROR are sufficient here:
                            -- the received FCS bytes are deliberately not
                            -- calculated or compared.
                            if rx_frame_error = '1' or rx_error = '1' then
                                recv_error_count_i <= recv_error_count_i + 1;
                            else
                                recv_count_i <= recv_count_i + 1;
                            end if;
                            rx_in_frame    <= '0';
                            rx_frame_error <= '0';
                        elsif rx_error = '1' and rx_error_active = '0' then
                            -- Count a false-carrier/code-error event that is
                            -- not accompanied by RX_DV once, regardless of
                            -- how many enabled cycles it remains asserted.
                            recv_error_count_i <= recv_error_count_i + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process count_events;
end architecture rtl;
