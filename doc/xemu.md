## This is the 'xemu' documentation file.

# Table of Contents:

[Introduction](#introduction)  
[Installation](#installation)  
[Setup](#setup)  

## Introduction

An emulator for the mega65 has been developed. Refer to the following websites:  

1. https://github.com/MEGA65/xemu  (currently unsupported)  
1. https://github.com/lgblgblgb/xemu

This emulator can be used to emulate the C65 ROM and provide some 'mega65' functionality.  

The primary Installation Instructions are available on the web, refer to the above two websites for these details.  

It is recommended that you clone/install the xemu directory into the same toplevel directory as the other mega-related projects. We call this toplevel directory ```$GIT_ROOT```.  

## Installation

The following installation instructions assume a vanilla install of Ubuntu 15.04 or similar. This guide was developed using Ubuntu 15.05 within a VM within OSX on a MacBookPro.  

Please read *all* instructions before doing anything on your keyboard.  

Install ```git``` if not already installed:

```
$> sudo apt-get install git
```

Get into the toplevel development directory. This will/may become important when we start linking between the xemu and the mega65-core projects. The current toplevel working directory may look like this:

```
$> cd $GIT_ROOT
$GIT_ROOT$> ls -al
total 24
drwxrwxr-x  4 user user  4096 Dec 23 13:49 .
drwxrwxr-x 12 user user 12288 Jan 22 19:34 ..
drwxrwxr-x  8 user user  4096 Jan  7 21:00 mega65-core
drwxrwxr-x  8 user user  4096 Jan  1 04:33 m65dbg
drwxrwxr-x 10 user user  4096 Dec 23 13:49 Ophis
$GIT_ROOT$>
```

download the repository from github

```
$GIT_ROOT$> git clone https://github.com/lgblgblgb/xemu.git
```

The xemu project contains many emulators, but we only care about the ```c65``` and ```mega65``` emulator targets.  
If you ```make``` in the toplevel directory, an attempt to make all targets will be made, as shown below.

```
$GIT_ROOT$> cd xemu
$GIT_ROOT/xemu$> make
```

The above command will make all the targets, including "vic20", "c64", c65", "mega65", etc...  
We just want the "mega65" target made, so you can just make that by:

```
$GIT_ROOT/xemu$> cd targets
$GIT_ROOT/xemu/targets$> cd mega65
$GIT_ROOT/xemu/targets/mega65$> make
```

See below regarding errors.  

NOTE: when making the application, it may complain about not having the "SDL2" libraries. If this is the case follow the steps below.  

To see if the SDL2 libraries are installed, type:

```
$GIT_ROOT/xemu$> sdl2-config --version
```

To install the SDL2 libraries:

1. in a browser, download the source at https://www.libsdl.org/release/SDL2-2.0.5.tar.gz  
this will be saved in ~/Downloads
enter the following commands:
1. ```cd ~/Downloads/```
1. ```tar xvfz SDL2-2.0.5.tar.gz```
1. ```cd SDL2-2.0.5/```
1. ```mkdir build```
1. ```cd build```
1. ```../configure```
1. ```grep MISSING config.status```  
NOTE: see below regarding the above command, ie re VM
1. ```make```
1. ```sudo make install```

NOTE: that i tried ```sudo apt-get install libsdl2 TAB TAB -> libsdl2-2.0-0``` but only version 2.0.0 would realise even after ```sudo apt-get update && sudo apt-get upgrade```.  
NOTE: that i tried ```sudo apt-get install libsdl2-dev``` but only version 2.0.2 would realise even after ```sudo apt-get update && sudo apt-get upgrade```.  

At this point, we assume that SDL2 is installed (at least version 2.0.4).  

We also need to download the ROMS, do that by:  

```
$GIT_ROOT/xemu$> make roms
```
The above command will download the proprietry roms from the zimmers website.

At this point, make sure that the xemu application is made, ie:
```
$GIT_ROOT/xemu/targets/mega65$> make
```

After the xemu application is made, and roms are downloaded, you can try and run the mega65-emulator using:
```
$GIT_ROOT/xemu$> ./build/bin/xmega65.native
```

NOTE: it may complain about "Cannot initialise SDL: No available video device". This is likely due to the use of a VirtualMachine. If this is the case follow the steps below:

1. ```sudo apt-get install xorg-dev```  
NOTE that you will now need to reconfigure/rebuild/reinstall the SDL2 packages as done above.  
NOTE that you will also see that the "grep MISSING" should now make sense.
1. ```cd ~/Downloads/SDL2-2.0.5/build```
1. ```../configure```
1. ```grep MISSING config.status``` (NOTE: 'MISSING' will now NOT be found)  
1. ```make```
1. ```sudo make install```

Rerunning the xemu should now work, atleast in part.

A graphical screen should now appear with some dialogs, as well as console-output, but then it will ERROR and exit.

An error may be "No SD-Card image called 'mega65.img' was found". If this is the case, goto the following site and download a known-to-be good working version of the SD-image file.  
https://raw.githubusercontent.com/lgblgblgb/xemu/gh-pages/files/sd-card-image-for-xemu-xmega65.img.gz  
Again, the downloaded file should be placed into the ```~/Downloads``` directory.  

move the downloaded zip-file to the xemu directory, then unzip and rename it:
```
$GIT_ROOT/xemu$> mv ~/Downloads/sd-card-image-for-xemu-xmega65.img.gz .
$GIT_ROOT/xemu$> gunzip sd-card-image-for-xemu-xmega65.img.gz 
$GIT_ROOT/xemu$> mv sd-card-image-for-xemu-xmega65.img mega65.img
```

Then re-run the xemu application

```
$GIT_ROOT/xemu$> ./build/bin/xmega65.native
```

NOTE: that at the time of writing this, the source-repository at "https://github.com/lgblgblgb/xemu" contains a more mature version of the emulator. Infact, not only does it emulate the mega65 but also emulates other 8-bit processors.
One of the processors it emulates is the 'ep128', and the source code relies on having the GTK3 libraries installed. If you dont have the GTK3 libraries installed, then the ```make``` at the toplevel xemu directory will fail because the 'ep128' target cannot find the GTK3 libraries.  
So, to avoid the ```make``` failing, it is recommended to only ```make``` the mega65 target as described above,  
ie: ```$GIT_ROOT/xemu/targets/mega65$> make```

## setup

The current version of the emulator has a built-in KICKSTART file. If you want to have the emulator execute your own local version of KICKSTART, then place a copy of ```KICKUP.M65``` in one of the directories searched (view the console-output).  

You may also like to embed KICKSTART into the SD-Card image-file called ```mega65.img```. Details of this are not provided at this stage.

The End.
