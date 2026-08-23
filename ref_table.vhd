library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ref_table is
port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    data         : in  unsigned(199 downto 0);
    empty_in     : in  std_logic;
    frame_type   : in  unsigned(2 downto 0);
    data_written : out std_logic := '0';
    price_table  : out unsigned(145 downto 0)
);
end ref_table;

architecture rtl of ref_table is

    ----------------------------------------------------------------
    -- Reference table
    --
    -- Word layout (144 bits):
    --   bit  136       : valid flag (folded in so there is only
    --                    ONE memory array -> one BRAM to infer)
    --   bits 135..72   : reference number
    --   bits 71..0     : price / shares fields
    --
    -- IMPORTANT: every write to "ram" below writes the FULL 144-bit
    -- word in a single assignment (ram(addr) <= <144-bit value>),
    -- even in branches that only logically change one field. Mixing
    -- full-word writes with partial-range writes (ram(addr)(136)<=...,
    -- ram(addr)(135 downto 0)<=..., etc.) across different branches of
    -- the same process is what causes Vivado to lose track of a clean
    -- write-enable granularity and fall back to a synthetic per-bit
    -- write enable ([Synth 8-6841], "byte width (1) is not a multiple
    -- of 8/9") -- which in turn balloons BRAM usage far past what an
    -- 8192 x 144 table should need. Keeping every write path uniform
    -- (read-modify-write into ram_v, then one full assignment) avoids
    -- that entirely.
    ----------------------------------------------------------------
    type ram_t is array (0 to 8191) of unsigned(143 downto 0);

    signal ram : ram_t := (others => (others => '0'));

    -- Tell Vivado to implement this memory using Block RAM
    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";


    ----------------------------------------------------------------
    -- State machine
    ----------------------------------------------------------------
    type state_t is (IDLE, READ, CHECK, WRITE);

    signal state : state_t := IDLE;


    ----------------------------------------------------------------
    -- Frame types
    ----------------------------------------------------------------
    constant ADD      : unsigned(2 downto 0) := "000";
    constant CANCEL   : unsigned(2 downto 0) := "001";
    constant REPLACE  : unsigned(2 downto 0) := "010";
    constant EXECUTED : unsigned(2 downto 0) := "011";
    constant DELETE   : unsigned(2 downto 0) := "100";


    ----------------------------------------------------------------
    -- Address/search
    ----------------------------------------------------------------
    signal address : unsigned(12 downto 0) := (others => '0');

    signal search_count : unsigned(13 downto 0) := (others => '0');


    ----------------------------------------------------------------
    -- Registered BRAM output
    ----------------------------------------------------------------
    signal read_data : unsigned(143 downto 0) := (others => '0');


    ----------------------------------------------------------------
    -- Latched frame_type
    --
    -- frame_type is an input and may change on the cycle the
    -- caller advances to the next message. Latch it in IDLE so
    -- READ/CHECK/WRITE all act on the frame type that started
    -- this transaction, not whatever is on the port right now.
    ----------------------------------------------------------------
    signal frame_type_r : unsigned(2 downto 0) := (others => '0');

begin


    process(clk)

        variable ram_v : unsigned(143 downto 0);
        variable replace_data : unsigned(71 downto 0);

    begin

        if rising_edge(clk) then

            --------------------------------------------------------
            -- RESET
            --------------------------------------------------------
            if rst = '1' then

                state        <= IDLE;
                address      <= (others => '0');
                search_count <= (others => '0');
                read_data    <= (others => '0');
                frame_type_r <= (others => '0');

                -- NOTE: ram is intentionally NOT cleared here.
                -- Clearing an 8192-entry BRAM in a single cycle is
                -- not synthesizable as real reset logic; it would
                -- force Vivado off the BRAM primitive. Power-up
                -- content is all-zero, so every valid bit (136)
                -- starts at '0' anyway.

                data_written <= '0';


            else

                case state is


                    ------------------------------------------------
                    -- IDLE
                    ------------------------------------------------
                    when IDLE =>

                        data_written <= '0';

                        if empty_in = '0' then

                            ------------------------------------------------
                            -- Calculate initial hash address.
                            --
                            -- 8192 entries = 13 address bits.
                            ------------------------------------------------
                            address <= data(84 downto 72);

                            search_count <= (others => '0');

                            frame_type_r <= frame_type;


                            case frame_type is

                                when ADD |
                                     CANCEL |
                                     EXECUTED |
                                     REPLACE |
                                     DELETE =>

                                    -- Every frame type, including ADD,
                                    -- goes through READ first so the
                                    -- valid bit is only ever tested
                                    -- off a registered BRAM read.
                                    state <= READ;

                                when others =>
                                    state <= IDLE;

                            end case;

                        end if;


                    ------------------------------------------------
                    -- READ
                    --
                    -- Synchronous BRAM read.
                    --
                    -- The RAM contents are loaded into read_data
                    -- on this clock edge.
                    ------------------------------------------------
                    when READ =>

                        read_data <= ram(to_integer(address));

                        state <= CHECK;


                    ------------------------------------------------
                    -- CHECK
                    --
                    -- read_data now contains the RAM entry read
                    -- during the previous READ cycle.
                    ------------------------------------------------
                    when CHECK =>

                        case frame_type_r is

                            ----------------------------------------
                            -- ADD: looking for an EMPTY slot
                            ----------------------------------------
                            when ADD =>

                                if read_data(136) = '0' then

                                    -- Empty slot found.
                                    search_count <= (others => '0');
                                    state <= WRITE;

                                elsif search_count >= 8191 then

                                    -- Table full - drop.
                                    search_count <= (others => '0');
                                    state <= IDLE;

                                else

                                    if address = 8191 then
                                        address <= (others => '0');
                                    else
                                        address <= address + 1;
                                    end if;

                                    search_count <= search_count + 1;
                                    state <= READ;

                                end if;


                            ----------------------------------------
                            -- CANCEL / EXECUTED / REPLACE / DELETE:
                            -- looking for a MATCHING valid entry
                            ----------------------------------------
                            when others =>

                                if read_data(135 downto 72) =
                                   data(135 downto 72)
                                   and read_data(136) = '1' then

                                    search_count <= (others => '0');
                                    state <= WRITE;

                                elsif search_count >= 8191 then

                                    search_count <= (others => '0');
                                    state <= IDLE;

                                else

                                    if address = 8191 then
                                        address <= (others => '0');
                                    else
                                        address <= address + 1;
                                    end if;

                                    search_count <= search_count + 1;
                                    state <= READ;

                                end if;

                        end case;


                    ------------------------------------------------
                    -- WRITE
                    --
                    -- Every branch below writes the ENTIRE 144-bit
                    -- word to ram in one assignment (via ram_v), even
                    -- ADD and DELETE which only conceptually touch
                    -- part of the entry. See the note on ram_t above.
                    ------------------------------------------------
                    when WRITE =>


                        case frame_type_r is


                            ------------------------------------------------
                            -- ADD
                            --
                            -- read_data(136) was confirmed '0' in CHECK,
                            -- so the previous contents of this slot (if
                            -- any, e.g. left over from a prior DELETE) are
                            -- fully superseded -- build the whole new word
                            -- from scratch rather than patching read_data.
                            ------------------------------------------------
                            when ADD =>

                                ram_v := (others => '0');
                                ram_v(136)          := '1';
                                ram_v(135 downto 0) := data(135 downto 0);

                                ram(to_integer(address)) <= ram_v;

                                data_written <= '1';

                                state <= IDLE;

                                price_table(71 downto 0) <= ram_v(71 downto 0);
                                price_table(145 downto 144) <= "00";




                            ------------------------------------------------
                            -- CANCEL / EXECUTED
                            ------------------------------------------------
                            when CANCEL | EXECUTED =>

                                ------------------------------------------------
                                -- Copy RAM entry to a variable.
                                -- This allows us to modify it immediately.
                                ------------------------------------------------
                                ram_v := read_data;


                                ------------------------------------------------
                                -- If cancelling/executing all remaining
                                -- shares, remove the order.
                                ------------------------------------------------
                                if ram_v(63 downto 32) <=
                                   data(63 downto 32) then

                                    ram_v(136) := '0';


                                else

                                    ------------------------------------------------
                                    -- Subtract shares.
                                    ------------------------------------------------
                                    ram_v(63 downto 32) :=
                                        ram_v(63 downto 32)
                                        - data(63 downto 32);

                                end if;

                                ram(to_integer(address)) <= ram_v;

                                price_table(71 downto 0) <= data(71 downto 0);
                                price_table(145 downto 144) <= "01";

                                data_written <= '1';

                                state <= IDLE;


                            ------------------------------------------------
                            -- REPLACE
                            ------------------------------------------------
                            when REPLACE =>

                                ------------------------------------------------
                                -- Start with the existing order.
                                -- (bit 136 / valid carries over unchanged)
                                ------------------------------------------------
                                ram_v := read_data;

                                replace_data := ram_v(71 downto 0);


                                ------------------------------------------------
                                -- New reference number.
                                ------------------------------------------------
                                ram_v(135 downto 72) :=
                                    data(199 downto 136);


                                ------------------------------------------------
                                -- New price/shares information. and side
                                ------------------------------------------------
                                ram_v(71 downto 0) :=
                                    data(71 downto 0);


                                ------------------------------------------------
                                -- Write modified order back.
                                ------------------------------------------------
                                ram(to_integer(address)) <= ram_v;

                                price_table(71 downto 0) <= replace_data;
                                price_table(143 downto 72) <= ram_v(71 downto 0);
                                price_table(145 downto 144) <= "10";

                                data_written <= '1';

                                state <= IDLE;


                            ------------------------------------------------
                            -- DELETE
                            --
                            -- Only the valid bit conceptually changes, but
                            -- we still read-modify-write the FULL word
                            -- (rather than ram(addr)(136)<='0' alone) to
                            -- keep this write path structurally identical
                            -- to CANCEL/EXECUTED/REPLACE above.
                            ------------------------------------------------
                            when DELETE =>

                                ram_v := read_data;
                                ram_v(136) := '0';

                                ram(to_integer(address)) <= ram_v;

                                price_table(72 downto 0) <= ram_v(72 downto 0);
                                price_table(145 downto 144) <= "11"; 

                                data_written <= '1';

                                state <= IDLE;


                            ------------------------------------------------
                            -- Anything else
                            ------------------------------------------------
                            when others =>

                                state <= IDLE;

                        end case;

                end case;

            end if;

        end if;

    end process;

end architecture;