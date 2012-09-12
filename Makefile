# uncomment right device
#DEVICE	?= M88
DEVICE	?= M168

#assembler
ASM	:= avra

compile: lcd88.hex

bootloader: bootloader.hex

lcd88.hex: bootloader.inc lcd88.asm
	$(ASM) lcd88.asm -l lcd88.lst


install: lcd88.hex
	cat lcd88.hex|./ihex2bin >lcd88.bin
	lsz -X -vvvvv -b lcd88.bin >/dev/ttyUSB0 </dev/ttyUSB0

bootloader.hex bootloader.lst: bootloader.asm
	$(ASM) --define $(DEVICE) bootloader.asm -l bootloader.lst

bootloader.inc: bootloader.lst
	sh makeinclude.sh bootloader.lst bootloader.inc

bootloader_install:
	cat bootloader.hex|./ihex2bin >bootloader.bin
	lsz -X -vvvvv -b bootloader.bin >/dev/ttyUSB0 </dev/ttyUSB0

.PHONY: clean

clean:
	rm -f *.hex *.epp *.obj *.lst *.cof *.bin *.inc.*

.PHONY: distclean

distclean: clean
	rm -f bootloader.inc

