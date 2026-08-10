library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity byte_counter is
    port(   
        clk : in  std_logic;
        rst : in std_logic;
        success : in std_logic;
        offset : in unsigned(2 downto 0);
        frame_type_in : in unsigned(2 downto 0);
        byte_count : out unsigned(6 downto 0)    

    );

end byte_counter;

architecture rtl of byte_counter is

    signal count_reg : unsigned(6 downto 0):=(others => '0');
    signal current_offset : unsigned(6 downto 0):= (others => '0');
    
begin 
    process(clk)

        begin 
            if rising_edge(clk) then 
                if rst = '1' then 
                    count_reg <= (others => '0');
                    current_offset <= (others => '0');
                else 

                    if (success = '1') and (frame_type_in /= "000") then 
                        count_reg <= (others => '0');
                        current_offset <= resize(offset, current_offset'length);

                    elsif count_reg >= 32 then 
                        count_reg <= (others => '0');

                    else 
                        count_reg <= count_reg + 8;

                    end if;
                end if;
            end if;
        end process;

        byte_count <= count_reg + resize(current_offset, count_reg'length);

end rtl;




        
