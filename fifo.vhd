library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo is 

    generic(
        DATA_WIDTH : integer := 203;
        DEPTH      : integer := 2048
    );

    port (
        clk : in std_logic;
        rst : in std_logic;

        din  : in  unsigned(DATA_WIDTH - 1 downto 0);
        dout : out unsigned(DATA_WIDTH - 1 downto 0) := (others => '0');

        full_out  : out std_logic := '0';
        empty_out : out std_logic := '1';

        success_in : in std_logic;
        read_in   : in std_logic
    );

end fifo;


architecture rtl of fifo is

    signal write_point : unsigned(10 downto 0) := (others => '0');
    signal read_point  : unsigned(10 downto 0) := (others => '0');

    signal full  : std_logic := '0';
    signal empty : std_logic := '1';

    type ram_t is array (0 to 2047) of unsigned(202 downto 0);
    signal ram : ram_t := (others => (others => '0')); 

    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";

    signal count : unsigned(11 downto 0) := (others => '0');

begin

    process(clk)

        variable count_next : unsigned(11 downto 0);

    begin 

        if rising_edge(clk) then 

            if rst = '1' then
                
                write_point <= (others => '0');
                read_point  <= (others => '0');

                count <= (others => '0');

                full  <= '0';
                empty <= '1';

            else 

                -- Start with the current count
                count_next := count;


                -- WRITE
                if success_in = '1' and full = '0'  then 

                    ram(to_integer(write_point)) <= din;
                    write_point <= write_point + 1;

                end if;


                -- READ
                if read_in = '1' and empty = '0' then 

                    read_point <= read_point + 1;

                end if;


                -- Update count
                if success_in = '1' and full = '0' and
                   not (read_in = '1' and empty = '0') then

                    count_next := count + 1;

                end if;

                if read_in = '1' and empty = '0' then 

                    dout <= ram(to_integer(read_point));
                    read_point <= read_point + 1;

                    count_next := count - 1;

                end if;


                -- Store new count
                count <= count_next;


                -- Update EMPTY
                if count_next = 0 then
                    empty <= '1';
                else
                    empty <= '0';
                end if;


                -- Update FULL
                if count_next = 2048 then
                    full <= '1';
                else
                    full <= '0';
                end if;

            end if;


        end if;

    end process;


    -- Outputs
    full_out  <= full;
    empty_out <= empty;

end rtl;