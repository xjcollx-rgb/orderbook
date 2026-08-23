--------------------------------------------------------------------------------
-- tb_ref_table.vhd
--
-- Self-checking testbench for the ref_table hashed order-reference RAM.
--
-- APPROACH
-- --------
-- ref_table exposes no read-data port -- the only observable output is the
-- single-cycle "data_written" pulse. This testbench is therefore black-box:
-- it never peeks at internal signals (dut.ram, dut.state, ...), which keeps
-- it portable across simulators (GHDL / Questa / Vivado xsim) and immune to
-- the fact that ram_t is a type declared locally inside the DUT architecture
-- (and so can't be named from outside for a hierarchical/external-name probe
-- without simulator-specific tricks).
--
-- Correctness of the *contents* of the table is instead proven indirectly,
-- by construction of the transaction sequences:
--
--   * Timing: the number of clock cycles between issuing a transaction and
--     seeing data_written pulse tells us exactly how many probe/collision
--     steps the search took (2 clock cycles per READ/CHECK loop iteration).
--     We calibrate a "base_cycles" value from a known collision-free ADD,
--     then predict the exact cycle count for later collision scenarios and
--     assert against it. This proves linear probing is actually happening.
--
--   * Share/price correctness: after a partial CANCEL/EXECUTED, we can't
--     read back the remaining share count directly -- so instead we issue a
--     *second* CANCEL/EXECUTED for exactly the expected remainder. If the
--     DUT subtracted correctly, this second transaction removes the entry
--     (provable because a third attempt then reports "not found"). If the
--     DUT had a subtraction bug, the entry would still be present and the
--     third attempt would incorrectly report "found".
--
--   * REPLACE correctness: after replacing OLD ref -> NEW ref, we prove the
--     stored reference number actually changed by (a) confirming a search
--     for OLD ref now fails, and (b) confirming a search for NEW ref
--     succeeds at exactly the predicted number of probes (NEW ref's home
--     address generally differs from the slot's physical location, since
--     REPLACE does not rehash). We then confirm the replaced share count
--     was written correctly using the same cancel-exact-remainder trick.
--
-- "Not found" (search exhausts all 8192 slots) is a deterministic, bounded
-- event in this FSM: search_count counts 0..8191 inclusive before giving up.
-- So a "not found" result is confirmed by waiting a calibrated worst-case
-- window and observing no data_written pulse in it -- not by an open-ended
-- timeout, since the RTL guarantees termination by that point.
--
-- RUNTIME
-- -------
-- Several test cases deliberately provoke a full 8192-slot search-miss
-- (~16.4k clock cycles each). With RUN_FULL_TABLE_TEST enabled (fills all
-- 8192 entries to test the table-full/drop path) total runtime is on the
-- order of a few hundred thousand clock cycles -- trivial simulation time,
-- but set RUN_FULL_TABLE_TEST to false below for a faster iteration loop.
--
-- Run with e.g.:
--   ghdl -a --std=08 ref_table.vhd tb_ref_table.vhd
--   ghdl -e --std=08 tb_ref_table
--   ghdl -r --std=08 tb_ref_table
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ref_table is
end entity tb_ref_table;

architecture sim of tb_ref_table is

    ----------------------------------------------------------------
    -- Config
    ----------------------------------------------------------------
    constant CLK_PERIOD           : time    := 10 ns;
    constant RUN_FULL_TABLE_TEST  : boolean := true;  -- set false to skip the ~50k-cycle full-table test

    ----------------------------------------------------------------
    -- Frame type encodings (must match DUT)
    ----------------------------------------------------------------
    constant F_ADD      : unsigned(2 downto 0) := "000";
    constant F_CANCEL   : unsigned(2 downto 0) := "001";
    constant F_REPLACE  : unsigned(2 downto 0) := "010";
    constant F_EXECUTED : unsigned(2 downto 0) := "011";
    constant F_DELETE   : unsigned(2 downto 0) := "100";

    ----------------------------------------------------------------
    -- DUT signals
    ----------------------------------------------------------------
    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal tb_data       : unsigned(199 downto 0) := (others => '0');
    signal tb_empty      : std_logic := '1';
    signal tb_frame      : unsigned(2 downto 0)   := (others => '0');
    signal tb_dw         : std_logic;

    signal sim_done : boolean := false;

    ----------------------------------------------------------------
    -- Data-word builder
    --
    -- Mirrors the field layout the DUT expects on "data":
    --   d(199:136) = new reference number (REPLACE only)
    --   d(135:72)  = reference number used as the search key
    --                (also doubles as the new entry's own ref# for ADD)
    --   d(84:72)   = low 13 bits of the above -> initial hash address
    --   d(63:32)   = shares
    --   d(31:0)    = price
    ----------------------------------------------------------------
    function build_data(
        ref_num : unsigned(63 downto 0);
        shares  : unsigned(31 downto 0);
        price   : unsigned(31 downto 0);
        new_ref : unsigned(63 downto 0) := (others => '0')
    ) return unsigned is
        variable d : unsigned(199 downto 0) := (others => '0');
    begin
        d(199 downto 136) := new_ref;
        d(135 downto 72)  := ref_num;
        d(63 downto 32)   := shares;
        d(31 downto 0)    := price;
        return d;
    end function;

begin

    ----------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------
    dut: entity work.ref_table
        port map (
            clk          => clk,
            rst          => rst,
            data         => tb_data,
            empty_in     => tb_empty,
            frame_type   => tb_frame,
            data_written => tb_dw
        );

    ----------------------------------------------------------------
    -- Clock
    ----------------------------------------------------------------
    clk_gen: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    ----------------------------------------------------------------
    -- Stimulus + checking
    ----------------------------------------------------------------
    stim: process

        variable err_count : integer := 0;
        variable base_cycles    : integer := 0;  -- calibrated: cycles for a collision-free hit
        variable max_wait_cycles: integer := 0;  -- calibrated: safe upper bound to confirm "not found"

        ------------------------------------------------------------
        -- Drives one transaction and waits (bounded) for data_written.
        --   found     -> true if data_written pulsed within max_wait cycles
        --   cyc_count -> number of clock edges from the wait-loop start
        --                until data_written was observed (or max_wait if
        --                it never appeared)
        ------------------------------------------------------------
        procedure send_txn(
            constant din      : in  unsigned(199 downto 0);
            constant ftype    : in  unsigned(2 downto 0);
            constant max_wait : in  integer;
            variable found     : out boolean;
            variable cyc_count : out integer
        ) is
            variable c : integer := 0;
        begin
            wait until rising_edge(clk);
            tb_data  <= din;
            tb_frame <= ftype;
            tb_empty <= '0';

            wait until rising_edge(clk);
            tb_empty <= '1';

            found := false;
            c := 0;
            while c < max_wait loop
                wait until rising_edge(clk);
                c := c + 1;
                if tb_dw = '1' then
                    found := true;
                    exit;
                end if;
            end loop;

            cyc_count := c;
        end procedure;

        ------------------------------------------------------------
        -- Pass/fail bookkeeping
        ------------------------------------------------------------
        procedure check(constant cond : in boolean; constant msg : in string) is
        begin
            if cond then
                report "PASS: " & msg severity note;
            else
                report "FAIL: " & msg severity error;
                err_count := err_count + 1;
            end if;
        end procedure;

        -- local helpers
        variable found     : boolean;
        variable cyc        : integer;
        variable cyc2       : integer;
        variable found2      : boolean;

        variable ref1, ref2, ref3, ref4, ref5, ref6, ref7, new_ref7 : unsigned(63 downto 0);
        variable ref_fill, ref_overflow : unsigned(63 downto 0);

    begin
        --------------------------------------------------------------
        -- Reset
        --------------------------------------------------------------
        rst <= '1';
        tb_empty <= '1';
        wait for CLK_PERIOD * 5;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        check(tb_dw = '0', "TC1: data_written is idle low out of reset");

        --------------------------------------------------------------
        -- TC2: basic ADD then exact-shares CANCEL, and calibration
        --------------------------------------------------------------
        ref1 := to_unsigned(4200, 64);

        send_txn(build_data(ref1, to_unsigned(100, 32), to_unsigned(500, 32)),
                 F_ADD, 200000, found, cyc);
        check(found, "TC2: ADD ref1 succeeds");
        base_cycles     := cyc;                          -- calibrate collision-free latency
        max_wait_cycles := base_cycles + 2*8191 + 50;     -- calibrated worst-case full-table search
        report "Calibration: base_cycles=" & integer'image(base_cycles)
             & "  max_wait_cycles=" & integer'image(max_wait_cycles) severity note;

        send_txn(build_data(ref1, to_unsigned(100, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(found, "TC2: CANCEL ref1 (exact shares) finds and removes it");
        check(cyc = base_cycles, "TC2: CANCEL ref1 hit at expected (collision-free) latency");

        send_txn(build_data(ref1, to_unsigned(1, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(not found, "TC2: CANCEL ref1 again correctly reports not-found (was removed)");

        --------------------------------------------------------------
        -- TC3: partial CANCEL correctly decrements shares
        --------------------------------------------------------------
        ref3 := to_unsigned(777, 64);

        send_txn(build_data(ref3, to_unsigned(1000, 32), to_unsigned(250, 32)),
                 F_ADD, max_wait_cycles, found, cyc);
        check(found, "TC3: ADD ref3 (1000 shares) succeeds");

        send_txn(build_data(ref3, to_unsigned(400, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(found, "TC3: partial CANCEL ref3 (400 of 1000) finds the entry");

        send_txn(build_data(ref3, to_unsigned(600, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(found, "TC3: CANCEL ref3 for exact remainder (600) finds and fully removes it");

        send_txn(build_data(ref3, to_unsigned(1, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(not found, "TC3: CANCEL ref3 again reports not-found -> share subtraction was correct");

        --------------------------------------------------------------
        -- TC4: same, via EXECUTED
        --------------------------------------------------------------
        ref4 := to_unsigned(888, 64);

        send_txn(build_data(ref4, to_unsigned(50, 32), to_unsigned(10, 32)),
                 F_ADD, max_wait_cycles, found, cyc);
        check(found, "TC4: ADD ref4 (50 shares) succeeds");

        send_txn(build_data(ref4, to_unsigned(20, 32), to_unsigned(0, 32)),
                 F_EXECUTED, max_wait_cycles, found, cyc);
        check(found, "TC4: partial EXECUTED ref4 (20 of 50) finds the entry");

        send_txn(build_data(ref4, to_unsigned(30, 32), to_unsigned(0, 32)),
                 F_EXECUTED, max_wait_cycles, found, cyc);
        check(found, "TC4: EXECUTED ref4 for exact remainder (30) finds and fully removes it");

        send_txn(build_data(ref4, to_unsigned(1, 32), to_unsigned(0, 32)),
                 F_EXECUTED, max_wait_cycles, found, cyc);
        check(not found, "TC4: EXECUTED ref4 again reports not-found -> share subtraction was correct");

        --------------------------------------------------------------
        -- TC5: hash collision handling (linear probing)
        --   ref2 = ref1 + 8192 -> identical low-13 address bits as ref1
        --------------------------------------------------------------
        ref1 := to_unsigned(4200, 64);
        ref2 := ref1 + to_unsigned(8192, 64);

        send_txn(build_data(ref1, to_unsigned(100, 32), to_unsigned(500, 32)),
                 F_ADD, max_wait_cycles, found, cyc);
        check(found and cyc = base_cycles,
              "TC5: ADD ref1 lands directly in its (now-free) home slot");

        send_txn(build_data(ref2, to_unsigned(200, 32), to_unsigned(600, 32)),
                 F_ADD, max_wait_cycles, found, cyc);
        check(found and cyc = base_cycles + 2,
              "TC5: ADD ref2 (colliding address) probes one extra slot before landing");

        send_txn(build_data(ref1, to_unsigned(100, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(found and cyc = base_cycles,
              "TC5: CANCEL ref1 found immediately at its home address");

        send_txn(build_data(ref2, to_unsigned(200, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(found and cyc = base_cycles + 2,
              "TC5: CANCEL ref2 correctly skips the now-invalid home slot and finds ref2 next to it");

        send_txn(build_data(ref1, to_unsigned(1, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(not found, "TC5: ref1 confirmed removed");

        send_txn(build_data(ref2, to_unsigned(1, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(not found, "TC5: ref2 confirmed removed");

        --------------------------------------------------------------
        -- TC6: DELETE, and reuse of a freed slot
        --------------------------------------------------------------
        ref5 := to_unsigned(999, 64);

        send_txn(build_data(ref5, to_unsigned(10, 32), to_unsigned(20, 32)),
                 F_ADD, max_wait_cycles, found, cyc);
        check(found, "TC6: ADD ref5 succeeds");

        send_txn(build_data(ref5, to_unsigned(0, 32), to_unsigned(0, 32)),
                 F_DELETE, max_wait_cycles, found, cyc);
        check(found, "TC6: DELETE ref5 finds and removes it");

        send_txn(build_data(ref5, to_unsigned(0, 32), to_unsigned(0, 32)),
                 F_DELETE, max_wait_cycles, found, cyc);
        check(not found, "TC6: DELETE ref5 again correctly reports not-found");

        -- TC6b: a new ADD colliding on ref5's now-free home address should
        -- land directly there (proves the invalidated slot is reclaimed on
        -- the very first probe, not skipped/leaked).
        ref6 := ref5 + to_unsigned(8192 * 3, 64);
        send_txn(build_data(ref6, to_unsigned(5, 32), to_unsigned(5, 32)),
                 F_ADD, max_wait_cycles, found, cyc);
        check(found and cyc = base_cycles,
              "TC6b: ADD ref6 reclaims ref5's freed home slot directly");

        send_txn(build_data(ref6, to_unsigned(5, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(found and cyc = base_cycles, "TC6b: CANCEL ref6 cleans up");

        --------------------------------------------------------------
        -- TC7: REPLACE updates reference number and share/price fields
        --   in place (does not rehash to the new reference's own slot)
        --------------------------------------------------------------
        ref7     := to_unsigned(1500, 64);   -- home address 1500
        new_ref7 := to_unsigned(50000, 64);  -- home address 50000 mod 8192 = 848

        send_txn(build_data(ref7, to_unsigned(300, 32), to_unsigned(700, 32)),
                 F_ADD, max_wait_cycles, found, cyc);
        check(found and cyc = base_cycles, "TC7: ADD ref7 succeeds at its home slot");

        send_txn(build_data(ref7, to_unsigned(999, 32), to_unsigned(555, 32), new_ref7),
                 F_REPLACE, max_wait_cycles, found, cyc);
        check(found and cyc = base_cycles,
              "TC7: REPLACE finds the old entry directly via its own home address");

        -- Old reference number must no longer be resolvable: search starting
        -- at ref7's home address (1500) sweeps the whole table and misses,
        -- since the slot's stored ref field is now new_ref7.
        send_txn(build_data(ref7, to_unsigned(1, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc);
        check(not found, "TC7: searching by the OLD reference number after REPLACE finds nothing");

        -- New reference number must resolve, but only after probing forward
        -- from its own home address (848) all the way to where the entry
        -- physically lives (1500), i.e. 1500-848 = 652 extra probes.
        send_txn(build_data(new_ref7, to_unsigned(999, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found, cyc2);
        check(found and cyc2 = base_cycles + 2*652,
              "TC7: searching by the NEW reference number finds the replaced entry "
              & "at the predicted probe distance, and its share count (999) matches "
              & "what REPLACE wrote, fully removing it");

        send_txn(build_data(new_ref7, to_unsigned(1, 32), to_unsigned(0, 32)),
                 F_CANCEL, max_wait_cycles, found2, cyc);
        check(not found2, "TC7: NEW reference number confirmed removed after the exact-remainder CANCEL");

        --------------------------------------------------------------
        -- TC8 (optional, expensive): table-full behaviour
        --   Fill all 8192 slots with distinct, non-colliding addresses
        --   (ref = k has low-13 bits = k for k in 0..8191), then confirm
        --   one more ADD is correctly dropped (never asserts data_written).
        --------------------------------------------------------------
        if RUN_FULL_TABLE_TEST then

            for k in 0 to 8191 loop
                ref_fill := to_unsigned(k, 64);
                send_txn(build_data(ref_fill, to_unsigned(1, 32), to_unsigned(1, 32)),
                         F_ADD, max_wait_cycles, found, cyc);
                if not found or cyc /= base_cycles then
                    check(false, "TC8: fill ADD failed at index " & integer'image(k));
                    exit;  -- stop flooding the log if something is already wrong
                end if;
            end loop;
            check(true, "TC8: filled all 8192 slots with distinct, collision-free addresses");

            ref_overflow := to_unsigned(10000, 64);  -- low 13 bits = 1808, collides with an occupied slot
            send_txn(build_data(ref_overflow, to_unsigned(1, 32), to_unsigned(1, 32)),
                     F_ADD, max_wait_cycles, found, cyc);
            check(not found, "TC8: ADD to a completely full table is correctly dropped");

        else
            report "TC8 skipped (RUN_FULL_TABLE_TEST = false)" severity note;
        end if;

        --------------------------------------------------------------
        -- Summary
        --------------------------------------------------------------
        report "----------------------------------------------------" severity note;
        if err_count = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report integer'image(err_count) & " CHECK(S) FAILED" severity error;
        end if;
        report "----------------------------------------------------" severity note;

        sim_done <= true;
        wait;

    end process;

end architecture sim;