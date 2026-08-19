library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_tb is
end fifo_tb;


architecture sim of fifo_tb is

    constant DATA_WIDTH : integer := 200;
    constant DEPTH      : integer := 2048;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal din  : unsigned(DATA_WIDTH - 1 downto 0) := (others => '0');
    signal dout : unsigned(DATA_WIDTH - 1 downto 0);

    signal full_out  : std_logic;
    signal empty_out : std_logic;

    signal succes_in : std_logic := '0';
    signal read_in   : std_logic := '0';

begin

    -- Clock: 10 ns period
    clk <= not clk after 5 ns;


    -- DUT
    uut : entity work.fifo
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            DEPTH      => DEPTH
        )
        port map (
            clk        => clk,
            rst        => rst,

            din        => din,
            dout       => dout,

            full_out   => full_out,
            empty_out  => empty_out,

            success_in  => succes_in,
            read_in    => read_in
        );


    process
    begin

        --------------------------------------------------
        -- RESET
        --------------------------------------------------

        rst <= '1';

        wait for 20 ns;

        rst <= '0';

        wait for 10 ns;


        --------------------------------------------------
        -- WRITE 3 VALUES
        --------------------------------------------------

        din <= to_unsigned(100, DATA_WIDTH);
        succes_in <= '1';

        wait for 10 ns;


        din <= to_unsigned(200, DATA_WIDTH);

        wait for 10 ns;


        din <= to_unsigned(300, DATA_WIDTH);

        wait for 10 ns;


        succes_in <= '0';

        wait for 10 ns;


        --------------------------------------------------
        -- READ FIRST VALUE
        --------------------------------------------------

        read_in <= '1';

        wait for 10 ns;

        read_in <= '0';

        wait for 10 ns;

        assert dout = to_unsigned(100, DATA_WIDTH)
            report "ERROR: Expected 100"
            severity error;


        --------------------------------------------------
        -- READ SECOND VALUE
        --------------------------------------------------

        read_in <= '1';

        wait for 10 ns;

        read_in <= '0';

        wait for 10 ns;

        assert dout = to_unsigned(200, DATA_WIDTH)
            report "ERROR: Expected 200"
            severity error;


        --------------------------------------------------
        -- READ THIRD VALUE
        --------------------------------------------------

        read_in <= '1';

        wait for 10 ns;

        read_in <= '0';

        wait for 10 ns;

        assert dout = to_unsigned(300, DATA_WIDTH)
            report "ERROR: Expected 300"
            severity error;


        --------------------------------------------------
        -- FIFO SHOULD NOW BE EMPTY
        --------------------------------------------------

        assert empty_out = '1'
            report "ERROR: FIFO should be empty"
            severity error;


        report "FIFO TEST PASSED"
            severity note;


        wait;

    end process;

end sim;