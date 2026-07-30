library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debug_status_pkg.all;

-- Stream a coherent snapshot of the fixed-format debug status line one byte at
-- a time. This avoids storing and serializing a multi-kilobit vector.
entity uart_status_report is
    generic (
        CLOCK_FREQ_HZ   : positive := 125_000_000;
        BAUD_RATE       : positive := 9600;
        PAUSE_BIT_TIMES : positive := 5
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        status     : in  debug_status_t;
        snapshot_taken : out std_logic;
        data_out   : out std_logic_vector(7 downto 0);
        data_valid : out std_logic;
        data_ready : in  std_logic
    );
end entity uart_status_report;

architecture rtl of uart_status_report is
    constant CLKS_PER_BIT : positive := CLOCK_FREQ_HZ / BAUD_RATE;
    constant PAUSE_CYCLES : positive := CLKS_PER_BIT * PAUSE_BIT_TIMES;
    constant WORD_COUNT   : positive := 23;
    constant LAST_SEGMENT : natural := WORD_COUNT * 2;

    type report_state_t is (PAUSE, SEND);
    signal state           : report_state_t := PAUSE;
    signal pause_count     : natural range 0 to PAUSE_CYCLES - 1 := 0;
    signal segment_index   : natural range 0 to LAST_SEGMENT := 0;
    signal character_index : natural range 0 to 31 := 0;
    signal status_latched  : debug_status_t := DEBUG_STATUS_RESET;
    signal snapshot_taken_i : std_logic := '0';

    subtype text_segment_t is string(1 to 20);

    function padded_text(text_value : string) return text_segment_t is
        variable result : text_segment_t := (others => ' ');
    begin
        for source_index in text_value'range loop
            result(source_index - text_value'low + 1) :=
                text_value(source_index);
        end loop;
        return result;
    end function;

    function segment_is_word(segment_value : natural) return boolean is
    begin
        return segment_value mod 2 = 1;
    end function;

    function segment_text(segment_value : natural) return text_segment_t is
    begin
        case segment_value is
            when 0  => return padded_text("FRAME(S=0x");
            when 2  => return padded_text(" R=0x");
            when 4  => return padded_text(" F=0x");
            when 6  => return padded_text(" E=0x");
            when 8  => return padded_text(") PCS=0x");
            when 10 => return padded_text(" PHYSTS=0x");
            when 12 => return padded_text(" BMCR=0x");
            when 14 => return padded_text(" BMSR=0x");
            when 16 => return padded_text(" STS1=0x");
            when 18 => return padded_text(" RECR=0x");
            when 20 => return padded_text(" ISR=0x");
            when 22 => return padded_text(" MSE(A=0x");
            when 24 => return padded_text(" B=0x");
            when 26 => return padded_text(" C=0x");
            when 28 => return padded_text(" D=0x");
            when 30 => return padded_text(") ANAR=0x");
            when 32 => return padded_text(" ANLPAR=0x");
            when 34 => return padded_text(" ANER=0x");
            when 36 => return padded_text(" PHYCR=0x");
            when 38 => return padded_text(" CFG1=0x");
            when 40 => return padded_text(" CFG4=0x");
            when 42 => return padded_text(" STRAP2=0x");
            when 44 => return padded_text(" ANA_LD=0x");
            when 46 => return padded_text(CR & LF);
            when others => return (others => ' ');
        end case;
    end function;

    function status_word (
        status_value : debug_status_t;
        word_index   : natural
    ) return std_logic_vector is
    begin
        case word_index is
            when 0  => return status_value.frame_sent_count;
            when 1  => return status_value.recv_count;
            when 2  => return status_value.recv_fcs_error_count;
            when 3  => return status_value.recv_error_count;
            when 4  => return status_value.pcs_status;
            when 5  => return status_value.phy.physts;
            when 6  => return status_value.phy.bmcr;
            when 7  => return status_value.phy.bmsr;
            when 8  => return status_value.phy.sts1;
            when 9  => return status_value.phy.recr;
            when 10 => return status_value.phy.isr;
            when 11 => return status_value.phy.mse_a;
            when 12 => return status_value.phy.mse_b;
            when 13 => return status_value.phy.mse_c;
            when 14 => return status_value.phy.mse_d;
            when 15 => return status_value.phy.anar;
            when 16 => return status_value.phy.anlpar;
            when 17 => return status_value.phy.aner;
            when 18 => return status_value.phy.phycr;
            when 19 => return status_value.phy.cfg1;
            when 20 => return status_value.phy.cfg4;
            when 21 => return status_value.phy.strap_sts2;
            when 22 => return status_value.phy.ana_ld_data_ctrl;
            when others => return x"0000";
        end case;
    end function;

    function hex_character(nibble : std_logic_vector(3 downto 0))
        return character is
    begin
        case nibble is
            when x"0" => return '0';
            when x"1" => return '1';
            when x"2" => return '2';
            when x"3" => return '3';
            when x"4" => return '4';
            when x"5" => return '5';
            when x"6" => return '6';
            when x"7" => return '7';
            when x"8" => return '8';
            when x"9" => return '9';
            when x"A" => return 'A';
            when x"B" => return 'B';
            when x"C" => return 'C';
            when x"D" => return 'D';
            when x"E" => return 'E';
            when x"F" => return 'F';
            when others => return '?';
        end case;
    end function;

    function current_character (
        segment_value   : natural;
        character_value : natural;
        status_value    : debug_status_t
    ) return character is
        variable word_value : std_logic_vector(15 downto 0);
        variable text_value : text_segment_t;
    begin
        if segment_is_word(segment_value) then
            word_value := status_word(status_value, segment_value / 2);
            return hex_character(word_value(
                15 - character_value * 4 downto
                12 - character_value * 4));
        end if;
        text_value := segment_text(segment_value);
        return text_value(character_value + 1);
    end function;

    function current_length(segment_value : natural) return positive is
    begin
        if segment_is_word(segment_value) then
            return 4;
        end if;
        case segment_value is
            when 0             => return 10;
            when 2 | 4 | 6     => return 5;
            when 8             => return 8;
            when 10            => return 10;
            when 12 | 14 | 16 |
                 18 | 34 | 38 |
                 40            => return 8;
            when 20            => return 7;
            when 22            => return 9;
            when 24 | 26 | 28  => return 5;
            when 30 | 36       => return 9;
            when 32 | 42 | 44  => return 10;
            when 46            => return 2;
            when others        => return 1;
        end case;
    end function;
begin
    snapshot_taken <= snapshot_taken_i;
    data_valid <= '1' when state = SEND else '0';
    data_out <= std_logic_vector(to_unsigned(character'pos(current_character(
        segment_index, character_index, status_latched)), 8));

    sequencer : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state           <= PAUSE;
                pause_count     <= 0;
                segment_index   <= 0;
                character_index <= 0;
                status_latched  <= DEBUG_STATUS_RESET;
                snapshot_taken_i <= '0';
            else
                snapshot_taken_i <= '0';
                case state is
                    when PAUSE =>
                        if pause_count = PAUSE_CYCLES - 1 then
                            pause_count     <= 0;
                            segment_index   <= 0;
                            character_index <= 0;
                            status_latched  <= status;
                            snapshot_taken_i <= '1';
                            state           <= SEND;
                        else
                            pause_count <= pause_count + 1;
                        end if;

                    when SEND =>
                        if data_ready = '1' then
                            if character_index =
                               current_length(segment_index) - 1 then
                                character_index <= 0;
                                if segment_index = LAST_SEGMENT then
                                    state       <= PAUSE;
                                    pause_count <= 0;
                                else
                                    segment_index <= segment_index + 1;
                                end if;
                            else
                                character_index <= character_index + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process sequencer;
end architecture rtl;
