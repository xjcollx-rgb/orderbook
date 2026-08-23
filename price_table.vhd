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


    bid1_price   : out unsigned(31 downto 0) := (others => '0');
    bid1_shares  : out unsigned(31 downto 0) := (others => '0');

    ask1_price   : out unsigned(31 downto 0) := (others => '0');
    ask1_shares  : out unsigned(31 downto 0) := (others => '0');

    data_written : out std_logic
);
end price_table;

architecture rtl of price_table is

    ----------------------------------------------------------------
    -- Main aggregation table: 2048 price levels, hashed + linear
    -- probed on price.
    --
    -- Word layout (97 bits):
    --   bit  96      : valid
    --   bits 95..64  : price
    --   bits 63..32  : aggregate buy shares  at this price
    --   bits 31..0   : aggregate sell shares at this price
    ----------------------------------------------------------------
    type ram_t is array (0 to 2047) of unsigned(96 downto 0);
    signal ram : ram_t := (others => (others => '0'));

    type ram_bucket is array(0 to 255) of unsigned(255 downto 0);
    signal buckets : ram_bucket := (others =>(others=> '0'));

    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";

    attribute bucket_style : string;
    attribute bucket_style of buckets : signal is "block";

    ----------------------------------------------------------------
    -- State machine
    ----------------------------------------------------------------
    type state_t is (IDLE, READ, CHECK, WRITE, RESCAN);
    signal state : state_t := IDLE;

    -- Operation types
    constant ADD     : unsigned(1 downto 0) := "00";
    constant EXECCAN : unsigned(1 downto 0) := "01";
    constant REPLACE : unsigned(1 downto 0) := "10";
    constant DELETE  : unsigned(1 downto 0) := "11";

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
    signal price_table_address : unsigned(0 to 2047);

    signal price_found : std_logic;

    signal bucket_empty_0 : std_logic;
    signal bucket_empty_1 : std_logic;
    signal bucket_empty_2 : std_logic;
    signal bucket_empty_3 : std_logic;
    signal bucket_empty_4 : std_logic;
    signal bucket_empty_5 : std_logic;    
    signal bucket_empty_6 : std_logic;    
    signal bucket_empty_7 : std_logic;

begin


    process(clk)


    begin
        if rising_edge(clk) then

            if rst = '1' then


            else

                case state is

                    when IDLE =>

                        data_written <= '0';

                        if fifo_empty = '0' then
                            
                            original_hash<= price_table(7 downto 0) xor price_table(15 downto 8) xor price_table(23 downto 16) xor price_table(31 downto 24);
                            original_price <= price_table(31 downto 0);
                            original_shares <= price_table(63 downto 32);
                            original_side <= price_table(71 downto 64);

                            replace_hash <= price_table(79 downto 72) xor price_table(87 downto 80) xor price_table(95 downto 88) xor price_table(103 downto 96);
                            replace_price <= price_table(103 downto 72);
                            replace_shares <= price_table(135 downto 104);
                            replace_side <= price_table(143 downto 136);
                            
                            state <= READ;


                        end if;

                    when READ =>

                            if replace_run = '0' then
                                bucket_data <= buckets(to_integer(original_hash));
                            
                            else 
                                bucket_data <= buckets(to_integer(replace_hash));
                                
                            end if;
                        state <= CHECK;

                    when CHECK =>

                        if bucket_data(31 downto 0) = (others => '0') then 
                                bucket_empty_0 <= '1';

                        elsif bucket_data(63 downto 32 ) = (others => '0') then 
                                bucket_empty_1 <= '1';

                        elsif bucket_data(95 downto 64 ) = (others => '0') then 
                                bucket_empty_2 <= '1';

                        elsif bucket_data(127 downto 96 ) = (others => '0') then 
                                bucket_empty_3 <= '1';

                        elsif bucket_data(159 downto 128) = (others => '0') then 
                                bucket_empty_4 <= '1';

                        elsif bucket_data(191 downto 160 ) = (others => '0') then 
                                bucket_empty_5 <= '1';

                        elsif bucket_data(223 downto 192) = (others => '0') then 
                                bucket_empty_6 <= '1';

                        elsif bucket_data(255 downto 224 ) = (others => '0') then 
                                bucket_empty_7 <= '1';
                        end if;

                        
                        if replace_run = '0' then 
                            if bucket_data(31 downto 0) = original_price then 
                                price_table_address <= (original_hash * 8);
                                price_found <= '1';
                            end if;

                            if bucket_data(63 downto 32) = original_price then 
                                price_table_address <= (original_hash * 8) + 1;
                                price_found <= '1';
                            end if;
                            if bucket_data(95 downto 64) = original_price then 
                                price_table_address <= (original_hash * 8) + 2;
                                price_found <= '1';
                            end if;
                            if bucket_data(127 downto 96) = original_price then 
                                price_table_address <= (original_hash * 8) + 3;
                                price_found <= '1';
                            end if;

                            if bucket_data(159 downto 128) = original_price then 
                                price_table_address <= (original_hash * 8) + 4;
                                price_found <= '1';
                            end if;

                            if bucket_data(191 downto 160) = original_price then 
                                price_table_address <= (original_hash * 8) + 5;
                                price_found <= '1';
                            end if;

                            if bucket_data(223 downto 192) = original_price then 
                                price_table_address <= (original_hash * 8) + 6;
                                price_found <= '1';
                            end if; 

                            if bucket_data(255 downto 224) = original_price then 
                                price_table_address <= (original_hash * 8) + 7;
                                price_found <= '1';
                            end if;

                        else 

                            if bucket_data(31 downto 0) = replace_price then 
                                price_table_address <= (replace_hash * 8);
                            elsif bucket_data(63 downto 32) = replace_price then 
                                price_table_address <= (replace_hash * 8) + 1;
                            elsif bucket_data(95 downto 64) = replace_price then 
                                price_table_address <= (replace_hash * 8) + 2;
                            elsif bucket_data(127 downto 96) = replace_price then 
                                price_table_address <= (replace_hash * 8) + 3;
                            elsif bucket_data(159 downto 128) = replace_price then 
                                price_table_address <= (replace_hash * 8) + 4;
                            elsif bucket_data(191 downto 160) = replace_price then 
                                price_table_address <= (replace_hash * 8) + 5;
                            elsif bucket_data(223 downto 192) = replace_price then 
                                price_table_address <= (replace_hash * 8) + 6;
                            elsif bucket_data(255 downto 224) = replace_price then 
                                price_table_address <= (replace_hash * 8) + 7;
                            end if;

                        end if;


                    when WRITE =>

                    when RESCAN =>



                end case;

            end if;

        end if;

    end process;

end architecture;