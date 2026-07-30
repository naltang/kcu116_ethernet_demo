library ieee;
use ieee.std_logic_1164.all;
use work.dp83867_pkg.all;

package debug_status_pkg is
    type debug_status_t is record
        profile_code     : std_logic_vector(7 downto 0);
        frame_sent_count : std_logic_vector(15 downto 0);
        recv_count       : std_logic_vector(15 downto 0);
        recv_fcs_error_count : std_logic_vector(15 downto 0);
        recv_error_count : std_logic_vector(15 downto 0);
        pcs_status       : std_logic_vector(15 downto 0);
        phy              : phy_diagnostics_t;
    end record;

    constant DEBUG_STATUS_RESET : debug_status_t := (
        profile_code     => phy_profile_code(PHY_PROFILE_CENTER),
        frame_sent_count => (others => '0'),
        recv_count       => (others => '0'),
        recv_fcs_error_count => (others => '0'),
        recv_error_count => (others => '0'),
        pcs_status       => (others => '0'),
        phy              => PHY_DIAGNOSTICS_RESET
    );
end package debug_status_pkg;
