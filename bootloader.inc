; bootloader include file
;

.cseg
.org	0x0f00
boot_start:

.org	0x0f7f
; # write blocks to flash
; - Z : flash address
; - Y : ram address
; - temp (r16) : number of bytes to write
; destroyed: r0,r1,r17,r20,r24
boot_block_write:


;end
