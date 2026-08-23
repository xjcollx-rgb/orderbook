library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity type_processor is
    port (

    data : in unsigned(63 downto 0);
    clk : in std_logic;
    rst : in std_logic;
    frame : out unsigned(199 downto 0);
    byte_count : in unsigned(6 downto 0);
    success : out std_logic;
    frame_size_out : out unsigned(6 downto 0);
    previous_offset_out : out unsigned(2 downto 0);
    state_out : out std_logic:= '1';
    previous_success_out : out std_logic;
    current_frame_stored : out std_logic
    );

end type_processor;


architecture rtl of type_processor is

    signal frame_reg : unsigned(199 downto 0):= (others => '0');
    signal overflow_reg : unsigned(55 downto 0);

    signal byte_0_count : unsigned(6 downto 0);
    signal byte_1_count : unsigned(6 downto 0);
    signal byte_2_count : unsigned(6 downto 0);
    signal byte_3_count : unsigned(6 downto 0);
    signal byte_4_count : unsigned(6 downto 0);
    signal byte_5_count : unsigned(6 downto 0);
    signal byte_6_count : unsigned(6 downto 0);
    signal byte_7_count : unsigned(6 downto 0);

    signal offset : unsigned(2 downto 0):= (others => '0');

    signal frame_type     : unsigned(2 downto 0);

    signal success_signal : std_logic ;
    signal frame_size     : unsigned(6 downto 0):= ("0000000");

    constant ADD      : unsigned(2 downto 0) := "000";
    constant CANCEL   : unsigned(2 downto 0) := "001";
    constant REPLACE  : unsigned(2 downto 0) := "010";
    constant EXECUTED : unsigned(2 downto 0) := "011";
    constant DELETE   : unsigned(2 downto 0) := "100";
    constant ADD_SIZE : unsigned(6 downto 0):= "0100100";
    constant CANCEL_SIZE : unsigned(6 downto 0):= "0010111";
    constant REPALCE_SIZE : unsigned(6 downto 0):= "0100011";
    constant EXECUTED_SIZE : unsigned(6 downto 0):= "0011111";
    constant DELETE_SIZE : unsigned(6 downto 0):= "0010011";

    type state_t is (IDLE,PROCESSING);
    signal state : state_t := PROCESSING;
    signal state_signal : std_logic:= '1';
    signal previous_success : std_logic;
    signal previous_offset  : unsigned(2 downto 0):= ("000");

    signal debug_type_v : unsigned(2 downto 0);
    signal debug_offset_v : unsigned(2 downto 0);
    signal debug_size_v : unsigned(6 downto 0);

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

    variable type_v : unsigned(2 downto 0);
    variable size_v : unsigned(6 downto 0);
    variable offset_v : unsigned(2 downto 0);


    begin 

        if rising_edge(clk) then 

            if rst = '1' then 
                frame_reg <= (others => '0');
                success_signal <= '0';  -- Add this
                offset <= (others => '0'); 
                previous_success <= '0';
                previous_offset <= "000";

                
                type_v := (others => '0');
                size_v := (others => '0');
                offset_v := (others => '0');

            else
                -- should keep success signal high for one cycle only
                success_signal <= '0';
                current_frame_stored <= '0';
                offset_v := offset;
                type_v := frame_type;
                size_v := frame_size;

                case state is
                when IDLE =>
                    state_signal <= '0';
                
                if byte_0_count = frame_size then 

                    case data(7 downto 0) is
                        when x"41" =>
                            offset_v := offset + 4;
                            type_v   := ADD;
                            size_v   := ADD_SIZE;
                            success_signal <= '1';
                            state <= PROCESSING;

                        when x"58" =>
                            offset_v := offset + 7;
                            type_v   := CANCEL;
                            size_v   := CANCEL_SIZE;
                            success_signal <= '1';
                            state <= PROCESSING;

                        when x"55" =>
                            offset_v := offset + 3;
                            type_v   := REPLACE;
                            size_v   := REPALCE_SIZE;
                            success_signal <= '1';
                            state <= PROCESSING;

                        when x"45" =>
                            offset_v := offset + 7;
                            type_v   := EXECUTED;
                            size_v   := EXECUTED_SIZE;
                            success_signal <= '1';
                            state <= PROCESSING;

                        when x"44" =>
                            offset_v := offset + 3;
                            type_v   := DELETE;
                            size_v   := DELETE_SIZE;
                            success_signal <= '1';
                            state <= PROCESSING;

                        when others => size_v := "0000000";
                    end case;
                end if;
                
                when PROCESSING =>

                state_signal <= '1';

                if success_signal = '1' then 
                        previous_success <= '1';
                end if; 

                if (byte_count <= frame_size-1) and (frame_size-1 <= byte_count + 7) then
                    current_frame_stored <= '1';
                end if;


                if (byte_count <= frame_size) and (frame_size <= byte_count + 7) then 
                    --type byte identifier + reset signal for counter 

                    if byte_0_count = frame_size then

                        case data(7 downto 0) is
                            when x"41" =>
                                offset_v := offset + 4;
                                type_v   := ADD;
                                size_v   := ADD_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"58" =>
                                offset_v := offset + 7;
                                type_v   := CANCEL;
                                size_v   := CANCEL_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"55" =>
                                offset_v := offset + 3;
                                type_v   := REPLACE;
                                size_v   := REPALCE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"45" =>
                                offset_v := offset + 7;
                                type_v   := EXECUTED;
                                size_v   := EXECUTED_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"44" =>
                                offset_v := offset + 3;
                                type_v   := DELETE;
                                size_v   := DELETE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when others => 
                                size_v       := (others => '0');
                                type_v       := (others => '0');
                                offset_v     := (others => '0');
                                state        <= IDLE;
                                state_signal <= '0';
                                previous_success <= '0';
                                previous_offset <= "000";
                                
                        end case;

                    elsif byte_1_count = frame_size then

                        case data(15 downto 8) is
                            when x"41" =>
                                offset_v := offset + 4;
                                type_v   := ADD;
                                size_v   := ADD_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"58" =>
                                offset_v := offset + 7;
                                type_v   := CANCEL;
                                size_v   := CANCEL_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"55" =>
                                offset_v := offset + 3;
                                type_v   := REPLACE;
                                size_v   := REPALCE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"45" =>
                                offset_v := offset + 7;
                                type_v   := EXECUTED;
                                size_v   := EXECUTED_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"44" =>
                                offset_v := offset + 3;
                                type_v   := DELETE;
                                size_v   := DELETE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when others => 
                                size_v       := (others => '0');
                                type_v       := (others => '0');
                                offset_v     := (others => '0');
                                state        <= IDLE;
                                state_signal <= '0';
                                previous_success <= '0';
                                previous_offset <= "000";

                        end case;

                    elsif byte_2_count = frame_size then

                        case data(23 downto 16) is
                            when x"41" =>
                                offset_v := offset + 4;
                                type_v   := ADD;
                                size_v   := ADD_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"58" =>
                                offset_v := offset + 7;
                                type_v   := CANCEL;
                                size_v   := CANCEL_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"55" =>
                                offset_v := offset + 3;
                                type_v   := REPLACE;
                                size_v   := REPALCE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"45" =>
                                offset_v := offset + 7;
                                type_v   := EXECUTED;
                                size_v   := EXECUTED_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"44" =>
                                offset_v := offset + 3;
                                type_v   := DELETE;
                                size_v   := DELETE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when others => 
                                size_v       := (others => '0');
                                type_v       := (others => '0');
                                offset_v     := (others => '0');
                                state        <= IDLE;
                                state_signal <= '0';
                                previous_success <= '0';
                                previous_offset <= "000";
                        end case;

                    elsif byte_3_count = frame_size then

                        case data(31 downto 24) is
                            when x"41" =>
                                offset_v := offset + 4;
                                type_v   := ADD;
                                size_v   := ADD_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"58" =>
                                offset_v := offset + 7;
                                type_v   := CANCEL;
                                size_v   := CANCEL_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"55" =>
                                offset_v := offset + 3;
                                type_v   := REPLACE;
                                size_v   := REPALCE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"45" =>
                                offset_v := offset + 7;
                                type_v   := EXECUTED;
                                size_v   := EXECUTED_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"44" =>
                                offset_v := offset + 3;
                                type_v   := DELETE;
                                size_v   := DELETE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when others => 
                                size_v       := (others => '0');
                                type_v       := (others => '0');
                                offset_v     := (others => '0');
                                state        <= IDLE;
                                state_signal <= '0';
                                previous_success <= '0';
                                previous_offset <= "000";
                        end case;

                    elsif byte_4_count = frame_size then

                        case data(39 downto 32) is
                            when x"41" =>
                                offset_v := offset + 4;
                                type_v   := ADD;
                                size_v   := ADD_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"58" =>
                                offset_v := offset + 7;
                                type_v   := CANCEL;
                                size_v   := CANCEL_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"55" =>
                                offset_v := offset + 3;
                                type_v   := REPLACE;
                                size_v   := REPALCE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"45" =>
                                offset_v := offset + 7;
                                type_v   := EXECUTED;
                                size_v   := EXECUTED_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"44" =>
                                offset_v := offset + 3;
                                type_v   := DELETE;
                                size_v   := DELETE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when others => 
                                size_v       := (others => '0');
                                type_v       := (others => '0');
                                offset_v     := (others => '0');
                                state        <= IDLE;
                                state_signal <= '0';
                                previous_success <= '0';
                                previous_offset <= "000";
                        end case;

                    elsif byte_5_count = frame_size then

                        case data(47 downto 40) is
                            when x"41" =>
                                offset_v := offset + 4;
                                type_v   := ADD;
                                size_v   := ADD_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"58" =>
                                offset_v := offset + 7;
                                type_v   := CANCEL;
                                size_v   := CANCEL_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"55" =>
                                offset_v := offset + 3;
                                type_v   := REPLACE;
                                size_v   := REPALCE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"45" =>
                                offset_v := offset + 7;
                                type_v   := EXECUTED;
                                size_v   := EXECUTED_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"44" =>
                                offset_v := offset + 3;
                                type_v   := DELETE;
                                size_v   := DELETE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when others => 
                                size_v       := (others => '0');
                                type_v       := (others => '0');
                                offset_v     := (others => '0');
                                state        <= IDLE;
                                state_signal <= '0';
                                previous_success <= '0';
                                previous_offset <= "000";
                        end case;

                    elsif byte_6_count = frame_size then

                        case data(55 downto 48) is
                            when x"41" =>
                                offset_v := offset + 4;
                                type_v   := ADD;
                                size_v   := ADD_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"58" =>
                                offset_v := offset + 7;
                                type_v   := CANCEL;
                                size_v   := CANCEL_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"55" =>
                                offset_v := offset + 3;
                                type_v   := REPLACE;
                                size_v   := REPALCE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"45" =>
                                offset_v := offset + 7;
                                type_v   := EXECUTED;
                                size_v   := EXECUTED_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"44" =>
                                offset_v := offset + 3;
                                type_v   := DELETE;
                                size_v   := DELETE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when others => 
                                size_v       := (others => '0');
                                type_v       := (others => '0');
                                offset_v     := (others => '0');
                                state        <= IDLE;
                                state_signal <= '0';
                                previous_success <= '0';
                                previous_offset <= "000";
                        end case;

                    elsif byte_7_count = frame_size then

                        case data(63 downto 56) is
                            when x"41" =>
                                offset_v := offset + 4;
                                type_v   := ADD;
                                size_v   := ADD_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"58" =>
                                offset_v := offset + 7;
                                type_v   := CANCEL;
                                size_v   := CANCEL_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"55" =>
                                offset_v := offset + 3;
                                type_v   := REPLACE;
                                size_v   := REPALCE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"45" =>
                                offset_v := offset + 7;
                                type_v   := EXECUTED;
                                size_v   := EXECUTED_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when x"44" =>
                                offset_v := offset + 3;
                                type_v   := DELETE;
                                size_v   := DELETE_SIZE;
                                success_signal <= '1';

                                if previous_success = '1' then 
                                    previous_offset <= previous_offset + offset;
                                end if;

                            when others => 
                                size_v       := (others => '0');
                                type_v       := (others => '0');
                                offset_v     := (others => '0');
                                state        <= IDLE;
                                state_signal <= '0';
                                previous_success <= '0';
                                previous_offset <= "000";
                        end case;
                    
                    else 
                        state <= IDLE;

                    end if;

                end if;
                    --frame building logic
                    case frame_type is 
                        when ADD => 

                            case to_integer(byte_0_count) is
                                when 11 => frame_reg(135 downto 128) <= data(7 downto 0);-- ref number
                                when 12 => frame_reg(127 downto 120) <= data(7 downto 0);
                                when 13 => frame_reg(119 downto 112) <= data(7 downto 0);
                                when 14 => frame_reg(111 downto 104) <= data(7 downto 0);
                                when 15 => frame_reg(103 downto 96) <= data(7 downto 0);
                                when 16 => frame_reg(95 downto 88) <= data(7 downto 0);
                                when 17 => frame_reg(87 downto 80) <= data(7 downto 0);
                                when 18 => frame_reg(79 downto 72) <= data(7 downto 0);
                                when 19 => frame_reg(71 downto 64) <= data(7 downto 0);-- side
                                when 20 => frame_reg(63 downto 56) <= data(7 downto 0);-- shares
                                when 21 => frame_reg(55 downto 48) <= data(7 downto 0);
                                when 22 => frame_reg(47 downto 40) <= data(7 downto 0);
                                when 23 => frame_reg(39 downto 32) <= data(7 downto 0);
                                when 32 => frame_reg(31 downto 24) <= data(7 downto 0);-- price
                                when 33 => frame_reg(23 downto 16) <= data(7 downto 0);
                                when 34 => frame_reg(15 downto 8) <= data(7 downto 0);
                                when 35 => frame_reg(7 downto 0) <= data(7 downto 0);
                                when others => null;
                            end case;

                            case to_integer(byte_1_count) is
                                when 11 => frame_reg(135 downto 128) <= data(15 downto 8);
                                when 12 => frame_reg(127 downto 120) <= data(15 downto 8);
                                when 13 => frame_reg(119 downto 112) <= data(15 downto 8);
                                when 14 => frame_reg(111 downto 104) <= data(15 downto 8);
                                when 15 => frame_reg(103 downto 96) <= data(15 downto 8);
                                when 16 => frame_reg(95 downto 88) <= data(15 downto 8);
                                when 17 => frame_reg(87 downto 80) <= data(15 downto 8);
                                when 18 => frame_reg(79 downto 72) <= data(15 downto 8);
                                when 19 => frame_reg(71 downto 64) <= data(15 downto 8);
                                when 20 => frame_reg(63 downto 56) <= data(15 downto 8);
                                when 21 => frame_reg(55 downto 48) <= data(15 downto 8);
                                when 22 => frame_reg(47 downto 40) <= data(15 downto 8);
                                when 23 => frame_reg(39 downto 32) <= data(15 downto 8);
                                when 32 => frame_reg(31 downto 24) <= data(15 downto 8);
                                when 33 => frame_reg(23 downto 16) <= data(15 downto 8);
                                when 34 => frame_reg(15 downto 8) <= data(15 downto 8);
                                when 35 => frame_reg(7 downto 0) <= data(15 downto 8);
                                when others => null;
                            end case;

                            case to_integer(byte_2_count) is
                                when 11 => frame_reg(135 downto 128) <= data(23 downto 16);
                                when 12 => frame_reg(127 downto 120) <= data(23 downto 16);
                                when 13 => frame_reg(119 downto 112) <= data(23 downto 16);
                                when 14 => frame_reg(111 downto 104) <= data(23 downto 16);
                                when 15 => frame_reg(103 downto 96) <= data(23 downto 16);
                                when 16 => frame_reg(95 downto 88) <= data(23 downto 16);
                                when 17 => frame_reg(87 downto 80) <= data(23 downto 16);
                                when 18 => frame_reg(79 downto 72) <= data(23 downto 16);
                                when 19 => frame_reg(71 downto 64) <= data(23 downto 16);
                                when 20 => frame_reg(63 downto 56) <= data(23 downto 16);
                                when 21 => frame_reg(55 downto 48) <= data(23 downto 16);
                                when 22 => frame_reg(47 downto 40) <= data(23 downto 16);
                                when 23 => frame_reg(39 downto 32) <= data(23 downto 16);
                                when 32 => frame_reg(31 downto 24) <= data(23 downto 16);
                                when 33 => frame_reg(23 downto 16) <= data(23 downto 16);
                                when 34 => frame_reg(15 downto 8) <= data(23 downto 16);
                                when 35 => frame_reg(7 downto 0) <= data(23 downto 16);
                                when others => null;
                            end case;

                            case to_integer(byte_3_count) is
                                when 11 => frame_reg(135 downto 128) <= data(31 downto 24);
                                when 12 => frame_reg(127 downto 120) <= data(31 downto 24);
                                when 13 => frame_reg(119 downto 112) <= data(31 downto 24);
                                when 14 => frame_reg(111 downto 104) <= data(31 downto 24);
                                when 15 => frame_reg(103 downto 96) <= data(31 downto 24);
                                when 16 => frame_reg(95 downto 88) <= data(31 downto 24);
                                when 17 => frame_reg(87 downto 80) <= data(31 downto 24);
                                when 18 => frame_reg(79 downto 72) <= data(31 downto 24);
                                when 19 => frame_reg(71 downto 64) <= data(31 downto 24);
                                when 20 => frame_reg(63 downto 56) <= data(31 downto 24);
                                when 21 => frame_reg(55 downto 48) <= data(31 downto 24);
                                when 22 => frame_reg(47 downto 40) <= data(31 downto 24);
                                when 23 => frame_reg(39 downto 32) <= data(31 downto 24);
                                when 32 => frame_reg(31 downto 24) <= data(31 downto 24);
                                when 33 => frame_reg(23 downto 16) <= data(31 downto 24);
                                when 34 => frame_reg(15 downto 8) <= data(31 downto 24);
                                when 35 => frame_reg(7 downto 0) <= data(31 downto 24);
                                when others => null;
                            end case;

                            case to_integer(byte_4_count) is
                                when 11 => frame_reg(135 downto 128) <= data(39 downto 32);
                                when 12 => frame_reg(127 downto 120) <= data(39 downto 32);
                                when 13 => frame_reg(119 downto 112) <= data(39 downto 32);
                                when 14 => frame_reg(111 downto 104) <= data(39 downto 32);
                                when 15 => frame_reg(103 downto 96) <= data(39 downto 32);
                                when 16 => frame_reg(95 downto 88) <= data(39 downto 32);
                                when 17 => frame_reg(87 downto 80) <= data(39 downto 32);
                                when 18 => frame_reg(79 downto 72) <= data(39 downto 32);
                                when 19 => frame_reg(71 downto 64) <= data(39 downto 32);
                                when 20 => frame_reg(63 downto 56) <= data(39 downto 32);
                                when 21 => frame_reg(55 downto 48) <= data(39 downto 32);
                                when 22 => frame_reg(47 downto 40) <= data(39 downto 32);
                                when 23 => frame_reg(39 downto 32) <= data(39 downto 32);
                                when 32 => frame_reg(31 downto 24) <= data(39 downto 32);
                                when 33 => frame_reg(23 downto 16) <= data(39 downto 32);
                                when 34 => frame_reg(15 downto 8) <= data(39 downto 32);
                                when 35 => frame_reg(7 downto 0) <= data(39 downto 32);
                                when others => null;
                            end case;

                            case to_integer(byte_5_count) is
                                when 11 => frame_reg(135 downto 128) <= data(47 downto 40);
                                when 12 => frame_reg(127 downto 120) <= data(47 downto 40);
                                when 13 => frame_reg(119 downto 112) <= data(47 downto 40);
                                when 14 => frame_reg(111 downto 104) <= data(47 downto 40);
                                when 15 => frame_reg(103 downto 96) <= data(47 downto 40);
                                when 16 => frame_reg(95 downto 88) <= data(47 downto 40);
                                when 17 => frame_reg(87 downto 80) <= data(47 downto 40);
                                when 18 => frame_reg(79 downto 72) <= data(47 downto 40);
                                when 19 => frame_reg(71 downto 64) <= data(47 downto 40);
                                when 20 => frame_reg(63 downto 56) <= data(47 downto 40);
                                when 21 => frame_reg(55 downto 48) <= data(47 downto 40);
                                when 22 => frame_reg(47 downto 40) <= data(47 downto 40);
                                when 23 => frame_reg(39 downto 32) <= data(47 downto 40);
                                when 32 => frame_reg(31 downto 24) <= data(47 downto 40);
                                when 33 => frame_reg(23 downto 16) <= data(47 downto 40);
                                when 34 => frame_reg(15 downto 8) <= data(47 downto 40);
                                when 35 => frame_reg(7 downto 0) <= data(47 downto 40);
                                when others => null;
                            end case;

                            case to_integer(byte_6_count) is
                                when 11 => frame_reg(135 downto 128) <= data(55 downto 48);
                                when 12 => frame_reg(127 downto 120) <= data(55 downto 48);
                                when 13 => frame_reg(119 downto 112) <= data(55 downto 48);
                                when 14 => frame_reg(111 downto 104) <= data(55 downto 48);
                                when 15 => frame_reg(103 downto 96) <= data(55 downto 48);
                                when 16 => frame_reg(95 downto 88) <= data(55 downto 48);
                                when 17 => frame_reg(87 downto 80) <= data(55 downto 48);
                                when 18 => frame_reg(79 downto 72) <= data(55 downto 48);
                                when 19 => frame_reg(71 downto 64) <= data(55 downto 48);
                                when 20 => frame_reg(63 downto 56) <= data(55 downto 48);
                                when 21 => frame_reg(55 downto 48) <= data(55 downto 48);
                                when 22 => frame_reg(47 downto 40) <= data(55 downto 48);
                                when 23 => frame_reg(39 downto 32) <= data(55 downto 48);
                                when 32 => frame_reg(31 downto 24) <= data(55 downto 48);
                                when 33 => frame_reg(23 downto 16) <= data(55 downto 48);
                                when 34 => frame_reg(15 downto 8) <= data(55 downto 48);
                                when 35 => frame_reg(7 downto 0) <= data(55 downto 48);
                                when others => null;
                            end case;

                            case to_integer(byte_7_count) is
                                when 11 => frame_reg(135 downto 128) <= data(63 downto 56);
                                when 12 => frame_reg(127 downto 120) <= data(63 downto 56);
                                when 13 => frame_reg(119 downto 112) <= data(63 downto 56);
                                when 14 => frame_reg(111 downto 104) <= data(63 downto 56);
                                when 15 => frame_reg(103 downto 96) <= data(63 downto 56);
                                when 16 => frame_reg(95 downto 88) <= data(63 downto 56);
                                when 17 => frame_reg(87 downto 80) <= data(63 downto 56);
                                when 18 => frame_reg(79 downto 72) <= data(63 downto 56);
                                when 19 => frame_reg(71 downto 64) <= data(63 downto 56);
                                when 20 => frame_reg(63 downto 56) <= data(63 downto 56);
                                when 21 => frame_reg(55 downto 48) <= data(63 downto 56);
                                when 22 => frame_reg(47 downto 40) <= data(63 downto 56);
                                when 23 => frame_reg(39 downto 32) <= data(63 downto 56);
                                when 32 => frame_reg(31 downto 24) <= data(63 downto 56);
                                when 33 => frame_reg(23 downto 16) <= data(63 downto 56);
                                when 34 => frame_reg(15 downto 8) <= data(63 downto 56);
                                when 35 => frame_reg(7 downto 0) <= data(63 downto 56);
                                when others => null;
                            end case;

                        when CANCEL | EXECUTED =>

                            case to_integer(byte_0_count) is
                                when 11 => frame_reg(135 downto 128) <= data(7 downto 0);
                                when 12 => frame_reg(127 downto 120) <= data(7 downto 0);
                                when 13 => frame_reg(119 downto 112) <= data(7 downto 0);
                                when 14 => frame_reg(111 downto 104) <= data(7 downto 0);
                                when 15 => frame_reg(103 downto 96) <= data(7 downto 0);
                                when 16 => frame_reg(95 downto 88) <= data(7 downto 0);
                                when 17 => frame_reg(87 downto 80) <= data(7 downto 0);
                                when 18 => frame_reg(79 downto 72) <= data(7 downto 0);
                                when 19 => frame_reg(63 downto 56) <= data(7 downto 0);
                                when 20 => frame_reg(55 downto 48) <= data(7 downto 0);
                                when 21 => frame_reg(47 downto 40) <= data(7 downto 0);
                                when 22 => frame_reg(39 downto 32) <= data(7 downto 0);
                                when others => null;
                            end case;

                            case to_integer(byte_1_count) is
                                when 11 => frame_reg(135 downto 128) <= data(15 downto 8);
                                when 12 => frame_reg(127 downto 120) <= data(15 downto 8);
                                when 13 => frame_reg(119 downto 112) <= data(15 downto 8);
                                when 14 => frame_reg(111 downto 104) <= data(15 downto 8);
                                when 15 => frame_reg(103 downto 96) <= data(15 downto 8);
                                when 16 => frame_reg(95 downto 88) <= data(15 downto 8);
                                when 17 => frame_reg(87 downto 80) <= data(15 downto 8);
                                when 18 => frame_reg(79 downto 72) <= data(15 downto 8);
                                when 19 => frame_reg(63 downto 56) <= data(15 downto 8);
                                when 20 => frame_reg(55 downto 48) <= data(15 downto 8);
                                when 21 => frame_reg(47 downto 40) <= data(15 downto 8);
                                when 22 => frame_reg(39 downto 32) <= data(15 downto 8);
                                when others => null;
                            end case;

                            case to_integer(byte_2_count) is
                                when 11 => frame_reg(135 downto 128) <= data(23 downto 16);
                                when 12 => frame_reg(127 downto 120) <= data(23 downto 16);
                                when 13 => frame_reg(119 downto 112) <= data(23 downto 16);
                                when 14 => frame_reg(111 downto 104) <= data(23 downto 16);
                                when 15 => frame_reg(103 downto 96) <= data(23 downto 16);
                                when 16 => frame_reg(95 downto 88) <= data(23 downto 16);
                                when 17 => frame_reg(87 downto 80) <= data(23 downto 16);
                                when 18 => frame_reg(79 downto 72) <= data(23 downto 16);
                                when 19 => frame_reg(63 downto 56) <= data(23 downto 16);
                                when 20 => frame_reg(55 downto 48) <= data(23 downto 16);
                                when 21 => frame_reg(47 downto 40) <= data(23 downto 16);
                                when 22 => frame_reg(39 downto 32) <= data(23 downto 16);
                                when others => null;
                            end case;

                            case to_integer(byte_3_count) is
                                when 11 => frame_reg(135 downto 128) <= data(31 downto 24);
                                when 12 => frame_reg(127 downto 120) <= data(31 downto 24);
                                when 13 => frame_reg(119 downto 112) <= data(31 downto 24);
                                when 14 => frame_reg(111 downto 104) <= data(31 downto 24);
                                when 15 => frame_reg(103 downto 96) <= data(31 downto 24);
                                when 16 => frame_reg(95 downto 88) <= data(31 downto 24);
                                when 17 => frame_reg(87 downto 80) <= data(31 downto 24);
                                when 18 => frame_reg(79 downto 72) <= data(31 downto 24);
                                when 19 => frame_reg(63 downto 56) <= data(31 downto 24);
                                when 20 => frame_reg(55 downto 48) <= data(31 downto 24);
                                when 21 => frame_reg(47 downto 40) <= data(31 downto 24);
                                when 22 => frame_reg(39 downto 32) <= data(31 downto 24);
                                when others => null;
                            end case;

                            case to_integer(byte_4_count) is
                                when 11 => frame_reg(135 downto 128) <= data(39 downto 32);
                                when 12 => frame_reg(127 downto 120) <= data(39 downto 32);
                                when 13 => frame_reg(119 downto 112) <= data(39 downto 32);
                                when 14 => frame_reg(111 downto 104) <= data(39 downto 32);
                                when 15 => frame_reg(103 downto 96) <= data(39 downto 32);
                                when 16 => frame_reg(95 downto 88) <= data(39 downto 32);
                                when 17 => frame_reg(87 downto 80) <= data(39 downto 32);
                                when 18 => frame_reg(79 downto 72) <= data(39 downto 32);
                                when 19 => frame_reg(63 downto 56) <= data(39 downto 32);
                                when 20 => frame_reg(55 downto 48) <= data(39 downto 32);
                                when 21 => frame_reg(47 downto 40) <= data(39 downto 32);
                                when 22 => frame_reg(39 downto 32) <= data(39 downto 32);
                                when others => null;
                            end case;

                            case to_integer(byte_5_count) is
                                when 11 => frame_reg(135 downto 128) <= data(47 downto 40);
                                when 12 => frame_reg(127 downto 120) <= data(47 downto 40);
                                when 13 => frame_reg(119 downto 112) <= data(47 downto 40);
                                when 14 => frame_reg(111 downto 104) <= data(47 downto 40);
                                when 15 => frame_reg(103 downto 96) <= data(47 downto 40);
                                when 16 => frame_reg(95 downto 88) <= data(47 downto 40);
                                when 17 => frame_reg(87 downto 80) <= data(47 downto 40);
                                when 18 => frame_reg(79 downto 72) <= data(47 downto 40);
                                when 19 => frame_reg(63 downto 56) <= data(47 downto 40);
                                when 20 => frame_reg(55 downto 48) <= data(47 downto 40);
                                when 21 => frame_reg(47 downto 40) <= data(47 downto 40);
                                when 22 => frame_reg(39 downto 32) <= data(47 downto 40);
                                when others => null;
                            end case;

                            case to_integer(byte_6_count) is
                                when 11 => frame_reg(135 downto 128) <= data(55 downto 48);
                                when 12 => frame_reg(127 downto 120) <= data(55 downto 48);
                                when 13 => frame_reg(119 downto 112) <= data(55 downto 48);
                                when 14 => frame_reg(111 downto 104) <= data(55 downto 48);
                                when 15 => frame_reg(103 downto 96) <= data(55 downto 48);
                                when 16 => frame_reg(95 downto 88) <= data(55 downto 48);
                                when 17 => frame_reg(87 downto 80) <= data(55 downto 48);
                                when 18 => frame_reg(79 downto 72) <= data(55 downto 48);
                                when 19 => frame_reg(63 downto 56) <= data(55 downto 48);
                                when 20 => frame_reg(55 downto 48) <= data(55 downto 48);
                                when 21 => frame_reg(47 downto 40) <= data(55 downto 48);
                                when 22 => frame_reg(39 downto 32) <= data(55 downto 48);
                                when others => null;
                            end case;

                            case to_integer(byte_7_count) is
                                when 11 => frame_reg(135 downto 128) <= data(63 downto 56);
                                when 12 => frame_reg(127 downto 120) <= data(63 downto 56);
                                when 13 => frame_reg(119 downto 112) <= data(63 downto 56);
                                when 14 => frame_reg(111 downto 104) <= data(63 downto 56);
                                when 15 => frame_reg(103 downto 96) <= data(63 downto 56);
                                when 16 => frame_reg(95 downto 88) <= data(63 downto 56);
                                when 17 => frame_reg(87 downto 80) <= data(63 downto 56);
                                when 18 => frame_reg(79 downto 72) <= data(63 downto 56);
                                when 19 => frame_reg(63 downto 56) <= data(63 downto 56);
                                when 20 => frame_reg(55 downto 48) <= data(63 downto 56);
                                when 21 => frame_reg(47 downto 40) <= data(63 downto 56);
                                when 22 => frame_reg(39 downto 32) <= data(63 downto 56);
                                when others => null;
                            end case;

                        when REPLACE =>

                            case to_integer(byte_0_count) is
                                when 11 => frame_reg(199 downto 192) <= data(7 downto 0);
                                when 12 => frame_reg(191 downto 184) <= data(7 downto 0);
                                when 13 => frame_reg(183 downto 176) <= data(7 downto 0);
                                when 14 => frame_reg(175 downto 168) <= data(7 downto 0);
                                when 15 => frame_reg(167 downto 160) <= data(7 downto 0);
                                when 16 => frame_reg(159 downto 152) <= data(7 downto 0);
                                when 17 => frame_reg(151 downto 144) <= data(7 downto 0);
                                when 18 => frame_reg(143 downto 136) <= data(7 downto 0);
                                when 19 => frame_reg(135 downto 128) <= data(7 downto 0);
                                when 20 => frame_reg(127 downto 120) <= data(7 downto 0);
                                when 21 => frame_reg(119 downto 112) <= data(7 downto 0);
                                when 22 => frame_reg(111 downto 104) <= data(7 downto 0);
                                when 23 => frame_reg(103 downto 96) <= data(7 downto 0);
                                when 24 => frame_reg(95 downto 88) <= data(7 downto 0);
                                when 25 => frame_reg(87 downto 80) <= data(7 downto 0);
                                when 26 => frame_reg(79 downto 72) <= data(7 downto 0);
                                when 27 => frame_reg(63 downto 56) <= data(7 downto 0);
                                when 28 => frame_reg(55 downto 48) <= data(7 downto 0);
                                when 29 => frame_reg(47 downto 40) <= data(7 downto 0);
                                when 30 => frame_reg(39 downto 32) <= data(7 downto 0);
                                when 31 => frame_reg(31 downto 24) <= data(7 downto 0);
                                when 32 => frame_reg(23 downto 16) <= data(7 downto 0);
                                when 33 => frame_reg(15 downto 8) <= data(7 downto 0);
                                when 34 => frame_reg(7 downto 0) <= data(7 downto 0);
                                when others => null;
                            end case;

                            case to_integer(byte_1_count) is
                                when 11 => frame_reg(199 downto 192) <= data(15 downto 8);
                                when 12 => frame_reg(191 downto 184) <= data(15 downto 8);
                                when 13 => frame_reg(183 downto 176) <= data(15 downto 8);
                                when 14 => frame_reg(175 downto 168) <= data(15 downto 8);
                                when 15 => frame_reg(167 downto 160) <= data(15 downto 8);
                                when 16 => frame_reg(159 downto 152) <= data(15 downto 8);
                                when 17 => frame_reg(151 downto 144) <= data(15 downto 8);
                                when 18 => frame_reg(143 downto 136) <= data(15 downto 8);
                                when 19 => frame_reg(135 downto 128) <= data(15 downto 8);
                                when 20 => frame_reg(127 downto 120) <= data(15 downto 8);
                                when 21 => frame_reg(119 downto 112) <= data(15 downto 8);
                                when 22 => frame_reg(111 downto 104) <= data(15 downto 8);
                                when 23 => frame_reg(103 downto 96) <= data(15 downto 8);
                                when 24 => frame_reg(95 downto 88) <= data(15 downto 8);
                                when 25 => frame_reg(87 downto 80) <= data(15 downto 8);
                                when 26 => frame_reg(79 downto 72) <= data(15 downto 8);
                                when 27 => frame_reg(63 downto 56) <= data(15 downto 8);
                                when 28 => frame_reg(55 downto 48) <= data(15 downto 8);
                                when 29 => frame_reg(47 downto 40) <= data(15 downto 8);
                                when 30 => frame_reg(39 downto 32) <= data(15 downto 8);
                                when 31 => frame_reg(31 downto 24) <= data(15 downto 8);
                                when 32 => frame_reg(23 downto 16) <= data(15 downto 8);
                                when 33 => frame_reg(15 downto 8) <= data(15 downto 8);
                                when 34 => frame_reg(7 downto 0) <= data(15 downto 8);
                                when others => null;
                            end case;

                            case to_integer(byte_2_count) is
                                when 11 => frame_reg(199 downto 192) <= data(23 downto 16);
                                when 12 => frame_reg(191 downto 184) <= data(23 downto 16);
                                when 13 => frame_reg(183 downto 176) <= data(23 downto 16);
                                when 14 => frame_reg(175 downto 168) <= data(23 downto 16);
                                when 15 => frame_reg(167 downto 160) <= data(23 downto 16);
                                when 16 => frame_reg(159 downto 152) <= data(23 downto 16);
                                when 17 => frame_reg(151 downto 144) <= data(23 downto 16);
                                when 18 => frame_reg(143 downto 136) <= data(23 downto 16);
                                when 19 => frame_reg(135 downto 128) <= data(23 downto 16);
                                when 20 => frame_reg(127 downto 120) <= data(23 downto 16);
                                when 21 => frame_reg(119 downto 112) <= data(23 downto 16);
                                when 22 => frame_reg(111 downto 104) <= data(23 downto 16);
                                when 23 => frame_reg(103 downto 96) <= data(23 downto 16);
                                when 24 => frame_reg(95 downto 88) <= data(23 downto 16);
                                when 25 => frame_reg(87 downto 80) <= data(23 downto 16);
                                when 26 => frame_reg(79 downto 72) <= data(23 downto 16);
                                when 27 => frame_reg(63 downto 56) <= data(23 downto 16);
                                when 28 => frame_reg(55 downto 48) <= data(23 downto 16);
                                when 29 => frame_reg(47 downto 40) <= data(23 downto 16);
                                when 30 => frame_reg(39 downto 32) <= data(23 downto 16);
                                when 31 => frame_reg(31 downto 24) <= data(23 downto 16);
                                when 32 => frame_reg(23 downto 16) <= data(23 downto 16);
                                when 33 => frame_reg(15 downto 8) <= data(23 downto 16);
                                when 34 => frame_reg(7 downto 0) <= data(23 downto 16);
                                when others => null;
                            end case;

                            case to_integer(byte_3_count) is
                                when 11 => frame_reg(199 downto 192) <= data(31 downto 24);
                                when 12 => frame_reg(191 downto 184) <= data(31 downto 24);
                                when 13 => frame_reg(183 downto 176) <= data(31 downto 24);
                                when 14 => frame_reg(175 downto 168) <= data(31 downto 24);
                                when 15 => frame_reg(167 downto 160) <= data(31 downto 24);
                                when 16 => frame_reg(159 downto 152) <= data(31 downto 24);
                                when 17 => frame_reg(151 downto 144) <= data(31 downto 24);
                                when 18 => frame_reg(143 downto 136) <= data(31 downto 24);
                                when 19 => frame_reg(135 downto 128) <= data(31 downto 24);
                                when 20 => frame_reg(127 downto 120) <= data(31 downto 24);
                                when 21 => frame_reg(119 downto 112) <= data(31 downto 24);
                                when 22 => frame_reg(111 downto 104) <= data(31 downto 24);
                                when 23 => frame_reg(103 downto 96) <= data(31 downto 24);
                                when 24 => frame_reg(95 downto 88) <= data(31 downto 24);
                                when 25 => frame_reg(87 downto 80) <= data(31 downto 24);
                                when 26 => frame_reg(79 downto 72) <= data(31 downto 24);
                                when 27 => frame_reg(63 downto 56) <= data(31 downto 24);
                                when 28 => frame_reg(55 downto 48) <= data(31 downto 24);
                                when 29 => frame_reg(47 downto 40) <= data(31 downto 24);
                                when 30 => frame_reg(39 downto 32) <= data(31 downto 24);
                                when 31 => frame_reg(31 downto 24) <= data(31 downto 24);
                                when 32 => frame_reg(23 downto 16) <= data(31 downto 24);
                                when 33 => frame_reg(15 downto 8) <= data(31 downto 24);
                                when 34 => frame_reg(7 downto 0) <= data(31 downto 24);
                                when others => null;
                            end case;

                            case to_integer(byte_4_count) is
                                when 11 => frame_reg(199 downto 192) <= data(39 downto 32);
                                when 12 => frame_reg(191 downto 184) <= data(39 downto 32);
                                when 13 => frame_reg(183 downto 176) <= data(39 downto 32);
                                when 14 => frame_reg(175 downto 168) <= data(39 downto 32);
                                when 15 => frame_reg(167 downto 160) <= data(39 downto 32);
                                when 16 => frame_reg(159 downto 152) <= data(39 downto 32);
                                when 17 => frame_reg(151 downto 144) <= data(39 downto 32);
                                when 18 => frame_reg(143 downto 136) <= data(39 downto 32);
                                when 19 => frame_reg(135 downto 128) <= data(39 downto 32);
                                when 20 => frame_reg(127 downto 120) <= data(39 downto 32);
                                when 21 => frame_reg(119 downto 112) <= data(39 downto 32);
                                when 22 => frame_reg(111 downto 104) <= data(39 downto 32);
                                when 23 => frame_reg(103 downto 96) <= data(39 downto 32);
                                when 24 => frame_reg(95 downto 88) <= data(39 downto 32);
                                when 25 => frame_reg(87 downto 80) <= data(39 downto 32);
                                when 26 => frame_reg(79 downto 72) <= data(39 downto 32);
                                when 27 => frame_reg(63 downto 56) <= data(39 downto 32);
                                when 28 => frame_reg(55 downto 48) <= data(39 downto 32);
                                when 29 => frame_reg(47 downto 40) <= data(39 downto 32);
                                when 30 => frame_reg(39 downto 32) <= data(39 downto 32);
                                when 31 => frame_reg(31 downto 24) <= data(39 downto 32);
                                when 32 => frame_reg(23 downto 16) <= data(39 downto 32);
                                when 33 => frame_reg(15 downto 8) <= data(39 downto 32);
                                when 34 => frame_reg(7 downto 0) <= data(39 downto 32);
                                when others => null;
                            end case;

                            case to_integer(byte_5_count) is
                                when 11 => frame_reg(199 downto 192) <= data(47 downto 40);
                                when 12 => frame_reg(191 downto 184) <= data(47 downto 40);
                                when 13 => frame_reg(183 downto 176) <= data(47 downto 40);
                                when 14 => frame_reg(175 downto 168) <= data(47 downto 40);
                                when 15 => frame_reg(167 downto 160) <= data(47 downto 40);
                                when 16 => frame_reg(159 downto 152) <= data(47 downto 40);
                                when 17 => frame_reg(151 downto 144) <= data(47 downto 40);
                                when 18 => frame_reg(143 downto 136) <= data(47 downto 40);
                                when 19 => frame_reg(135 downto 128) <= data(47 downto 40);
                                when 20 => frame_reg(127 downto 120) <= data(47 downto 40);
                                when 21 => frame_reg(119 downto 112) <= data(47 downto 40);
                                when 22 => frame_reg(111 downto 104) <= data(47 downto 40);
                                when 23 => frame_reg(103 downto 96) <= data(47 downto 40);
                                when 24 => frame_reg(95 downto 88) <= data(47 downto 40);
                                when 25 => frame_reg(87 downto 80) <= data(47 downto 40);
                                when 26 => frame_reg(79 downto 72) <= data(47 downto 40);
                                when 27 => frame_reg(63 downto 56) <= data(47 downto 40);
                                when 28 => frame_reg(55 downto 48) <= data(47 downto 40);
                                when 29 => frame_reg(47 downto 40) <= data(47 downto 40);
                                when 30 => frame_reg(39 downto 32) <= data(47 downto 40);
                                when 31 => frame_reg(31 downto 24) <= data(47 downto 40);
                                when 32 => frame_reg(23 downto 16) <= data(47 downto 40);
                                when 33 => frame_reg(15 downto 8) <= data(47 downto 40);
                                when 34 => frame_reg(7 downto 0) <= data(47 downto 40);
                                when others => null;
                            end case;

                            case to_integer(byte_6_count) is
                                when 11 => frame_reg(199 downto 192) <= data(55 downto 48);
                                when 12 => frame_reg(191 downto 184) <= data(55 downto 48);
                                when 13 => frame_reg(183 downto 176) <= data(55 downto 48);
                                when 14 => frame_reg(175 downto 168) <= data(55 downto 48);
                                when 15 => frame_reg(167 downto 160) <= data(55 downto 48);
                                when 16 => frame_reg(159 downto 152) <= data(55 downto 48);
                                when 17 => frame_reg(151 downto 144) <= data(55 downto 48);
                                when 18 => frame_reg(143 downto 136) <= data(55 downto 48);
                                when 19 => frame_reg(135 downto 128) <= data(55 downto 48);
                                when 20 => frame_reg(127 downto 120) <= data(55 downto 48);
                                when 21 => frame_reg(119 downto 112) <= data(55 downto 48);
                                when 22 => frame_reg(111 downto 104) <= data(55 downto 48);
                                when 23 => frame_reg(103 downto 96) <= data(55 downto 48);
                                when 24 => frame_reg(95 downto 88) <= data(55 downto 48);
                                when 25 => frame_reg(87 downto 80) <= data(55 downto 48);
                                when 26 => frame_reg(79 downto 72) <= data(55 downto 48);
                                when 27 => frame_reg(63 downto 56) <= data(55 downto 48);
                                when 28 => frame_reg(55 downto 48) <= data(55 downto 48);
                                when 29 => frame_reg(47 downto 40) <= data(55 downto 48);
                                when 30 => frame_reg(39 downto 32) <= data(55 downto 48);
                                when 31 => frame_reg(31 downto 24) <= data(55 downto 48);
                                when 32 => frame_reg(23 downto 16) <= data(55 downto 48);
                                when 33 => frame_reg(15 downto 8) <= data(55 downto 48);
                                when 34 => frame_reg(7 downto 0) <= data(55 downto 48);
                                when others => null;
                            end case;

                            case to_integer(byte_7_count) is
                                when 11 => frame_reg(199 downto 192) <= data(63 downto 56);
                                when 12 => frame_reg(191 downto 184) <= data(63 downto 56);
                                when 13 => frame_reg(183 downto 176) <= data(63 downto 56);
                                when 14 => frame_reg(175 downto 168) <= data(63 downto 56);
                                when 15 => frame_reg(167 downto 160) <= data(63 downto 56);
                                when 16 => frame_reg(159 downto 152) <= data(63 downto 56);
                                when 17 => frame_reg(151 downto 144) <= data(63 downto 56);
                                when 18 => frame_reg(143 downto 136) <= data(63 downto 56);
                                when 19 => frame_reg(135 downto 128) <= data(63 downto 56);
                                when 20 => frame_reg(127 downto 120) <= data(63 downto 56);
                                when 21 => frame_reg(119 downto 112) <= data(63 downto 56);
                                when 22 => frame_reg(111 downto 104) <= data(63 downto 56);
                                when 23 => frame_reg(103 downto 96) <= data(63 downto 56);
                                when 24 => frame_reg(95 downto 88) <= data(63 downto 56);
                                when 25 => frame_reg(87 downto 80) <= data(63 downto 56);
                                when 26 => frame_reg(79 downto 72) <= data(63 downto 56);
                                when 27 => frame_reg(63 downto 56) <= data(63 downto 56);
                                when 28 => frame_reg(55 downto 48) <= data(63 downto 56);
                                when 29 => frame_reg(47 downto 40) <= data(63 downto 56);
                                when 30 => frame_reg(39 downto 32) <= data(63 downto 56);
                                when 31 => frame_reg(31 downto 24) <= data(63 downto 56);
                                when 32 => frame_reg(23 downto 16) <= data(63 downto 56);
                                when 33 => frame_reg(15 downto 8) <= data(63 downto 56);
                                when 34 => frame_reg(7 downto 0) <= data(63 downto 56);
                                when others => null;
                            end case;

                        when DELETE =>

                            case to_integer(byte_0_count) is
                                when 11 => frame_reg(135 downto 128) <= data(7 downto 0);
                                when 12 => frame_reg(127 downto 120) <= data(7 downto 0);
                                when 13 => frame_reg(119 downto 112) <= data(7 downto 0);
                                when 14 => frame_reg(111 downto 104) <= data(7 downto 0);
                                when 15 => frame_reg(103 downto 96) <= data(7 downto 0);
                                when 16 => frame_reg(95 downto 88) <= data(7 downto 0);
                                when 17 => frame_reg(87 downto 80) <= data(7 downto 0);
                                when 18 => frame_reg(79 downto 72) <= data(7 downto 0);
                                when others => null;
                            end case;

                            case to_integer(byte_1_count) is
                                when 11 => frame_reg(135 downto 128) <= data(15 downto 8);
                                when 12 => frame_reg(127 downto 120) <= data(15 downto 8);
                                when 13 => frame_reg(119 downto 112) <= data(15 downto 8);
                                when 14 => frame_reg(111 downto 104) <= data(15 downto 8);
                                when 15 => frame_reg(103 downto 96) <= data(15 downto 8);
                                when 16 => frame_reg(95 downto 88) <= data(15 downto 8);
                                when 17 => frame_reg(87 downto 80) <= data(15 downto 8);
                                when 18 => frame_reg(79 downto 72) <= data(15 downto 8);
                                when others => null;
                            end case;

                            case to_integer(byte_2_count) is
                                when 11 => frame_reg(135 downto 128) <= data(23 downto 16);
                                when 12 => frame_reg(127 downto 120) <= data(23 downto 16);
                                when 13 => frame_reg(119 downto 112) <= data(23 downto 16);
                                when 14 => frame_reg(111 downto 104) <= data(23 downto 16);
                                when 15 => frame_reg(103 downto 96) <= data(23 downto 16);
                                when 16 => frame_reg(95 downto 88) <= data(23 downto 16);
                                when 17 => frame_reg(87 downto 80) <= data(23 downto 16);
                                when 18 => frame_reg(79 downto 72) <= data(23 downto 16);
                                when others => null;
                            end case;

                            case to_integer(byte_3_count) is
                                when 11 => frame_reg(135 downto 128) <= data(31 downto 24);
                                when 12 => frame_reg(127 downto 120) <= data(31 downto 24);
                                when 13 => frame_reg(119 downto 112) <= data(31 downto 24);
                                when 14 => frame_reg(111 downto 104) <= data(31 downto 24);
                                when 15 => frame_reg(103 downto 96) <= data(31 downto 24);
                                when 16 => frame_reg(95 downto 88) <= data(31 downto 24);
                                when 17 => frame_reg(87 downto 80) <= data(31 downto 24);
                                when 18 => frame_reg(79 downto 72) <= data(31 downto 24);
                                when others => null;
                            end case;

                            case to_integer(byte_4_count) is
                                when 11 => frame_reg(135 downto 128) <= data(39 downto 32);
                                when 12 => frame_reg(127 downto 120) <= data(39 downto 32);
                                when 13 => frame_reg(119 downto 112) <= data(39 downto 32);
                                when 14 => frame_reg(111 downto 104) <= data(39 downto 32);
                                when 15 => frame_reg(103 downto 96) <= data(39 downto 32);
                                when 16 => frame_reg(95 downto 88) <= data(39 downto 32);
                                when 17 => frame_reg(87 downto 80) <= data(39 downto 32);
                                when 18 => frame_reg(79 downto 72) <= data(39 downto 32);
                                when others => null;
                            end case;

                            case to_integer(byte_5_count) is
                                when 11 => frame_reg(135 downto 128) <= data(47 downto 40);
                                when 12 => frame_reg(127 downto 120) <= data(47 downto 40);
                                when 13 => frame_reg(119 downto 112) <= data(47 downto 40);
                                when 14 => frame_reg(111 downto 104) <= data(47 downto 40);
                                when 15 => frame_reg(103 downto 96) <= data(47 downto 40);
                                when 16 => frame_reg(95 downto 88) <= data(47 downto 40);
                                when 17 => frame_reg(87 downto 80) <= data(47 downto 40);
                                when 18 => frame_reg(79 downto 72) <= data(47 downto 40);
                                when others => null;
                            end case;

                            case to_integer(byte_6_count) is
                                when 11 => frame_reg(135 downto 128) <= data(55 downto 48);
                                when 12 => frame_reg(127 downto 120) <= data(55 downto 48);
                                when 13 => frame_reg(119 downto 112) <= data(55 downto 48);
                                when 14 => frame_reg(111 downto 104) <= data(55 downto 48);
                                when 15 => frame_reg(103 downto 96) <= data(55 downto 48);
                                when 16 => frame_reg(95 downto 88) <= data(55 downto 48);
                                when 17 => frame_reg(87 downto 80) <= data(55 downto 48);
                                when 18 => frame_reg(79 downto 72) <= data(55 downto 48);
                                when others => null;
                            end case;

                            case to_integer(byte_7_count) is
                                when 11 => frame_reg(135 downto 128) <= data(63 downto 56);
                                when 12 => frame_reg(127 downto 120) <= data(63 downto 56);
                                when 13 => frame_reg(119 downto 112) <= data(63 downto 56);
                                when 14 => frame_reg(111 downto 104) <= data(63 downto 56);
                                when 15 => frame_reg(103 downto 96) <= data(63 downto 56);
                                when 16 => frame_reg(95 downto 88) <= data(63 downto 56);
                                when 17 => frame_reg(87 downto 80) <= data(63 downto 56);
                                when 18 => frame_reg(79 downto 72) <= data(63 downto 56);
                                when others => null;
                            end case;

                        when others =>
                            null;
                    end case;

                end case;

            end if;

        frame_type <= type_v;
        frame_size <= size_v;
        offset <= offset_v;
        debug_type_v <= type_v;
        debug_offset_v <= offset_v;
        debug_size_v <= size_v;

        end if;


        

    end process;           

    frame <= frame_reg;
    success <= success_signal;
    frame_size_out <= frame_size;
    previous_offset_out <= previous_offset;
    state_out <= state_signal;
    previous_success_out <= previous_success;


end architecture;   