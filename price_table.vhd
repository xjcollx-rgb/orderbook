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
    bbo_delete : out std_logic
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
    -- State machine
    ----------------------------------------------------------------
    type state_t is (IDLE, READ_BUCKETS, CHECK, READ_PRICE_TABLE, WRITE_PRICE_TABLE);
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
    signal bucket_data : unsigned(255 downto 0);
    signal price_table_address : unsigned(10 downto 0);
    signal read_data : unsigned(95 downto 0);



    signal price_found : std_logic;

    signal empty_slot_address : unsigned(10 downto 0);
    signal empty_slot_found : std_logic;
    signal empty_bucket_address : unsigned(2 downto 0);
    signal price_found_bucket_address : unsigned(2 downto 0);

begin


    process(clk)

        variable v_read_data : unsigned(95 downto 0);
        variable v_bucket_data : unsigned(255 downto 0);

    begin
        if rising_edge(clk) then

            if rst = '1' then


            else

                case state is

                    when IDLE =>

                        data_written <= '0';
                        empty_slot_found <= '0';
                        empty_slot_address <= (others => '0');
                        price_found <= '0';
                        price_table_address <= (others => '0');
                        replace_run <= '0';


                        if fifo_empty = '0' then
                            
                            original_hash<= price_table(7 downto 0) xor price_table(15 downto 8) xor price_table(23 downto 16) xor price_table(31 downto 24);
                            original_price <= price_table(31 downto 0);
                            original_shares <= price_table(63 downto 32);
                            original_side <= price_table(71 downto 64);

                            replace_hash <= price_table(79 downto 72) xor price_table(87 downto 80) xor price_table(95 downto 88) xor price_table(103 downto 96);
                            replace_price <= price_table(103 downto 72);
                            replace_shares <= price_table(135 downto 104);
                            replace_side <= price_table(143 downto 136);
                            
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
                            if bucket_data(31 downto 0) = (others => '0') then 
                                empty_slot_address <= (original_hash & "000");
                                empty_slot_found <= '1';
                                empty_bucket_address <= "000";

                            elsif bucket_data(63 downto 32 ) = (others => '0') then 
                                empty_slot_address <= (original_hash & "000") + 1;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "001";

                            elsif bucket_data(95 downto 64 ) = (others => '0') then 
                                empty_slot_address <= (original_hash & "000") + 2;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "010";

                            elsif bucket_data(127 downto 96 ) = (others => '0') then 
                                empty_slot_address <= (original_hash & "000") + 3;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "011";

                            elsif bucket_data(159 downto 128) = (others => '0') then 
                                empty_slot_address <= (original_hash & "000") + 4;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "100";

                            elsif bucket_data(191 downto 160 ) = (others => '0') then 
                                empty_slot_address <= (original_hash & "000") + 5;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "101";

                            elsif bucket_data(223 downto 192) = (others => '0') then 
                                empty_slot_address <= (original_hash & "000") + 6;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "110";

                            elsif bucket_data(255 downto 224 ) = (others => '0') then 
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

                            if bucket_data(31 downto 0) = (others => '0') then 
                                empty_slot_address <= (replace_hash & "000");
                                empty_slot_found <= '1';
                                empty_bucket_address <= "000";

                            elsif bucket_data(63 downto 32 ) = (others => '0') then 
                                empty_slot_address <= (replace_hash & "000") + 1;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "001";

                            elsif bucket_data(95 downto 64 ) = (others => '0') then 
                                empty_slot_address <= (replace_hash & "000") + 2;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "010";

                            elsif bucket_data(127 downto 96 ) = (others => '0') then 
                                empty_slot_address <= (replace_hash & "000") + 3;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "011";

                            elsif bucket_data(159 downto 128) = (others => '0') then 
                                empty_slot_address <= (replace_hash & "000") + 4;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "100";

                            elsif bucket_data(191 downto 160 ) = (others => '0') then 
                                empty_slot_address <= (replace_hash & "000") + 5;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "101";

                            elsif bucket_data(223 downto 192) = (others => '0') then 
                                empty_slot_address <= (replace_hash & "000") + 6;
                                empty_slot_found <= '1';
                                empty_bucket_address <= "110";

                            elsif bucket_data(255 downto 224 ) = (others => '0') then 
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

                            elsif empty_slot_found = '1' then 

                                state <= WRITE_PRICE_TABLE;

                            else --need to add some sort of over flow incase the buckets are full

                                

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
                                            ram(to_integer(price_table_address)) <= v_read_data;
                                            bbo_shares <= v_read_data(95 downto 48);
                                            state <= IDLE;

                                        else 

                                            v_read_data(47 downto 0) := v_read_data(47 downto 0) + resize(original_shares, 48);
                                            ram(to_integer(price_table_address)) <= v_read_data;
                                            bbo_shares <= v_read_data(47 downto 0);
                                            state <= IDLE;

                                        end if;

                                        bbo_price <= original_price;
                                        bbo_side <= original_side;
                                        bbo_delete <= '0';

                                        data_written <= '1';

                                    elsif empty_slot_found = '1' then
                                        
                                        v_bucket_data(31 + (to_integer(empty_bucket_address) * 32)  downto (to_integer(empty_bucket_address) * 32)) := original_price;
                                        buckets(to_integer(original_hash)) <= v_bucket_data;

                                        if original_side = BUY then 

                                            ram(to_integer(empty_slot_address)) <=  resize(original_shares, 48) & (others => '0');
                                            state <= IDLE;

                                        else 

                                            ram(to_integer(empty_slot_address)) <= (others => '0') & resize(original_shares, 48) ;
                                            state <= IDLE;

                                        end if;

                                        data_written <= '1';
                                        bbo_price <= original_price;
                                        bbo_shares <= resize(original_shares, 48);
                                        bbo_side <= original_side;
                                        bbo_delete <= '0';
                                    else 
                                    
                                    -- undcieded what to do with overflow yet

                                    end if;



                                when EXECCAN | DELETE=>
                                        
                                    if price_found = '1' then 

                                        if original_side = BUY then 

                                            v_read_data(95 downto 48) := v_read_data(95 downto 48) - resize(original_shares, 48);

                                            if v_read_data(95 downto 48) = (others => '0') then 
                                                bbo_price <= original_price;
                                                bbo_delete <= '1';
                                                bbo_side <= original_side;
                                            end if;

                                            if v_read_data(95 downto 48) = (others => '0') and v_read_data(47 downto 0) = (others => '0') then
                                                v_bucket_data(31 + (to_integer(price_found_bucket_address) * 32)  downto (to_integer(price_found_bucket_address) * 32)) := (others => '0');
                                                buckets(to_integer(original_hash)) <= v_bucket_data; 
                                                state <= IDLE;

                                            else 
                                            ram(to_integer(price_table_address)) <= v_read_data;
                                            bbo_price <= original_price;
                                            bbo_shares <= v_read_data(95 downto 48);
                                            bbo_side <= original_side;
                                            bbo_delete <= '0';
                                            state <= IDLE;
                                            
                                            end if;

                                            data_written <= '1';
                                        else 

                                            v_read_data(47 downto 0) := v_read_data(47 downto 0) - resize(original_shares, 48);

                                            if v_read_data(47 downto 0) = (others => '0') then 
                                                bbo_price <= original_price;
                                                bbo_delete <= '1';
                                                bbo_side <= original_side;
                                            end if;

                                            if v_read_data(95 downto 48) = (others => '0') and v_read_data(47 downto 0) = (others => '0') then
                                                v_bucket_data(31 + (to_integer(price_found_bucket_address) * 32)  downto (to_integer(price_found_bucket_address) * 32)) := (others => '0');
                                                buckets(to_integer(original_hash)) <= v_bucket_data; 
                                                state <= IDLE;

                                            else 

                                            ram(to_integer(price_table_address)) <= v_read_data;
                                            bbo_price <= original_price;
                                            bbo_shares <= v_read_data(47 downto 0);
                                            bbo_side <= original_side;
                                            bbo_delete <= '0';
                                            state <= IDLE;

                                            end if;

                                            data_written <= '1';

                                        end if;
                                    
                                    else 
                                    
                                    -- undcieded what to do with unfound replace/delete/cancel yet

                                    end if;

                                when REPLACE => 

                                    if replace_run = '0' then 

                                        if price_found = '1' then   

                                            if original_side = BUY then 

                                                v_read_data(95 downto 48) := v_read_data(95 downto 48) - resize(original_shares, 48);

                                                if v_read_data(95 downto 48) = (others => '0') then 
                                                    bbo_price <= original_price;
                                                    bbo_delete <= '1';
                                                    bbo_side <= original_side;
                                                end if;

                                                if v_read_data(95 downto 48) = (others => '0') and v_read_data(47 downto 0) = (others => '0') then
                                                    v_bucket_data(31 + (to_integer(price_found_bucket_address) * 32)  downto (to_integer(price_found_bucket_address) * 32)) := (others => '0');
                                                    buckets(to_integer(original_hash)) <= v_bucket_data; 
                                                    state <= READ_BUCKETS;
                                                else 
                                                    ram(to_integer(price_table_address)) <= v_read_data;
                                                    bbo_price <= original_price;
                                                    bbo_shares <= v_read_data(95 downto 48);
                                                    bbo_side <= original_side;
                                                    bbo_delete <= '0';
                                                    state <= READ_BUCKETS;
                                                
                                                end if;
                                            else 

                                                v_read_data(47 downto 0) := v_read_data(47 downto 0) - resize(original_shares, 48);

                                                if v_read_data(47 downto 0) = (others => '0') then 
                                                    bbo_price <= original_price;
                                                    bbo_delete <= '1';
                                                    bbo_side <= original_side;
                                                end if;

                                                if v_read_data(95 downto 48) = (others => '0') and v_read_data(47 downto 0) = (others => '0') then
                                                    v_bucket_data(31 + (to_integer(price_found_bucket_address) * 32)  downto (to_integer(price_found_bucket_address) * 32)) := (others => '0');
                                                    buckets(to_integer(original_hash)) <= v_bucket_data; 
                                                    state <= READ_BUCKETS;

                                                else 

                                                    ram(to_integer(price_table_address)) <= v_read_data;
                                                    bbo_price <= original_price;
                                                    bbo_shares <= v_read_data(47 downto 0);
                                                    bbo_side <= original_side;
                                                    bbo_delete <= '0';
                                                    state <= READ_BUCKETS;

                                                end if;

                                            end if;

                                            replace_run <= '1';

                                        else 

                                            -- has to exsits for a replace order, not sure what to do here
                                        end if;
                                        
                                    else
                                    
                                        if price_found = '1' then 

                                            if original_side = BUY then 

                                                v_read_data(95 downto 48) := v_read_data(95 downto 48) + resize(replace_shares, 48);
                                                ram(to_integer(price_table_address)) <= v_read_data;
                                                bbo_shares <= v_read_data(95 downto 48);
                                                state <= IDLE;

                                            else 

                                                v_read_data(47 downto 0) := v_read_data(47 downto 0) + resize(replace_shares, 48);
                                                ram(to_integer(price_table_address)) <= v_read_data;
                                                bbo_shares <= v_read_data(47 downto 0);
                                                state <= IDLE;

                                            end if;

                                            bbo_price <= replace_price;
                                            bbo_side <= replace_side;
                                            bbo_delete <= '0';

                                            data_written <= '1';

                                        elsif empty_slot_found = '1' then
                                            
                                            v_bucket_data(31 + (to_integer(empty_bucket_address) * 32)  downto (to_integer(empty_bucket_address) * 32)) := replace_price;
                                            buckets(to_integer(replace_hash)) <= v_bucket_data;

                                            if original_side = BUY then 

                                                ram(to_integer(empty_slot_address)) <=  resize(replace_shares, 48) & (others => '0');
                                                state <= IDLE;

                                            else 

                                                ram(to_integer(empty_slot_address)) <= (others => '0') & resize(replace_shares, 48) ;
                                                state <= IDLE;

                                            end if;

                                            data_written <= '1';
                                            bbo_price <= replace_price;
                                            bbo_shares <= resize(replace_shares, 48);
                                            bbo_side <= replace_side;
                                            bbo_delete <= '0';
                                        else 
                                        
                                        -- undcieded what to do with overflow yet

                                        end if;
                                    

                                    end if;

                                

                        end case;

                end case;

            end if;

        end if;

    end process;

end architecture;