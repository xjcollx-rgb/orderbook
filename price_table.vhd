library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity price_table is
port (
    clk          : in  std_logic;
    rst          : in  std_logic;

    price_table  : in  unsigned(143 downto 0);
    frame_type_in   : in unsigned(1 downto 0);
    fifo_empty : in  std_logic; 

    data_written : out std_logic;

    bbo_price : out unsigned(31 downto 0);
    bbo_shares : out unsigned(47 downto 0);
    bbo_side : out unsigned(7 downto 0);
    bbo_delete : out std_logic;

    buy_rescan_in : in std_logic;
    sell_rescan_in : in std_logic;

    rescan_out : out std_logic;

    -- rescan phase 1: burst of one bucket (8 price/address pairs) per cycle to BBO
    rescan_bucket_prices : out unsigned(255 downto 0);
    rescan_bucket_addrs  : out unsigned(87 downto 0);
    rescan_bucket_valid  : out std_logic;
    rescan_last_bucket   : out std_logic;
    rescan_buckets_processed_out : in std_logic;

    -- BBO's sorted top 10 addresses, returned once ready
    top10_addr_in  : in unsigned(109 downto 0);
    top10_valid_in : in std_logic;

    -- rescan phase 2: one share value per cycle back to BBO
    rescan_share_out   : out unsigned(47 downto 0);
    rescan_share_valid : out std_logic;
    rescan_share_last  : out std_logic
);
end price_table;

architecture rtl of price_table is

    ----------------------------------------------------------------
    --   price tbale
    --   bits 95..48  : aggregate buy shares  at this price
    --   bits 47..0   : aggregate sell shares at this price
    ----------------------------------------------------------------
    type ram_t is array (0 to 2047) of unsigned(95 downto 0);
    signal ram : ram_t := (others => (others => '0'));

    type ram_bucket is array(0 to 255) of unsigned(255 downto 0);
    signal buckets : ram_bucket := (others =>(others=> '0'));

    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";

    attribute ram_style of buckets : signal is "block";

    ----------------------------------------------------------------
    -- Single canonical write port for ram / buckets (BRAM inference)
    ----------------------------------------------------------------
    signal ram_we    : std_logic;
    signal ram_waddr : unsigned(10 downto 0);
    signal ram_wdata : unsigned(95 downto 0);

    signal buckets_we    : std_logic;
    signal buckets_waddr : unsigned(7 downto 0);
    signal buckets_wdata : unsigned(255 downto 0);

    ----------------------------------------------------------------
    -- State machine
    ----------------------------------------------------------------
    type state_t is (IDLE, READ_BUCKETS, CHECK, READ_PRICE_TABLE, WRITE_PRICE_TABLE, RESCAN_PRICES, RESCAN_WAIT, RESCAN_SHARES);
    signal state : state_t := IDLE;

    -- Operation types
    constant ADD     : unsigned(1 downto 0) := "00";
    constant EXECCAN : unsigned(1 downto 0) := "01";
    constant REPLACE : unsigned(1 downto 0) := "10";
    constant DELETE  : unsigned(1 downto 0) := "11";

    -- sides
    constant BUY : unsigned(7 downto 0) := x"42";
    constant SELL : unsigned(7 downto 0) := x"53";

    -- Hash table search control
    signal original_hash : unsigned(7 downto 0);
    signal original_price : unsigned(31 downto 0);
    signal original_shares : unsigned(31 downto 0);
    signal original_side : unsigned(7 downto 0);
    signal replace_hash : unsigned(7 downto 0);
    signal replace_price : unsigned(31 downto 0);
    signal replace_shares : unsigned(31 downto 0);
    signal replace_side : unsigned(7 downto 0);
    signal replace_run : std_logic;
    -- Second hash (rehash) support for collision resolution
    signal original_hash2 : unsigned(7 downto 0);
    signal replace_hash2  : unsigned(7 downto 0);
    signal hash_attempts  : unsigned(2 downto 0) := (others => '0');
    constant MAX_HASH_ATTEMPTS : unsigned(2 downto 0) := "001";
    signal bucket_data : unsigned(255 downto 0);
    signal price_table_address : unsigned(10 downto 0);
    signal read_data : unsigned(95 downto 0);



    signal price_found : std_logic;

    signal empty_slot_address : unsigned(10 downto 0);
    signal empty_slot_found : std_logic;
    signal empty_bucket_address : unsigned(2 downto 0);
    signal price_found_bucket_address : unsigned(2 downto 0);

    --rescan stuff 
    signal buy_rescan_pending : std_logic := '0';
    signal sell_rescan_pending : std_logic := '0';
    signal rescan_side_is_buy : std_logic;
    signal rescan_buckets_counter : unsigned(7 downto 0) := (others => '0');
    signal rescan_top10_addr : unsigned(109 downto 0);
    signal rescan_price_count : unsigned(3 downto 0) := (others => '0');
    signal rescan_buckets_processed : std_logic;

begin


    process(clk)

        variable v_read_data : unsigned(95 downto 0);
        variable v_bucket_data : unsigned(255 downto 0);

    begin
        if rising_edge(clk) then

            if rst = '1' then


            else

                ram_we     <= '0';
                buckets_we <= '0';
                rescan_bucket_valid <= '0';
                rescan_last_bucket  <= '0';
                rescan_share_valid  <= '0';
                rescan_share_last   <= '0';

                case state is

                    when IDLE =>

                        data_written <= '0';
                        empty_slot_found <= '0';
                        empty_slot_address <= (others => '0');
                        price_found <= '0';
                        price_table_address <= (others => '0');
                        replace_run <= '0';
                        rescan_out <= '0';
                        hash_attempts <= (others => '0');

                        if (buy_rescan_pending = '1') or (sell_rescan_pending = '1') then 

                            rescan_side_is_buy     <= buy_rescan_pending;
                            buy_rescan_pending      <= '0';
                            sell_rescan_pending     <= '0';
                            rescan_buckets_counter  <= (others => '0');
                            state <= RESCAN_PRICES;

                        end if;


                        if fifo_empty = '0' then
                            
                            original_hash<= price_table(7 downto 0) xor price_table(15 downto 8) xor price_table(23 downto 16) xor price_table(31 downto 24);
                            original_price <= price_table(31 downto 0);
                            original_shares <= price_table(63 downto 32);
                            original_side <= price_table(71 downto 64);
                            original_hash2 <= (price_table(7 downto 0) xor price_table(23 downto 16)) + (price_table(15 downto 8) xor price_table(31 downto 24));

                            replace_hash <= price_table(79 downto 72) xor price_table(87 downto 80) xor price_table(95 downto 88) xor price_table(103 downto 96);
                            replace_price <= price_table(103 downto 72);
                            replace_shares <= price_table(135 downto 104);
                            replace_side <= price_table(143 downto 136);
                            replace_hash2 <= (price_table(79 downto 72) xor price_table(95 downto 88)) + (price_table(87 downto 80) xor price_table(103 downto 96));
                            
                            state <= READ_BUCKETS;


                        end if;

                    when READ_BUCKETS =>

                            if replace_run = '0' then
                                bucket_data <= buckets(to_integer(original_hash));
                            
                            else 
                                bucket_data <= buckets(to_integer(replace_hash));
                                
                            end if;
                        state <= CHECK;

                    when CHECK =>


                        if replace_run = '0' then 
                            if bucket_data(31 downto 0) = to_unsigned(0,32) then 
                                empty_slot_address <= (original_hash & "000");
                                empty_slot_found <= '1';
                                empty_bucket_address <= "000";

                            elsif bucket_data(63 downto 32 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (original_hash & "000") + 1;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "001";

                            elsif bucket_data(95 downto 64 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (original_hash & "000") + 2;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "010";

                            elsif bucket_data(127 downto 96 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (original_hash & "000") + 3;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "011";

                            elsif bucket_data(159 downto 128) = to_unsigned(0,32) then 
                                empty_slot_address <= (original_hash & "000") + 4;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "100";

                            elsif bucket_data(191 downto 160 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (original_hash & "000") + 5;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "101";

                            elsif bucket_data(223 downto 192) = to_unsigned(0,32) then 
                                empty_slot_address <= (original_hash & "000") + 6;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "110";

                            elsif bucket_data(255 downto 224 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (original_hash & "000") + 7;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "111";
                            end if;

                        
                        
                            if bucket_data(31 downto 0) = original_price then 
                                price_table_address <= (original_hash & "000");
                                price_found <= '1';
                                price_found_bucket_address <= "000";
                            end if;

                            if bucket_data(63 downto 32) = original_price then 
                                price_table_address <= (original_hash & "000") + 1;
                                price_found <= '1';
                                price_found_bucket_address <= "001";
                            end if;

                            if bucket_data(95 downto 64) = original_price then 
                                price_table_address <= (original_hash & "000") + 2;
                                price_found <= '1';
                                price_found_bucket_address <= "010";
                            end if;
                            if bucket_data(127 downto 96) = original_price then 
                                price_table_address <= (original_hash & "000") + 3;
                                price_found <= '1';
                                price_found_bucket_address <= "011";
                            end if;

                            if bucket_data(159 downto 128) = original_price then 
                                price_table_address <= (original_hash & "000") + 4;
                                price_found <= '1';
                                price_found_bucket_address <= "100";
                            end if;

                            if bucket_data(191 downto 160) = original_price then 
                                price_table_address <= (original_hash & "000") + 5;
                                price_found <= '1';
                                price_found_bucket_address <= "101";
                            end if;

                            if bucket_data(223 downto 192) = original_price then 
                                price_table_address <= (original_hash & "000") + 6;
                                price_found <= '1';
                                price_found_bucket_address <= "110";
                            end if; 

                            if bucket_data(255 downto 224) = original_price then 
                                price_table_address <= (original_hash & "000") + 7;
                                price_found <= '1';
                                price_found_bucket_address <= "111";
                            end if;

                        

                            

                        else 

                            if bucket_data(31 downto 0) = to_unsigned(0,32) then 
                                empty_slot_address <= (replace_hash & "000");
                                empty_slot_found <= '1';
                                empty_bucket_address <= "000";

                            elsif bucket_data(63 downto 32 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (replace_hash & "000") + 1;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "001";

                            elsif bucket_data(95 downto 64 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (replace_hash & "000") + 2;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "010";

                            elsif bucket_data(127 downto 96 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (replace_hash & "000") + 3;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "011";

                            elsif bucket_data(159 downto 128) = to_unsigned(0,32) then 
                                empty_slot_address <= (replace_hash & "000") + 4;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "100";

                            elsif bucket_data(191 downto 160 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (replace_hash & "000") + 5;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "101";

                            elsif bucket_data(223 downto 192) = to_unsigned(0,32) then 
                                empty_slot_address <= (replace_hash & "000") + 6;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "110";

                            elsif bucket_data(255 downto 224 ) = to_unsigned(0,32) then 
                                empty_slot_address <= (replace_hash & "000") + 7;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "111";
                            end if;

                        
                        
                            if bucket_data(31 downto 0) = replace_price then 
                                price_table_address <= (replace_hash & "000");
                                price_found <= '1';
                            end if;

                            if bucket_data(63 downto 32) = replace_price then 
                                price_table_address <= (replace_hash & "000") + 1;
                                price_found <= '1';
                            end if;
                            if bucket_data(95 downto 64) = replace_price then 
                                price_table_address <= (replace_hash & "000") + 2;
                                price_found <= '1';
                            end if;
                            if bucket_data(127 downto 96) = replace_price then 
                                price_table_address <= (replace_hash & "000") + 3;
                                price_found <= '1';
                            end if;

                            if bucket_data(159 downto 128) = replace_price then 
                                price_table_address <= (replace_hash & "000") + 4;
                                price_found <= '1';
                            end if;

                            if bucket_data(191 downto 160) = replace_price then 
                                price_table_address <= (replace_hash & "000") + 5;
                                price_found <= '1';
                            end if;

                            if bucket_data(223 downto 192) = replace_price then 
                                price_table_address <= (replace_hash & "000") + 6;
                                price_found <= '1';
                            end if; 

                            if bucket_data(255 downto 224) = replace_price then 
                                price_table_address <= (replace_hash & "000") + 7;
                                price_found <= '1';
                            end if;

                        end if;

                        state <= READ_PRICE_TABLE;


                    when READ_PRICE_TABLE =>

                            if price_found = '1' then 

                                read_data <= ram(to_integer(price_table_address));
                                state <= WRITE_PRICE_TABLE;

                            elsif empty_slot_found = '1' and (frame_type_in = ADD or (frame_type_in = REPLACE and replace_run = '1')) then

                                -- an empty slot only counts as "found" for operations that are
                                -- allowed to insert (ADD, or the insert-phase of REPLACE).
                                -- EXECCAN/DELETE and the REPLACE search-phase must actually
                                -- locate the price, so an empty slot here does not stop the search.
                                state <= WRITE_PRICE_TABLE;

                            else --need to add some sort of over flow incase the buckets are full

                                if hash_attempts < MAX_HASH_ATTEMPTS then

                                    hash_attempts <= hash_attempts + 1;

                                    if replace_run = '0' then
                                        original_hash <= original_hash2;
                                    else
                                        replace_hash <= replace_hash2;
                                    end if;

                                    state <= READ_BUCKETS;

                                else

                                    -- price could not be located (or no free slot found) after
                                    -- exhausting all hash attempts; drop it
                                    state <= IDLE;

                                end if;

                            end if;

                    when WRITE_PRICE_TABLE =>

                            v_read_data := read_data;
                            v_bucket_data := bucket_data;
                            empty_slot_found <= '0';
                            price_found <= '0';

                        case frame_type_in is 

                                when ADD => 

                                    if price_found = '1' then 

                                        if original_side = BUY then 

                                            v_read_data(95 downto 48) := v_read_data(95 downto 48) + resize(original_shares, 48);
                                            ram_we    <= '1';
                                            ram_waddr <= price_table_address;
                                            ram_wdata <= v_read_data;
                                            bbo_shares <= v_read_data(95 downto 48);
                                            state <= IDLE;

                                        else 

                                            v_read_data(47 downto 0) := v_read_data(47 downto 0) + resize(original_shares, 48);
                                            ram_we    <= '1';
                                            ram_waddr <= price_table_address;
                                            ram_wdata <= v_read_data;
                                            bbo_shares <= v_read_data(47 downto 0);
                                            state <= IDLE;

                                        end if;

                                        bbo_price <= original_price;
                                        bbo_side <= original_side;
                                        bbo_delete <= '0';

                                        data_written <= '1';

                                    elsif empty_slot_found = '1' then
                                        
                                        v_bucket_data(31 + (to_integer(empty_bucket_address) * 32)  downto (to_integer(empty_bucket_address) * 32)) := original_price;
                                        buckets_we    <= '1';
                                        buckets_waddr <= original_hash;
                                        buckets_wdata <= v_bucket_data;

                                        if original_side = BUY then 

                                            ram_we    <= '1';
                                            ram_waddr <= empty_slot_address;
                                            ram_wdata <= resize(original_shares, 48) & to_unsigned(0, 48);
                                            state <= IDLE;

                                        else 

                                            ram_we    <= '1';
                                            ram_waddr <= empty_slot_address;
                                            ram_wdata <= to_unsigned(0,48) & resize(original_shares, 48);
                                            state <= IDLE;

                                        end if;

                                        data_written <= '1';
                                        bbo_price <= original_price;
                                        bbo_shares <= resize(original_shares, 48);
                                        bbo_side <= original_side;
                                        bbo_delete <= '0';


                                    end if;



                                when EXECCAN | DELETE=>
                                        
                                    if price_found = '1' then 

                                        if original_side = BUY then 

                                            v_read_data(95 downto 48) := v_read_data(95 downto 48) - resize(original_shares, 48);

                                            if v_read_data(95 downto 48) = to_unsigned(0,48) then 
                                                bbo_price <= original_price;
                                                bbo_delete <= '1';
                                                bbo_side <= original_side;
                                            end if;

                                            if v_read_data(95 downto 48) = to_unsigned(0,48) and v_read_data(47 downto 0) = to_unsigned(0,48) then
                                                v_bucket_data(31 + (to_integer(price_found_bucket_address) * 32)  downto (to_integer(price_found_bucket_address) * 32)) := (others => '0');
                                                buckets_we    <= '1';
                                                buckets_waddr <= original_hash;
                                                buckets_wdata <= v_bucket_data;
                                                state <= IDLE;

                                            else 
                                            ram_we    <= '1';
                                            ram_waddr <= price_table_address;
                                            ram_wdata <= v_read_data;
                                            bbo_price <= original_price;
                                            bbo_shares <= v_read_data(95 downto 48);
                                            bbo_side <= original_side;
                                            bbo_delete <= '0';
                                            state <= IDLE;
                                            
                                            end if;

                                            data_written <= '1';
                                        else 

                                            v_read_data(47 downto 0) := v_read_data(47 downto 0) - resize(original_shares, 48);

                                            if v_read_data(47 downto 0) = to_unsigned(0,48) then 
                                                bbo_price <= original_price;
                                                bbo_delete <= '1';
                                                bbo_side <= original_side;
                                            end if;

                                            if v_read_data(95 downto 48) = to_unsigned(0,48) and v_read_data(47 downto 0) = to_unsigned(0,48) then
                                                v_bucket_data(31 + (to_integer(price_found_bucket_address) * 32)  downto (to_integer(price_found_bucket_address) * 32)) := (others => '0');
                                                buckets_we    <= '1';
                                                buckets_waddr <= original_hash;
                                                buckets_wdata <= v_bucket_data;
                                                state <= IDLE;

                                            else 

                                            ram_we    <= '1';
                                            ram_waddr <= price_table_address;
                                            ram_wdata <= v_read_data;
                                            bbo_price <= original_price;
                                            bbo_shares <= v_read_data(47 downto 0);
                                            bbo_side <= original_side;
                                            bbo_delete <= '0';
                                            state <= IDLE;

                                            end if;

                                            data_written <= '1';

                                        end if;

                                    end if;

                                when REPLACE => 

                                    if replace_run = '0' then 

                                        if price_found = '1' then   

                                            if original_side = BUY then 

                                                v_read_data(95 downto 48) := v_read_data(95 downto 48) - resize(original_shares, 48);

                                                if v_read_data(95 downto 48) = to_unsigned(0,48) then 
                                                    bbo_price <= original_price;
                                                    bbo_delete <= '1';
                                                    bbo_side <= original_side;
                                                end if;

                                                if v_read_data(95 downto 48) = to_unsigned(0,48) and v_read_data(47 downto 0) = to_unsigned(0,48) then
                                                    v_bucket_data(31 + (to_integer(price_found_bucket_address) * 32)  downto (to_integer(price_found_bucket_address) * 32)) := (others => '0');
                                                    buckets_we    <= '1';
                                                    buckets_waddr <= original_hash;
                                                    buckets_wdata <= v_bucket_data;
                                                    state <= READ_BUCKETS;
                                                else 
                                                    ram_we    <= '1';
                                                    ram_waddr <= price_table_address;
                                                    ram_wdata <= v_read_data;
                                                    bbo_price <= original_price;
                                                    bbo_shares <= v_read_data(95 downto 48);
                                                    bbo_side <= original_side;
                                                    bbo_delete <= '0';
                                                    state <= READ_BUCKETS;
                                                
                                                end if;
                                            else 

                                                v_read_data(47 downto 0) := v_read_data(47 downto 0) - resize(original_shares, 48);

                                                if v_read_data(47 downto 0) = to_unsigned(0,48) then 
                                                    bbo_price <= original_price;
                                                    bbo_delete <= '1';
                                                    bbo_side <= original_side;
                                                end if;

                                                if v_read_data(95 downto 48) = to_unsigned(0,48) and v_read_data(47 downto 0) = to_unsigned(0,48) then
                                                    v_bucket_data(31 + (to_integer(price_found_bucket_address) * 32)  downto (to_integer(price_found_bucket_address) * 32)) := (others => '0');
                                                    buckets_we    <= '1';
                                                    buckets_waddr <= original_hash;
                                                    buckets_wdata <= v_bucket_data;
                                                    state <= READ_BUCKETS;

                                                else 

                                                    ram_we    <= '1';
                                                    ram_waddr <= price_table_address;
                                                    ram_wdata <= v_read_data;
                                                    bbo_price <= original_price;
                                                    bbo_shares <= v_read_data(47 downto 0);
                                                    bbo_side <= original_side;
                                                    bbo_delete <= '0';
                                                    state <= READ_BUCKETS;

                                                end if;

                                            end if;

                                            replace_run <= '1';
                                            hash_attempts <= (others => '0');

                                        end if;
                                        
                                    else
                                    
                                        if price_found = '1' then 

                                            if original_side = BUY then 

                                                v_read_data(95 downto 48) := v_read_data(95 downto 48) + resize(replace_shares, 48);
                                                ram_we    <= '1';
                                                ram_waddr <= price_table_address;
                                                ram_wdata <= v_read_data;
                                                bbo_shares <= v_read_data(95 downto 48);
                                                state <= IDLE;

                                            else 

                                                v_read_data(47 downto 0) := v_read_data(47 downto 0) + resize(replace_shares, 48);
                                                ram_we    <= '1';
                                                ram_waddr <= price_table_address;
                                                ram_wdata <= v_read_data;
                                                bbo_shares <= v_read_data(47 downto 0);
                                                state <= IDLE;

                                            end if;

                                            bbo_price <= replace_price;
                                            bbo_side <= replace_side;
                                            bbo_delete <= '0';

                                            data_written <= '1';

                                        elsif empty_slot_found = '1' then
                                            
                                            v_bucket_data(31 + (to_integer(empty_bucket_address) * 32)  downto (to_integer(empty_bucket_address) * 32)) := replace_price;
                                            buckets_we    <= '1';
                                            buckets_waddr <= replace_hash;
                                            buckets_wdata <= v_bucket_data;

                                            if original_side = BUY then 

                                                ram_we    <= '1';
                                                ram_waddr <= empty_slot_address;
                                                ram_wdata <= resize(replace_shares, 48) & to_unsigned(0, 48);
                                                state <= IDLE;

                                            else 

                                                ram_we    <= '1';
                                                ram_waddr <= empty_slot_address;
                                                ram_wdata <= to_unsigned(0, 48) & resize(replace_shares, 48);
                                                state <= IDLE;

                                            end if;

                                            data_written <= '1';
                                            bbo_price <= replace_price;
                                            bbo_shares <= resize(replace_shares, 48);
                                            bbo_side <= replace_side;
                                            bbo_delete <= '0';

                                        end if;
                                    

                                    end if;

                                

                        end case;

                when RESCAN_PRICES => 

                    rescan_out <= '1';

                    rescan_bucket_valid  <= '1';
                    rescan_bucket_prices <= buckets(to_integer(rescan_buckets_counter));

                    for i in 0 to 7 loop
                        
                        rescan_bucket_addrs((11 * i) + 10 downto 11 * i) <= (rescan_buckets_counter & "000") + i; 

                    end loop;

                    if rescan_buckets_counter = 255 then 

                        rescan_last_bucket <= '1';
                        state <= RESCAN_WAIT;

                    else

                        rescan_buckets_counter <= rescan_buckets_counter + 1;
                        state <= RESCAN_WAIT;

                    end if;

                when RESCAN_WAIT =>

                    rescan_bucket_valid <= '0';

                    if top10_valid_in = '1' then

                        rescan_top10_addr  <= top10_addr_in;
                        rescan_price_count <= (others => '0');
                        state <= RESCAN_SHARES;

                    end if;

                    if rescan_buckets_processed = '1' then 

                        state <= RESCAN_PRICES;

                    end if;

                when RESCAN_SHARES =>  

                        rescan_share_valid <= '1';

                        if rescan_side_is_buy = '1' then 

                            rescan_share_out <= ram(to_integer(rescan_top10_addr((11 * to_integer(rescan_price_count)) + 10 downto 11 * to_integer(rescan_price_count))))(95 downto 48);
                        else 

                            rescan_share_out <= ram(to_integer(rescan_top10_addr((11 * to_integer(rescan_price_count)) + 10 downto 11 * to_integer(rescan_price_count))))(47 downto 0);

                        end if;

                        if rescan_price_count = 9 then 

                            rescan_share_last <= '1';
                            rescan_out <= '0';
                            state <= IDLE;
                            
                        else

                            rescan_price_count <= rescan_price_count + 1;

                        end if;

                end case;

                if ram_we = '1' then
                    ram(to_integer(ram_waddr)) <= ram_wdata;
                end if;

                if buckets_we = '1' then
                    buckets(to_integer(buckets_waddr)) <= buckets_wdata;
                end if;

                if buy_rescan_in = '1' then
                    buy_rescan_pending <= '1';
                end if;

                if sell_rescan_in = '1' then
                    sell_rescan_pending <= '1';
                end if;

            end if;
            

        end if;

    end process;

end architecture;