:BasicUpstart2(start)
//--------------------------------------------------------------------------
//--------------------------------------------------------------------------
//  					KOALA SHOWER
//
//This code displays the Koala picture in the file picture.prg
//--------------------------------------------------------------------------
//--------------------------------------------------------------------------
			.var picture = LoadBinary("picture.prg", BF_KOALA)

start:  	lda #$38
			sta $d018
			lda #$d8
			sta $d016
			lda #$3b
			sta $d011
			lda #BLACK
			sta $d020
			lda #picture.getBackgroundColor()
			sta $d021
			ldx #0

loop1:		.for (var i=0; i<4; i++) {
				lda colorRam+i*$100,x
				sta $d800+i*$100,x
			}
			inx
			bne loop1
			jmp *

*=$0c00	"ScreenRam"; 			.fill picture.getScreenRamSize(), picture.getScreenRam(i)
*=$1c00	"ColorRam:"; colorRam: 	.fill picture.getColorRamSize(), picture.getColorRam(i)
*=$2000	"Bitmap";				.fill picture.getBitmapSize(), picture.getBitmap(i)




