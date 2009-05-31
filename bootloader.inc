; bootloader include file
;

.cseg
.org	0x0f00
boot_start:

.org	0x0f80
; # write blocks to flash
; - Z : flash address
; - Y : ram address
; - temp : number of bytes to write
boot_block_write:


;end
