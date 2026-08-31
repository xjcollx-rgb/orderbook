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

    type price_array is array (0 to 9) of unsigned(31 downto 0);
    type share_array is array (0 to 9) of unsigned(47 downto 0);

    signal buy_prices  : price_array;
    signal buy_shares  : share_array;

    signal sell_prices : price_array;
    signal sell_shares : share_array;

    signal buy_price_count : unsigned(3 downto 0);
    signal sell_price_count : unsigned(3 downto 0);

    signal buy_reconstruction : std_logic;
    signal sell_reconstruction : std_logic;

    signal sell_lowest_delete : unsigned(31 downto 0);
    signal buy_highest_delete : unsigned(31 downto 0);

    signal buy_table_filled : std_logic;
    signal sell_table_filled : std_logic;
begin 

    process(clk)

    begin 

        if rising_edge(clk) then
            
            if rst = '1' then
                
            else 

                if data_written = '1' then 


                    if delete_in <= '1' then
                        
                        if side_in = BUY then 

                                for i in 0 to to_integer(buy_price_count) - 1 loop

                                    if price_in = buy_prices(i) then 

                                        for j in i to to_integer(buy_price_count) - 2 loop  

                                            buy_prices(j) <= buy_prices(j + 1);
                                            buy_shares(j) <= buy_shares(j + 1);

                                        end loop;

                                    end if;
                                    
                                    buy_prices(to_integer(buy_price_count) - 1) <= (others => '0');
                                    buy_shares(to_integer(buy_price_count) - 1) <= (others => '0');
                                    buy_highest_delete <= buy_prices(to_integer(buy_price_count));
                                    buy_price_count <= buy_price_count - 1;

                                    if buy_table_filled = '1' then 

                                        buy_reconstruction <= '1';

                                    end if;

                                    exit;

                                end loop;

                            else 

                                for i in 0 to to_integer(sell_price_count) - 1 loop

                                    if price_in = sell_prices(i) then 

                                        for j in i to to_integer(sell_price_count) - 2 loop  

                                            sell_prices(j) <= sell_prices(j + 1);
                                            sell_shares(j) <= sell_shares(j + 1);

                                        end loop;

                                    end if;
                                    
                                    sell_prices(to_integer(sell_price_count) - 1) <= (others => '0');
                                    sell_shares(to_integer(sell_price_count) - 1) <= (others => '0');
                                    sell_lowest_delete <= sell_prices(to_integer(sell_price_count) - 1);
                                    sell_price_count <= sell_price_count - 1;

                                    if sell_table_filled = '1' then 

                                        sell_reconstruction <= '1';

                                    end if;

                                    exit;

                                end loop;

                            end if;



                    else 


                    end if;

                    if side_in = BUY then 

                        if buy_reconstruction = '0' then            
                        
                            for i in 0 to 9 loop     
                            
                                if price_in > buy_prices(i) then 

                                    for j in 9 downto i + 1 loop     

                                        buy_prices(j) <= buy_prices(j - 1);
                                        buy_shares(j) <= buy_shares(j - 1);
                                        
                                    end loop;

                                    buy_prices(i) <= price_in;
                                    buy_shares(i) <= shares_in; 
                                    buy_price_count <= buy_price_count + 1;

                                    exit;


                                elsif price_in = buy_prices (i) then
                                    
                                    buy_shares(i) <= shares_in + buy_shares(i);

                                    exit;

                                end if;
                            
                            end loop;

                            if buy_price_count >= 9 then

                                buy_table_filled <= '1';
                            
                            end if;

                        else 

                        end if;

                    else 

                        if sell_reconstruction = '0' then 

                            for i in 0 to 9 loop     
                            
                                if price_in < sell_prices(i) then 

                                    for j in 9 downto i + 1 loop     

                                        sell_prices(j) <= sell_prices(j - 1);
                                        sell_shares(j) <= sell_shares(j - 1);
                                        
                                    end loop;

                                    sell_prices(i) <= price_in;
                                    sell_shares(i) <= shares_in;
                                    sell_price_count <= sell_price_count + 1; 

                                    exit;


                                elsif price_in = sell_prices (i) then
                                    
                                    sell_shares(i) <= shares_in + sell_shares(i);

                                    exit;
                                    
                                end if;
                            
                            end loop;

                            if sell_price_count >= 9 then

                                sell_table_filled <= '1';
                            
                            end if;
                        
                        else 

                        
                        end if;

                    end if; 

                            
                    

                end if;



            end if;

        end if;

    end process;

end rtl;