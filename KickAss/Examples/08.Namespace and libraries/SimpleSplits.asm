#import "Libs/MyStdLibs.lib"

BasicUpstart2(start)
//------------------------------------------
start: 
		ClearScreen($0400, ' ')
		mov #LIGHT_GRAY : $d021
		setupIrq #$32 : #irq1
		jmp *
		
//------------------------------------------
irq1:	irqStart
		pause #32
		mov #DARK_GRAY : $d020
		irqEnd #$32+25*8 : #irq2 
//------------------------------------------
irq2:	irqStart
		pause #32
		mov #GRAY : $d020
		irqEnd #$32 : #irq1 
		

//We can't see the help-functions like _16bit_nextArgument since it inside a namespace 
.asserterror "Testing function visibility", _16bit_nextArgument($1234)  
		