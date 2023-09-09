# Building mega65-core

This document describes how to build the MEGA65 core. The Linux operating system is strongly recommended for the best experience. These instructions assume some familiarity with the Linux command line.

For assistance with these steps, ask in the [MEGA65 Discord](https://mega65.org/chat).

## Installing support software

The build process requires a set of tools and libraries common to most Linux distributions. You can ensure that all of the needed tools are installed with a command such as this one for Ubuntu Linux:

```
sudo apt install build-essential python3 libpng-dev libncurses5-dev \
                 libtinfo5 libusb-1.0-0-dev git pkg-config wget sshpass \
                 unzip imagemagick p7zip-full libgtest-dev libgmock-dev \
                 libreadline-dev libcairo2-dev libgif-dev libgtest-dev \
		 libgmock-dev
```

(If you're having issues with the build that look like components are missing, check [the Jenkins builder Docker configuration](https://github.com/MEGA65/builder-docker/blob/main/megabuild/Dockerfile) for an updated list.)

## Installing Xilinx Vivado

The MEGA65 core uses [Xilinx Vivado](https://www.xilinx.com/products/design-tools/vivado.html), Standard edition, for compiling VHDL. The Standard edition can be used free of charge, but it requires an account on the Xilinx website.

**Before running the installer:** Make sure you have the packages `libncurses5-dev` and `libtinfo5` installed! If either of these packages are missing, the Xilinx installer will hang on the last step during "Generating installed devices list." If this happens, quit the installer and double-check you have these packages.

To install Xilinx Vivado:

1. [Create an account](https://login.amd.com/) on the Xilinx website. You will need to provide the email address and password to the installer.
1. [Download the Xilinx installer](https://www.xilinx.com/support/download.html).
1. Run the installer. Use the following options when prompted:
    * Select Vivado Standard edition.
    * When prompted to select which components to install, expand the Devices list and make sure "Artix-7" is selected. You can deselect the others if you wish, or just leave the default selections.
    * For the installation root path, change the default value to: `/opt/Xilinx`

The download and installation process takes a while, as much as two hours.

## Installing Exomizer

The core build uses a tool called [Exomizer](https://bitbucket.org/magli143/exomizer/wiki/Home).

1. Clone [the Exomizer source repo](https://bitbucket.org/magli143/exomizer/src).
    * `cd ~`
    * `git clone https://bitbucket.org/magli143/exomizer.git`
2. Build.
    * `cd exomizer/src`
    * `make`
3. Put the `exomizer` binary on your command path. For example, to set your command path to include the `~/exomizer/src` directory:
    * `export PATH=$PATH:~/exomizer/src`

(TODO: Can we make this a submodule or local copy?)

## Checking out the MEGA65 core repository

The MEGA65 core code lives in the [mega65-core](https://github.com/MEGA65/mega65-core) Github repository. If you want to contribute changes to the core, you will want to [fork the repo](https://docs.github.com/en/get-started/quickstart/fork-a-repo), then base your contribution on the `development` branch. You will need a Github account and a Git client.

If you just want to build the bitstream from source, you can [download the repository](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives) from Github. No account or `git` is needed to download a public repository. Be sure to select the appropriate branch before starting the download.

The following commands check out your forked Github repository and switch to the `development` branch, replacing `YOURNAME` with your Github username:

```
git clone git@github.com:YOURNAME/mega65-core.git
cd mega65-core
git branch development
```

This creates a local directory named `mega65-core`. You can pull recent changes made to the Github repository at any time like so:

```
git pull
```

## Compiling the bitstream

The `make` command initiates build tasks, as defined in the `Makefile`. There are `make` _targets_ for each type of MEGA65 main board. You must use the build target appropriate for your main board.

| Type of MEGA65 | Board type | Build command |
|-|-|-|
| MEGA65 late 2023 | R5 board | `make bin/mega65r5.bit` |
| MEGA65 2022-early 2023 / DevKit (2020) | R3A/R3 board | `make bin/mega65r3.bit` |
| Nexys4DDR (A7) FPGA dev kit | Nexys4DDR | `make bin/nexys4ddr-widget.bit` |
| Nexys4 FPGA dev kit | Nexys4 | `make bin/nexys4.bit` |

These commands build the bitstream to the filename that appears in the command, e.g. `bin/mega65r3.bit`.

You can also build a Vivado MCS memory configuration file the same way, replacing `.bit` with `.mcs` in the filename, such as: `make bin/mega65r3.mcs`

## Sending the bitstream to the MEGA65 using a JTAG interface

If you have the [XMOD FTDI JTAG Adapater](https://shop.trenz-electronic.de/en/TE0790-03L-XMOD-FTDI-JTAG-Adapter-not-compatible-with-Xilinx-Tools), you can connect your PC to your MEGA65 and transfer bitstreams directly to the FPGA for testing.

One way to transmit a bitstream is with the `m65` command-line tool included with [mega65-tools](https://github.com/mega65/mega65-tools).

1. Clone the [mega65-tools repo](https://github.com/mega65/mega65-tools).
    * `cd ~`
    * `git clone https://github.com/MEGA65/mega65-tools.git`
2. Build the `m65` tool.
    * `cd mega65-tools`
    * `make bin/m65`

To send a bitstream, replacing the name of the bitstream filename with the one you built earlier:

```
./bin/m65 -b ../mega65-core/bin/mega65r3-20230803.23-master-3f8d12c.bit
```

When successful, this resets the MEGA65 with the new bitstream running. You can confirm that the new version is running by holding the Mega key and pressing Tab to enter Matrix Mode. The bitstream version string is near the top of the screen. (Press Mega + Tab again to exit Matrix Mode.)

You can optionally include the `-k HICKUP.M65` argument to include a "hickup" file with the bitstream. There are other options for changing the boot mode of the machine, uploading ROMs and programs, and typing test commands. Run `m65` without arguments for a list.

## Installing the bitstream as a MEGA65 core

You can convert the bitstream file to a MEGA65 core file using the `bit2core` tool, also provided by `mega65-tools`. You can copy the core file to the MEGA65 SD card, then install it in a core slot using the core selection menu.

To build the `bit2core` tool, with `mega65-tools` checked out as above:

* `cd ~/mega65-tools`
* `make bin/bit2core`

To convert a bitstream to a core, provide the command with the board name, bitstream filename, a name and version string for the core, and an output filename. For example:

```
./bin/bit2core mega65r3 ../mega65-core/bin/mega65r3-20230803.23-master-3f8d12c.bit "MEGA65 test core" "test version 1" r3test.cor
```

To see a list of board names, run `bit2core` without arguments.
