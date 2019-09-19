BasicUpstart2(start)
//--------------------------------------------------------------------------
//--------------------------------------------------------------------------
// 			Graphic conversion with FloydSteinberg
//--------------------------------------------------------------------------
//--------------------------------------------------------------------------

start:	sei
		lda #$3b
		sta $d011
		lda #$18
		sta $d018
		lda #BLACK
		sta $d020
		ldx #0
		lda #BLACK | (WHITE<<4)
loop:	sta $0400,x
		sta $0500,x
		sta $0600,x
		sta $0700,x
		inx
		bne loop
		jmp *

		*=$2000 "Picture"
		.var pic1 = floydSteinberg("camel.jpg")
		.fill 40*200, pic1.get(i)


//--------------------------------------------------------------------------

.function floydSteinberg(filename) {
	.var width = 320
	.var height = 200

	.var picture = LoadPicture(filename)

	// Create intensity map
	.var intensityMap = List();
	.var maxInt = $0;
	.var minInt = $ffffff
	.for (var y=0; y<height; y++) {
		.for (var x=0; x<width; x++) {
			.var rgb = picture.getPixel(x,y)
			.var intensity = sqrt(pow(rgb&$ff,2) + pow((rgb>>8)&$ff,2) + pow((rgb>>16)&$ff,2))
			.eval intensityMap.add(intensity)
			.eval maxInt = max(maxInt, intensity)	
			.eval minInt = min(minInt, intensity)	
		}
		.eval intensityMap.add(0)	// Add extra colunn to catch overflow	
	}
	.for (var x=0; x<width+1; x++) 
		.eval intensityMap.add(0)	// Add extra row to catch overflow

	// Do Floyd-Steinberg dithering
	.var limit = (maxInt+minInt)/2
	.for (var y=0; y<height; y++) {
		.for (var x=0; x<width; x++) {
			.var int = intensityMap.get(x+y*(width+1))
			.var selectedPixel = int < limit ? 0 : 1
			.var selectedIntensity = int < limit ? minInt : maxInt
			.var error = int - selectedIntensity
			.eval intensityMap.set(x+y*(width+1), selectedPixel)

			.var idx;
			.eval idx = (x+1)+(y+0)*(width+1)
			.eval intensityMap.set(idx, intensityMap.get(idx) + error *7/16)
			.eval idx = (x-1)+(y+1)*(width+1)
			.eval intensityMap.set(idx, intensityMap.get(idx) + error *3/16)
			.eval idx = (x+0)+(y+1)*(width+1)
			.eval intensityMap.set(idx, intensityMap.get(idx) + error *5/16)
			.eval idx = (x+1)+(y+1)*(width+1)
			.eval intensityMap.set(idx, intensityMap.get(idx) + error *1/16) 
		}
	}
	
	// Convert to byteStream
	.var result = List()
	.for (var charY=0; charY<25; charY++) {
		.for (var charX=0; charX<40; charX++) {
			.for (var charRow=0;charRow<8; charRow++) {
				.var byte = 0
				.var idx = charX*8 + (charY*8+charRow)*(width+1)
				.for (var pixelNo=0;pixelNo<8; pixelNo++)
					.eval byte=byte*2+intensityMap.get(idx+pixelNo)
				.eval result.add(byte)			
			}
		}
	}
	.return result
}





