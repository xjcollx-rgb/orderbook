library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity orderbook_top is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- Continuous ITCH byte stream, 8 bytes (one non-overlapping chunk)
        -- presented per clock cycle -- matches the continuous-stream model
        -- byte_counter/type_processor are built around.
        data_in     : in  unsigned(63 downto 0);

        -- Top-of-book, ONE price level each side now (bbo only tracks
        -- best bid / best ask, not a second level -- bid2/ask2 no longer
        -- exist anywhere downstream, so those ports are removed).
        --
        -- NOTE: widened from 32 to 48 bits on the shares fields. bbo's
        -- best_buy_shares/best_sell_shares are unsigned(47 downto 0)
        -- (matching the 48-bit aggregate share fields carried through
        -- ref_table/price_table's RAM), so the old 32-bit ports here
        -- would silently truncate real share counts. Price stays 32 bits
        -- since that hasn't changed.
        bid1_price  : out unsigned(31 downto 0);
        bid1_shares : out unsigned(47 downto 0);

        ask1_price  : out unsigned(31 downto 0);
        ask1_shares : out unsigned(47 downto 0)

    );
end entity orderbook_top;

architecture structural of orderbook_top is

    component byte_counter is
        port(
            clk              : in  std_logic;
            rst              : in  std_logic;
            success          : in  std_logic;
            previous_offset  : in  unsigned(2 downto 0);
            frame_size_in    : in  unsigned(6 downto 0);
            byte_count       : out unsigned(6 downto 0);
            state_in         : in  std_logic := '1';
            previous_success : in  std_logic
        );
    end component;

    component type_processor is
        port (
            data                  : in  unsigned(63 downto 0);
            clk                   : in  std_logic;
            rst                   : in  std_logic;
            frame                 : out unsigned(202 downto 0);
            byte_count            : in  unsigned(6 downto 0);
            success               : out std_logic;
            frame_size_out        : out unsigned(6 downto 0);
            previous_offset_out   : out unsigned(2 downto 0);
            state_out             : out std_logic := '1';
            previous_success_out  : out std_logic;
            current_frame_stored  : out std_logic
        );
    end component;

    component fifo is
        generic(
            DATA_WIDTH : integer := 203;
            DEPTH      : integer := 2048
        );
        port (
            clk        : in  std_logic;
            rst        : in  std_logic;
            din        : in  unsigned(DATA_WIDTH - 1 downto 0);
            dout       : out unsigned(DATA_WIDTH - 1 downto 0) := (others => '0');
            full_out   : out std_logic := '0';
            empty_out  : out std_logic := '1';
            success_in : in  std_logic;
            read_in    : in  std_logic
        );
    end component;

    component price_fifo is
        generic(
        DATA_WIDTH : integer := 146;
        DEPTH      : integer := 512
        );
        port(

            clk : in std_logic;
            rst : in std_logic;
            din : in unsigned(DATA_WIDTH - 1 downto 0);
            dout : out unsigned(DATA_WIDTH - 1 downto 0);
            full_out : out std_logic;
            empty_out : out std_logic;
            success_in : in std_logic;
            read_in : in std_logic
        );

    end component;

    component ref_table is
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            data         : in  unsigned(199 downto 0);
            empty_in     : in  std_logic;
            frame_type   : in  unsigned(2 downto 0);
            data_written : out std_logic := '0';
            price_table  : out unsigned(145 downto 0)
        );
    end component;

    ------------------------------------------------------------------
    -- price_table: reworked to a single-order-write interface (one
    -- pending op's price/shares/side/delete presented to bbo per write)
    -- plus the two-phase rescan handshake with bbo, instead of directly
    -- exposing bid1/bid2/ask1/ask2 itself.
    --
    -- Port widths: the incoming 146-bit price_fifo word is split here
    -- into a 144-bit data field and a 2-bit frame_type field, since
    -- that's how this entity's internal packing (ADD/EXECCAN/REPLACE/
    -- DELETE encoded in 2 bits, matching the op-type constants used
    -- inside price_table's own architecture) expects it.
    ------------------------------------------------------------------
    component price_table is
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;

            price_table  : in  unsigned(143 downto 0);
            frame_type_in : in unsigned(1 downto 0);
            fifo_empty   : in  std_logic;

            data_written : out std_logic;

            bbo_price  : out unsigned(31 downto 0);
            bbo_shares : out unsigned(47 downto 0);
            bbo_side   : out unsigned(7 downto 0);
            bbo_delete : out std_logic;

            buy_rescan_in  : in std_logic;
            sell_rescan_in : in std_logic;

            rescan_out : out std_logic;

            rescan_bucket_prices : out unsigned(255 downto 0);
            rescan_bucket_addrs  : out unsigned(87 downto 0);
            rescan_bucket_valid  : out std_logic;
            rescan_last_bucket   : out std_logic;
            rescan_buckets_processed_out : in std_logic;

            top10_addr_in  : in unsigned(109 downto 0);
            top10_valid_in : in std_logic;

            rescan_share_out   : out unsigned(47 downto 0);
            rescan_share_valid : out std_logic;
            rescan_share_last  : out std_logic
        );
    end component;

    ------------------------------------------------------------------
    -- bbo: holds the live top-10 cache each side, derives best_buy/
    -- best_sell from it, and drives the rescan handshake back to
    -- price_table when the cache needs full reconstruction.
    ------------------------------------------------------------------
    component bbo is
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
    end component;

    -- type_processor <-> byte_counter feedback pair
    signal tp_frame                : unsigned(202 downto 0);
    signal tp_success              : std_logic;
    signal tp_frame_size           : unsigned(6 downto 0);
    signal tp_previous_offset      : unsigned(2 downto 0);
    signal tp_state                : std_logic;
    signal tp_previous_success     : std_logic;
    signal tp_current_frame_stored : std_logic;
    signal bc_byte_count           : unsigned(6 downto 0);

    -- fifo <-> pop-handshake FSM <-> ref_table
    signal fifo_din_s   : unsigned(202 downto 0);
    signal fifo_dout_s  : unsigned(202 downto 0);
    signal fifo_full_s  : std_logic;
    signal fifo_empty_s : std_logic;
    signal fifo_read_s  : std_logic := '0';

    signal have_valid_head : std_logic := '0';
    signal read_pending     : std_logic := '0';
    signal fifo_empty  : std_logic := '1';

    -- price_fifo <-> price_table
    signal ref_fifo_success : std_logic;
    signal price_fifo_read : std_logic;
    signal price_fifo_din : unsigned(145 downto 0);
    signal price_fifo_dout : unsigned(145 downto 0);
    signal price_fifo_full : std_logic;
    signal price_fifo_empty : std_logic;

    ------------------------------------------------------------------
    -- price_fifo_dout split: top 2 bits are the op-type code (ADD /
    -- EXECCAN / REPLACE / DELETE), bottom 144 bits are the order data.
    -- Matches price_table's internal field layout exactly (144 + 2 =
    -- 146 = price_fifo's DATA_WIDTH).
    ------------------------------------------------------------------
    signal price_table_data_s      : unsigned(143 downto 0);
    signal price_table_frame_type_s : unsigned(1 downto 0);

    -- price_table <-> bbo: single pending write
    signal bbo_price_s        : unsigned(31 downto 0);
    signal bbo_shares_s       : unsigned(47 downto 0);
    signal bbo_side_s         : unsigned(7 downto 0);
    signal bbo_delete_s       : std_logic;
    signal bbo_data_written_s : std_logic;

    -- price_table <-> bbo: rescan handshake, phase 1 (bucket stream)
    signal rescan_bucket_prices_s   : unsigned(255 downto 0);
    signal rescan_bucket_addrs_s    : unsigned(87 downto 0);
    signal rescan_bucket_valid_s    : std_logic;
    signal rescan_last_bucket_s     : std_logic;
    signal rescan_bucket_processed_s : std_logic;

    -- price_table <-> bbo: rescan handshake, phase 2 (share stream)
    signal top10_addr_s        : unsigned(109 downto 0);
    signal top10_valid_s       : std_logic;
    signal rescan_share_s      : unsigned(47 downto 0);
    signal rescan_share_valid_s : std_logic;
    signal rescan_share_last_s  : std_logic;

    -- bbo -> price_table: full-rescan requests
    signal buy_rescan_s  : std_logic;
    signal sell_rescan_s : std_logic;

    -- price_table: rescan-in-progress flag, no external consumer
    -- currently -- left unconnected via "open" in the port map below.

begin

    ------------------------------------------------------------------
    -- Stage 1: type_processor / byte_counter feedback pair
    ------------------------------------------------------------------
    u_type_processor : type_processor
        port map (
            data                 => data_in,
            clk                  => clk,
            rst                  => rst,
            frame                => tp_frame,
            byte_count           => bc_byte_count,
            success              => tp_success,
            frame_size_out       => tp_frame_size,
            previous_offset_out  => tp_previous_offset,
            state_out            => tp_state,
            previous_success_out => tp_previous_success,
            current_frame_stored => tp_current_frame_stored
        );

    u_byte_counter : byte_counter
        port map (
            clk              => clk,
            rst              => rst,
            success          => tp_success,
            previous_offset  => tp_previous_offset,
            frame_size_in    => tp_frame_size,
            byte_count       => bc_byte_count,
            state_in         => tp_state,
            previous_success => tp_previous_success
        );

    ------------------------------------------------------------------
    -- Stage 2: elastic buffer between the byte-serial front end and
    -- the multi-cycle ref_table hash lookup
    ------------------------------------------------------------------
    fifo_din_s <= tp_frame;

    u_fifo : fifo
        generic map (
            DATA_WIDTH => 203,
            DEPTH      => 2048
        )
        port map (
            clk        => clk,
            rst        => rst,
            din        => fifo_din_s,
            dout       => fifo_dout_s,
            full_out   => fifo_full_s,
            empty_out  => fifo_empty_s,
            success_in => tp_current_frame_stored,
            read_in    => fifo_read_s
        );

    ------------------------------------------------------------------
    -- Stage 3: reference-number hash table
    ------------------------------------------------------------------
    u_ref_table : ref_table
        port map (
            clk          => clk,
            rst          => rst,
            data         => fifo_dout_s(199 downto 0),
            empty_in     => fifo_empty_s,
            frame_type   => fifo_dout_s(202 downto 200),
            data_written => ref_fifo_success,
            price_table  => price_fifo_din
        );

    u_price_fifo : price_fifo
        port map (
            clk        => clk,
            rst        => rst,
            din        => price_fifo_din,
            dout       => price_fifo_dout,
            empty_out  => price_fifo_empty,
            full_out   => price_fifo_full,
            success_in => ref_fifo_success,
            read_in    => price_fifo_read
        );

    ------------------------------------------------------------------
    -- price_fifo_dout split into price_table's two input fields.
    ------------------------------------------------------------------
    price_table_frame_type_s <= price_fifo_dout(145 downto 144);
    price_table_data_s       <= price_fifo_dout(143 downto 0);

    ------------------------------------------------------------------
    -- Stage 4: price-level aggregation (hash table over price levels)
    ------------------------------------------------------------------
    u_price_table : price_table
        port map (
            clk          => clk,
            rst          => rst,

            price_table   => price_table_data_s,
            frame_type_in => price_table_frame_type_s,
            fifo_empty    => price_fifo_empty,

            data_written => bbo_data_written_s,

            bbo_price  => bbo_price_s,
            bbo_shares => bbo_shares_s,
            bbo_side   => bbo_side_s,
            bbo_delete => bbo_delete_s,

            buy_rescan_in  => buy_rescan_s,
            sell_rescan_in => sell_rescan_s,

            rescan_out => open,

            rescan_bucket_prices => rescan_bucket_prices_s,
            rescan_bucket_addrs  => rescan_bucket_addrs_s,
            rescan_bucket_valid  => rescan_bucket_valid_s,
            rescan_last_bucket   => rescan_last_bucket_s,
            rescan_buckets_processed_out => rescan_bucket_processed_s,

            top10_addr_in  => top10_addr_s,
            top10_valid_in => top10_valid_s,

            rescan_share_out   => rescan_share_s,
            rescan_share_valid => rescan_share_valid_s,
            rescan_share_last  => rescan_share_last_s
        );

    price_fifo_read <= bbo_data_written_s;

    ------------------------------------------------------------------
    -- Stage 5: top-of-book cache + rescan orchestration
    ------------------------------------------------------------------
    u_bbo : bbo
        port map (
            clk => clk,
            rst => rst,

            price_in  => bbo_price_s,
            shares_in => bbo_shares_s,
            side_in   => bbo_side_s,
            delete_in => bbo_delete_s,

            data_written_in => bbo_data_written_s,

            best_buy_price  => bid1_price,
            best_buy_shares => bid1_shares,

            best_sell_price  => ask1_price,
            best_sell_shares => ask1_shares,

            buy_rescan  => buy_rescan_s,
            sell_rescan => sell_rescan_s,

            rescan_price_address    => top10_addr_s,
            rescan_prices_in        => rescan_bucket_prices_s,
            rescan_price_address_in => rescan_bucket_addrs_s,

            -- Dead port carried over from an earlier interface revision:
            -- bbo tracks its own share-stream index internally
            -- (rescan_share_idx) rather than relying on an externally
            -- supplied count, and price_table has no matching output for
            -- this signal. Tied off rather than left dangling.
            rescan_shares_count_in => (others => '0'),

            rescan_share_in => rescan_share_s,

            rescan_share_valid => rescan_share_valid_s,
            rescan_share_last  => rescan_share_last_s,
            rescan_bucket_valid => rescan_bucket_valid_s,
            rescan_last_bucket  => rescan_last_bucket_s,

            rescan_bucket_processed => rescan_bucket_processed_s,
            top_10_valid            => top10_valid_s
        );

end architecture structural;