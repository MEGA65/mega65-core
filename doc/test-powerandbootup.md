## Power and BOOT-up

* Power up the board:  
ensure that the host-PC is providing power through the USB cable, and that the POWER switch is ON.  
-> Host-PC should show some output generated from the SerialDebugger.  
-> Boot sequence is: approx 3-secs of boot-display (black screen with white text), then falls into c65 mode.  
-> verify that the VGA screen shows the same as below:  
![alt tag](https://raw.githubusercontent.com/Ben-401/mega65pics/master/c65mode.jpg)  

* Reset the board:  
press and release the "CPU_RESET" button.  
-> during the approx 3-secs of boot-display, the LCD should display ``4800 4502``.  
-> when in c65 mode, the LCD should display ``0400 4502``.  

* reprogram the board:  
press and release the "PROG" button.  
-> (results are the same as the above test)  
-> during the approx 3-secs of boot-display, the LCD should display ``4800 4502``.  
-> when in c65 mode, the LCD should display ``0400 4502``.  

* hold the boot-screen:  
assert SW-15 (switch 15 on the far LHS) by pushing it UP,  
press and release the "PROG" button.  
-> boot screen should be displayed,  
-> after boot-up, a message at the top of the screen should be displayed "RELEASE SW-15 TO CONTINUE BOOTING."  
-> verify the text of the boot-screen is similar to the below:  
![alt tag](https://raw.githubusercontent.com/Ben-401/mega65pics/master/bootscreen.jpg)  

* display debug output:  
assert SW-15 and SW-12 by pushing them UP/ON,  
press and release the "PROG" button.  
-> boot screen should be displayed,  
-> during boot, a number of text lines will be displayed (and sent via serial-cooms to the host-PC),  
-> after boot-up, a message at the top of the screen should be displayed "RELEASE SW-15 TO CONTINUE BOOTING."  
-> verify the text of the boot-screen is similar to the below:  
[pic-sw1512 (with debug)]  
-> verify the text of the serial-comms is similar to the below:  
```
here is some text...  
and more  
and last.
```  
release SW-15 by pushing it DOWN/OFF,  
-> boot-screen should disappear and c65 mode presented,  
-> serial comms should display:  
```
here is some text  
```  


The End.
