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
        byte_count : out unsigned(6 downto 0)    

    );

end byte_counter;

architecture rtl of byte_counter is

    signal count_reg : unsigned(6 downto 0):=(others => '0');
    signal current_offset : unsigned(2 downto 0):= (others => '0');
    signal current_success : std_logic := '0';
    
begin 
    process(clk)
--need to make this counter reset depend on frame size and not success
        begin 
            if rising_edge(clk) then 
                if rst = '1' then 
                    count_reg <= (others => '0');
                    current_offset <= (others => '0');
                    current_success <= '0';

                else 

                    count_reg <= count_reg + 8;

                    if (success = '1')  then 

                        if current_success = '1' then 
                            --current_offset <= resize(offset, current_offset'length);
                        else 

                            current_success <= '1';
                            
                        end if;

                    end if;

                    if (count_reg + resize(current_offset, count_reg'length) + 8 >= frame_size_in) and (current_success = '1') then 
                        count_reg <= (others => '0');
                        current_offset <= current_offset + offset;


                    end if;
                end if;
            end if;
        end process;

        byte_count <= count_reg + resize(current_offset, count_reg'length);

end rtl;




        
