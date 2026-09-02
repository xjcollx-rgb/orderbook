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

        rescan_price_address    : out unsigned(109 downto 0);
        rescan_prices_in        : in  unsigned(255 downto 0);
        rescan_price_address_in : in  unsigned(87 downto 0);
        rescan_shares_count_in  : in  unsigned(4 downto 0);
        rescan_share_in         : in  unsigned(47 downto 0);

        rescan_share_valid      : in  std_logic;
        rescan_share_last       : in  std_logic;
        rescan_bucket_valid     : in  std_logic;
        rescan_last_bucket      : in  std_logic;
        rescan_bucket_processed : out std_logic;
        top_10_valid            : out std_logic

    );

end bbo;


architecture rtl of bbo is

    constant BUY  : unsigned(7 downto 0) := x"42";
    constant SELL : unsigned(7 downto 0) := x"53";

    type price_array is array (0 to 9) of unsigned(31 downto 0);
    type share_array is array (0 to 9) of unsigned(47 downto 0);

    ----------------------------------------------------------------
    -- Top-level FSM.
    --
    -- RESCAN_PRICES_WAIT : waiting for price_table to present a
    --                       valid bucket (rescan_bucket_valid = '1').
    -- RESCAN_PRICES_FOLD : folding the 8 candidates from the current
    --                       bucket into the scratch top-10, ONE
    --                       candidate per clock (this is the fix for
    --                       the 494-level combinational path -- each
    --                       cycle now only does a single ~10-wide
    --                       compare/shift insertion instead of 8
    --                       chained insertions).
    ----------------------------------------------------------------
    type state_t is (NORMAL, RESCAN_PRICES_WAIT, RESCAN_PRICES_FOLD, RESCAN_SHARES);
    signal state : state_t := NORMAL;

    signal buy_prices : price_array;
    signal buy_shares : share_array;

    signal sell_prices : price_array;
    signal sell_shares : share_array;

    signal buy_price_count  : unsigned(3 downto 0);
    signal sell_price_count : unsigned(3 downto 0);

    signal buy_reconstruction  : std_logic;
    signal sell_reconstruction : std_logic;

    signal buy_lowest_delete   : unsigned(31 downto 0);
    signal sell_highest_delete : unsigned(31 downto 0);

    signal buy_table_filled  : std_logic;
    signal sell_table_filled : std_logic;

    signal buy_rescan_reg  : std_logic;
    signal sell_rescan_reg : std_logic;

    signal ordered_rescan_prices  : unsigned(255 downto 0);
    signal ordered_rescan_address : unsigned(87 downto 0);

    constant TOPN : integer := 10;
    constant BKTN : integer := 8;

    type rescan_price_array is array (0 to TOPN-1) of unsigned(31 downto 0);
    type rescan_addr_array  is array (0 to TOPN-1) of unsigned(10 downto 0);

    signal rescan_prices_work : rescan_price_array := (others => (others => '0'));
    signal rescan_addrs_work  : rescan_addr_array  := (others => (others => '0'));
    signal rescan_count_work  : unsigned(3 downto 0) := (others => '0');

    signal rescan_is_buy    : std_logic := '0';
    signal rescan_share_idx : unsigned(3 downto 0) := (others => '0');

    ----------------------------------------------------------------
    -- Latched copy of the current bucket's contents. Latched once
    -- when rescan_bucket_valid = '1', then held stable across the
    -- 8 fold cycles so the source data doesn't need to stay driven
    -- by price_table for the whole fold.
    ----------------------------------------------------------------
    signal bucket_prices_latched : unsigned(255 downto 0) := (others => '0');
    signal bucket_addrs_latched  : unsigned(87 downto 0)  := (others => '0');
    signal bucket_last_latched   : std_logic := '0';

    -- Which of the 8 candidates in the latched bucket is being
    -- folded in this cycle.
    signal bucket_slot_idx : unsigned(2 downto 0) := (others => '0');

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

    buy_rescan  <= buy_rescan_reg;
    sell_rescan <= sell_rescan_reg;


    --------------------------------------------------------------------
    -- Main process
    --------------------------------------------------------------------

    process(clk)

        variable buy_count_int  : integer;
        variable sell_count_int : integer;

        variable found : boolean;

        -- Single-candidate insertion scratch (used one candidate at a
        -- time now, so these no longer need to carry state across 8
        -- sequential folds within one cycle).
        variable v_prices   : rescan_price_array;
        variable v_addrs    : rescan_addr_array;
        variable v_count    : integer range 0 to TOPN;
        variable cand_price : unsigned(31 downto 0);
        variable cand_addr  : unsigned(10 downto 0);

        -- Parallel insertion-position computation. is_better(i) is
        -- independent for every i (no dependency on other indices), so
        -- all TOPN comparisons can be evaluated simultaneously instead
        -- of threading a serial "inserted" flag through them. position
        -- is simply the count of existing entries that outrank the
        -- candidate, which is exactly its insertion index (the array
        -- is always kept sorted, so the "better" entries always form a
        -- contiguous prefix).
        variable is_better  : std_logic_vector(0 to TOPN - 1);
        variable position   : integer range 0 to TOPN;

    begin

        if rising_edge(clk) then

            if rst = '1' then

                buy_price_count  <= (others => '0');
                sell_price_count <= (others => '0');

                buy_reconstruction  <= '0';
                sell_reconstruction <= '0';

                buy_table_filled  <= '0';
                sell_table_filled <= '0';

                buy_rescan_reg  <= '0';
                sell_rescan_reg <= '0';

                rescan_count_work <= (others => '0');
                rescan_share_idx  <= (others => '0');

                bucket_slot_idx      <= (others => '0');
                bucket_prices_latched <= (others => '0');
                bucket_addrs_latched  <= (others => '0');
                bucket_last_latched   <= '0';

                rescan_bucket_processed <= '0';
                top_10_valid            <= '0';

                buy_lowest_delete   <= (others => '0');
                sell_highest_delete <= (others => '0');

                state <= NORMAL;

                for i in 0 to 9 loop
                    buy_prices(i) <= (others => '0');
                    buy_shares(i) <= (others => '0');
                    sell_prices(i) <= (others => '0');
                    sell_shares(i) <= (others => '0');
                    rescan_prices_work(i) <= (others => '0');
                    rescan_addrs_work(i)  <= (others => '0');
                end loop;

            else

                -- Default: these are one-cycle pulses, deassert unless
                -- explicitly re-asserted below.
                rescan_bucket_processed <= '0';

                case state is


                when NORMAL =>

                    if buy_price_count = 1 and buy_table_filled = '1' and buy_reconstruction = '1' and buy_rescan_reg = '0' then

                        buy_rescan_reg    <= '1';
                        rescan_is_buy     <= '1';
                        rescan_count_work <= (others => '0');

                        for i in 0 to TOPN-1 loop
                            rescan_prices_work(i) <= (others => '0');
                            rescan_addrs_work(i)  <= (others => '0');
                        end loop;

                        state <= RESCAN_PRICES_WAIT;

                    end if;

                    if sell_price_count = 1 and sell_table_filled = '1' and sell_reconstruction = '1' and sell_rescan_reg = '0' then

                        sell_rescan_reg   <= '1';
                        rescan_is_buy     <= '0';
                        rescan_count_work <= (others => '0');

                        for i in 0 to TOPN-1 loop
                            rescan_prices_work(i) <= (others => '0');
                            rescan_addrs_work(i)  <= (others => '0');
                        end loop;

                        state <= RESCAN_PRICES_WAIT;

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
                                                    buy_lowest_delete  <= buy_prices(buy_count_int - 1);
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

                                if buy_count_int >= 9 then
                                    buy_table_filled   <= '1';
                                    buy_reconstruction <= '0';
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

                                if sell_count_int >= 9 then
                                    sell_table_filled   <= '1';
                                    sell_reconstruction <= '0';
                                end if;

                            end if;

                        end if;

                    end if;


                ----------------------------------------------------------------
                -- RESCAN_PRICES_WAIT
                --
                -- Sit here until price_table presents a valid bucket. When it
                -- does, latch the whole 256-bit / 88-bit bucket contents into
                -- registers, reset the per-bucket slot counter to 0, and move
                -- into the fold state. Latching once here (rather than reading
                -- rescan_prices_in/rescan_price_address_in directly across all
                -- 8 fold cycles) means price_table is free to change those
                -- buses on the next cycle without corrupting an in-progress
                -- fold, and it keeps each fold cycle's logic depth independent
                -- of anything upstream.
                ----------------------------------------------------------------

                when RESCAN_PRICES_WAIT =>

                    if rescan_bucket_valid = '1' then

                        bucket_prices_latched <= rescan_prices_in;
                        bucket_addrs_latched  <= rescan_price_address_in;
                        bucket_last_latched   <= rescan_last_bucket;

                        bucket_slot_idx <= (others => '0');

                        state <= RESCAN_PRICES_FOLD;

                    end if;


                ----------------------------------------------------------------
                -- RESCAN_PRICES_FOLD
                --
                -- Folds exactly ONE candidate (bucket_slot_idx) from the
                -- latched bucket into the scratch top-10 per clock cycle.
                -- This replaces the old single-cycle loop over all 8
                -- candidates, which synthesized to ~494 logic levels because
                -- 8 insertion passes were chained combinationally with no
                -- register between them. Each cycle here does only one
                -- ~10-wide compare/shift insertion, so the combinational
                -- depth per cycle is roughly 1/8th of the old design.
                ----------------------------------------------------------------

                when RESCAN_PRICES_FOLD =>

                    v_prices := rescan_prices_work;
                    v_addrs  := rescan_addrs_work;
                    v_count  := to_integer(rescan_count_work);

                    cand_price := bucket_prices_latched(31 + to_integer(bucket_slot_idx)*32 downto to_integer(bucket_slot_idx)*32);
                    cand_addr  := bucket_addrs_latched(10 + to_integer(bucket_slot_idx)*11 downto to_integer(bucket_slot_idx)*11);

                    if cand_price /= to_unsigned(0, 32) then

                        ------------------------------------------------------------
                        -- Stage 1: TOPN independent comparisons, fully parallel.
                        -- is_better(i) = "existing slot i is valid AND currently
                        -- outranks the candidate". Only depends on v_prices(i),
                        -- v_count and cand_price -- never on any other is_better(k).
                        ------------------------------------------------------------

                        for i in 0 to TOPN - 1 loop

                            if (i < v_count) and (
                                 (rescan_is_buy = '1' and v_prices(i) > cand_price) or
                                 (rescan_is_buy = '0' and v_prices(i) < cand_price)) then
                                is_better(i) := '1';
                            else
                                is_better(i) := '0';
                            end if;

                        end loop;

                        ------------------------------------------------------------
                        -- Stage 2: population count. Since the array is always
                        -- kept sorted, the "better" entries always form a
                        -- contiguous prefix (0..k-1), so this count IS the
                        -- candidate's insertion index. Only small integer
                        -- increments are chained here -- no 32-bit comparisons
                        -- in this stage -- so this is cheap even if synthesis
                        -- doesn't balance it into a tree.
                        ------------------------------------------------------------

                        position := 0;

                        for i in 0 to TOPN - 1 loop
                            if is_better(i) = '1' then
                                position := position + 1;
                            end if;
                        end loop;

                        ------------------------------------------------------------
                        -- Stage 3: place the candidate and shift lower entries
                        -- down. Descending order over j is required: it
                        -- guarantees v_prices(j-1)/v_addrs(j-1) is still holding
                        -- its ORIGINAL (pre-shift) value at the moment it's read,
                        -- since higher indices are written first. The condition
                        -- "j > position" is a single small-integer comparison,
                        -- independent per j -- not a chain -- so this is a
                        -- barrel-shift-style structure, not a priority chain.
                        ------------------------------------------------------------

                        if position < TOPN then

                            for j in TOPN - 1 downto 0 loop
                                if j > position then
                                    v_prices(j) := v_prices(j - 1);
                                    v_addrs(j)  := v_addrs(j - 1);
                                end if;
                            end loop;

                            v_prices(position) := cand_price;
                            v_addrs(position)  := cand_addr;

                            if v_count < TOPN then
                                v_count := v_count + 1;
                            end if;

                        end if;
                        -- else: candidate ranks below all TOPN existing entries
                        -- and the array is already full -- correctly discarded.

                        rescan_prices_work <= v_prices;
                        rescan_addrs_work  <= v_addrs;
                        rescan_count_work  <= to_unsigned(v_count, 4);

                    end if;

                    ------------------------------------------------------------
                    -- Advance to the next candidate in this bucket, or finish
                    -- the bucket and either move to the next one or, if this
                    -- was the last bucket, proceed to RESCAN_SHARES.
                    ------------------------------------------------------------

                    if bucket_slot_idx = to_unsigned(BKTN - 1, 3) then

                        if bucket_last_latched = '1' then

                            -- Note: this reads v_addrs (this cycle's freshly
                            -- computed values, including the very last
                            -- candidate just folded above) rather than the
                            -- rescan_addrs_work signal, which would still hold
                            -- the PREVIOUS cycle's value here.
                            for i in 0 to TOPN - 1 loop
                                rescan_price_address(10 + i*11 downto i*11) <= v_addrs(i);
                            end loop;

                            top_10_valid     <= '1';
                            rescan_share_idx <= (others => '0');
                            state            <= RESCAN_SHARES;

                        else

                            rescan_bucket_processed <= '1';
                            state                   <= RESCAN_PRICES_WAIT;

                        end if;

                    else

                        bucket_slot_idx <= bucket_slot_idx + 1;

                    end if;


                ----------------------------------------------------------------
                -- RESCAN_SHARES
                ----------------------------------------------------------------

                when RESCAN_SHARES =>

                    top_10_valid <= '0';

                    if rescan_share_valid = '1' then

                        if rescan_is_buy = '1' then
                            buy_prices(to_integer(rescan_share_idx)) <= rescan_prices_work(to_integer(rescan_share_idx));
                            buy_shares(to_integer(rescan_share_idx)) <= rescan_share_in;
                        else
                            sell_prices(to_integer(rescan_share_idx)) <= rescan_prices_work(to_integer(rescan_share_idx));
                            sell_shares(to_integer(rescan_share_idx)) <= rescan_share_in;
                        end if;

                        if rescan_share_last = '1' then

                            if rescan_is_buy = '1' then
                                buy_price_count    <= rescan_count_work;
                                buy_reconstruction <= '0';
                                buy_rescan_reg     <= '0';
                                if rescan_count_work = TOPN then
                                    buy_table_filled <= '1';
                                end if;
                            else
                                sell_price_count    <= rescan_count_work;
                                sell_reconstruction <= '0';
                                sell_rescan_reg     <= '0';
                                if rescan_count_work = TOPN then
                                    sell_table_filled <= '1';
                                end if;
                            end if;

                            state <= NORMAL;

                        else

                            rescan_share_idx <= rescan_share_idx + 1;

                        end if;

                    end if;

                end case;

            end if;

        end if;

    end process;

end rtl;