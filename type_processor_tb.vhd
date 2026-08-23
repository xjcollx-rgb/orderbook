library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity type_processor_tb is
end entity;

architecture simple of type_processor_tb is

    component type_processor
        port (
            data           : in  unsigned(63 downto 0);
            clk            : in  std_logic;
            rst            : in  std_logic;
            frame          : out unsigned(202 downto 0);
            byte_count     : in  unsigned(6 downto 0);
            success        : out std_logic;
            frame_size_out : out unsigned(6 downto 0);
            previous_offset_out     : out unsigned(2 downto 0);
            state_out      : out std_logic;
            previous_success_out : out std_logic;
            current_frame_stored : out std_logic
        );
    end component;

    component byte_counter
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            success       : in  std_logic;
            previous_offset        : in  unsigned(2 downto 0);
            frame_size_in : in  unsigned(6 downto 0);
            byte_count    : out unsigned(6 downto 0);
            state_in      : in std_logic;
            previous_success : in std_logic
        );
    end component;

    component fifo 
        port (
        clk : in std_logic;
        rst : in std_logic;

        din  : in  unsigned(202 downto 0);
        dout : out unsigned(202 downto 0) := (others => '0');

        full_out  : out std_logic := '0';
        empty_out : out std_logic := '1';

        success_in : in std_logic;
        read_in   : in std_logic

        
        );
    
    end component;

    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal data_in        : unsigned(63 downto 0) := (others => '0');
    signal byte_count     : unsigned(6 downto 0);
    signal success        : std_logic;
    signal frame_size_out : unsigned(6 downto 0);
    signal previous_offset_out     : unsigned(2 downto 0);
    signal state_out      : std_logic;
    signal frame       : unsigned(202 downto 0);
    signal previous_success : std_logic;
    signal current_frame_stored : std_logic;
    

    constant T : time := 10 ns;

    -- Byte layout (cumulative, 0-indexed):
    --   ADD      @ byte   0, size 36  (type byte x41, ends byte 35)
    --   CANCEL   @ byte  36, size 23  (type byte x58, ends byte 58)
    --   REPLACE  @ byte  59, size 35  (type byte x55, ends byte 93)
    --   EXECUTED @ byte  94, size 31  (type byte x45, ends byte 124)
    --   DELETE   @ byte 125, size 19  (type byte x44, ends byte 143)
    --
    -- Word boundaries (8 bytes each):
    --   Word  0: bytes  0- 7   ADD type (x41) at lane 0 (bits  7: 0)
    --   Word  1: bytes  8-15   payload
    --   Word  2: bytes 16-23   payload
    --   Word  3: bytes 24-31   payload
    --   Word  4: bytes 32-39   CANCEL type (x58) at lane 4 (bits 39:32)
    --   Word  5: bytes 40-47   payload
    --   Word  6: bytes 48-55   payload
    --   Word  7: bytes 56-63   REPLACE type (x55) at lane 3 (bits 31:24)
    --   Word  8: bytes 64-71   payload
    --   Word  9: bytes 72-79   payload
    --   Word 10: bytes 80-87   payload
    --   Word 11: bytes 88-95   EXECUTED type (x45) at lane 6 (bits 55:48)
    --   Word 12: bytes 96-103  payload
    --   Word 13: bytes104-111  payload
    --   Word 14: bytes112-119  payload
    --   Word 15: bytes120-127  DELETE type (x44) at lane 5 (bits 47:40)
    --   Word 16: bytes128-135  payload
    --   Word 17: bytes136-143  payload (last byte of DELETE)

    type word_array is array (natural range <>) of unsigned(63 downto 0);
    constant words : word_array(0 to 19) := (
        -- Word 0:  bytes  0- 7  ADD type at lane 0
        x"0000000000000041",  -- Word 0:  bytes 0-7   ADD type at lane 0
        x"0101010101010101",  -- Word 1:  bytes 8-15  ADD payload
        x"0101010101010101",  -- Word 2:  bytes 16-23 ADD payload
        x"0101010101010101",  -- Word 3:  bytes 24-31 ADD payload

        x"0000005800000000",  -- Word 4:  bytes 32-39 CANCEL type at lane 4
        x"0202020202020202",  -- Word 5:  bytes 40-47 CANCEL payload
        x"0202020202020202",  -- Word 6:  bytes 48-55 CANCEL payload

        x"0000000055000000",  -- Word 7:  bytes 56-63 REPLACE type at lane 3
        x"0303030303030303",  -- Word 8:  bytes 64-71 REPLACE payload
        x"0303030303030303",  -- Word 9:  bytes 72-79 REPLACE payload
        x"0303030303030303",  -- Word 10: bytes 80-87 REPLACE payload

        x"0000004500000000",  -- Word 11: bytes 88-95 EXECUTED type at lane 6
        x"0404040404040404",  -- Word 12: bytes 96-103 EXECUTED payload
        x"0404040404040404",  -- Word 13: bytes 104-111 EXECUTED payload
        x"0404040404040404",  -- Word 14: bytes 112-119 EXECUTED payload

        x"4444444444444444",  -- Word 15: bytes 120-127 DELETE type at lane 5
        x"0505050505050505",  -- Word 16: bytes 128-135 DELETE payload
        x"0505050505050505",  -- Word 17: bytes 136-143 DELETE payload

        x"0000000000000000",  -- Word 18: padding
        x"0000000000000000"   -- Word 19: padding

    );

begin

    clk <= not clk after T/2;

    uut: type_processor port map (
        data           => data_in,
        clk            => clk,
        rst            => rst,
        frame          => frame,
        byte_count     => byte_count,
        success        => success,
        frame_size_out => frame_size_out,
        previous_offset_out     => previous_offset_out,
        state_out      => state_out,
        previous_success_out => previous_success,
        current_frame_stored =>  current_frame_stored
    );

    cnt: byte_counter port map (
        clk           => clk,
        rst           => rst,
        success       => success,
        previous_offset        => previous_offset_out,
        frame_size_in => frame_size_out,
        byte_count    => byte_count,
        state_in      => state_out,
        previous_success => previous_success
    );

    pnt : fifo port map (

        clk => clk,
        rst => rst,
        success_in => current_frame_stored,
        din => frame,
        read_in => '0'

    );

    process
    begin
        rst <= '1';
        wait for 3 * T;
        rst <= '0';
        for i in 0 to 19 loop
            data_in <= words(i);
            wait until rising_edge(clk);
        end loop;
        wait for 5 * T;
        report "Test finished" severity note;
        wait;
    end process;

    process(clk)
        variable cnt : integer := 0;
    begin
        if rising_edge(clk) and success = '1' then
            cnt := cnt + 1;
            report "Frame #" & integer'image(cnt) &
                   " size=" & integer'image(to_integer(frame_size_out)) &
                   " offset=" & integer'image(to_integer(previous_offset_out)) &
                   " byte_count=" & integer'image(to_integer(byte_count)) &
                   " at time " & time'image(now);
        end if;
    end process;

end architecture;