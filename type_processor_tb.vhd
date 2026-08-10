library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity type_processor_tb is
end type_processor_tb;

architecture test of type_processor_tb is

------------------------------------------------------------------------
-- TYPE PROCESSOR
------------------------------------------------------------------------

component type_processor is
    port (
        data           : in  unsigned(63 downto 0);
        clk            : in  std_logic;
        rst            : in  std_logic;
        frame          : out unsigned(199 downto 0);
        byte_count     : in  unsigned(6 downto 0);
        success        : out std_logic;
        frame_type_out : out unsigned(2 downto 0);
        offset_out     : out unsigned(2 downto 0)
    );
end component;


------------------------------------------------------------------------
-- BYTE COUNTER
------------------------------------------------------------------------

component byte_counter is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        success    : in  std_logic;
        offset     : in  unsigned(2 downto 0);
        frame_type_in : in unsigned(2 downto 0);
        byte_count : out unsigned(6 downto 0)
    );
end component;


------------------------------------------------------------------------
-- SIGNALS
------------------------------------------------------------------------

signal clk : std_logic := '0';
signal rst : std_logic := '1';

signal data       : unsigned(63 downto 0) := (others => '0');
signal byte_count : unsigned(6 downto 0);

signal frame          : unsigned(199 downto 0);
signal success        : std_logic;
signal frame_type_out : unsigned(2 downto 0);
signal offset_out     : unsigned(2 downto 0);


constant CLK_PERIOD : time := 10 ns;


begin

------------------------------------------------------------------------
-- TYPE PROCESSOR
------------------------------------------------------------------------

type_processor_inst : type_processor
    port map (
        data           => data,
        clk            => clk,
        rst            => rst,
        frame          => frame,
        byte_count     => byte_count,
        success        => success,
        frame_type_out => frame_type_out,
        offset_out     => offset_out
    );


------------------------------------------------------------------------
-- BYTE COUNTER
------------------------------------------------------------------------

byte_counter_inst : byte_counter
    port map (
        clk        => clk,
        rst        => rst,
        success    => success,
        offset     => offset_out,
        frame_type_in => frame_type_out,
        byte_count => byte_count
    );


------------------------------------------------------------------------
-- CLOCK
------------------------------------------------------------------------

clk_process : process
begin

    clk <= '0';
    wait for CLK_PERIOD / 2;

    clk <= '1';
    wait for CLK_PERIOD / 2;

end process;


------------------------------------------------------------------------
-- TEST STREAM
--
-- The stream is constructed as:
--
--   ADD       36 bytes
--   CANCEL    23 bytes
--   REPLACE   35 bytes
--   EXECUTED  31 bytes
--   DELETE    19 bytes
--
-- Total = 144 bytes = 18 x 64-bit words
--
-- IMPORTANT:
--
-- Your type_processor treats data(7 downto 0) as the FIRST byte
-- in the incoming 64-bit word.
--
-- Therefore:
--
-- byte 0 = data(7 downto 0)
-- byte 1 = data(15 downto 8)
-- ...
-- byte 7 = data(63 downto 56)
--
------------------------------------------------------------------------

stimulus : process

    type byte_array is
        array (0 to 143) of unsigned(7 downto 0);

    variable stream : byte_array := (others => x"00");

    variable word : unsigned(63 downto 0);


    --------------------------------------------------------------------
    -- Put a 16-bit big-endian integer into the stream
    --------------------------------------------------------------------

    procedure put_u16(
        variable s : inout byte_array;
        constant p : in integer;
        constant v : in integer
    ) is
    begin

        s(p)     := to_unsigned((v / 256) mod 256, 8);
        s(p + 1) := to_unsigned(v mod 256, 8);

    end procedure;


    --------------------------------------------------------------------
    -- Put a 32-bit big-endian integer into the stream
    --------------------------------------------------------------------

    procedure put_u32(
        variable s : inout byte_array;
        constant p : in integer;
        constant v : in integer
    ) is
    begin

        s(p)     := to_unsigned((v / 16777216) mod 256, 8);
        s(p + 1) := to_unsigned((v / 65536) mod 256, 8);
        s(p + 2) := to_unsigned((v / 256) mod 256, 8);
        s(p + 3) := to_unsigned(v mod 256, 8);

    end procedure;


    --------------------------------------------------------------------
    -- Put a 64-bit value into the stream
    --
    -- VHDL integer is not large enough for the ITCH 64-bit fields,
    -- so these are supplied as eight individual bytes.
    --------------------------------------------------------------------

    procedure put_u64(
        variable s : inout byte_array;
        constant p : in integer;
        constant b0 : in unsigned(7 downto 0);
        constant b1 : in unsigned(7 downto 0);
        constant b2 : in unsigned(7 downto 0);
        constant b3 : in unsigned(7 downto 0);
        constant b4 : in unsigned(7 downto 0);
        constant b5 : in unsigned(7 downto 0);
        constant b6 : in unsigned(7 downto 0);
        constant b7 : in unsigned(7 downto 0)
    ) is
    begin

        s(p)     := b0;
        s(p + 1) := b1;
        s(p + 2) := b2;
        s(p + 3) := b3;
        s(p + 4) := b4;
        s(p + 5) := b5;
        s(p + 6) := b6;
        s(p + 7) := b7;

    end procedure;


    --------------------------------------------------------------------
    -- Send one 64-bit word
    --------------------------------------------------------------------

    procedure send_word(
        constant w : in unsigned(63 downto 0)
    ) is
    begin

        data <= w;

        wait until rising_edge(clk);

    end procedure;


    --------------------------------------------------------------------
    -- Build one 64-bit word from eight consecutive stream bytes
    --------------------------------------------------------------------

    procedure send_stream_word(
        constant start_byte : in integer
    ) is
        variable w : unsigned(63 downto 0);
    begin

        w(7 downto 0)   := stream(start_byte);
        w(15 downto 8)  := stream(start_byte + 1);
        w(23 downto 16) := stream(start_byte + 2);
        w(31 downto 24) := stream(start_byte + 3);
        w(39 downto 32) := stream(start_byte + 4);
        w(47 downto 40) := stream(start_byte + 5);
        w(55 downto 48) := stream(start_byte + 6);
        w(63 downto 56) := stream(start_byte + 7);

        send_word(w);

    end procedure;


begin

    --------------------------------------------------------------------
    -- RESET
    --------------------------------------------------------------------

    rst <= '1';

    wait for 3 * CLK_PERIOD;

    rst <= '0';

    wait for CLK_PERIOD;


    --------------------------------------------------------------------
    -- CONSTRUCT ITCH STREAM
    --------------------------------------------------------------------

    --------------------------------------------------------------------
    -- MESSAGE 1
    --
    -- ADD ORDER
    --
    -- 36 bytes
    --
    -- Offset  Length
    -- 0       1       Message Type       A
    -- 1       2       Stock Locate       1
    -- 3       2       Tracking Number    1
    -- 5       6       Timestamp          1000
    -- 11      8       Order Reference    123456
    -- 19      1       Buy/Sell            B
    -- 20      4       Shares              1000
    -- 24      8       Stock               AAPL
    -- 32      4       Price               150.0000
    --------------------------------------------------------------------

    stream(0) := x"41"; -- A

    put_u16(stream, 1, 1);
    put_u16(stream, 3, 1);

    -- timestamp = 1000
    stream(5)  := x"00";
    stream(6)  := x"00";
    stream(7)  := x"00";
    stream(8)  := x"00";
    stream(9)  := x"00";
    stream(10) := x"03";
    stream(10) := x"E8";

    -- order reference = 123456
    stream(11) := x"00";
    stream(12) := x"00";
    stream(13) := x"00";
    stream(14) := x"00";
    stream(15) := x"00";
    stream(16) := x"01";
    stream(17) := x"E2";
    stream(18) := x"40";

    stream(19) := x"42"; -- B

    put_u32(stream, 20, 1000);

    -- AAPL + spaces
    stream(24) := x"41";
    stream(25) := x"41";
    stream(26) := x"50";
    stream(27) := x"4C";
    stream(28) := x"20";
    stream(29) := x"20";
    stream(30) := x"20";
    stream(31) := x"20";

    -- 150.0000 = 1,500,000
    put_u32(stream, 32, 1500000);


    --------------------------------------------------------------------
    -- MESSAGE 2
    --
    -- ORDER CANCEL
    --
    -- 23 bytes
    --------------------------------------------------------------------

    stream(36) := x"58"; -- X

    put_u16(stream, 37, 1);
    put_u16(stream, 39, 2);

    -- timestamp
    stream(41) := x"00";
    stream(42) := x"00";
    stream(43) := x"00";
    stream(44) := x"00";
    stream(45) := x"00";
    stream(46) := x"03";
    stream(47) := x"E9";

    -- order reference
    stream(47) := x"00";
    stream(48) := x"00";
    stream(49) := x"00";
    stream(50) := x"00";
    stream(51) := x"00";
    stream(52) := x"01";
    stream(53) := x"E2";
    stream(54) := x"40";

    -- cancelled shares
    put_u32(stream, 55, 500);


    --------------------------------------------------------------------
    -- MESSAGE 3
    --
    -- ORDER REPLACE
    --
    -- 35 bytes
    --------------------------------------------------------------------

    stream(59) := x"55"; -- U

    put_u16(stream, 60, 1);
    put_u16(stream, 62, 3);

    -- timestamp
    stream(64) := x"00";
    stream(65) := x"00";
    stream(66) := x"00";
    stream(67) := x"00";
    stream(68) := x"00";
    stream(69) := x"03";
    stream(70) := x"EA";

    -- original order reference
    stream(71) := x"00";
    stream(72) := x"00";
    stream(73) := x"00";
    stream(74) := x"00";
    stream(75) := x"00";
    stream(76) := x"01";
    stream(77) := x"E2";
    stream(78) := x"40";

    -- new order reference
    stream(79) := x"00";
    stream(80) := x"00";
    stream(81) := x"00";
    stream(82) := x"00";
    stream(83) := x"00";
    stream(84) := x"05";
    stream(85) := x"39";
    stream(86) := x"7F";

    -- shares
    put_u32(stream, 87, 2000);

    -- price
    put_u32(stream, 91, 1510000);


    --------------------------------------------------------------------
    -- MESSAGE 4
    --
    -- ORDER EXECUTED
    --
    -- 31 bytes
    --------------------------------------------------------------------

    stream(94) := x"45"; -- E

    put_u16(stream, 95, 1);
    put_u16(stream, 97, 4);

    -- timestamp
    stream(99)  := x"00";
    stream(100) := x"00";
    stream(101) := x"00";
    stream(102) := x"00";
    stream(103) := x"00";
    stream(104) := x"03";
    stream(105) := x"EB";

    -- order reference
    stream(106) := x"00";
    stream(107) := x"00";
    stream(108) := x"00";
    stream(109) := x"00";
    stream(110) := x"00";
    stream(111) := x"05";
    stream(112) := x"39";
    stream(113) := x"7F";

    -- executed shares
    put_u32(stream, 114, 1000);

    -- match number
    stream(118) := x"00";
    stream(119) := x"00";
    stream(120) := x"00";
    stream(121) := x"00";
    stream(122) := x"00";
    stream(123) := x"00";
    stream(124) := x"00";
    stream(125) := x"01";


    --------------------------------------------------------------------
    -- MESSAGE 5
    --
    -- ORDER DELETE
    --
    -- 19 bytes
    --------------------------------------------------------------------

    stream(125) := x"44"; -- D

    put_u16(stream, 126, 1);
    put_u16(stream, 128, 5);

    -- timestamp
    stream(130) := x"00";
    stream(131) := x"00";
    stream(132) := x"00";
    stream(133) := x"00";
    stream(134) := x"00";
    stream(135) := x"03";
    stream(136) := x"EC";

    -- order reference
    stream(137) := x"00";
    stream(138) := x"00";
    stream(139) := x"00";
    stream(140) := x"00";
    stream(141) := x"00";
    stream(142) := x"05";
    stream(143) := x"39";
    stream(144 - 1) := x"7F";


    --------------------------------------------------------------------
    -- SEND THE STREAM
    --
    -- 144 bytes = 18 words
    --------------------------------------------------------------------

    report "======================================";
    report "Starting ITCH stream test";
    report "======================================";


    for i in 0 to 17 loop

        send_stream_word(i * 8);

    end loop;


    --------------------------------------------------------------------
    -- ALLOW FINAL SUCCESS TO PROPAGATE
    --------------------------------------------------------------------

    wait for 3 * CLK_PERIOD;


    report "======================================";
    report "ITCH stream test complete";
    report "======================================";


    wait;

end process;


------------------------------------------------------------------------
-- MONITOR
--
-- This prints every successful message detection.
------------------------------------------------------------------------

monitor : process(clk)

    variable message_number : integer := 0;

begin

    if rising_edge(clk) then

        if success = '1' then

            message_number := message_number + 1;

            report "--------------------------------------";

            case frame_type_out is

                when "000" =>
                    report "ADD detected";

                when "001" =>
                    report "CANCEL detected";

                when "010" =>
                    report "REPLACE detected";

                when "011" =>
                    report "EXECUTED detected";

                when "100" =>
                    report "DELETE detected";

                when others =>
                    report "UNKNOWN message";

            end case;

            report "Message number = "
                & integer'image(message_number);

            report "byte_count = "
                & integer'image(to_integer(byte_count));

            report "offset = "
                & integer'image(to_integer(offset_out));

            report "--------------------------------------";

        end if;

    end if;

end process;

end test;
