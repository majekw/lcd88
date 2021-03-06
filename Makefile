# uncomment right device and don't forget to do 'make clean' after that!
#DEVICE	?= M88
#DEVICE	?= M168
#DEVICE  ?= M328
#FCK = FCK11

# for Arduino Pro mini
DEVICE = M328
FCK = FCK16

#assembler
ASM	:= avra

compile: lcd88.hex

bootloader: bootloader.hex

lcd88.hex: bootloader.inc lcd88.asm lcd-s65.asm lcd-s65-ls020.asm lcd-s65-l2f50.asm lcd-s65-st7735.asm math-6-10.asm models.asm Makefile
	$(ASM) --define $(DEVICE) --define $(FCK) lcd88.asm -l lcd88.lst


install: lcd88.hex
	cat lcd88.hex|./ihex2bin >lcd88.bin
	lsz -X -vvvvv -b lcd88.bin >/dev/ttyUSB0 </dev/ttyUSB0

bootloader.hex bootloader.lst: bootloader.asm Makefile
	$(ASM) --define $(DEVICE) --define $(FCK) bootloader.asm -l bootloader.lst

bootloader.inc: bootloader.lst
	sh makeinclude.sh bootloader.lst bootloader.inc

bootloader_install:
	avrdude -c usbasp -p$(DEVICE) -U flash:w:bootloader.hex

.PHONY: clean

clean:
	rm -f *.hex *.epp *.obj *.lst *.cof *.bin *.inc.* bootloader.inc


m328-16-fuses:
	avrdude -c usbasp -p m328p -v -U hfuse:w:0xde:m -U lfuse:w:0xf7:m
