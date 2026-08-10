library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity byte_count is
    port(   
        clk : in  std_logic;
        rst : in std_logic;
        byte_count : out unsigned(6 downto 0)    

    );

end byte_count;

architecture rtl of byte_count is

    signal count_reg : unsigned(6 downto 0):=(others => '0');
begin 
    process(clk)

        begin 
            if rising_edge(clk) then 
                if rst = '1' then 
                    count_reg <= (others => '0');
                else 

                    if count_reg >= 32 then 
                        count_reg <= (others => '0');
                        
                    else 
                        count_reg <= count_reg + 8;

                    end if;
                end if;
            end if;
        end process;

        byte_count <= count_reg;

end rtl;




        