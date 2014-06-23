lcd88
=====

Open source, flexible PPM coder/mixer/brain for R/C transmitter.

Main website: http://majek.mamy.to/lcd88


About
-----

LCD88 is software for Atmega88/168/328 controller to generate PPM waveform.
It also support simple keyboard and graphic LCD.
Main goal of this project is to make cheap and powerful replacement for old
R/C transmitters. So, for few $ you could retrofit your old TX to make
fully programmable 8 channels (or more) transmitter.


Configuring
-----------

1. Open Makefile
2. Uncomment one of defines with processor type (M88, M168 or M328)
3. Uncomment clock selection (FCK16 for 16MHz or FCK11 for 11.0592MHz).
If you need another clock, you need to hack a little in lcd88.asm,
but don't set it higher than 16MHz!
4. Open lcd-s65.asm
5. Uncomment one define with lcd_l2f50, lcd_ls020 or lcd_st7735 depending
on you lcd hardware

Compiling/burning
---------

You need [AVRA](http://avra.sourceforge.net) to compile it.
Also some 'make' and Linux environment could help :-)
If you have Linux, just type 'make' and it should make everything.
Right now it's not very friendly for other systems, so in case of troubles,
look into Makefile and try make all steps manually.

After succesful compilation you should have 2 .hex files:
- lcd88.hex
- bootloader.hex

Bootloader image you must burn using USBASP or other 'traditional'
programmer. Then you could transfer lcd88.hex converted to raw binary
over serial.


Hardware
--------

Of course, you need some hardware to run this software :-)

Processors supported:
- Atmega88 (but support for it will be discontinued soon)
- Atmega168 and Atmega328 (both you can find on Arduino boards)

Processor clock supported: up to 16MHz (so, everything below or equal
will run fine).

Graphic LCD:
- 176x132 lcd used in old Siemens S65 phones, L2F50 and LS020 versions
- cheap 1.8" 160x128 tft based on ST7735, Arduino's GTFT should also work

Keyboard: it's only one part that you must do yourself as it's non standard.
Schematic is in pcb/ directory (Eagle files)
Required:
- 6 tact switches
- 6 diodes 1N4148
- 3 resistors about 1-10k

Depending on AVR voltage and variant of LCD, level converter also could
be required.

For more info about hardware look at http://majek.mamy.to/en/lcd88-hardware/
Models
------

Of course you need some models definitions:-)

For now, look into models.asm and try to figure out yourself how it works :-)
More info how blocks works is at http://majek.mamy.to/en/lcd88-how-it-works/


Author(s)
---------

Most of code made by Marek Wodzinski

Hardware specific code for S65 lcd based on C sources from Christian Kranz
(L2F50_display4.02 at http://www.superkranz.de/christian/S65_Display/DisplayIndex.html )

Fonts: 8x8 I got from Linux sources, other fonts are probably from open source
projetcs I don't remember :-(

m88def.inc, m168def.inc and m328def.inc are made by Atmel.

License
-------

All work is under GPL v3 license available in LICENSE file.

I'm not responsible in any way for uses or misuses of this code.
Use it at your own risk!
