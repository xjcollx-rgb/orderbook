library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ref_table is 
port (
    clk : in STD_LOGIC;
    rst : in STD_LOGIC;
    data : in unsigned(191 downto 0);
    success : in std_logic;
    frame_type : unsigned(1 downto 0)

);
end ref_table;

architecture rtl of ref_table is 

    type ram_t is array (0 to 8191) of unsigned(143 downto 0);
    type valid_t is array (0 to 8191) of std_logic;
    signal ram : ram_t := (others => (others => '0'));
    signal valid : valid_t := (others => '0');

    type state_t is (IDLE, READ, WRITE);
    signal state : state_t := IDLE;
    
    constant ADD      : unsigned(2 downto 0) := "000";
    constant CANCEL   : unsigned(2 downto 0) := "001";
    constant REPLACE  : unsigned(2 downto 0) := "010";
    constant EXECUTED : unsigned(2 downto 0) := "011";
    constant DELETE   : unsigned(2 downto 0) := "100";
    constant MAX_STORAGE : unsigned(12 downto 0) := "1111111111111";

    signal address : unsigned(12 downto 0) := (others => '0');
    signal read_data : unsigned(135 downto 0);
    signal search_count : unsigned(4 downto 0):= (others => '0');

begin 

    address <= (data(135 downto 72) mod MAX_STORAGE);

    process(clk)
    begin 

        if rising_edge (clk) then 
            if rst = '1' then 
                state <= IDLE;
                valid <= (others => '0');

            else 
                case state is 

                    when IDLE => 
                        if success = '1' then 
                            case frame_type is 
                                when ADD =>
                                    state <= WRITE;

                                when CANCEL | EXECUTED | REPLACE =>
                                state <= READ;

                                when others => null;
                            end case;

                        end if;
                    
                    when READ =>
                        read_data <= ram(to_integer(address));

                        if read_data(135 downto 72) = data(135 downto 72) and valid(to_integer(address)) = '1' then 
                            state <= WRITE;
                            search_count <= (others => '0');
                        elsif search_count >= 20 then 
                            state <= IDLE;
                            search_count <= (others => '0');
                        else 

                        address <= address + 1;
                        search_count <= search_count +1;

                        end if; 

                    when WRITE => 
                        Case frame_type is
                            when ADD =>
                                if valid(to_integer(address)) = '0' then 
                                    ram(to_integer(address)) <= data(135 downto 0);
                                    state <= IDLE;
                                else 
                                    address <= address + 1;
                                end if;

                            when CANCEL | EXECUTED =>
                                read_data(63 downto 32) <= read_data(63 downto 32) - data(63 downto 32);

                                if read_data(63 downto 32) >= 0 then 
                                    valid(to_integer(address)) <= '0';
                                    state <= IDLE;
                                else
                                    ram(to_integer(address)) <= read_data;
                                    state <= IDLE;
                                end if;

                            when REPLACE =>
                                read_data(135 downto 72) <= data(191 downto 136);
                                read_data(63 downto 0) <= data(63 downto 0);
                                ram(to_integer(address)) <= read_data;
                                state <= IDLE;

                            when DELETE =>
                                valid_t(address) <= '0';
                                state <= IDLE;
                        end case; 

                end case;
                
            end if;

        end if;


    end process;
    

end architecture;