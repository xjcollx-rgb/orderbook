library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ref_table is 
port (
    clk : in STD_LOGIC;
    rst : in STD_LOGIC;
    data : in unsigned(135 downto 0);
    success : in std_logic;
    frame_type : unsigned(1 downto 0)
    


);
end ref_table;

architecture rtl of ref_table is 

    type ram_t is array (0 to 4095) of unsigned(71 downto 0);
    signal ram : ram_t;

    
    constant ADD      : unsigned(1 downto 0) := "00";
    constant CANCEL   : unsigned(1 downto 0) := "01";
    constant REPLACE  : unsigned(1 downto 0) := "10";
    constant EXECUTED : unsigned(1 downto 0) := "11";

    signal address : unsigned(12 downto 0) := (others => '0');



begin 

process(clk)
begin 

    address <= data( 85 downto 72) / 2;


    if rising_edge(clk) then 

        case frame_type is 
            when ADD => 
            -- If this address is null, if not then + 2 to address and tey again; 
                ram(to_integer(address)) <= data(135 downto 64);
                ram(to_integer(address + 1)) <= data(63 downto 0);

            when CANCEL => 

                while(ram(to_integer()))

            when REPLACE => 

            when EXECUTED => 

        end case;

    end if;

end process;
    

end architecture;