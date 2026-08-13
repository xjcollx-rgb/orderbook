library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity byte_counter is
    port(   
        clk : in  std_logic;
        rst : in std_logic;
        success : in std_logic;
        offset : in unsigned(2 downto 0);
        frame_size_in : in unsigned(6 downto 0);
        byte_count : out unsigned(6 downto 0);
        state_in : in std_logic:= '1'   

    );

end byte_counter;

architecture rtl of byte_counter is

    signal count_reg : unsigned(6 downto 0):=(others => '0');
    signal current_offset : unsigned(2 downto 0):= (others => '0');
    signal previous_success : std_logic := '0';
    
begin 
    process(clk)
--possibly move previous_success into type_pro so it can reset on the 
        begin 
            if rising_edge(clk) then 
                if rst = '1' then 
                    count_reg <= (others => '0');
                    current_offset <= (others => '0');
                    previous_success <= '0';

                else 

                    if state_in = '1' then 
                        count_reg <= count_reg + 8;
                    end if;

                    if (success = '1')  then 
                        previous_success <= '1';

                    end if;

                    if state_in = '0' then 

                        previous_success <= '0';
                    end if;

                    if (count_reg + resize(current_offset, count_reg'length) + 8 >= frame_size_in) and (previous_success = '1') then 
                        count_reg <= (others => '0');
                        current_offset <= current_offset + offset;


                    end if;
                end if;
            end if;
        end process;

        byte_count <= count_reg + resize(current_offset, count_reg'length);

end rtl;




        
