library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity type_processor_tb is
end entity;

architecture simple of type_processor_tb is

    component type_processor
        port (
            data           : in  unsigned(63 downto 0);
            clk            : in  std_logic;
            rst            : in  std_logic;
            frame          : out unsigned(199 downto 0);
            byte_count     : in  unsigned(6 downto 0);
            success        : out std_logic;
            frame_type_out : out unsigned(2 downto 0);
            offset_out     : out unsigned(2 downto 0)
        );
    end component;

    component byte_counter
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            success       : in  std_logic;
            offset        : in  unsigned(2 downto 0);
            frame_type_in : in  unsigned(2 downto 0);
            byte_count    : out unsigned(6 downto 0)
        );
    end component;

    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal data_in        : unsigned(63 downto 0) := (others => '0');
    signal byte_count     : unsigned(6 downto 0);
    signal success        : std_logic;
    signal frame_type_out : unsigned(2 downto 0);
    signal offset_out     : unsigned(2 downto 0);

    constant T : time := 10 ns;

    -- Pre?computed word sequence (18 words)
    type word_array is array (natural range <>) of unsigned(63 downto 0);
    constant words : word_array(0 to 17) := (
        -- 0: ADD type (x41) in byte0
        x"0000000000000058",
        -- 1?4: don't care (ADD payload)
        x"0000000000000000",
        x"0000000000000000",
        x"0000000000000000",
        x"0000000000000000",
        -- 5: CANCEL type (x58) in byte0
        x"0000000000000041",
        -- 6?7: don't care (CANCEL payload)
        x"0000000000000000",
        x"0000000000000000",
        -- 8: REPLACE type (x55) in byte4 (bits 39..32)
        x"0000005500000000",
        -- 9?11: don't care (REPLACE payload)
        x"0000000000000000",
        x"0000000000000000",
        x"0000000000000000",
        -- 12: EXECUTED type (x45) in byte5 (bits 47..40)
        x"0000450000000000",
        -- 13?15: don't care (EXECUTED payload)
        x"0000000000000000",
        x"0000000000000000",
        x"0000000000000000",
        -- 16: DELETE type (x44) in byte2 (bits 23..16)
        x"0000000000440000",
        -- 17: don't care
        x"0000000000000000"
    );

begin

    clk <= not clk after T/2;

    uut: type_processor port map (
        data_in, clk, rst, open, byte_count,
        success, frame_type_out, offset_out
    );

    cnt: byte_counter port map (
        clk, rst, success, offset_out,
        frame_type_out, byte_count
    );

    -- Main stimulus
    process
    begin
        -- Reset
        rst <= '1';
        wait for 3 * T;
        rst <= '0';
        -- Send the 18 words, one per clock
        for i in 0 to 17 loop
            data_in <= words(i);
            wait until rising_edge(clk);
        end loop;
        -- Wait a few more cycles to see any final activity
        wait for 5 * T;
        report "Test finished" severity note;
        wait;
    end process;

    -- Monitor successes
    process(clk)
        variable cnt : integer := 0;
    begin
        if rising_edge(clk) and success = '1' then
            cnt := cnt + 1;
            report "Frame #" & integer'image(cnt) &
                   " type=" & integer'image(to_integer(frame_type_out)) &
                   " at time " & time'image(now);
        end if;
    end process;

end architecture;