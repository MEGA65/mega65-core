BasicUpstart2(start)
//---------------------------------------------------------
//---------------------------------------------------------
//			SID Player (Single speed)
//---------------------------------------------------------
//---------------------------------------------------------
			.var music = LoadSid("Nightshift.sid")		//<- Here we load the sid file

start:		lda #$00
			sta $d020
			sta $d021
			ldx #0
			ldy #0
			lda #music.startSong-1						//<- Here we get the startsong and init address from the sid file
			jsr music.init	
			sei
			lda #<irq1
			sta $0314
			lda #>irq1
			sta $0315
			lda #$1b
			sta $d011
			lda #$80
			sta $d012
			lda #$7f
			sta $dc0d
			sta $dd0d
			lda #$81
			sta $d01a
			lda $dc0d
			lda $dd0d
			asl $d019
			cli
			jmp *

//---------------------------------------------------------
irq1:  	    asl $d019
			inc $d020
			jsr music.play 									// <- Here we get the play address from the sid file
			dec $d020
			jmp $ea81

//---------------------------------------------------------
			*=music.location "Music"
			.fill music.size, music.getData(i)				// <- Here we put the music in memory

//----------------------------------------------------------
			// Print the music info while assembling
			.print ""
			.print "SID Data"
			.print "--------"
			.print "location=$"+toHexString(music.location)
			.print "init=$"+toHexString(music.init)
			.print "play=$"+toHexString(music.play)
			.print "songs="+music.songs
			.print "startSong="+music.startSong
			.print "size=$"+toHexString(music.size)
			.print "name="+music.name
			.print "author="+music.author
			.print "copyright="+music.copyright

			.print ""
			.print "Additional tech data"
			.print "--------------------"
			.print "header="+music.header
			.print "header version="+music.version
			.print "flags="+toBinaryString(music.flags)
			.print "speed="+toBinaryString(music.speed)
			.print "startpage="+music.startpage
			.print "pagelength="+music.pagelength
