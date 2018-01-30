;===============================================================================
;Option list definitions
;-----------------------
;
;Configuration option lists definitions.
;
;
;Using the option lists
;----------------------
;
;The input options are defined by a type and a list of details for that type.  
;They usually have an offset and flag byte followed by a set of pascal-style   
;strings.  The option is defined in the type byte high nybble and the low nybble 
;used to set the current value (except for string and button input types, see 
;below).  Pascal strings are used to speed up various operations (list 
;traversal, on-screen manipulation).  Use .defPStr to declare a Pascal string.
;
;The options are defined in a list for each page and grouped under six tabs.
;Each list is therefore an on-screen page worth of options and can be navigated
;by the user.  Each list must be a maximum of 256 bytes due to a limitation in
;the current implementation.  This limitation is checked with compile asserts.
;
;Each page (or list) is defined to belong to one of six tabs, as already 
;mentioned.  These tabs are:  System, Disk, Video, Audio, Network and Save.  
;The Save tab options must not be changed as the code relies on them being 
;defined in a particular way (although the text of the buttons can be changed).
;
;The pages are listed in an index for each tab such that the code can traverse
;the lists as defined here.  The number of pages in a tab must also be defined.
;
;Furthermore, two magic bytes are defined here to determine the system version
;compatibility.
;
;
;The input types are:
;	00	-	end of list, no data bytes
;	10	-	button, requires 1 string: label
;	20	-	option (on/off, one of two enabled)
;			followed by word offset and byte flags
;			requires 3 strings:  label, option unset, option set.
;	30	-	string input.
;			followed by word offset and byte for string 
;			length requires 1 string:  label
;			requires data area of string length for storage.
;			input string will be null or length terminated.
;	40	- 	Blank line, no data
;	50	-	MAC Address input.  requires 1 string (label), word
;			offset and data	area of 6 bytes for storage of address.
;	
;===============================================================================


;-------------------------------------------------------------------------------
configMagicByte0	=	$01
configMagicByte1	=	$01
;-------------------------------------------------------------------------------
	


;-------------------------------------------------------------------------------
;System tab
;-------------------------------------------------------------------------------
systemPageCnt	=	1
	
systemOptions0:
	.byte		$20			;option input type
	.word		$0005			;offset into config table
	.byte		$01			;bits for testing/setting
	.defPStr	"joystick 2 amiga mouse mode:"	;label
	.defPStr	'normal'		;option unset
	.defPStr	"1351 emulation"	;option set

	.byte		$20			;option input type
	.word		$0005			;offset into config table
	.byte		$08			;bits for testing/setting
	.defPStr	"joystick 1 amiga mouse detection:"	;label
	.defPStr	'conservative'		;option unset
	.defPStr	"aggressive"	;option set

	.byte		$20			;option input type
	.word		$0005			;offset into config table
	.byte		$02			;bits for testing/setting
	.defPStr	"joystick 1 amiga mouse mode:"	;label
	.defPStr	'normal'		;option unset
	.defPStr	"1351 emulation"	;option set

	.byte		$20			;option input type
	.word		$0005			;offset into config table
	.byte		$04			;bits for testing/setting
	.defPStr	"joystick 2 amiga mouse detection:"	;label
	.defPStr	'conservative'		;option unset
	.defPStr	"aggressive"	;option set


	.byte		$00			;end of list type
systemOptions0_end:
	.assert		(systemOptions0_end - systemOptions0) < 256, error, "System Options too large!"

systemPageIndex:
	.word		systemOptions0
	

;-------------------------------------------------------------------------------
;Disk tab
;-------------------------------------------------------------------------------
diskPageCnt 	=	1

diskOptions0:
	.byte		$20			;option input type
	.word		$0004			;offset into config table
	.byte		$01			;bits for testing/setting
	.defPStr	"f011 disk controller:"	;label
	.defPStr	"uses sdcard disk image";option unset
	.defPStr	'uses 3.5" floppy drive';option set

	.byte		$30			;string input type
	.word		$0010			;offset into config table
	.byte		$10			;input string length
	.defPStr	"default disk image:"	;label
	
	.byte		$00, $00, $00, $00	;storage for value
	.byte		$00, $00, $00, $00
	.byte		$00, $00, $00, $00
	.byte		$00, $00, $00, $00

	.byte		$00			;end of list type
diskOptions0_end:
	.assert		(diskOptions0_end - diskOptions0) < 256, error, "Disk Options 0 too large!"

diskPageIndex:
	.word		diskOptions0
	
	
;-------------------------------------------------------------------------------
;Video tab
;-------------------------------------------------------------------------------
videoPageCnt	=	1

videoOptions0:
	.byte		$20
	.word		$0002
	.byte		$80
	.defPStr	"video mode:"
	.defPStr	"pal  50hz (800*600)"
	.defPStr	"ntsc 60hz (800*600)"
	.byte		$00
videoOptions0_end:
	.assert		(videoOptions0_end - videoOptions0) < 256, error, "Video Options 0 too large!"

videoPageIndex:
	.word		videoOptions0


;-------------------------------------------------------------------------------
;Audio tab
;-------------------------------------------------------------------------------
audioPageCnt	=	1

audioOptions0:
	.byte		$20
	.word		$0003
	.byte		$40
	.defPStr	"audio output:"
	.defPStr	"stereo"
	.defPStr	"mono"

	.byte		$20
	.word		$0003
	.byte		$20
	.defPStr	"swap stereo channels:"
	.defPStr	"no"
	.defPStr	"yes"

	.byte		$20
	.word		$0003
	.byte		$80
	.defPStr	"dac algorithm:"
	.defPStr	"pdm"
	.defPStr	"pwm"


	.byte		$20
	.word		$0003
	.byte		$01
	.defPStr	"audio amplifier:"
	.defPStr	"off"
	.defPStr	"on"

	.byte		$00
audioOptions0_end:
	.assert		(audioOptions0_end - audioOptions0) < 256, error, "Audio Options 0 too large!"
	
audioPageIndex:
	.word		audioOptions0


;-------------------------------------------------------------------------------
;Network tab
;-------------------------------------------------------------------------------
networkPageCnt	=	1

networkOptions0:
	.byte		$50
	.word		$0006
	.defPStr	"mac address:"
	.byte		$00, $00, $00, $00, $00, $00
	.byte		$00
networkOptions0_end:
	.assert		(networkOptions0_end - networkOptions0) < 256, error, "Network Options 0 too large!"

networkPageIndex:
	.word		networkOptions0


;-------------------------------------------------------------------------------
;Save tab
;-------------------------------------------------------------------------------
savePageCnt	=	1

;*******************************************************************************
;Do not change the order or number of options in these lists!
;*******************************************************************************
saveOptions0:
	.byte		$10
	.defPStr	"exit without saving"
	.byte		$10
	.defPStr	"apply settings now"
	.byte		$10
	.defPStr	"save for this boot and exit"
	.byte		$10
	.defPStr	"save as defaults and exit"
	.byte		$00
	
saveOptions1:
	.byte		$40
	.byte		$40
	.byte		$40
	.byte		$10
	.defPStr	"cancel"
	.byte		$10
	.defPStr	"ok"
	.byte		$00
	
saveOptions2:
	.byte		$00
	
savePageIndex:
	.word		saveOptions0, saveOptions1, saveOptions2
