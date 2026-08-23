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

        -- Top-of-book, two price levels each side, from price_table
        bid1_price  : out unsigned(31 downto 0);
        bid1_shares : out unsigned(31 downto 0);
        bid2_price  : out unsigned(31 downto 0);
        bid2_shares : out unsigned(31 downto 0);

        ask1_price  : out unsigned(31 downto 0);
        ask1_shares : out unsigned(31 downto 0);
        ask2_price  : out unsigned(31 downto 0);
        ask2_shares : out unsigned(31 downto 0)

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

    component price_table is
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            price_table  : in  unsigned(145 downto 0);
            fifo_empty : in  std_logic;
            bid1_price   : out unsigned(31 downto 0) := (others => '0');
            bid1_shares  : out unsigned(31 downto 0) := (others => '0');
            bid2_price   : out unsigned(31 downto 0) := (others => '0');
            bid2_shares  : out unsigned(31 downto 0) := (others => '0');
            ask1_price   : out unsigned(31 downto 0) := (others => '0');
            ask1_shares  : out unsigned(31 downto 0) := (others => '0');
            ask2_price   : out unsigned(31 downto 0) := (others => '0');
            ask2_shares  : out unsigned(31 downto 0) := (others => '0');
            data_written : out std_logic
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

    ------------------------------------------------------------------
    -- Stage 4: price-level aggregation / top-of-book
    ------------------------------------------------------------------
    u_price_table : price_table
        port map (
            clk          => clk,
            rst          => rst,
            price_table  => price_fifo_dout,
            fifo_empty => price_fifo_empty,
            bid1_price   => bid1_price,
            bid1_shares  => bid1_shares,
            bid2_price   => bid2_price,
            bid2_shares  => bid2_shares,
            ask1_price   => ask1_price,
            ask1_shares  => ask1_shares,
            ask2_price   => ask2_price,
            ask2_shares  => ask2_shares,
            data_written => price_fifo_read
        );

    u_price_fifo : price_fifo 
        port map (
            clk => clk,
            rst => rst,
            din => price_fifo_din,
            dout => price_fifo_dout,
            empty_out => price_fifo_empty,
            full_out => price_fifo_full,
            success_in => ref_fifo_success,
            read_in => price_fifo_read

        );

end architecture structural;