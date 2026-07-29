library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Count completed Ethernet transmit and receive events in the PCS client
-- clock domain. Normal 1000BASE-X carrier extension is filtered internally.
entity ethernet_statistics is
    generic (
        COUNTER_WIDTH : positive := 16
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        active           : in  std_logic;
        clk_enable       : in  std_logic;
        frame_sent       : in  std_logic;
        gmii_rxd          : in  std_logic_vector(7 downto 0);
        rx_dv            : in  std_logic;
        rx_er             : in  std_logic;
        recv_started      : out std_logic;
        recv_error_event  : out std_logic;
        frame_sent_count : out unsigned(COUNTER_WIDTH - 1 downto 0);
        recv_count       : out unsigned(COUNTER_WIDTH - 1 downto 0);
        recv_error_count : out unsigned(COUNTER_WIDTH - 1 downto 0)
    );
end entity ethernet_statistics;

architecture rtl of ethernet_statistics is
    type receive_state_t is (RX_IDLE, RX_FRAME, RX_STANDALONE_ERROR);
    signal receive_state : receive_state_t := RX_IDLE;

    signal frame_sent_count_i : unsigned(COUNTER_WIDTH - 1 downto 0) :=
        (others => '0');
    signal recv_count_i : unsigned(COUNTER_WIDTH - 1 downto 0) :=
        (others => '0');
    signal recv_error_count_i : unsigned(COUNTER_WIDTH - 1 downto 0) :=
        (others => '0');
    signal rx_frame_error : std_logic := '0';
    signal rx_error       : std_logic;
begin
    frame_sent_count <= frame_sent_count_i;
    recv_count       <= recv_count_i;
    recv_error_count <= recv_error_count_i;
    rx_error <= rx_er when not (
        rx_er = '1' and rx_dv = '0' and gmii_rxd = x"0F") else '0';

    count_events : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                frame_sent_count_i <= (others => '0');
                recv_count_i       <= (others => '0');
                recv_error_count_i <= (others => '0');
                receive_state      <= RX_IDLE;
                rx_frame_error     <= '0';
                recv_started       <= '0';
                recv_error_event   <= '0';
            else
                recv_started     <= '0';
                recv_error_event <= '0';

                -- Unsigned arithmetic intentionally provides modulo-2^WIDTH
                -- rollover for all three statistics.
                if frame_sent = '1' then
                    frame_sent_count_i <= frame_sent_count_i + 1;
                end if;

                if active = '0' then
                    -- Discard an incomplete receive event when the PCS client
                    -- interface loses synchronization.  Lifetime counters are
                    -- retained until the external reset is asserted.
                    receive_state  <= RX_IDLE;
                    rx_frame_error <= '0';
                elsif clk_enable = '1' then
                    case receive_state is
                        when RX_IDLE =>
                            if rx_dv = '1' then
                                receive_state  <= RX_FRAME;
                                rx_frame_error <= rx_error;
                                recv_started   <= '1';
                            elsif rx_error = '1' then
                                receive_state <= RX_STANDALONE_ERROR;
                                recv_error_count_i <=
                                    recv_error_count_i + 1;
                                recv_error_event <= '1';
                            end if;

                        when RX_FRAME =>
                            if rx_dv = '1' then
                                if rx_error = '1' then
                                    rx_frame_error <= '1';
                                end if;
                            else
                                -- RX_DV framing and RX_ER are sufficient here:
                                -- the received FCS is deliberately not checked.
                                if rx_frame_error = '1' or rx_error = '1' then
                                    recv_error_count_i <=
                                        recv_error_count_i + 1;
                                    recv_error_event <= '1';
                                else
                                    recv_count_i <= recv_count_i + 1;
                                end if;
                                receive_state  <= RX_IDLE;
                                rx_frame_error <= '0';
                            end if;

                        when RX_STANDALONE_ERROR =>
                            if rx_dv = '1' then
                                receive_state  <= RX_FRAME;
                                rx_frame_error <= rx_error;
                                recv_started   <= '1';
                            elsif rx_error = '0' then
                                receive_state <= RX_IDLE;
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process count_events;
end architecture rtl;
