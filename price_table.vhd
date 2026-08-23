library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity price_table is
port (
    clk          : in  std_logic;
    rst          : in  std_logic;

    -- Bus from ref_table:
    --   [145:144] frame type: 00 ADD, 01 EXEC/CANCEL, 10 REPLACE, 11 DELETE
    --   [143:72]  "replacing" order data (REPLACE only)
    --   [71:0]    "original"   order data (normal case, or OLD order on REPLACE)
    --   each 72b order = side[71:64] | shares[63:32] | price[31:0]
    --   ASSUMPTION: side(64) = '0' buy / '1' sell
    price_table  : in  unsigned(145 downto 0);
    data_written : in  std_logic;   -- pulses for one cycle when price_table is valid

    -- Top?2 BBO, each side
    bid1_price   : out unsigned(31 downto 0) := (others => '0');
    bid1_shares  : out unsigned(31 downto 0) := (others => '0');
    bid2_price   : out unsigned(31 downto 0) := (others => '0');
    bid2_shares  : out unsigned(31 downto 0) := (others => '0');

    ask1_price   : out unsigned(31 downto 0) := (others => '0');
    ask1_shares  : out unsigned(31 downto 0) := (others => '0');
    ask2_price   : out unsigned(31 downto 0) := (others => '0');
    ask2_shares  : out unsigned(31 downto 0) := (others => '0')
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

    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";

    ----------------------------------------------------------------
    -- State machine
    ----------------------------------------------------------------
    type state_t is (IDLE, READ, CHECK, WRITE, RESCAN_READ, RESCAN_ACC);
    signal state : state_t := IDLE;

    -- Operation types
    constant TYPE_ADD     : unsigned(1 downto 0) := "00";
    constant TYPE_EXECCAN : unsigned(1 downto 0) := "01";
    constant TYPE_REPLACE : unsigned(1 downto 0) := "10";
    constant TYPE_DELETE  : unsigned(1 downto 0) := "11";

    -- Hash table search control
    signal address          : unsigned(10 downto 0) := (others => '0');
    signal search_count     : unsigned(11 downto 0) := (others => '0');
    signal read_data        : unsigned(96 downto 0) := (others => '0');

    -- Operation being processed
    signal frame_type_r     : unsigned(1 downto 0)  := (others => '0');
    signal pass_r           : std_logic := '0';   -- '0' = pass1 (or only pass), '1' = REPLACE pass2
    signal cur_order        : unsigned(71 downto 0) := (others => '0');
    signal new_order_r      : unsigned(71 downto 0) := (others => '0'); -- stashed REPLACE new order

    -- First empty slot found during search (for ADD)
    signal first_empty_addr  : unsigned(10 downto 0) := (others => '0');
    signal first_empty_valid : std_logic := '0';

    -- Write control
    signal write_addr       : unsigned(10 downto 0) := (others => '0');
    signal write_is_new     : std_logic := '0';  -- '1' = write to a previously empty slot

    -- Deferred rescan bookkeeping
    signal pending_pass2    : std_logic := '0';  -- start pass2 after rescan finishes

    ----------------------------------------------------------------
    -- Top?2 registers for each side (direct outputs)
    ----------------------------------------------------------------
    signal bid1_valid_r   : std_logic := '0';
    signal bid1_price_r   : unsigned(31 downto 0) := (others => '0');
    signal bid1_shares_r  : unsigned(31 downto 0) := (others => '0');
    signal bid2_valid_r   : std_logic := '0';
    signal bid2_price_r   : unsigned(31 downto 0) := (others => '0');
    signal bid2_shares_r  : unsigned(31 downto 0) := (others => '0');

    signal ask1_valid_r   : std_logic := '0';
    signal ask1_price_r   : unsigned(31 downto 0) := (others => '0');
    signal ask1_shares_r  : unsigned(31 downto 0) := (others => '0');
    signal ask2_valid_r   : std_logic := '0';
    signal ask2_price_r   : unsigned(31 downto 0) := (others => '0');
    signal ask2_shares_r  : unsigned(31 downto 0) := (others => '0');

    ----------------------------------------------------------------
    -- Rescan accumulators (used during full RAM sweep)
    ----------------------------------------------------------------
    signal rs_bid1_valid, rs_bid2_valid : std_logic := '0';
    signal rs_bid1_price, rs_bid1_shares : unsigned(31 downto 0) := (others => '0');
    signal rs_bid2_price, rs_bid2_shares : unsigned(31 downto 0) := (others => '0');
    signal rs_ask1_valid, rs_ask2_valid : std_logic := '0';
    signal rs_ask1_price, rs_ask1_shares : unsigned(31 downto 0) := (others => '0');
    signal rs_ask2_price, rs_ask2_shares : unsigned(31 downto 0) := (others => '0');

    signal scan_addr        : unsigned(10 downto 0) := (others => '0');

    ----------------------------------------------------------------
    -- hash11: fold a 32?bit price into an 11?bit address
    ----------------------------------------------------------------
    function hash11(p : unsigned(31 downto 0)) return unsigned is
        variable h : unsigned(10 downto 0);
    begin
        h := p(10 downto 0)
             xor p(21 downto 11)
             xor ("0" & p(31 downto 22));
        return h;
    end function;

begin

    ----------------------------------------------------------------
    -- Output assignments (directly from internal registers)
    ----------------------------------------------------------------
    bid1_price  <= bid1_price_r  when bid1_valid_r = '1' else (others => '0');
    bid1_shares <= bid1_shares_r when bid1_valid_r = '1' else (others => '0');
    bid2_price  <= bid2_price_r  when bid2_valid_r = '1' else (others => '0');
    bid2_shares <= bid2_shares_r when bid2_valid_r = '1' else (others => '0');

    ask1_price  <= ask1_price_r  when ask1_valid_r = '1' else (others => '0');
    ask1_shares <= ask1_shares_r when ask1_valid_r = '1' else (others => '0');
    ask2_price  <= ask2_price_r  when ask2_valid_r = '1' else (others => '0');
    ask2_shares <= ask2_shares_r when ask2_valid_r = '1' else (others => '0');

    ----------------------------------------------------------------
    -- Main state machine (synchronous, rising edge)
    ----------------------------------------------------------------
    process(clk)

        -- Variables used in various states
        variable v_is_add      : boolean;
        variable v_is_sub      : boolean;
        variable v_side        : std_logic;
        variable v_price       : unsigned(31 downto 0);
        variable v_delta       : unsigned(31 downto 0);
        variable v_old_buy     : unsigned(31 downto 0);
        variable v_old_sell    : unsigned(31 downto 0);
        variable v_new_buy     : unsigned(31 downto 0);
        variable v_new_sell    : unsigned(31 downto 0);
        variable v_valid       : std_logic;
        variable v_touch_shares: unsigned(31 downto 0);
        variable v_need_rescan : boolean;

        -- Next values for bid shadow registers (used in WRITE)
        variable n_bid1_valid, n_bid2_valid : std_logic;
        variable n_bid1_price, n_bid1_shares : unsigned(31 downto 0);
        variable n_bid2_price, n_bid2_shares : unsigned(31 downto 0);

        -- Next values for ask shadow registers (used in WRITE)
        variable n_ask1_valid, n_ask2_valid : std_logic;
        variable n_ask1_price, n_ask1_shares : unsigned(31 downto 0);
        variable n_ask2_price, n_ask2_shares : unsigned(31 downto 0);

        -- Next values for rescan accumulators (used in RESCAN_ACC)
        variable n_rs_bid1_valid, n_rs_bid2_valid : std_logic;
        variable n_rs_bid1_price, n_rs_bid1_shares : unsigned(31 downto 0);
        variable n_rs_bid2_price, n_rs_bid2_shares : unsigned(31 downto 0);
        variable n_rs_ask1_valid, n_rs_ask2_valid : std_logic;
        variable n_rs_ask1_price, n_rs_ask1_shares : unsigned(31 downto 0);
        variable n_rs_ask2_price, n_rs_ask2_shares : unsigned(31 downto 0);

    begin
        if rising_edge(clk) then

            if rst = '1' then
                -- Reset everything except the RAM content (assumed zero at power?up)
                state             <= IDLE;
                address           <= (others => '0');
                search_count      <= (others => '0');
                read_data         <= (others => '0');
                frame_type_r      <= (others => '0');
                pass_r            <= '0';
                first_empty_valid <= '0';
                pending_pass2     <= '0';

                bid1_valid_r <= '0'; bid1_price_r <= (others=>'0'); bid1_shares_r <= (others=>'0');
                bid2_valid_r <= '0'; bid2_price_r <= (others=>'0'); bid2_shares_r <= (others=>'0');
                ask1_valid_r <= '0'; ask1_price_r <= (others=>'0'); ask1_shares_r <= (others=>'0');
                ask2_valid_r <= '0'; ask2_price_r <= (others=>'0'); ask2_shares_r <= (others=>'0');

                rs_bid1_valid <= '0'; rs_bid1_price <= (others=>'0'); rs_bid1_shares <= (others=>'0');
                rs_bid2_valid <= '0'; rs_bid2_price <= (others=>'0'); rs_bid2_shares <= (others=>'0');
                rs_ask1_valid <= '0'; rs_ask1_price <= (others=>'0'); rs_ask1_shares <= (others=>'0');
                rs_ask2_valid <= '0'; rs_ask2_price <= (others=>'0'); rs_ask2_shares <= (others=>'0');
                scan_addr <= (others => '0');

            else

                -- Default: no rescan needed
                v_need_rescan := false;

                case state is

                    ----------------------------------------------------
                    -- IDLE: wait for a new operation
                    ----------------------------------------------------
                    when IDLE =>
                        if data_written = '1' then
                            -- Latch operation data
                            frame_type_r      <= price_table(145 downto 144);
                            cur_order         <= price_table(71 downto 0);
                            new_order_r       <= price_table(143 downto 72);
                            pass_r            <= '0';
                            search_count      <= (others => '0');
                            first_empty_valid <= '0';
                            -- Start search at hash of the price
                            address           <= hash11(price_table(31 downto 0));
                            state             <= READ;
                        end if;

                    ----------------------------------------------------
                    -- READ: synchronous BRAM read (one cycle latency)
                    ----------------------------------------------------
                    when READ =>
                        read_data <= ram(to_integer(address));
                        state     <= CHECK;

                    ----------------------------------------------------
                    -- CHECK: examine the current table entry
                    ----------------------------------------------------
                    when CHECK =>
                        -- Determine if this pass is an add or a subtract
                        v_is_add := (frame_type_r = TYPE_ADD)
                                    or (frame_type_r = TYPE_REPLACE and pass_r = '1');
                        v_is_sub := not v_is_add;

                        if read_data(96) = '1' and read_data(95 downto 64) = cur_order(31 downto 0) then
                            -- Matching price level found
                            write_addr   <= address;
                            write_is_new <= '0';
                            state        <= WRITE;

                        else
                            -- Remember first empty slot if we find one
                            if read_data(96) = '0' and first_empty_valid = '0' then
                                first_empty_addr  <= address;
                                first_empty_valid <= '1';
                            end if;

                            -- Have we searched all 2048 slots?
                            if search_count >= 2047 then
                                if v_is_add and first_empty_valid = '1' then
                                    -- Use the first empty slot we saw
                                    write_addr   <= first_empty_addr;
                                    write_is_new <= '1';
                                    state        <= WRITE;
                                elsif v_is_add and read_data(96) = '0' then
                                    -- The current slot is empty and we haven't seen another
                                    write_addr   <= address;
                                    write_is_new <= '1';
                                    state        <= WRITE;
                                else
                                    -- Table full (add) or no match found (subtract) ? drop
                                    state <= IDLE;
                                end if;
                            else
                                -- Continue linear probing
                                if address = 2047 then
                                    address <= (others => '0');
                                else
                                    address <= address + 1;
                                end if;
                                search_count <= search_count + 1;
                                state        <= READ;
                            end if;
                        end if;

                    ----------------------------------------------------
                    -- WRITE: update RAM and the top?2 shadow registers
                    ----------------------------------------------------
                    when WRITE =>
                        v_is_add := (frame_type_r = TYPE_ADD)
                                    or (frame_type_r = TYPE_REPLACE and pass_r = '1');
                        v_side   := cur_order(64);
                        v_need_rescan := false;

                        --------------------------------------------------
                        -- 1. Compute new aggregate buy/sell shares
                        --------------------------------------------------
                        if v_is_add then
                            v_price := cur_order(31 downto 0);

                            if write_is_new = '1' then
                                v_old_buy  := (others => '0');
                                v_old_sell := (others => '0');
                            else
                                v_old_buy  := read_data(63 downto 32);
                                v_old_sell := read_data(31 downto 0);
                            end if;

                            if v_side = '0' then
                                v_new_buy  := v_old_buy + cur_order(63 downto 32);
                                v_new_sell := v_old_sell;
                            else
                                v_new_sell := v_old_sell + cur_order(63 downto 32);
                                v_new_buy  := v_old_buy;
                            end if;

                            ram(to_integer(write_addr)) <= '1' & v_price & v_new_buy & v_new_sell;

                        else
                            -- Subtract path (EXEC/CANCEL, DELETE, REPLACE pass1)
                            v_price := read_data(95 downto 64);
                            v_delta := cur_order(63 downto 32);

                            v_old_buy  := read_data(63 downto 32);
                            v_old_sell := read_data(31 downto 0);

                            if v_side = '0' then
                                if v_delta >= v_old_buy then
                                    v_new_buy := (others => '0');
                                else
                                    v_new_buy := v_old_buy - v_delta;
                                end if;
                                v_new_sell := v_old_sell;
                            else
                                if v_delta >= v_old_sell then
                                    v_new_sell := (others => '0');
                                else
                                    v_new_sell := v_old_sell - v_delta;
                                end if;
                                v_new_buy := v_old_buy;
                            end if;

                            if v_new_buy = 0 and v_new_sell = 0 then
                                v_valid := '0';
                            else
                                v_valid := '1';
                            end if;

                            ram(to_integer(write_addr)) <= v_valid & v_price & v_new_buy & v_new_sell;
                        end if;

                        -- Shares that matter for the touched side
                        if v_side = '0' then
                            v_touch_shares := v_new_buy;
                        else
                            v_touch_shares := v_new_sell;
                        end if;

                        --------------------------------------------------
                        -- 2. Update the top?2 list for the touched side
                        --------------------------------------------------
                        -- Start with current register values
                        n_bid1_valid := bid1_valid_r;
                        n_bid1_price := bid1_price_r;
                        n_bid1_shares := bid1_shares_r;
                        n_bid2_valid := bid2_valid_r;
                        n_bid2_price := bid2_price_r;
                        n_bid2_shares := bid2_shares_r;

                        n_ask1_valid := ask1_valid_r;
                        n_ask1_price := ask1_price_r;
                        n_ask1_shares := ask1_shares_r;
                        n_ask2_valid := ask2_valid_r;
                        n_ask2_price := ask2_price_r;
                        n_ask2_shares := ask2_shares_r;

                        if v_side = '0' then
                            -- -------- BID side (highest price first) --------
                            if bid1_valid_r = '1' and bid1_price_r = v_price then
                                -- Price is currently #1
                                if v_touch_shares = 0 then
                                    -- #1 disappears: promote #2 to #1, clear #2
                                    n_bid1_valid := bid2_valid_r;
                                    n_bid1_price := bid2_price_r;
                                    n_bid1_shares := bid2_shares_r;
                                    n_bid2_valid := '0';
                                    n_bid2_price := (others => '0');
                                    n_bid2_shares := (others => '0');
                                    v_need_rescan := true;
                                else
                                    n_bid1_shares := v_touch_shares;
                                end if;

                            elsif bid2_valid_r = '1' and bid2_price_r = v_price then
                                -- Price is currently #2
                                if v_touch_shares = 0 then
                                    n_bid2_valid := '0';
                                    n_bid2_price := (others => '0');
                                    n_bid2_shares := (others => '0');
                                    v_need_rescan := true;
                                else
                                    n_bid2_shares := v_touch_shares;
                                end if;

                            else
                                -- Price not in top?2 yet
                                if v_touch_shares /= 0 then
                                    if bid1_valid_r = '0' then
                                        n_bid1_valid := '1';
                                        n_bid1_price := v_price;
                                        n_bid1_shares := v_touch_shares;
                                    elsif v_price > bid1_price_r then
                                        n_bid2_valid := bid1_valid_r;
                                        n_bid2_price := bid1_price_r;
                                        n_bid2_shares := bid1_shares_r;
                                        n_bid1_valid := '1';
                                        n_bid1_price := v_price;
                                        n_bid1_shares := v_touch_shares;
                                    elsif bid2_valid_r = '0' then
                                        n_bid2_valid := '1';
                                        n_bid2_price := v_price;
                                        n_bid2_shares := v_touch_shares;
                                    elsif v_price > bid2_price_r then
                                        n_bid2_valid := '1';
                                        n_bid2_price := v_price;
                                        n_bid2_shares := v_touch_shares;
                                    end if;
                                end if;
                            end if;

                            -- Commit bid registers
                            bid1_valid_r <= n_bid1_valid;
                            bid1_price_r <= n_bid1_price;
                            bid1_shares_r <= n_bid1_shares;
                            bid2_valid_r <= n_bid2_valid;
                            bid2_price_r <= n_bid2_price;
                            bid2_shares_r <= n_bid2_shares;

                        else
                            -- -------- ASK side (lowest price first) --------
                            if ask1_valid_r = '1' and ask1_price_r = v_price then
                                if v_touch_shares = 0 then
                                    n_ask1_valid := ask2_valid_r;
                                    n_ask1_price := ask2_price_r;
                                    n_ask1_shares := ask2_shares_r;
                                    n_ask2_valid := '0';
                                    n_ask2_price := (others => '0');
                                    n_ask2_shares := (others => '0');
                                    v_need_rescan := true;
                                else
                                    n_ask1_shares := v_touch_shares;
                                end if;

                            elsif ask2_valid_r = '1' and ask2_price_r = v_price then
                                if v_touch_shares = 0 then
                                    n_ask2_valid := '0';
                                    n_ask2_price := (others => '0');
                                    n_ask2_shares := (others => '0');
                                    v_need_rescan := true;
                                else
                                    n_ask2_shares := v_touch_shares;
                                end if;

                            else
                                if v_touch_shares /= 0 then
                                    if ask1_valid_r = '0' then
                                        n_ask1_valid := '1';
                                        n_ask1_price := v_price;
                                        n_ask1_shares := v_touch_shares;
                                    elsif v_price < ask1_price_r then
                                        n_ask2_valid := ask1_valid_r;
                                        n_ask2_price := ask1_price_r;
                                        n_ask2_shares := ask1_shares_r;
                                        n_ask1_valid := '1';
                                        n_ask1_price := v_price;
                                        n_ask1_shares := v_touch_shares;
                                    elsif ask2_valid_r = '0' then
                                        n_ask2_valid := '1';
                                        n_ask2_price := v_price;
                                        n_ask2_shares := v_touch_shares;
                                    elsif v_price < ask2_price_r then
                                        n_ask2_valid := '1';
                                        n_ask2_price := v_price;
                                        n_ask2_shares := v_touch_shares;
                                    end if;
                                end if;
                            end if;

                            -- Commit ask registers
                            ask1_valid_r <= n_ask1_valid;
                            ask1_price_r <= n_ask1_price;
                            ask1_shares_r <= n_ask1_shares;
                            ask2_valid_r <= n_ask2_valid;
                            ask2_price_r <= n_ask2_price;
                            ask2_shares_r <= n_ask2_shares;
                        end if;

                        --------------------------------------------------
                        -- 3. Decide next state
                        --------------------------------------------------
                        if v_need_rescan then
                            -- Start a full rescan of BOTH sides
                            scan_addr <= (others => '0');
                            -- Clear rescan accumulators
                            rs_bid1_valid <= '0';
                            rs_bid1_price <= (others => '0');
                            rs_bid1_shares <= (others => '0');
                            rs_bid2_valid <= '0';
                            rs_bid2_price <= (others => '0');
                            rs_bid2_shares <= (others => '0');
                            rs_ask1_valid <= '0';
                            rs_ask1_price <= (others => '0');
                            rs_ask1_shares <= (others => '0');
                            rs_ask2_valid <= '0';
                            rs_ask2_price <= (others => '0');
                            rs_ask2_shares <= (others => '0');

                            -- If this is REPLACE pass1, remember to do pass2 later
                            if frame_type_r = TYPE_REPLACE and pass_r = '0' then
                                pending_pass2 <= '1';
                            else
                                pending_pass2 <= '0';
                            end if;

                            state <= RESCAN_READ;

                        elsif frame_type_r = TYPE_REPLACE and pass_r = '0' then
                            -- No rescan needed: go straight to pass2
                            pass_r            <= '1';
                            cur_order         <= new_order_r;
                            search_count      <= (others => '0');
                            first_empty_valid <= '0';
                            address           <= hash11(new_order_r(31 downto 0));
                            state             <= READ;

                        else
                            state <= IDLE;
                        end if;

                    ----------------------------------------------------
                    -- RESCAN_READ: read next RAM entry
                    ----------------------------------------------------
                    when RESCAN_READ =>
                        read_data <= ram(to_integer(scan_addr));
                        state     <= RESCAN_ACC;

                    ----------------------------------------------------
                    -- RESCAN_ACC: update best two bids/asks
                    ----------------------------------------------------
                    when RESCAN_ACC =>
                        -- Start with current accumulator values
                        n_rs_bid1_valid := rs_bid1_valid;
                        n_rs_bid1_price := rs_bid1_price;
                        n_rs_bid1_shares := rs_bid1_shares;
                        n_rs_bid2_valid := rs_bid2_valid;
                        n_rs_bid2_price := rs_bid2_price;
                        n_rs_bid2_shares := rs_bid2_shares;

                        n_rs_ask1_valid := rs_ask1_valid;
                        n_rs_ask1_price := rs_ask1_price;
                        n_rs_ask1_shares := rs_ask1_shares;
                        n_rs_ask2_valid := rs_ask2_valid;
                        n_rs_ask2_price := rs_ask2_price;
                        n_rs_ask2_shares := rs_ask2_shares;

                        if read_data(96) = '1' then
                            -- Bid side: highest price first
                            if read_data(63 downto 32) /= 0 then
                                if n_rs_bid1_valid = '0' then
                                    n_rs_bid1_valid := '1';
                                    n_rs_bid1_price := read_data(95 downto 64);
                                    n_rs_bid1_shares := read_data(63 downto 32);
                                elsif read_data(95 downto 64) > n_rs_bid1_price then
                                    n_rs_bid2_valid := n_rs_bid1_valid;
                                    n_rs_bid2_price := n_rs_bid1_price;
                                    n_rs_bid2_shares := n_rs_bid1_shares;
                                    n_rs_bid1_valid := '1';
                                    n_rs_bid1_price := read_data(95 downto 64);
                                    n_rs_bid1_shares := read_data(63 downto 32);
                                elsif n_rs_bid2_valid = '0' then
                                    n_rs_bid2_valid := '1';
                                    n_rs_bid2_price := read_data(95 downto 64);
                                    n_rs_bid2_shares := read_data(63 downto 32);
                                elsif read_data(95 downto 64) > n_rs_bid2_price then
                                    n_rs_bid2_valid := '1';
                                    n_rs_bid2_price := read_data(95 downto 64);
                                    n_rs_bid2_shares := read_data(63 downto 32);
                                end if;
                            end if;

                            -- Ask side: lowest price first
                            if read_data(31 downto 0) /= 0 then
                                if n_rs_ask1_valid = '0' then
                                    n_rs_ask1_valid := '1';
                                    n_rs_ask1_price := read_data(95 downto 64);
                                    n_rs_ask1_shares := read_data(31 downto 0);
                                elsif read_data(95 downto 64) < n_rs_ask1_price then
                                    n_rs_ask2_valid := n_rs_ask1_valid;
                                    n_rs_ask2_price := n_rs_ask1_price;
                                    n_rs_ask2_shares := n_rs_ask1_shares;
                                    n_rs_ask1_valid := '1';
                                    n_rs_ask1_price := read_data(95 downto 64);
                                    n_rs_ask1_shares := read_data(31 downto 0);
                                elsif n_rs_ask2_valid = '0' then
                                    n_rs_ask2_valid := '1';
                                    n_rs_ask2_price := read_data(95 downto 64);
                                    n_rs_ask2_shares := read_data(31 downto 0);
                                elsif read_data(95 downto 64) < n_rs_ask2_price then
                                    n_rs_ask2_valid := '1';
                                    n_rs_ask2_price := read_data(95 downto 64);
                                    n_rs_ask2_shares := read_data(31 downto 0);
                                end if;
                            end if;
                        end if;

                        -- Commit accumulator updates
                        rs_bid1_valid <= n_rs_bid1_valid;
                        rs_bid1_price <= n_rs_bid1_price;
                        rs_bid1_shares <= n_rs_bid1_shares;
                        rs_bid2_valid <= n_rs_bid2_valid;
                        rs_bid2_price <= n_rs_bid2_price;
                        rs_bid2_shares <= n_rs_bid2_shares;
                        rs_ask1_valid <= n_rs_ask1_valid;
                        rs_ask1_price <= n_rs_ask1_price;
                        rs_ask1_shares <= n_rs_ask1_shares;
                        rs_ask2_valid <= n_rs_ask2_valid;
                        rs_ask2_price <= n_rs_ask2_price;
                        rs_ask2_shares <= n_rs_ask2_shares;

                        -- Check if scan is complete
                        if scan_addr = 2047 then
                            -- Copy accumulators to the actual top?2 registers
                            bid1_valid_r <= n_rs_bid1_valid;
                            bid1_price_r <= n_rs_bid1_price;
                            bid1_shares_r <= n_rs_bid1_shares;
                            bid2_valid_r <= n_rs_bid2_valid;
                            bid2_price_r <= n_rs_bid2_price;
                            bid2_shares_r <= n_rs_bid2_shares;
                            ask1_valid_r <= n_rs_ask1_valid;
                            ask1_price_r <= n_rs_ask1_price;
                            ask1_shares_r <= n_rs_ask1_shares;
                            ask2_valid_r <= n_rs_ask2_valid;
                            ask2_price_r <= n_rs_ask2_price;
                            ask2_shares_r <= n_rs_ask2_shares;

                            -- If we deferred a REPLACE pass2, start it now
                            if pending_pass2 = '1' then
                                pending_pass2     <= '0';
                                pass_r            <= '1';
                                cur_order         <= new_order_r;
                                search_count      <= (others => '0');
                                first_empty_valid <= '0';
                                address           <= hash11(new_order_r(31 downto 0));
                                state             <= READ;
                            else
                                state <= IDLE;
                            end if;
                        else
                            scan_addr <= scan_addr + 1;
                            state     <= RESCAN_READ;
                        end if;

                end case;

            end if; -- reset
        end if; -- rising_edge
    end process;

end architecture;