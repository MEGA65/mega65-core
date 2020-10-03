--------------------------------------------------------------------------------
-- vga_to_hdmi.vhd                                                            --
-- VGA to HDMI converter IP core; also injects PCM stereo audio.              --
--------------------------------------------------------------------------------
-- (C) Copyright 2020 Adam Barnes <ambarnes@gmail.com>                        --
-- This file is part of The Tyto Project. The Tyto Project is free software:  --
-- you can redistribute it and/or modify it under the terms of the GNU Lesser --
-- General Public License as published by the Free Software Foundation,       --
-- either version 3 of the License, or (at your option) any later version.    --
-- The Tyto Project is distributed in the hope that it will be useful, but    --
-- WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public     --
-- License for more details. You should have received a copy of the GNU       --
-- Lesser General Public License along with The Tyto Project. If not, see     --
-- https://www.gnu.org/licenses/.                                             --
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

library work;
use work.types_pkg.all;
use work.hdmi_tx_encoder_pkg.all;

entity vga_to_hdmi is
    port (

      -- Select which of the two audio clocks above to use
      select_44100 : in std_logic;
      
        dvi         : in    std_logic;                     -- DVI mode disables all HDMI enhancements e.g. audio
        vic         : in    std_logic_vector(7 downto 0);  -- CEA/CTA VIC
        aspect      : in    std_logic_vector(1 downto 0);  -- for aspect ratio signalling in AVI InfoFrames
        pix_rep     : in    std_logic;                     -- signals pixel repetition (SD interlaced modes)
        vs_pol      : in    std_logic;                     -- vertical sync output polarity   } 1 = active high
        hs_pol      : in    std_logic;                     -- horizontal sync output polarity } 

        vga_rst     : in    std_logic;                     -- reset
        vga_clk     : in    std_logic;                     -- pixel clock
        vga_vs      : in    std_logic;                     -- vertical sync   } active high
        vga_hs      : in    std_logic;                     -- horizontal sync }
        vga_de      : in    std_logic;                     -- data (pixel) enable
        vga_r       : in    std_logic_vector(7 downto 0);  -- pixel data, red channel   }
        vga_g       : in    std_logic_vector(7 downto 0);  -- pixel data, green channel } 0..255
        vga_b       : in    std_logic_vector(7 downto 0);  -- pixel data, blue channel  }

        pcm_rst     : in    std_logic;                     -- audio reset
        pcm_clk     : in    std_logic;                     -- audio clock        } combined = fs
        pcm_clken   : in    std_logic;                     -- audio clock enable }  (audio sample rate)
        pcm_l       : in    std_logic_vector(15 downto 0); -- left channel  } audio
        pcm_r       : in    std_logic_vector(15 downto 0); -- right channel }  sample
        pcm_acr     : in    std_logic;                     -- HDMI ACR packet strobe (frequency = 128fs/N e.g. 1kHz)
        pcm_n       : in    std_logic_vector(19 downto 0); -- HDMI ACR N value
        pcm_cts     : in    std_logic_vector(19 downto 0); -- HDMI ACR CTS value

        tmds        : out   slv_9_0_t(0 to 2)              -- parallel TMDS symbol stream x 3 channels 

    );
end entity vga_to_hdmi;

architecture synth of vga_to_hdmi is

    constant SUBPACKETS     : integer := 4; -- per packet
    constant PACKET_TYPES   : integer := 6; -- types of data packet supported in this design

    constant CTL_NULL       : std_logic_vector(3 downto 0) := "0000";
    constant CTL_PRE_VIDEO  : std_logic_vector(3 downto 0) := "0001"; -- video period preamble
    constant CTL_PRE_DATA   : std_logic_vector(3 downto 0) := "0101"; -- data period preamble

    ----------------------------------------------------------------------
    -- audio/ACR related

    signal pcm_n_s          : std_logic_vector(19 downto 0);   -- pcm_n   } synchronised
    signal pcm_cts_s        : std_logic_vector(19 downto 0);   -- pcm_cts }
    signal pcm_cs_v         : std_logic_vector(0 to 39);       -- IEC60958 channel status as a vector
    signal pcm_count        : integer range 0 to SUBPACKETS-1; -- used to assemble 4x samples into sample packet

    signal iec_count        : integer range 0 to 191;          -- IEC60958 frame #
    signal iec_sync         : std_logic;                       -- IEC60958 b preamble (sync)
    signal iec_l            : std_logic_vector(23 downto 0);   -- IEC60958 left channel sample
    signal iec_lv           : std_logic;                       -- IEC60958 left channel status
    signal iec_lu           : std_logic;                       -- IEC60958 left user data
    signal iec_lc           : std_logic;                       -- IEC60958 left channel status
    signal iec_lp           : std_logic;                       -- IEC60958 left channel status
    signal iec_r            : std_logic_vector(23 downto 0);   -- IEC60958 right channel sample
    signal iec_rv           : std_logic;                       -- IEC60958 right channel status
    signal iec_ru           : std_logic;                       -- IEC60958 right user data
    signal iec_rc           : std_logic;                       -- IEC60958 right channel status
    signal iec_rp           : std_logic;                       -- IEC60958 right channel status
    signal iec_req          : std_logic;                       -- } CDC macro handshaking
    signal iec_ack          : std_logic;                       -- }

    signal vga_iec_en       : std_logic;                       -- enable for the following...
    signal vga_iec_sync     : std_logic;                       -- iec_sync } synchronised to vga_clk
    signal vga_iec_l        : std_logic_vector(23 downto 0);   -- iec_l    }
    signal vga_iec_lv       : std_logic;                       -- iec_lv   }
    signal vga_iec_lu       : std_logic;                       -- iec_lu   }
    signal vga_iec_lc       : std_logic;                       -- iec_lc   }
    signal vga_iec_lp       : std_logic;                       -- iec_lp   }
    signal vga_iec_r        : std_logic_vector(23 downto 0);   -- iec_r    }
    signal vga_iec_rv       : std_logic;                       -- iec_rv   }
    signal vga_iec_ru       : std_logic;                       -- iec_ru   }
    signal vga_iec_rc       : std_logic;                       -- iec_rc   }
    signal vga_iec_rp       : std_logic;                       -- iec_rp   }
    signal vga_iec_data     : std_logic_vector(56 downto 0);   -- bus to carry above signals
    signal vga_acr          : std_logic;                       -- ACR enable pulse, synchronous to vga_clk

    ----------------------------------------------------------------------
    -- video input related

    signal dvi_s            : std_logic;                     -- dvi     } synchronised
    signal vic_s            : std_logic_vector(7 downto 0);  -- vic     }
    signal aspect_s         : std_logic_vector(1 downto 0);  -- aspect  }
    signal pix_rep_s        : std_logic;                     -- pix_rep }
    signal vs_pol_s         : std_logic;                     -- vs_pol  }
    signal hs_pol_s         : std_logic;                     -- hs_pol  }
    
    signal vga_vs_p         : std_logic;                     -- vga_vs } polarity adjusted
    signal vga_hs_p         : std_logic;                     -- vga_hs }

    signal vga_vs_1         : std_logic;                     -- vga_vs, delayed by 1 clock
    signal vga_hs_1         : std_logic;                     -- vga_hs, delayed by 1 clock
    signal vga_de_1         : std_logic;                     -- vga_de, delayed by 1 clock

    constant buf_size : integer := 128;
    type buf_t is array(0 to buf_size-1) of std_logic_vector(26 downto 0);

    signal buf              : buf_t;                         -- video input buffer (circular)
    signal buf_addr         : integer range 0 to buf_size-1; -- video input buffer write/read address
    signal buf_valid        : boolean;                       -- indicates buffer has been filled once
    signal buf_vs           : std_logic;                     -- buffered VGA vertical sync
    signal buf_hs           : std_logic;                     -- buffered VGA horizontal sync
    signal buf_de           : std_logic;                     -- buffered VGA data (pixel) enable
    signal buf_p            : slv_7_0_t(0 to 2);             -- buffered VGA pixel data, 3 channels
    signal blank_count      : integer range 0 to buf_size;   -- video blank count

    ----------------------------------------------------------------------
    -- encoding related

    type u8 is array(natural range <>) of unsigned(7 downto 0);
    type hb_array_t is array(0 to PACKET_TYPES-1) of u8(0 to 2);
    type pb_array_t is array(0 to PACKET_TYPES-1) of u8(0 to 27);
    type sb_array_t is array(0 to 3) of u8(0 to 6);
    type period_t is (
            CONTROL,
            VIDEO_PRE,
            VIDEO_GB,
            VIDEO,
            DATA_PRE,
            DATA_GB_LEADING,
            DATA_ISLAND,
            DATA_GB_TRAILING
        );

    signal data_req     : std_logic_vector(0 to PACKET_TYPES-1); -- } data packet handshaking
    signal data_ack     : std_logic_vector(0 to PACKET_TYPES-1); -- }

    -- Used to animate SPD text by changing it periodically
    signal spd_toggle : unsigned(5 downto 0) := to_unsigned(0,6);
    
    signal hb_a         : u8(0 to 2);                       -- header bytes of audio sample packet in progress
    signal pb_a         : u8(0 to 27);                      -- packet bytes of audio sample packet in progress
    signal hb           : hb_array_t;                       -- header bytes for packet types 0..3
    signal pb           : pb_array_t;                       -- packet bytes for packet types 0..3

                                                            -- HDMI encoding pipeline stage 1...
    signal s1_period    : period_t;                         -- period type
    signal s1_pcount    : unsigned(4 downto 0);             -- counts time spent in period up to a max of 31 (also data island character #)
    signal s1_dcount    : unsigned(4 downto 0);             -- counts consecutive data packets (max allowed is 18)
    signal s1_hb        : u8(0 to 2);                       -- current header
    signal s1_sb        : sb_array_t;                       -- current set of 4 subpackets
    signal s1_vs        : std_logic;                        -- vertical sync (pipelined from buffered input)
    signal s1_hs        : std_logic;                        -- horizontal sync (pipelined from buffered input)
    signal s1_de        : std_logic;                        -- data (pixel) enable (pipelined from buffered from input)
    signal s1_p         : slv_7_0_t(0 to 2);                -- pixel data (3 channels) (pipelined from buffered input)
    signal s1_enc       : std_logic_vector(1 downto 0);     -- encoding type required
    signal s1_ctl       : std_logic_vector(3 downto 0);     -- CTL bits (indicate preamble type)

                                                            -- HDMI encoding pipeline stage 2...
    signal s2_data      : std_logic;                        -- data period active
    signal s2_pcount    : unsigned(s1_pcount'range);        -- data island character #=
    signal s2_bch4      : std_logic;                        -- BCH block 4 bit
    signal s2_bch_e     : std_logic_vector(3 downto 0);     -- BCH blocks 0-3 even bit
    signal s2_bch_o     : std_logic_vector(3 downto 0);     -- BCH blocks 0-3 odd bit
    signal s2_vs        : std_logic;                        -- vertical sync (pipelined from previous stage)
    signal s2_hs        : std_logic;                        -- horizontal sync (pipelined from previous stage)
    signal s2_de        : std_logic;                        -- data (pixel) enable (pipelined from previous stage)
    signal s2_p         : slv_7_0_t(0 to 2);                -- pixel data (3 channels) (pipelined from previous stage)
    signal s2_enc       : std_logic_vector(1 downto 0);     -- encoding type (pipelined from previous stage)
    signal s2_ctl       : std_logic_vector(3 downto 0);     -- CTL bits (pipelined from previous stage)

                                                            -- HDMI encoding pipeline stage 3...
    signal s3_data      : std_logic;                        -- data period active
    signal s3_pcount    : unsigned(s1_pcount'range);        -- data island character #
    signal s3_bch4      : std_logic;                        -- BCH block 4 bit
    signal s3_bch_e     : std_logic_vector(s2_bch_e'range); -- BCH blocks 0-3 even bit
    signal s3_bch_o     : std_logic_vector(s2_bch_o'range); -- BCH blocks 0-3 odd bit
    signal s3_bch_ecc   : slv_7_0_t(0 to SUBPACKETS);       -- ECC values for header (0) and 4 subpackets (1..4)
    signal s3_vs        : std_logic;                        -- vertical sync (pipelined from previous stage)
    signal s3_hs        : std_logic;                        -- horizontal sync (pipelined from previous stage)
    signal s3_de        : std_logic;                        -- data (pixel) enable (pipelined from previous stage)
    signal s3_p         : slv_7_0_t(0 to 2);                -- pixel data (3 channels) (pipelined from previous stage)
    signal s3_enc       : std_logic_vector(1 downto 0);     -- encoding type (pipelined from previous stage)
    signal s3_ctl       : std_logic_vector(3 downto 0);     -- CTL bits (pipelined from previous stage)

                                                            -- HDMI encoding pipeline stage 4...
    signal s4_vs        : std_logic;                        -- vertical sync (pipelined from previous stage)
    signal s4_hs        : std_logic;                        -- horizontal sync (pipelined from previous stage)
    signal s4_de        : std_logic;                        -- data (pixel) enable (pipelined from previous stage)
    signal s4_p         : slv_7_0_t(0 to 2);                -- pixel data (3 channels) (pipelined from previous stage)
    signal s4_enc       : std_logic_vector(1 downto 0);     -- encoding type (pipelined from previous stage)
    signal s4_ctl       : std_logic_vector(3 downto 0);     -- CTL bits (pipelined from previous stage)
    signal s4_c         : slv_1_0_t(0 to 2);                -- C input to TMDS encoder x 3 channels
    signal s4_d         : slv_3_0_t(0 to 2);                -- aux data input to TMDS encoder x 3 channels

    ----------------------------------------------------------------------
    -- constant packet content

    -- packet type 0: audio clock sample packet
    constant hb_0 : u8(0 to 2) := ( x"02", x"0F", x"00" );

    -- packet type 1: audio clock regeneration packet
    constant hb_1 : u8(0 to 2) := ( x"01", x"00", x"00" );

    -- packet type 2: audio infoframe packet
    -- Fix field values based on HDMI test 7-31 results with N5998A protocol
    -- analyser
    constant hb_2 : u8(0 to 2) := ( x"84", x"01", x"0A" );
    constant pb_2 : u8(0 to 27) := (
            0  => x"70", -- checksum 84+01+0A+01+CKS = 00
            1  => x"01", -- 00000001  CT(3:0),RSVD,CC(2:0)
            2  => x"00", -- 00000000  F(27:25),SF(2:0),SS(1:0)
            3  => x"00", -- 00000000  F(37:35),CXT(4:0)
            4  => x"00", -- 00000000  CA(7:0)
            5  => x"00", -- 00000001  DM_INH,LSV(3:0),F(52),LFEBL(1:0)
            6  => x"00", -- 00000000  F(67:60)
            7  => x"00", -- 00000000  F(77:70)
            8  => x"00", -- 00000000  F(87:80)
            9  => x"00", -- 00000000  F(97:90)
            10 => x"00", -- 00000000  F(107:100)
            others => x"00" -- zero
        );

    -- type 3: AVI infoframe packet
    constant hb_3 : u8(0 to 2) := ( x"82", x"02", x"0D" );
    constant pb_3 : u8(0 to 27) := (
            0 => x"00",     -- *NOT CONSTANT* checksum
            1 => x"12",     -- RSVD,Y(1:0),A0,B(1:0),S(1:0)
            2 => x"00",     -- *PART CONSTANT* C(1:0),M(1:0),R(3:0)
            3 => x"88",     -- ITC,EC(2:0),Q(1:0),SC(1:0)
            4 => x"00",     -- *NOT CONSTANT* VIC
            5 => x"B0",     -- *PART CONSTANT* YQ(1:0),CN(1:0),PR(3:0)
            others => x"00" -- zero
        );

    -- type 4: Source Product Descriptor #1
    constant hb_4 : u8(0 to 2) := ( x"83", x"01", x"19" );
    constant pb_4 : u8(0 to 27) := (
      0 => x"50",     -- checksum
      -- ASCIIZ Vendor (8 bytes): "MEGA65"
      1 => x"4D",
      2 => x"45",
      3 => x"47",
      4 => x"41",
      5 => x"36",
      6 => x"35",
      7 => x"00",
      8 => x"00",
      -- ASCIIZ Product (16 bytes): "MEGA65"
      9 => x"4D",
      10 => x"45",
      11 => x"47",
      12 => x"41",
      13 => x"36",
      14 => x"35",
      15 => x"00",
      16 => x"00",
      -- Source type (1 byte)
      -- Indicate as "Game"
      25 => x"09",
      others => x"00" -- zero
        );

    -- type 5: Source Product Descriptor #2 (test ahead of supporting scrolling
    -- SPD text ;)
    constant hb_5 : u8(0 to 2) := ( x"83", x"01", x"19" );
    constant pb_5 : u8(0 to 27) := (
      0 => x"50",     -- checksum
      -- ASCIIZ Vendor (8 bytes): "MEGA65"
      1 => x"4D",
      2 => x"45",
      3 => x"47",
      4 => x"41",
      5 => x"36",
      6 => x"35",
      7 => x"00",
      8 => x"00",
      -- ASCIIZ Product (16 bytes): "MEGA65"
      9 => x"4D",
      10 => x"45",
      11 => x"47",
      12 => x"41",
      13 => x"36",
      14 => x"35",
      15 => x"00",
      16 => x"00",
      -- Source type (1 byte)
      -- Indicate as "Game"
      25 => x"09",
      others => x"00" -- zero
        );

    function sum( data : u8 ) return unsigned is
        variable r : unsigned(7 downto 0);
    begin
        r := x"00";
        for i in 0 to data'length-1 loop
            r := r + data(i);
        end loop;
        return r;
    end function sum;

    constant sum_3 : unsigned(7 downto 0) := sum( hb_3 & pb_3 );

    ----------------------------------------------------------------------

begin

    -- add IEC60958 channel status to PCM stream

    pcm_cs_v(0) <= '0';              -- consumer use
    pcm_cs_v(1) <= '0';              -- PCM samples
    pcm_cs_v(2) <= '1';              -- no copyright
    pcm_cs_v(3 to 5) <= "000";       -- 2 channels without pre-emphasis
    pcm_cs_v(6 to 7) <= "00";        -- channel status mode 0
    pcm_cs_v(8 to 15) <= "01000000"; -- category code
    pcm_cs_v(16 to 19) <= "0000";    -- source - do not take into account
    pcm_cs_v(20 to 23) <= "0000";    -- channel number - do not take into account
    pcm_cs_v(28 to 29) <= "00";      -- clock accuracy level 2
    pcm_cs_v(30) <= '0';             -- reserved
    pcm_cs_v(31) <= '0';             -- reserved
    pcm_cs_v(32) <= '1';             -- max sample word length is 24 bits
    pcm_cs_v(33 to 35) <= "000";     -- word length not indicated
    pcm_cs_v(36 to 39) <= "0000";    -- original sample frequency not indicated

    process(pcm_rst,pcm_clk)

        variable cs : std_logic;

        function xor_v(v : std_logic_vector) return std_logic is
            variable i : integer;
            variable r : std_logic;
        begin
            r := '0';
            for i in 0 to v'length-1 loop
                r := r xor v(i);
            end loop;
            return r;
        end function xor_v;

    begin
      
        if pcm_rst = '1' then

            iec_count   <= 0;
            iec_sync    <= '0';
            iec_l       <= (others => '0');
            iec_lv      <= '0';
            iec_lu      <= '0';
            iec_lc      <= '0';
            iec_lp      <= '0';
            iec_r       <= (others => '0');
            iec_rv      <= '0';
            iec_ru      <= '0';
            iec_rc      <= '0';
            iec_rp      <= '0';

        elsif rising_edge(pcm_clk) then

          -- Inform sink of the correct audio sample rate
          if select_44100 = '0' then
            pcm_cs_v(24 to 27) <= "0100"; -- 48KHz
          else
            pcm_cs_v(24 to 27) <= "0000"; -- 44.1KHz
          end if;
                    
          if pcm_clken = '1' then
            if iec_count < 40 then
              cs := pcm_cs_v(iec_count);
            else
              cs := '0';
            end if;
                iec_sync <= '0';
                if iec_count = 0 then
                    iec_sync <= '1';
                end if;
                iec_l  <= pcm_l & x"00";
                iec_lv <= '0';
                iec_lu <= '0';
                iec_lc <= cs;
                iec_lp <= xor_v(pcm_l & cs & iec_sync);
                iec_r  <= pcm_r & x"00";
                iec_rv <= '0';
                iec_ru <= '0';
                iec_rc <= cs;
                iec_rp <= xor_v(pcm_r & cs & iec_sync);
                if iec_count = 191 then
                    iec_count <= 0;
                else
                    iec_count <= iec_count+1;
                end if;
                iec_req <= '1';
            elsif iec_ack = '1' then
                iec_req <= '0';
            end if;

        end if;
    end process;

    -- clock domain crossing

    CDC_IEC: xpm_cdc_handshake
        generic map (
            DEST_EXT_HSK   => 0,
            DEST_SYNC_FF   => 4,
            INIT_SYNC_FF   => 0,
            SIM_ASSERT_CHK => 1,
            SRC_SYNC_FF    => 4,
            WIDTH          => 57
        )
        port map (
            src_clk  => pcm_clk,
            src_in(56)   => iec_sync,
            src_in(55)  => iec_rp,
            src_in(54) => iec_rc,
            src_in(53) => iec_ru,
            src_in(52) => iec_rv,
            src_in(51 downto 28) => iec_r,
            src_in(27) => iec_lp,
            src_in(26) => iec_lc,
            src_in(25) => iec_lu,
            src_in(24) => iec_lv,
            src_in(23 downto 0) => iec_l,
            src_send => iec_req,
            src_rcv  => iec_ack,
            dest_clk => vga_clk,
            dest_req => vga_iec_en,
            dest_ack => '0', -- unused
            dest_out => vga_iec_data
    );

    vga_iec_l    <= vga_iec_data(23 downto 0);
    vga_iec_lv   <= vga_iec_data(24);
    vga_iec_lu   <= vga_iec_data(25);
    vga_iec_lc   <= vga_iec_data(26);
    vga_iec_lp   <= vga_iec_data(27);
    vga_iec_r    <= vga_iec_data(51 downto 28);
    vga_iec_rv   <= vga_iec_data(52);
    vga_iec_ru   <= vga_iec_data(53);
    vga_iec_rc   <= vga_iec_data(54);
    vga_iec_rp   <= vga_iec_data(55);
    vga_iec_sync <= vga_iec_data(56);

    CDC_ACR : xpm_cdc_pulse
      generic map (
            DEST_SYNC_FF   => 4,
            INIT_SYNC_FF   => 1,
            REG_OUTPUT     => 0,
            RST_USED       => 1,
            SIM_ASSERT_CHK => 1
            )
      port map (
        src_rst    => pcm_rst,
        src_clk    => pcm_clk,
        src_pulse  => pcm_acr,
        dest_rst   => vga_rst,
        dest_clk   => vga_clk,
        dest_pulse => vga_acr
        );
    

    SYNC : xpm_cdc_array_single
        generic map (
            DEST_SYNC_FF    => 2,
            INIT_SYNC_FF    => 1,
            SIM_ASSERT_CHK  => 1,
            SRC_INPUT_REG   => 0,
            WIDTH           => 54
        )
        port map (
            src_clk                => '0',
            src_in(53 downto 34)   => pcm_n,
            src_in(33 downto 14)   => pcm_cts,
            src_in(13)             => dvi,
            src_in(12 downto 5)    => vic,
            src_in(4 downto 3)     => aspect,
            src_in(2)              => pix_rep,
            src_in(1)              => vs_pol,
            src_in(0)              => hs_pol,
            dest_clk               => vga_clk,
            dest_out(53 downto 34) => pcm_n_s,
            dest_out(33 downto 14) => pcm_cts_s,
            dest_out(13)           => dvi_s,
            dest_out(12 downto 5)  => vic_s,
            dest_out(4 downto 3)   => aspect_s,
            dest_out(2)            => pix_rep_s,
            dest_out(1)            => vs_pol_s,
            dest_out(0)            => hs_pol_s
        );

    -- inject preambles, guardbands and data packets

    vga_vs_p <= vga_vs xnor vs_pol_s;
    vga_hs_p <= vga_hs xnor hs_pol_s;

    process(vga_rst,vga_clk)

        variable buf_rdata  : std_logic_vector(26 downto 0);
        variable p          : integer range 0 to PACKET_TYPES-1;
        variable s1_hb_byte : integer range 0 to 3;
        variable s1_hb_bit  : integer range 0 to 7;
        variable s1_sb_byte : integer range 0 to 7;
        variable s1_sb_2bit : integer range 0 to 3;

        -- BCH ECC functions (see hdmi_bch_ecc.py)
        function bch_ecc_1( -- 1 bit per clock
            q : std_logic_vector(7 downto 0);
            d : std_logic
        ) return std_logic_vector is
            variable r : std_logic_vector(7 downto 0);
        begin
            r(0) := d xor q(0) xor q(1);
            r(1) := d xor q(0) xor q(2);
            r(2) := q(3);
            r(3) := q(4);
            r(4) := q(5);
            r(5) := q(6);
            r(6) := q(7);
            r(7) := d xor q(0);
            return r;
        end function bch_ecc_1;
        function bch_ecc_2( -- 2 bits per clock
            q : std_logic_vector(7 downto 0);
            d : std_logic_vector(1 downto 0)
        ) return std_logic_vector is
            variable r : std_logic_vector(7 downto 0);
        begin
            r(0) := d(1) xor q(1) xor q(2);
            r(1) := d(0) xor d(1) xor q(0) xor q(1) xor q(3);
            r(2) := q(4);
            r(3) := q(5);
            r(4) := q(6);
            r(5) := q(7);
            r(6) := d(0) xor q(0);
            r(7) := d(0) xor d(1) xor q(0) xor q(1);
            return r;
        end function bch_ecc_2;

    begin

        if vga_rst = '1' then

            vga_vs_1    <= '0';
            vga_hs_1    <= '0';
            vga_de_1    <= '0';
            buf_valid   <= false;
            buf_addr    <= 0;
            buf_vs      <= '0';
            buf_hs      <= '0';
            buf_de      <= '0';
            buf_p       <= (others => (others => '0'));
            blank_count <= 0;
            data_req    <= (others => '0');
            data_ack    <= (others => '0');
            hb_a        <= (others => (others => '0'));
            pb_a        <= (others => (others => '0'));
            hb          <= (others => (others => (others => '0')));
            pb          <= (others => (others => (others => '0')));
            s1_period   <= CONTROL;
            s1_pcount   <= (others => '0');
            s1_dcount   <= (others => '0');
            s1_hb       <= (others => (others => '0'));
            s1_sb       <= (others => (others => (others => '0')));
            s1_vs       <= '0';
            s1_hs       <= '0';
            s1_de       <= '0';
            s1_p        <= (others => (others => '0'));
            s1_enc      <= ENC_DVI;
            s1_ctl      <= CTL_NULL;
            s2_data     <= '0';
            s2_pcount   <= (others => '0');
            s2_bch4     <= '0';
            s2_bch_e    <= (others => '0');
            s2_bch_o    <= (others => '0');
            s2_vs       <= '0';
            s2_hs       <= '0';
            s2_de       <= '0';
            s2_p        <= (others => (others => '0'));
            s2_enc      <= ENC_DVI;
            s2_ctl      <= CTL_NULL;
            s3_data     <= '0';
            s3_pcount   <= (others => '0');
            s3_bch4     <= '0';
            s3_bch_e    <= (others => '0');
            s3_bch_o    <= (others => '0');
            s3_bch_ecc  <= (others => (others => '0'));
            s3_vs       <= '0';
            s3_hs       <= '0';
            s3_de       <= '0';
            s3_p        <= (others => (others => '0'));
            s3_enc      <= ENC_DVI;
            s3_ctl      <= CTL_NULL;
            s4_vs       <= '0';
            s4_hs       <= '0';
            s4_de       <= '0';
            s4_p        <= (others => (others => '0'));
            s4_enc      <= ENC_DVI;
            s4_ctl      <= CTL_NULL;
            s4_d        <= (others => (others => '0'));

        elsif rising_edge(vga_clk) then

            vga_vs_1 <= vga_vs_p;
            vga_hs_1 <= vga_hs_p;
            vga_de_1 <= vga_de;

            -- video input buffer for blank counting

            buf_rdata := buf(buf_addr); -- read before write
            buf(buf_addr) <= vga_vs_p & vga_hs_p & vga_de & vga_b & vga_g & vga_r;
            if buf_addr = buf_size-1 then
                buf_addr <= 0;
                buf_valid <= true;
            else
                buf_addr <= buf_addr+1;
            end if;
            if buf_valid = true then
                buf_vs <= buf_rdata(26);
                buf_hs <= buf_rdata(25);
                buf_de <= buf_rdata(24);
                buf_p(0) <= buf_rdata(23 downto 16);
                buf_p(1) <= buf_rdata(15 downto 8);
                buf_p(2) <= buf_rdata(7 downto 0);
            else
                buf_vs <= '0';
                buf_hs <= '0';
                buf_de <= '0';
                buf_p <= (others => (others => '0'));
            end if;
            if buf_valid = true then
                if vga_de_1 = '0' and buf_de = '1' then
                    blank_count <= blank_count+1;
                elsif vga_de_1 = '1' and buf_de = '0' then
                    blank_count <= blank_count-1;
                end if;
            else
                if vga_de_1 = '0' then
                    blank_count <= blank_count+1;
                end if;
            end if;

             -- packet handshaking and contents

            hb_a(0 to 1) <= hb_0(0 to 1);
            hb_a(2)(3 downto 0) <= hb_0(2)(3 downto 0);
            if vga_iec_en = '1' then
                hb_a(2)(pcm_count+4) <= vga_iec_sync;
                pb_a((pcm_count*7)+0) <= unsigned(vga_iec_l(7 downto 0));
                pb_a((pcm_count*7)+1) <= unsigned(vga_iec_l(15 downto 8));
                pb_a((pcm_count*7)+2) <= unsigned(vga_iec_l(23 downto 16));
                pb_a((pcm_count*7)+3) <= unsigned(vga_iec_r(7 downto 0));
                pb_a((pcm_count*7)+4) <= unsigned(vga_iec_r(15 downto 8));
                pb_a((pcm_count*7)+5) <= unsigned(vga_iec_r(23 downto 16));
                pb_a((pcm_count*7)+6) <=
                    vga_iec_rp & vga_iec_rc & vga_iec_ru & vga_iec_rv &
                    vga_iec_lp & vga_iec_lc & vga_iec_lu & vga_iec_lv;
                pcm_count <= (pcm_count + 1) mod 4;
                if pcm_count = 0 then
                    data_req(0) <= '1';
                    hb(0) <= hb_a;
                    pb(0) <= pb_a;
                end if;
            end if;

            if vga_acr = '1' then
                data_req(1) <= '1';
            end if;
            hb(1) <= hb_1;
            pb(1) <= (others => x"00");
            for i in 0 to 3 loop
                pb(1)((i*7)+1) <= x"0" & unsigned(pcm_cts_s(19 downto 16));
                pb(1)((i*7)+2) <= unsigned(pcm_cts_s(15 downto 8));
                pb(1)((i*7)+3) <= unsigned(pcm_cts_s(7 downto 0));
                pb(1)((i*7)+4) <= x"0" & unsigned(pcm_n_s(19 downto 16));
                pb(1)((i*7)+5) <= unsigned(pcm_n_s(15 downto 8));
                pb(1)((i*7)+6) <= unsigned(pcm_n_s(7 downto 0));
            end loop;

            if vga_vs_p = '1' and vga_vs_1 = '0' then -- once per field
              data_req(2) <= '1';
            end if;
            hb(2) <= hb_2;
            pb(2) <= pb_2;

            -- XXX Only check for falling edge on VSYNC, as HSYNC may not be
            -- synchronised to VSYNC, depending on the video mode
            if vga_vs_p = '1' and vga_vs_1 = '0' then --  and vga_hs_p /= vga_hs_1 then -- once per frame
              data_req(3) <= '1';
              -- Send approximately once per second.
              -- XXX Try sending two different versions to see if we can do
              -- animated SPD :)
              if spd_toggle="000000" then
                data_req(4) <= '1';
              end if;
              if spd_toggle="100000" then
                data_req(5) <= '1';
              end if;
              spd_toggle <= spd_toggle + 1;
            end if;
            hb(3) <= hb_3;
            pb(3)(0 to 5) <= pb_3(0 to 5);
            pb(3)(0) <= -- checksum
                1 + not (
                    sum_3 +
                    pb(3)(2) +
                    pb(3)(4) +
                    pb(3)(5)(3 downto 0)
                );
            pb(3)(2)(5 downto 4) <= unsigned(aspect_s);
            pb(3)(2)(3) <= '1';
            pb(3)(2)(1 downto 0) <= unsigned(aspect_s);
            pb(3)(4) <= unsigned(vic_s);
            pb(3)(5)(0) <= pix_rep_s;
            pb(3)(6 to 27) <= pb_3(6 to 27);

            hb(4) <= hb_4;
            pb(4) <= pb_4;

            hb(5) <= hb_5;
            pb(5) <= pb_5;
            
            for i in 0 to PACKET_TYPES-1 loop
                if data_ack(i) = '1' then
                    data_req(i) <= '0';
                end if;
                if data_req(i) = '0' then
                    data_ack(i) <= '0';
                end if;
            end loop;

            -- HDMI encoding pipeline stage 1

            if s1_pcount /= "11111" then
                s1_pcount <= s1_pcount+1;
            end if;

            case s1_period is

                when CONTROL =>
                    if buf_de = '0' then
                        if vga_de = '1' and blank_count = 10 then -- counting down to video
                            s1_period <= VIDEO_PRE; s1_enc <= ENC_DVI; s1_ctl <= CTL_PRE_VIDEO;
                            s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                        elsif unsigned(s1_pcount) >= 11 and blank_count >= 66 then
                            -- we have satisfied 12 clock minimum for a control period;
                            -- to safely insert a data packet we need time for the following:
                            -- clocks   period
                            -- 8        data preamble
                            -- 2        data guardband
                            -- 32       single data packet
                            -- 2        data guardband
                            -- 12       minimum control period
                            -- 2        video preamble
                            -- 8        video guardband
                            -- total: 66
                            if data_req /= "000000" then
                                s1_period <= DATA_PRE; s1_enc <= ENC_DVI; s1_ctl <= CTL_PRE_DATA;
                                s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                                for i in 0 to (PACKET_TYPES-1) loop -- prioritize
                                    p := i;
                                    exit when data_req(p) = '1';
                                end loop;
                                data_ack(p) <= '1';
                                s1_hb <= hb(p);
                                s1_sb(0) <= pb(p)(0 to 6);
                                s1_sb(1) <= pb(p)(7 to 13);
                                s1_sb(2) <= pb(p)(14 to 20);
                                s1_sb(3) <= pb(p)(21 to 27);
                            end if;
                        end if;
                    end if;

                when VIDEO_PRE =>
                    if s1_pcount(2 downto 0) = "111" then
                        s1_period <= VIDEO_GB; s1_enc <= ENC_GB_VIDEO; s1_ctl <= CTL_NULL;
                        s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                    end if;

                when VIDEO_GB =>
                    if s1_pcount(0) = '1' then
                        s1_period <= VIDEO; s1_enc <= ENC_DVI; s1_ctl <= CTL_NULL;
                        s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                    end if;

                when VIDEO =>
                    if buf_de = '0' then
                        s1_period <= CONTROL; s1_enc <= ENC_DVI; s1_ctl <= CTL_NULL;
                        s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                    end if;

                when DATA_PRE =>
                    if s1_pcount(2 downto 0) = "111" then
                        s1_period <= DATA_GB_LEADING; s1_enc <= ENC_GB_DATA; s1_ctl <= CTL_NULL;
                        s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                    end if;

                when DATA_GB_LEADING =>
                    if s1_pcount(0) = '1' then
                        s1_period <= DATA_ISLAND; s1_enc <= ENC_DATA; s1_ctl <= CTL_NULL;
                        s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                    end if;

                when DATA_ISLAND =>
                    if (s1_pcount = "11111") then   -- last clock of this packet
                        if  (blank_count >= 56)     -- there is enough blanking time for another packet
                        and (s1_dcount < 17)        -- we haven't exceeded the limit of 18 consecutive packets
                        and (data_req /= "000000")    -- another packet is requested
                        then -- do another data packet
                            s1_pcount <= (others => '0');
                            s1_dcount <= s1_dcount+1;
                            for i in 0 to (PACKET_TYPES-1) loop -- prioritize
                                p := i;
                                exit when data_req(p) = '1';
                            end loop;
                            data_ack(p) <= '1';
                            s1_hb <= hb(p);
                            s1_sb(0) <= pb(p)(0 to 6);
                            s1_sb(1) <= pb(p)(7 to 13);
                            s1_sb(2) <= pb(p)(14 to 20);
                            s1_sb(3) <= pb(p)(21 to 27);
                        else -- wrap up
                            s1_period <= DATA_GB_TRAILING; s1_enc <= ENC_GB_DATA; s1_ctl <= CTL_NULL;
                            s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                        end if;
                    end if;

                when DATA_GB_TRAILING =>
                    if s1_pcount(0) = '1' then
                        s1_period <= CONTROL; s1_enc <= ENC_DVI; s1_ctl <= CTL_NULL;
                        s1_pcount <= (others => '0'); s1_dcount <= (others => '0');
                    end if;

            end case;

            s1_hb_byte  := to_integer(unsigned(s1_pcount(4 downto 3)));
            s1_hb_bit   := to_integer(unsigned(s1_pcount(2 downto 0)));
            s1_sb_byte  := to_integer(unsigned(s1_pcount(4 downto 2)));
            s1_sb_2bit  := to_integer(unsigned(s1_pcount(1 downto 0)));

            s1_vs  <= buf_vs;
            s1_hs  <= buf_hs;
            s1_de  <= buf_de;
            s1_p   <= buf_p;

            -- HDMI encoding pipeline stage 2

            s2_data <= '0';
            if s1_period = DATA_ISLAND then
                s2_data <= '1';
            end if;
            s2_pcount <= s1_pcount;
            s2_bch4 <= '0';
            if s1_hb_byte < s1_hb'length then
                s2_bch4 <= s1_hb(s1_hb_byte)(s1_hb_bit);
            end if;
            for i in 0 to 3 loop
                s2_bch_e(i) <= '0';
                s2_bch_o(i) <= '0';
                if s1_sb_byte < s1_sb(i)'length then
                    s2_bch_e(i) <= s1_sb(i)(s1_sb_byte)(0+(2*s1_sb_2bit));
                    s2_bch_o(i) <= s1_sb(i)(s1_sb_byte)(1+(2*s1_sb_2bit));
                end if;
            end loop;

            s2_vs  <= s1_vs;
            s2_hs  <= s1_hs;
            s2_de  <= s1_de;
            s2_p   <= s1_p;
            s2_enc <= s1_enc;
            s2_ctl <= s1_ctl;

            -- HDMI encoding pipeline stage 3

            s3_data <= s2_data;
            s3_pcount <= s2_pcount;
            s3_bch4 <= s2_bch4;
            s3_bch_e <= s2_bch_e;
            s3_bch_o <= s2_bch_o;
            if unsigned(s2_pcount(4 downto 0)) = 0 then
                s3_bch_ecc(4) <= bch_ecc_1(x"00",s2_bch4);
            elsif unsigned(s2_pcount(4 downto 0)) < 24 then
                s3_bch_ecc(4) <= bch_ecc_1(s3_bch_ecc(4),s2_bch4);
            end if;
            for i in 0 to 3 loop
                if unsigned(s2_pcount(4 downto 0)) = 0 then
                    s3_bch_ecc(i) <= bch_ecc_2(x"00",s2_bch_o(i) & s2_bch_e(i));
                elsif unsigned(s2_pcount(4 downto 0)) < 28 then
                    s3_bch_ecc(i) <= bch_ecc_2(s3_bch_ecc(i),s2_bch_o(i) & s2_bch_e(i));
                end if;
            end loop;

            s3_vs  <= s2_vs;
            s3_hs  <= s2_hs;
            s3_de  <= s2_de;
            s3_p   <= s2_p;
            s3_enc <= s2_enc;
            s3_ctl <= s2_ctl;

            -- HDMI encoding pipeline stage 4

            s4_d <= (others => (others => '0'));
            if s3_data = '1' then
                s4_d(0)(0) <= s3_hs;
                s4_d(0)(1) <= s3_vs;
                if unsigned(s3_pcount(4 downto 0)) < 24 then
                    s4_d(0)(2) <= s3_bch4;
                else
                    s4_d(0)(2) <= s3_bch_ecc(4)(to_integer(unsigned(s3_pcount(2 downto 0))));
                end if;
                if unsigned(s3_pcount) = 0 then
                    s4_d(0)(3) <= '0';
                else
                    s4_d(0)(3) <= '1';
                end if;
                if unsigned(s3_pcount(4 downto 0)) < 28 then
                    s4_d(1) <= s3_bch_e;
                    s4_d(2) <= s3_bch_o;
                else
                    for i in 0 to 3 loop
                        s4_d(1)(i) <= s3_bch_ecc(i)(0+(2*to_integer(unsigned(s3_pcount(1 downto 0)))));
                        s4_d(2)(i) <= s3_bch_ecc(i)(1+(2*to_integer(unsigned(s3_pcount(1 downto 0)))));
                    end loop;
                end if;
            end if;

            s4_vs  <= s3_vs;
            s4_hs  <= s3_hs;
            s4_de  <= s3_de;
            s4_p   <= s3_p;
            s4_enc <= s3_enc;
            s4_ctl <= s3_ctl;

            -- DVI override

            if dvi_s = '1' then
                s4_enc <= ENC_DVI;
                s4_ctl <= (others => '0');
                s4_d <= (others => (others => '0'));
            end if;

        end if;

     end process;

    -- final encoder and serialiser stage

    s4_c(0)(0) <= s4_hs;
    s4_c(0)(1) <= s4_vs;
    s4_c(1) <= s4_ctl(1 downto 0);
    s4_c(2) <= s4_ctl(3 downto 2);

    GEN_TMDS: for i in 0 to 2 generate
    begin
        ENCODER: entity work.hdmi_tx_encoder
            generic map (
                channel => i
            )
            port map (
                rst     => vga_rst,
                clk     => vga_clk,
                de      => s4_de,
                p       => s4_p(i),
                c       => s4_c(i),
                d       => s4_d(i),
                enc     => s4_enc,
                q       => tmds(i)
            );
    end generate GEN_TMDS;

end architecture synth;
