library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bbo is 

port (

    clk : in std_logic;
    rst : in std_logic;
    price_in : in unsigned( 31 downto 0); 
    shares_in : in unsigned(47 downto 0);
    side_in : in unsigned(7 downto 0);
    delete_in : in std_logic;
    data_written : in std_logic;


    best_buy_price : out unsigned(31 downto 0);
    best_buy_shares : out unsigned(47 downto 0);
    best_sell_price : out unsigned(31 downto 0);
    best_sell_shares : out unsigned(47 downto 0);
    full_table_rescan : out std_logic
    
);

end bbo;

architecture rtl of bbo is 

    -- sides
    constant BUY : unsigned(7 downto 0) := x"42";
    constant SELL : unsigned(7 downto 0) := x"53";

    signal buy_prices : unsigned(319 downto 0);
    signal buy_shares : unsigned(479 downto  0);

    signal sell_prices : unsigned(319 downto  0);
    signal sell_shares : unsigned(479 downto 0);

    signal buy_price_count : unsigned(3 downto 0);
    signal sell_price_count : unsigned(3 downto 0);

    signal reconstruction : std_logic;

begin 

    process(clk)

    begin 

        if rising_edge(clk) then
            
            if rst = '1' then
                
            else 

                if data_written = '1' then 

                    if reconstruction = '0' then

                        if delete_in = '0' then 
                        
                            if side_in = BUY then       
                            
                                if price_in > best_buy_price(319 downto 288) then 

                                    best_buy_price <= price_in & best_buy_price(319 downto 32);
                                    best_buy_shares <= shares_in & best_buy_shares(479 downto 48);
                                    
                                    buy_price_count <= buy_price_count + 1;

                                elsif price_in = best_buy_price (319 downto 288) then
                                    
                                    best_buy_shares(479 downto 432) <= shares_in;

                                end if;

                            else 

                            end if;
                        else 


                        end if;
                    else 

                    end if;

                end if;



            end if;

        end if;

    end process;

end rtl;