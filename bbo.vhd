
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bbo is

    port (
        clk : in std_logic;
        rst : in std_logic;

        price_in  : in unsigned(31 downto 0);
        shares_in : in unsigned(47 downto 0);
        side_in   : in unsigned(7 downto 0);
        delete_in : in std_logic;

        data_written_in : in std_logic;

        best_buy_price  : out unsigned(31 downto 0);
        best_buy_shares : out unsigned(47 downto 0);

        best_sell_price  : out unsigned(31 downto 0);
        best_sell_shares : out unsigned(47 downto 0);

        buy_rescan  : out std_logic;
        sell_rescan : out std_logic;

        rescan_price_address : out unsigned(109 downto 0)
    );

end bbo;


architecture rtl of bbo is

    constant BUY  : unsigned(7 downto 0) := x"42";
    constant SELL : unsigned(7 downto 0) := x"53";

    type price_array is array (0 to 9) of unsigned(31 downto 0);
    type share_array is array (0 to 9) of unsigned(47 downto 0);

    type state_t is (NORMAL, RESCAN_PRICES, RESCAN_SHARES);
    signal state : state_t := NORMAL;

    signal buy_prices : price_array;
    signal buy_shares : share_array;

    signal sell_prices : price_array;
    signal sell_shares : share_array;

    signal buy_price_count  : unsigned(3 downto 0);
    signal sell_price_count : unsigned(3 downto 0);

    signal buy_reconstruction  : std_logic;
    signal sell_reconstruction : std_logic;

    signal buy_lowest_delete  : unsigned(31 downto 0);
    signal sell_highest_delete : unsigned(31 downto 0);

    signal buy_table_filled  : std_logic;
    signal sell_table_filled : std_logic;

    signal buy_rescan_reg : std_logic;
    signal sell_rescan_reg : std_logic;

begin

    --------------------------------------------------------------------
    -- BBO outputs
    --
    -- BUY  : index 0 = highest buy
    -- SELL : index 0 = lowest sell
    --------------------------------------------------------------------

    best_buy_price  <= buy_prices(0);
    best_buy_shares <= buy_shares(0);

    best_sell_price  <= sell_prices(0);
    best_sell_shares <= sell_shares(0);


    --------------------------------------------------------------------
    -- Rescan request
    --------------------------------------------------------------------

    buy_rescan <= buy_reconstruction;
    sell_rescan <= sell_reconstruction;


    --------------------------------------------------------------------
    -- Main process
    --------------------------------------------------------------------

    process(clk)

        variable buy_count_int  : integer;
        variable sell_count_int : integer;

        variable found : boolean;

    begin

        if rising_edge(clk) then

            if rst = '1' then

                buy_price_count  <= (others => '0');
                sell_price_count <= (others => '0');

                buy_reconstruction  <= '0';
                sell_reconstruction <= '0';

                buy_table_filled  <= '0';
                sell_table_filled <= '0';

                buy_lowest_delete   <= (others => '0');
                sell_highest_delete <= (others => '0');

                for i in 0 to 9 loop

                    buy_prices(i) <= (others => '0');
                    buy_shares(i) <= (others => '0');

                    sell_prices(i) <= (others => '0');
                    sell_shares(i) <= (others => '0');

                end loop;

                case state is 


                when NORMAL => 

                    if buy_price_count = 1 and buy_table_filled = '1' then  

                        buy_rescan <= '1';
                        buy_rescan_reg <= '1';
                        state <= RESCAN_PRICES;
                    end if;

                    if sell_price_count = 1 and sell_table_filled = '1' then  

                        sell_rescan <= '1';
                        sell_rescan_reg <= '1';
                        state <= RESCAN_SHARES;
                    end if;


                    if data_written_in = '1' then

                        buy_count_int  := to_integer(buy_price_count);
                        sell_count_int := to_integer(sell_price_count);


                        ----------------------------------------------------------------
                        -- DELETE
                        ----------------------------------------------------------------

                        if delete_in = '1' then

                            ----------------------------------------------------------------
                            -- BUY DELETE
                            ----------------------------------------------------------------

                            if side_in = BUY then

                                found := false;

                                if buy_count_int > 0 then

                                    for i in 0 to 9 loop

                                        if i < buy_count_int then

                                            if price_in = buy_prices(i) then

                                                found := true;

                                                ------------------------------------------------
                                                -- If the table is full, remember the boundary
                                                -- that has now been exposed.
                                                --
                                                -- The current lowest cached BUY is at index 9.
                                                ------------------------------------------------

                                                if buy_table_filled = '1' then
                                                    buy_lowest_delete <= buy_prices(buy_count_int - 1);
                                                    buy_reconstruction <= '1';
                                                end if;


                                                ------------------------------------------------
                                                -- Shift everything above the deleted entry down.
                                                ------------------------------------------------

                                                for j in i to 8 loop

                                                    if j < buy_count_int - 1 then

                                                        buy_prices(j) <= buy_prices(j + 1);
                                                        buy_shares(j) <= buy_shares(j + 1);

                                                    end if;

                                                end loop;


                                                ------------------------------------------------
                                                -- Clear old final entry.
                                                ------------------------------------------------

                                                buy_prices(buy_count_int - 1) <= (others => '0');
                                                buy_shares(buy_count_int - 1) <= (others => '0');


                                                ------------------------------------------------
                                                -- Decrease count.
                                                ------------------------------------------------

                                                buy_price_count <= buy_price_count - 1;


                                                ------------------------------------------------
                                                -- Once the table is no longer full, the
                                                -- filled flag is cleared.
                                                ------------------------------------------------

                                                if buy_count_int <= 10 then
                                                    buy_table_filled <= '0';
                                                end if;

                                                exit;

                                            end if;

                                        end if;

                                    end loop;

                                end if;


                            ----------------------------------------------------------------
                            -- SELL DELETE
                            ----------------------------------------------------------------

                            else

                                found := false;

                                if sell_count_int > 0 then

                                    for i in 0 to 9 loop

                                        if i < sell_count_int then

                                            if price_in = sell_prices(i) then

                                                found := true;

                                                ------------------------------------------------
                                                -- SELL cache is lowest -> highest.
                                                -- Therefore the boundary is the highest
                                                -- cached SELL.
                                                ------------------------------------------------

                                                if sell_table_filled = '1' then
                                                    sell_highest_delete <= sell_prices(sell_count_int - 1);
                                                    sell_reconstruction <= '1';
                                                end if;


                                                ------------------------------------------------
                                                -- Shift entries down.
                                                ------------------------------------------------

                                                for j in i to 8 loop

                                                    if j < sell_count_int - 1 then

                                                        sell_prices(j) <= sell_prices(j + 1);
                                                        sell_shares(j) <= sell_shares(j + 1);

                                                    end if;

                                                end loop;


                                                ------------------------------------------------
                                                -- Clear final entry.
                                                ------------------------------------------------

                                                sell_prices(sell_count_int - 1) <= (others => '0');
                                                sell_shares(sell_count_int - 1) <= (others => '0');


                                                ------------------------------------------------
                                                -- Decrease count.
                                                ------------------------------------------------

                                                sell_price_count <= sell_price_count - 1;


                                                ------------------------------------------------
                                                -- No longer full.
                                                ------------------------------------------------

                                                if sell_count_int <= 10 then
                                                    sell_table_filled <= '0';
                                                end if;

                                                exit;

                                            end if;

                                        end if;

                                    end loop;

                                end if;

                            end if;


                        ----------------------------------------------------------------
                        -- ADD / UPDATE
                        ----------------------------------------------------------------

                        else

                            ----------------------------------------------------------------
                            -- BUY
                            ----------------------------------------------------------------

                            if side_in = BUY then

                                ----------------------------------------------------------------
                                -- Normal operation
                                ----------------------------------------------------------------

                                if buy_reconstruction = '0' then

                                    if buy_count_int < 10 then

                                        -- Search current entries and insert in order.

                                        for i in 0 to 9 loop

                                            if i < buy_count_int then

                                                if price_in > buy_prices(i) then

                                                    for j in 9 downto 1 loop

                                                        if j <= buy_count_int then
                                                            buy_prices(j) <= buy_prices(j - 1);
                                                            buy_shares(j) <= buy_shares(j - 1);
                                                        end if;

                                                    end loop;

                                                    buy_prices(i) <= price_in;
                                                    buy_shares(i) <= shares_in;

                                                    buy_price_count <= buy_price_count + 1;

                                                    exit;


                                                elsif price_in = buy_prices(i) then

                                                    buy_shares(i) <= buy_shares(i) + shares_in;

                                                    exit;

                                                end if;

                                            else

                                                -- Append to end if no better price was found.

                                                buy_prices(i) <= price_in;
                                                buy_shares(i) <= shares_in;

                                                buy_price_count <= buy_price_count + 1;

                                                exit;

                                            end if;

                                        end loop;


                                    else

                                        ----------------------------------------------------------------
                                        -- Table full.
                                        --
                                        -- Only insert if the new price belongs in the top 10.
                                        ----------------------------------------------------------------

                                        for i in 0 to 9 loop

                                            if price_in > buy_prices(i) then

                                                for j in 9 downto i + 1 loop

                                                    buy_prices(j) <= buy_prices(j - 1);
                                                    buy_shares(j) <= buy_shares(j - 1);

                                                end loop;

                                                buy_prices(i) <= price_in;
                                                buy_shares(i) <= shares_in;

                                                -- Count remains 10.

                                                exit;


                                            elsif price_in = buy_prices(i) then

                                                buy_shares(i) <= buy_shares(i) + shares_in;

                                                exit;

                                            end if;

                                        end loop;

                                    end if;


                                    if buy_count_int >= 9 then
                                        buy_table_filled <= '1';
                                    end if;


                                ----------------------------------------------------------------
                                -- Reconstruction mode
                                ----------------------------------------------------------------

                                else

                                    ------------------------------------------------------------
                                    -- Only accept prices that are in the region that can
                                    -- safely affect the current cached top 10.
                                    ------------------------------------------------------------

                                    if price_in >= buy_lowest_delete then

                                        for i in 0 to 9 loop

                                            if i < buy_count_int then

                                                if price_in > buy_prices(i) then

                                                    for j in 9 downto i + 1 loop

                                                        buy_prices(j) <= buy_prices(j - 1);
                                                        buy_shares(j) <= buy_shares(j - 1);

                                                    end loop;

                                                    buy_prices(i) <= price_in;
                                                    buy_shares(i) <= shares_in;

                                                    if buy_count_int < 10 then
                                                        buy_price_count <= buy_price_count + 1;
                                                    end if;

                                                    exit;


                                                elsif price_in = buy_prices(i) then

                                                    buy_shares(i) <= buy_shares(i) + shares_in;

                                                    exit;

                                                end if;

                                            else

                                                buy_prices(i) <= price_in;
                                                buy_shares(i) <= shares_in;

                                                if buy_count_int < 10 then
                                                    buy_price_count <= buy_price_count + 1;
                                                end if;

                                                exit;

                                            end if;

                                        end loop;


                                        if buy_count_int >= 9 then
                                            buy_table_filled <= '1';
                                        end if;

                                    end if;

                                end if;


                            ----------------------------------------------------------------
                            -- SELL
                            ----------------------------------------------------------------

                            else

                                ----------------------------------------------------------------
                                -- Normal operation
                                ----------------------------------------------------------------

                                if sell_reconstruction = '0' then

                                    if sell_count_int < 10 then

                                        for i in 0 to 9 loop

                                            if i < sell_count_int then

                                                if price_in < sell_prices(i) then

                                                    for j in 9 downto 1 loop

                                                        if j <= sell_count_int then
                                                            sell_prices(j) <= sell_prices(j - 1);
                                                            sell_shares(j) <= sell_shares(j - 1);
                                                        end if;

                                                    end loop;

                                                    sell_prices(i) <= price_in;
                                                    sell_shares(i) <= shares_in;

                                                    sell_price_count <= sell_price_count + 1;

                                                    exit;


                                                elsif price_in = sell_prices(i) then

                                                    sell_shares(i) <= sell_shares(i) + shares_in;

                                                    exit;

                                                end if;

                                            else

                                                -- Append to end.

                                                sell_prices(i) <= price_in;
                                                sell_shares(i) <= shares_in;

                                                sell_price_count <= sell_price_count + 1;

                                                exit;

                                            end if;

                                        end loop;


                                    else

                                        ------------------------------------------------------------
                                        -- Table full: only retain top 10 asks.
                                        ------------------------------------------------------------

                                        for i in 0 to 9 loop

                                            if price_in < sell_prices(i) then

                                                for j in 9 downto i + 1 loop

                                                    sell_prices(j) <= sell_prices(j - 1);
                                                    sell_shares(j) <= sell_shares(j - 1);

                                                end loop;

                                                sell_prices(i) <= price_in;
                                                sell_shares(i) <= shares_in;

                                                -- Count remains 10.

                                                exit;


                                            elsif price_in = sell_prices(i) then

                                                sell_shares(i) <= sell_shares(i) + shares_in;

                                                exit;

                                            end if;

                                        end loop;

                                    end if;


                                    if sell_count_int >= 9 then
                                        sell_table_filled <= '1';
                                    end if;


                                ----------------------------------------------------------------
                                -- Reconstruction mode
                                ----------------------------------------------------------------

                                else

                                    ------------------------------------------------------------
                                    -- SELL:
                                    -- only accept prices <= the remembered highest cached ask.
                                    ------------------------------------------------------------

                                    if price_in <= sell_highest_delete then

                                        for i in 0 to 9 loop

                                            if i < sell_count_int then

                                                if price_in < sell_prices(i) then

                                                    for j in 9 downto i + 1 loop

                                                        sell_prices(j) <= sell_prices(j - 1);
                                                        sell_shares(j) <= sell_shares(j - 1);

                                                    end loop;

                                                    sell_prices(i) <= price_in;
                                                    sell_shares(i) <= shares_in;

                                                    if sell_count_int < 10 then
                                                        sell_price_count <= sell_price_count + 1;
                                                    end if;

                                                    exit;


                                                elsif price_in = sell_prices(i) then

                                                    sell_shares(i) <= sell_shares(i) + shares_in;

                                                    exit;

                                                end if;

                                            else

                                                sell_prices(i) <= price_in;
                                                sell_shares(i) <= shares_in;

                                                if sell_count_int < 10 then
                                                    sell_price_count <= sell_price_count + 1;
                                                end if;

                                                exit;

                                            end if;

                                        end loop;


                                        if sell_count_int >= 9 then
                                            sell_table_filled <= '1';
                                        end if;

                                    end if;

                                end if;

                            end if;

                        end if;

                    end if;

                when RESCAN_PRICES =>

                    

                when RESCAN_SHARES =>

                end case;

            end if;


            

        end if;

    end process;

end rtl;
