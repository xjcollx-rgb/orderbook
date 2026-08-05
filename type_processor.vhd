library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity type_processor is
    port (

    data : in unsigned(63 downto 0);
    clk : in std_logic;
    rst : in std_logic;
    frame : out unsigned(135 downto 0);
    byte_count : in unsigned(6 downto 0);
    mode : out unsigned(1 downto 0);
    success : out unsigned;
    frame_type_out : out unsigned(1 downto 0)
    );

end type_processor;


architecture rtl of type_processor is

    signal frame_reg : unsigned(135 downto 0):= (others => '0');
    signal overflow_reg : unsigned(55 downto 0);

    signal byte_0_count : unsigned(6 downto 0);
    signal byte_1_count : unsigned(6 downto 0);
    signal byte_2_count : unsigned(6 downto 0);
    signal byte_3_count : unsigned(6 downto 0);
    signal byte_4_count : unsigned(6 downto 0);
    signal byte_5_count : unsigned(6 downto 0);
    signal byte_6_count : unsigned(6 downto 0);
    signal byte_7_count : unsigned(6 downto 0);

    signal current_offset : unsigned(2 downto 0);
    signal next_offset    : unsigned(2 downto 0);

    signal frame_type_raw : unsigned(1 downto 0):= (others => '0');
    signal frame_type     : unsigned(1 downto 0) := (others => '0');

    signal success_signal : unsigned := (others => '0');
    signal frame_size     : unsigned(5 downto 0);

    constant ADD      : unsigned(1 downto 0) := "00";
    constant CANCEL   : unsigned(1 downto 0) := "01";
    constant REPLACE  : unsigned(1 downto 0) := "10";
    constant EXECUTED : unsigned(1 downto 0) := "11";
    constant ADD_SIZE : unsigned(6 downto 0):= "0100011";
    constant CANCEl_SIZE : unsigned(6 downto 0):= "0100011";
    constant REPALCE_SIZE : unsigned(6 downto 0):= "0100011";
    constant EXECUTED_SIZE : unsigned(6 downto 0):= "0100011";

begin

    byte_0_count <= byte_count;
    byte_1_count <= byte_count + 1;
    byte_2_count <= byte_count + 2;
    byte_3_count <= byte_count + 3;
    byte_4_count <= byte_count + 4;
    byte_5_count <= byte_count + 5;
    byte_6_count <= byte_count + 6;
    byte_7_count <= byte_count + 7;

process(clk)
    begin 

        if rising_edge(clk) then 
            if rst = '1' then 
                frame_reg <= (others => '0');

            else
            --type byte identifier + reset signal for counter    
                if byte_0_count = frame_size + 1 then 
                    frame_type_raw <= data(7 downto 0);
                    success_signal <= "1";

                elsif byte_1_count = frame_size + 1 then 
                    frame_type_raw <= data(15 downto 8);
                    success_signal <= "1";

                elsif byte_2_count = frame_size + 1 then 
                    frame_type_raw <= data(23 downto 16);
                    success_signal <= "1";

                elsif byte_3_count = frame_size + 1 then 
                    frame_type_raw <= data(31 downto 24);
                    success_signal <= "1";

                elsif byte_4_count = frame_size + 1 then
                    frame_type_raw <= data(39 downto 32);
                    success_signal <= "1"; 
                    

                elsif byte_5_count = frame_size + 1 then 
                    frame_type_raw <= data(47 downto 40);
                    success_signal <= "1";

                elsif byte_6_count = frame_size + 1 then 
                    frame_type_raw <= data(55 downto 48);
                    success_signal <= "1";

                elsif byte_7_count = frame_size + 1 then 
                    frame_type_raw <= data(63 downto 56);
                    success_signal <= "1";
                
                end if;
                --frame building logic
                case frame_type is 
                    when ADD => 

                        case to_integer(byte_0_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                            
                            when others =>
                                null;
                        end case;

                        case to_integer(byte_1_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                            
                            when others =>
                                null;
                        end case;

                        case to_integer(byte_2_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                            
                            when others =>
                                null;
                        end case;

                        case to_integer(byte_3_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                            
                            when others =>
                                null;
                        end case;

                        case to_integer(byte_4_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                            
                            when others =>
                                null;
                        end case;

                        case to_integer(byte_5_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                            
                            when others =>
                                null;
                        end case;

                        case to_integer(byte_6_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                            
                            when others =>
                                null;
                        end case;

                        case to_integer(byte_7_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                            
                            when others => null;

                        end case;

                    when CANCEL or EXECUTED =>

                        case to_integer(byte_0_count) is 

                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);
                            
                            when others => null;

                        end case;

                        case to_integer(byte_1_count) is 

                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when others => null;

                        end case;
                        
                        case to_integer(byte_2_count) is 
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when others => null;

                        end case;

                        case to_integer(byte_3_count) is 
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when others => null;

                        end case;

                        case to_integer(byte_4_count) is 
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when others => null;

                        end case;

                        case to_integer(byte_5_count) is 
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when others => null;

                        end case;

                        case to_integer(byte_6_count) is 
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when others => null;

                        end case;

                        case to_integer(byte_7_count) is 
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when others => null;

                        end case;
                        
                    

                    when REPLACE =>

                        case to_integer(byte_0_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when others =>
                                null;
                        end case;

                        case to_integer(byte_1_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when others =>
                                null;
                        end case;

                        case to_integer(byte_2_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when others =>
                                null;
                        end case;

                        case to_integer(byte_3_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when others =>
                                null;
                        end case;

                        case to_integer(byte_4_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when others =>
                                null;
                        end case;

                        case to_integer(byte_5_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when others =>
                                null;
                        end case;

                        case to_integer(byte_6_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);

                            when others =>
                                null;
                        end case;

                        case to_integer(byte_7_count) is
                            when 11 => frame_reg(135 downto 128) <= data(7 downto 0);

                            when 12 => frame_reg(127 downto 120) <= data(7 downto 0);

                            when 13 => frame_reg(119 downto 112) <= data(7 downto 0);

                            when 14 => frame_reg(111 downto 104) <= data(7 downto 0);

                            when 15 => frame_reg(103 downto 96) <= data(7 downto 0);

                            when 16 => frame_reg(95 downto 88) <= data(7 downto 0);

                            when 17 => frame_reg(87 downto 80) <= data(7 downto 0);

                            when 18 => frame_reg(79 downto 72) <= data(7 downto 0);

                            when 19 => frame_reg(71 downto 64) <= data(7 downto 0);

                            when 20 => frame_reg(63 downto 56) <= data(7 downto 0);

                            when 21 => frame_reg(55 downto 48) <= data(7 downto 0);

                            when 22 => frame_reg(47 downto 40) <= data(7 downto 0);

                            when 23 => frame_reg(39 downto 32) <= data(7 downto 0);

                            when 32 => frame_reg(31 downto 24) <= data(7 downto 0);

                            when 33 => frame_reg(23 downto 16) <= data(7 downto 0);

                            when 34 => frame_reg(15 downto 8) <= data(7 downto 0);
                            
                            when others => null;

                        end case;

                    when others =>
                        null;
                end case;

                --Next frame offset
                case frame_type is 
                        when ADD => 
                            current_offset <= current_offset + 4;
                        when CANCEL or EXECUTED => 
                            current_offset <= current_offset + 7;
                        when REPLACE => 
                            current_offset <= current_offset + 3;
                        when others => 
                            null;
                end case;

            end if;

        end if;

    end process;

    process(frame_type_raw) 
    begin
        case frame_type_raw is
            when x"41" => frame_type <= ADD;
            
            when x"58" => frame_type <= CANCEL;

            when x"55" => frame_type <= REPLACE;

            when x"45" => frame_type <= EXECUTED;

            when others => frame_type <= frame_type;
        end case;
        
    end process;

    process (frame_type)
    begin 
        case frame_type is 
            when ADD => frame_size <= ADD_SIZE;

            when CANCEL => frame_size <= CANCEL_SIZE;

            when REPLACE => frame_size <= CANCEL_SIZE;

            when EXECUTED => frame_size <= EXECUTED_SIZE;

        end case;
    end process;
            

    frame <= frame_reg;
    mode <= frame_type;
    success <= success_signal;
    frame_type_out <= frame_type;

end architecture;   