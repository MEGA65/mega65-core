/**********************************************
		Simple script demo
************************************************/

.print "Hello World!"				// <- .print outputs to the console
.print ""

.print "Lets do a countdown:"
.for (var i=10; i>0; i--)			// <- For and while loops works like in other programming languages
	.print i
.print ""


.var x = 10.5						// <- This is how we define variables (we also did it in the for-loop)			
.const y = 3						// <- y is a constant 
.print "x*y-5=" + (x*y-5)
.print ""

.var list = List().add("Bill", "Joe", "Edgar")		// <- We can also use structures like lists and hashtables
.print "Who is at place number 2:" + list.get(2)
.print ""


// Several commands can be written on the same line by using ';'
.var a = 10; .var b = 20; .var c = sqrt(pow(a,2)+ pow(b,2))			// <- We also have the entire java math library
.print "Pythagoras says that c is " + c
.print ""

.print "Sinus:"
.var i=0;
.var spaceStr = "                          ";
.while (i++<10) {
	.var x = 5+5*sin(i*2*PI/10)
	.print spaceStr.substring(0,x)+"o"	
}






