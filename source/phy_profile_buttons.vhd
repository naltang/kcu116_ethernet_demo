library ieee;
use ieee.std_logic_1164.all;
use work.dp83867_pkg.all;

-- Synchronize and debounce the five active-high directional pushbuttons.
-- A valid press selects one PHY profile and emits one reinitialization pulse.
entity phy_profile_buttons is
    generic (
        DEBOUNCE_CYCLES : positive := 1_250_000
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        enable    : in  std_logic;
        button_c  : in  std_logic;
        button_n  : in  std_logic;
        button_e  : in  std_logic;
        button_s  : in  std_logic;
        button_w  : in  std_logic;
        profile   : out phy_profile_t;
        apply     : out std_logic
    );
end entity phy_profile_buttons;

architecture rtl of phy_profile_buttons is
    -- Bit order is C, N, E, S, W.
    signal button_meta   : std_logic_vector(4 downto 0) :=
        (others => '0');
    signal button_sync   : std_logic_vector(4 downto 0) :=
        (others => '0');
    signal button_stable : std_logic_vector(4 downto 0) :=
        (others => '0');

    type debounce_count_array_t is
        array (button_stable'range) of
            natural range 0 to DEBOUNCE_CYCLES - 1;
    signal debounce_count : debounce_count_array_t := (others => 0);

    signal profile_i : phy_profile_t := PHY_PROFILE_CENTER;
    signal apply_i   : std_logic := '0';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of button_meta : signal is "TRUE";
    attribute ASYNC_REG of button_sync : signal is "TRUE";
begin
    profile <= profile_i;
    apply   <= apply_i;

    controller : process(clk)
        variable pressed : std_logic_vector(4 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                button_meta   <= (others => '0');
                button_sync   <= (others => '0');
                button_stable <= (others => '0');
                debounce_count <= (others => 0);
                profile_i     <= PHY_PROFILE_CENTER;
                apply_i       <= '0';
            else
                button_meta <=
                    button_c & button_n & button_e & button_s & button_w;
                button_sync <= button_meta;
                apply_i     <= '0';
                pressed     := (others => '0');

                for button_index in button_stable'range loop
                    if button_sync(button_index) =
                       button_stable(button_index) then
                        debounce_count(button_index) <= 0;
                    elsif debounce_count(button_index) =
                          DEBOUNCE_CYCLES - 1 then
                        debounce_count(button_index) <= 0;
                        button_stable(button_index) <=
                            button_sync(button_index);
                        if button_sync(button_index) = '1' then
                            pressed(button_index) := '1';
                        end if;
                    else
                        debounce_count(button_index) <=
                            debounce_count(button_index) + 1;
                    end if;
                end loop;

                -- Accept exactly one new press only when no other button was
                -- already held. Pressing the selected button again deliberately
                -- reruns that profile for another independent trial.
                if enable = '1' and button_stable = "00000" then
                    case pressed is
                        when "10000" =>
                            profile_i <= PHY_PROFILE_CENTER;
                            apply_i   <= '1';
                        when "01000" =>
                            profile_i <= PHY_PROFILE_NORTH;
                            apply_i   <= '1';
                        when "00100" =>
                            profile_i <= PHY_PROFILE_EAST;
                            apply_i   <= '1';
                        when "00010" =>
                            profile_i <= PHY_PROFILE_SOUTH;
                            apply_i   <= '1';
                        when "00001" =>
                            profile_i <= PHY_PROFILE_WEST;
                            apply_i   <= '1';
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process controller;
end architecture rtl;
