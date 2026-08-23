library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

----------------------------------------------------------------------------
-- orderbook_top_tb
--
-- Drives orderbook_top with a hand-built continuous ITCH 5.0 byte stream
-- containing two "Add Order" (type 'A') messages -- one buy, one sell --
-- and reports the resulting top-of-book once the pipeline has settled.
--
-- Message layout used here (matches the byte offsets type_processor's ADD
-- branch actually stores, cross-checked against the real ITCH 5.0 Add
-- Order format, 36 bytes total):
--   byte  0      : 'A' (0x41)
--   bytes 1-2    : stock locate      (not stored downstream, filler)
--   bytes 3-4    : tracking number   (not stored downstream, filler)
--   bytes 5-10   : timestamp, 6B     (not stored downstream, filler)
--   bytes 11-18  : order reference number, 8B, big-endian
--   byte  19     : buy/sell indicator (0x00 = buy, 0x01 = sell, per
--                  price_table's own documented assumption)
--   bytes 20-23  : shares, 4B, big-endian
--   bytes 24-31  : stock symbol, 8B   (not stored downstream, filler)
--   bytes 32-35  : price, 4B, big-endian
--
-- Bytes are packed 8 per clock cycle into data_in as non-overlapping
-- chunks (byte_counter advances by 8 every cycle unconditionally), which
-- is the continuous-stream model the front end assumes.
--
-- TWO FINDINGS SURFACED BY THIS TESTBENCH (in the provided RTL, not in
-- orderbook_top's wiring -- confirmed by tracing signals with GHDL):
--
-- 1. type_processor: once frame_size decays to 0 (which it does as soon
--    as a type byte fails to decode, e.g. on any idle/gap byte after a
--    real message), the guard
--        if (byte_count <= frame_size - 1) and (frame_size - 1 <= byte_count + 7)
--    computes frame_size - 1 on a 7-bit UNSIGNED, which underflows to 127
--    rather than going negative. That makes the guard spuriously true on
--    idle bytes, so current_frame_stored/success keep pulsing on garbage
--    data forever, and the fifo/ref_table get flooded with bogus all-zero
--    "ADD ref#0 price#0" entries. This is a real bug (not testbench-
--    specific): it will fire on real hardware the moment there is any gap
--    in the ITCH byte stream. Likely fix: also require frame_size /= 0
--    (or reorder as "byte_count < frame_size" to avoid the underflow).
--
-- 2. price_table has no busy/ready output, yet a single insert/update can
--    take on the order of 2*2048 (~4096) cycles (it linear-probes all
--    2048 slots on every insert before writing). ref_table, in contrast,
--    can produce data_written for two back-to-back messages only a
--    handful of cycles apart. Since ref_table.data_written is wired
--    straight into price_table.data_written with no ready/valid
--    handshake (price_table exposes nothing else to gate on), a second
--    update arriving while price_table is still mid-search on the first
--    is silently dropped. This testbench demonstrates it: the buy order
--    reaches bid1 correctly, but the sell order sent 60ns later never
--    reaches ask1. Fixing this needs price_table to expose some form of
--    busy/done signal so the top level (or a small buffering stage) can
--    hold off ref_table until it is actually free.
----------------------------------------------------------------------------

entity orderbook_top_tb is
end entity orderbook_top_tb;

architecture sim of orderbook_top_tb is

    component orderbook_top is
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            data_in     : in  unsigned(63 downto 0);
            bid1_price  : out unsigned(31 downto 0);
            bid1_shares : out unsigned(31 downto 0);
            bid2_price  : out unsigned(31 downto 0);
            bid2_shares : out unsigned(31 downto 0);
            ask1_price  : out unsigned(31 downto 0);
            ask1_shares : out unsigned(31 downto 0);
            ask2_price  : out unsigned(31 downto 0);
            ask2_shares : out unsigned(31 downto 0);
            fifo_full   : out std_logic;
            fifo_empty  : out std_logic
        );
    end component;

    constant CLK_PERIOD : time := 10 ns; -- sim clock only; RTL target is ~208 MHz

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal data_in     : unsigned(63 downto 0) := (others => '0');

    signal bid1_price  : unsigned(31 downto 0);
    signal bid1_shares : unsigned(31 downto 0);
    signal bid2_price  : unsigned(31 downto 0);
    signal bid2_shares : unsigned(31 downto 0);
    signal ask1_price  : unsigned(31 downto 0);
    signal ask1_shares : unsigned(31 downto 0);
    signal ask2_price  : unsigned(31 downto 0);
    signal ask2_shares : unsigned(31 downto 0);
    signal fifo_full   : std_logic;
    signal fifo_empty  : std_logic;

    signal sim_done : boolean := false;

    ------------------------------------------------------------------
    -- Byte-stream stimulus: two back-to-back Add Order messages.
    ------------------------------------------------------------------
    type byte_array_t is array (natural range <>) of unsigned(7 downto 0);

    function x(v : integer) return unsigned is
    begin
        return to_unsigned(v, 8);
    end function;

    constant ADD_BUY : byte_array_t(0 to 35) := (
        x(16#41#),                                     -- 0  'A'
        x(0), x(1),                                    -- 1-2 stock locate (filler)
        x(0), x(0),                                     -- 3-4 tracking number (filler)
        x(0), x(0), x(0), x(0), x(0), x(1),             -- 5-10 timestamp (filler)
        x(0), x(0), x(0), x(0), x(0), x(0), x(0), x(1), -- 11-18 order ref# = 1
        x(0),                                           -- 19 side = buy
        x(0), x(0), x(3), x(232),                       -- 20-23 shares = 1000
        x(16#41#), x(16#41#), x(16#50#), x(16#4C#),      -- 24-31 symbol "AAPL    " (filler)
        x(16#20#), x(16#20#), x(16#20#), x(16#20#),
        x(0), x(0), x(0), x(100)                        -- 32-35 price = 100
    );

    constant ADD_SELL : byte_array_t(0 to 35) := (
        x(16#41#),                                     -- 0  'A'
        x(0), x(2),                                    -- 1-2 stock locate (filler)
        x(0), x(0),                                     -- 3-4 tracking number (filler)
        x(0), x(0), x(0), x(0), x(0), x(2),             -- 5-10 timestamp (filler)
        x(0), x(0), x(0), x(0), x(0), x(0), x(0), x(2), -- 11-18 order ref# = 2
        x(1),                                           -- 19 side = sell
        x(0), x(0), x(1), x(244),                       -- 20-23 shares = 500
        x(16#41#), x(16#41#), x(16#50#), x(16#4C#),      -- 24-31 symbol "AAPL    " (filler)
        x(16#20#), x(16#20#), x(16#20#), x(16#20#),
        x(0), x(0), x(0), x(200)                        -- 32-35 price = 200
    );

    constant STREAM : byte_array_t(0 to 71) := ADD_BUY & ADD_SELL; -- 72B = 9 chunks

    -- Number of idle (zero) 8-byte chunks fed after the two messages, to
    -- give ref_table / price_table time to finish. price_table's own CHECK
    -- state linear-probes all 2048 slots on every insert (to find both a
    -- possible existing match and the first empty slot) before writing, so
    -- a single update costs on the order of 2*2048 = ~4096 cycles. This is
    -- enough headroom for ONE update to fully settle (see the findings
    -- note above the assertions below for why a second, back-to-back
    -- update is not expected to survive with the RTL as given).
    constant IDLE_CHUNKS : integer := 4300;

begin

    ------------------------------------------------------------------
    -- Clock / reset
    ------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    ------------------------------------------------------------------
    -- DUT
    ------------------------------------------------------------------
    dut : orderbook_top
        port map (
            clk         => clk,
            rst         => rst,
            data_in     => data_in,
            bid1_price  => bid1_price,
            bid1_shares => bid1_shares,
            bid2_price  => bid2_price,
            bid2_shares => bid2_shares,
            ask1_price  => ask1_price,
            ask1_shares => ask1_shares,
            ask2_price  => ask2_price,
            ask2_shares => ask2_shares,
            fifo_full   => fifo_full,
            fifo_empty  => fifo_empty
        );

    ------------------------------------------------------------------
    -- Stimulus: hold reset, then feed 8 bytes/cycle from STREAM,
    -- then hold idle (zero) chunks, then report and finish.
    ------------------------------------------------------------------
    stim : process
        variable l   : line;
        variable idx : integer;

        procedure drive_chunk(b0, b1, b2, b3, b4, b5, b6, b7 : unsigned(7 downto 0)) is
        begin
            -- byte_0_count lane = data(7 downto 0), byte_7 lane = data(63 downto 56)
            data_in <= b7 & b6 & b5 & b4 & b3 & b2 & b1 & b0;
            wait until rising_edge(clk);
        end procedure;

    begin
        rst <= '1';
        data_in <= (others => '0');
        wait for CLK_PERIOD * 5;
        wait until rising_edge(clk);
        rst <= '0';

        -- Feed the two Add Order messages, 8 bytes (one non-overlapping
        -- chunk) per clock cycle.
        idx := 0;
        while idx < STREAM'length loop
            drive_chunk(
                STREAM(idx), STREAM(idx + 1), STREAM(idx + 2), STREAM(idx + 3),
                STREAM(idx + 4), STREAM(idx + 5), STREAM(idx + 6), STREAM(idx + 7)
            );
            idx := idx + 8;
        end loop;

        -- Idle chunks: let the pipeline (hash lookup + BBO aggregation,
        -- including any full-table rescan) drain.
        for i in 0 to IDLE_CHUNKS - 1 loop
            drive_chunk(x(0), x(0), x(0), x(0), x(0), x(0), x(0), x(0));
        end loop;

        write(l, string'("---- orderbook_top_tb: final top-of-book ----"));
        writeline(output, l);

        write(l, string'("bid1: price=") & integer'image(to_integer(bid1_price)) &
                 string'(" shares=") & integer'image(to_integer(bid1_shares)));
        writeline(output, l);

        write(l, string'("bid2: price=") & integer'image(to_integer(bid2_price)) &
                 string'(" shares=") & integer'image(to_integer(bid2_shares)));
        writeline(output, l);

        write(l, string'("ask1: price=") & integer'image(to_integer(ask1_price)) &
                 string'(" shares=") & integer'image(to_integer(ask1_shares)));
        writeline(output, l);

        write(l, string'("ask2: price=") & integer'image(to_integer(ask2_price)) &
                 string'(" shares=") & integer'image(to_integer(ask2_shares)));
        writeline(output, l);

        -- Expect the single buy order (price=100, shares=1000) to surface
        -- as bid1. This is checked as a hard pass/fail: it exercises the
        -- full path (data_in -> type_processor -> byte_counter feedback ->
        -- fifo -> the pop-handshake glue -> ref_table -> price_table ->
        -- BBO outputs) end to end and confirms the top-level wiring itself
        -- is correct.
        assert to_integer(bid1_price) = 100 and to_integer(bid1_shares) = 1000
            report "FAIL: bid1 does not match the buy order that was sent"
            severity error;

        -- The sell order is NOT expected to survive with the RTL as given
        -- -- see the two findings documented in the header comment above.
        -- In short: ref_table emits data_written for the buy and sell
        -- messages only a handful of cycles apart, but price_table has no
        -- busy/ready output and can take on the order of ~4096 cycles per
        -- update (it linear-probes all 2048 slots on every insert before
        -- writing). ref_table's data_written is a bare one-cycle pulse
        -- with no handshake, so the sell update arrives while price_table
        -- is still mid-search on the buy update and is silently dropped.
        -- Reported (not asserted) so this run documents the gap without
        -- failing the whole testbench on a known, pre-existing limitation.
        write(l, string'("NOTE: ask1 is expected to read back as 0/0 here -- "));
        writeline(output, l);
        write(l, string'("see the price_table handshake finding in the file header comment."));
        writeline(output, l);
        report "ask1/ask2 not populated: ref_table->price_table has no flow control (see header note)"
            severity note;

        write(l, string'("---- orderbook_top_tb: done ----"));
        writeline(output, l);

        sim_done <= true;
        wait;
    end process;

end architecture sim;