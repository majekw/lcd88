compile:
	avra lcd88.asm -l lcd88.lst


install:
	avra lcd88.asm -l lcd88.lst
	cat lcd88.hex|./ihex2bin >lcd88.bin
	lsz -X -vvvvv -b lcd88.bin >/dev/ttyUSB0 </dev/ttyUSB0

