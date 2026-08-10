library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity type_processor_tb is
end type_processor_tb;

architecture test of type_processor_tb is

    component type_processor is
        port (
            data : in unsigned(63 downto 0);
            clk : in std_logic;
            rst : in std_logic;
            frame : out unsigned(199 downto 0);
            byte_count : in unsigned(6 downto 0);
            success : out std_logic;
            frame_type_out : out unsigned(2 downto 0);
            offset_out : out unsigned(2 downto 0)
        );
    end component;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal data : unsigned(63 downto 0) := (others => '0');
    signal byte_count : unsigned(6 downto 0) := (others => '0');
    signal frame : unsigned(199 downto 0);
    signal success : std_logic;
    signal frame_type_out : unsigned(2 downto 0);
    signal offset_out : unsigned(2 downto 0);

    constant CLK_PERIOD : time := 10 ns;
    constant ADD : unsigned(2 downto 0) := "000";
    constant CANCEL : unsigned(2 downto 0) := "001";
    constant REPLACE : unsigned(2 downto 0) := "010";
    constant EXECUTED : unsigned(2 downto 0) := "011";
    constant DELETE : unsigned(2 downto 0) := "100";

begin

    dut : type_processor port map (
        data => data,
        clk => clk,
        rst => rst,
        frame => frame,
        byte_count => byte_count,
        success => success,
        frame_type_out => frame_type_out,
        offset_out => offset_out
    );

    -- Clock generation
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Test stimulus
    stimulus : process
        variable byte_cnt : integer;
    begin
        -- Reset
        rst <= '1';
        data <= (others => '0');
        byte_count <= (others => '0');
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 1: ADD message (36 bytes)
        -- Type byte 'A' (0x41) should appear at byte 35
        report "=== Testing ADD message ===";
        byte_cnt := 0;
        for i in 0 to 4 loop
            byte_count <= to_unsigned(byte_cnt, 7);
            -- Just send incrementing data to see what gets captured
            data <= x"0102030405060708";
            wait for CLK_PERIOD;
            byte_cnt := byte_cnt + 8;
            if byte_cnt >= 36 then
                exit;
            end if;
        end loop;
        -- Send final partial frame with type byte 'A' (0x41)
        byte_count <= to_unsigned(byte_cnt, 7);
        data <= x"4100000000000000";  -- Type byte in LSB (0x41 = 'A')
        wait for CLK_PERIOD * 2;

        report "ADD: frame_type_out = " & to_string(frame_type_out) & ", expected " & to_string(ADD);
        report "ADD: success = " & to_string(success);
        report "ADD: frame = " & to_hstring(frame);
        wait for CLK_PERIOD;

        -- Reset for next test
        rst <= '1';
        wait for CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 2: CANCEL message (23 bytes)
        -- Type byte 'X' (0x58) should appear at byte 22
        report "=== Testing CANCEL message ===";
        byte_cnt := 0;
        for i in 0 to 2 loop
            byte_count <= to_unsigned(byte_cnt, 7);
            data <= x"1111111111111111";
            wait for CLK_PERIOD;
            byte_cnt := byte_cnt + 8;
            if byte_cnt >= 23 then
                exit;
            end if;
        end loop;
        byte_count <= to_unsigned(byte_cnt, 7);
        data <= x"5800000000000000";  -- Type byte 'X' (0x58)
        wait for CLK_PERIOD * 2;

        report "CANCEL: frame_type_out = " & to_string(frame_type_out) & ", expected " & to_string(CANCEL);
        report "CANCEL: success = " & to_string(success);
        report "CANCEL: frame = " & to_hstring(frame);
        wait for CLK_PERIOD;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 3: DELETE message (19 bytes)
        -- Type byte 'D' (0x44) should appear at byte 18
        report "=== Testing DELETE message ===";
        byte_cnt := 0;
        for i in 0 to 2 loop
            byte_count <= to_unsigned(byte_cnt, 7);
            data <= x"2222222222222222";
            wait for CLK_PERIOD;
            byte_cnt := byte_cnt + 8;
            if byte_cnt >= 19 then
                exit;
            end if;
        end loop;
        byte_count <= to_unsigned(byte_cnt, 7);
        data <= x"4400000000000000";  -- Type byte 'D' (0x44)
        wait for CLK_PERIOD * 2;

        report "DELETE: frame_type_out = " & to_string(frame_type_out) & ", expected " & to_string(DELETE);
        report "DELETE: success = " & to_string(success);
        report "DELETE: frame = " & to_hstring(frame);
        wait for CLK_PERIOD;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 4: EXECUTED message (31 bytes)
        -- Type byte 'E' (0x45)
        report "=== Testing EXECUTED message ===";
        byte_cnt := 0;
        for i in 0 to 3 loop
            byte_count <= to_unsigned(byte_cnt, 7);
            data <= x"3333333333333333";
            wait for CLK_PERIOD;
            byte_cnt := byte_cnt + 8;
            if byte_cnt >= 31 then
                exit;
            end if;
        end loop;
        byte_count <= to_unsigned(byte_cnt, 7);
        data <= x"4500000000000000";  -- Type byte 'E' (0x45)
        wait for CLK_PERIOD * 2;

        report "EXECUTED: frame_type_out = " & to_string(frame_type_out) & ", expected " & to_string(EXECUTED);
        report "EXECUTED: success = " & to_string(success);
        report "EXECUTED: frame = " & to_hstring(frame);
        wait for CLK_PERIOD;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 5: REPLACE message (35 bytes)
        -- Type byte 'U' (0x55)
        report "=== Testing REPLACE message ===";
        byte_cnt := 0;
        for i in 0 to 4 loop
            byte_count <= to_unsigned(byte_cnt, 7);
            data <= x"4444444444444444";
            wait for CLK_PERIOD;
            byte_cnt := byte_cnt + 8;
            if byte_cnt >= 35 then
                exit;
            end if;
        end loop;
        byte_count <= to_unsigned(byte_cnt, 7);
        data <= x"5500000000000000";  -- Type byte 'U' (0x55)
        wait for CLK_PERIOD * 2;

        report "REPLACE: frame_type_out = " & to_string(frame_type_out) & ", expected " & to_string(REPLACE);
        report "REPLACE: success = " & to_string(success);
        report "REPLACE: frame = " & to_hstring(frame);
        wait for CLK_PERIOD;

        report "=== All tests complete ===";
        wait;
    end process;

end test;