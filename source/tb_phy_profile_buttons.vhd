library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.dp83867_pkg.all;

entity tb_phy_profile_buttons is
end entity tb_phy_profile_buttons;

architecture sim of tb_phy_profile_buttons is
    constant CLK_PERIOD : time := 10 ns;

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal enable   : std_logic := '0';
    signal button_c : std_logic := '0';
    signal button_n : std_logic := '0';
    signal button_e : std_logic := '0';
    signal button_s : std_logic := '0';
    signal button_w : std_logic := '0';
    signal profile  : phy_profile_t;
    signal apply    : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.phy_profile_buttons
        generic map (
            DEBOUNCE_CYCLES => 3
        )
        port map (
            clk      => clk,
            rst      => rst,
            enable   => enable,
            button_c => button_c,
            button_n => button_n,
            button_e => button_e,
            button_s => button_s,
            button_w => button_w,
            profile  => profile,
            apply    => apply
        );

    stimulus : process
        procedure wait_clocks(constant count : in positive) is
        begin
            for clock_index in 1 to count loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        procedure expect_press(
            constant expected_profile : in phy_profile_t
        ) is
        begin
            wait until apply = '1';
            assert profile = expected_profile
                report "Pushbutton selected the wrong PHY profile"
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
            assert apply = '0'
                report "Profile apply event was longer than one clock"
                severity failure;
        end procedure;

        procedure release_buttons is
        begin
            button_c <= '0';
            button_n <= '0';
            button_e <= '0';
            button_s <= '0';
            button_w <= '0';
            wait_clocks(8);
        end procedure;
    begin
        wait_clocks(2);
        rst    <= '0';
        enable <= '1';
        wait_clocks(2);
        assert profile = PHY_PROFILE_CENTER
            report "Pushbutton controller did not default to Center"
            severity failure;

        -- A pulse shorter than the debounce interval must be ignored.
        button_n <= '1';
        wait_clocks(2);
        button_n <= '0';
        wait_clocks(8);
        assert apply = '0' and profile = PHY_PROFILE_CENTER
            report "Short button pulse was not rejected" severity failure;

        button_n <= '1';
        expect_press(PHY_PROFILE_NORTH);
        release_buttons;

        button_e <= '1';
        expect_press(PHY_PROFILE_EAST);
        release_buttons;

        button_s <= '1';
        expect_press(PHY_PROFILE_SOUTH);
        release_buttons;

        button_w <= '1';
        expect_press(PHY_PROFILE_WEST);
        release_buttons;

        -- Re-selecting the active profile deliberately requests another run.
        button_w <= '1';
        expect_press(PHY_PROFILE_WEST);
        release_buttons;

        -- An ambiguous multi-button press must not select either profile.
        button_c <= '1';
        button_n <= '1';
        wait_clocks(8);
        assert apply = '0' and profile = PHY_PROFILE_WEST
            report "Simultaneous buttons were not rejected" severity failure;
        release_buttons;

        -- Presses made while PHY initialization is busy are ignored.
        enable   <= '0';
        button_c <= '1';
        wait_clocks(8);
        assert apply = '0' and profile = PHY_PROFILE_WEST
            report "Disabled pushbutton controller accepted a profile"
            severity failure;
        release_buttons;
        enable <= '1';

        button_c <= '1';
        expect_press(PHY_PROFILE_CENTER);
        release_buttons;

        report "PHY profile pushbutton synchronization and debounce verified"
            severity note;
        stop;
        wait;
    end process stimulus;

    watchdog : process
    begin
        wait for 5 us;
        assert false report "PHY profile pushbutton test timed out"
            severity failure;
        wait;
    end process watchdog;
end architecture sim;
