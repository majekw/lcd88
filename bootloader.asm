; Bootloader
; (C) 2007-2012 Marek Wodzinski
;
; Changelog:
; 2007.11.16	- first code
; 2007.11.17	- xmodem and flash programming done
; 2007.11.23	- fixed hang when there is a constant stream of data coming from rs
;		- removed other options, corrected banners
; 2009.05.31	- modified to suit atmega88
; 2011.11.11	- use SRAM_START from device definition instead of harcoding
; 2012.09.13	- small change to compile on both Mega88 and Mega168
; 2012.09.14	- fix for PAGESIZE on Atmega168/328
; 2012.12.27	- run bootloader code only after external reset
;		- changed order of programming steps from erase-fill-write to fill-erase-write
;		- added support for Atmega328

.ifdef M88
    .include "m88def.inc"
.else
    .ifdef M168
	.include "m168def.inc"
    .else
	.ifdef M328
	    .include "m328def.inc"
	.else
	    .error "No processor defined!"
	.endif
    .endif
.endif


.ifndef temp
.def	temp=r16
.def	temp2=r17
.def	temp3=r22
.endif
.def	rblock=r2
.def	rblocki=r3
.def	rcksum=r4
.def	cksum=r18
.def	block=r19
.def	spmcrval=r20
.def	response=r21
.def	looplo=r24
.def	loophi=r25


.equ	F_CPU=11059200			;CLK
;.equ	F_CPU=7372800
;.equ	RAM_START=0x100			;ram start
.equ	REC_BUF=SRAM_START		;receive buffer
.equ	WRITE_BUF=REC_BUF+256		;write buffer
.equ	boot_rx_timeout=F_CPU/641	;wait about 2s for char from UART

.equ	xmodem_SOH=0x01			;xmodem definitions
.equ	xmodem_EOT=0x04
.equ	xmodem_ACK=0x06
.equ	xmodem_NAK=0x15
.equ	xmodem_CAN=0x18
.equ	xmodem_C=0x45


.cseg

.ifdef	M328
    .org	FIRSTBOOTSTART
.else
    .org	SECONDBOOTSTART
.endif

boot_start:
		;disable interrupts
		cli
		
		;check reason of reset
		in	temp,MCUSR	;get reset flags
		clr	temp3		;zero
		;out	MCUSR,temp2	;clear status register	;commented out - allow main program to discover reset cause
		sbrs	temp,EXTRF	;check if external reset occured?
		rjmp	boot_jump0	;if not, just reboot
		
		;initialize stack
		ldi	temp,low(RAMEND)
		out	SPL,temp
		ldi	temp,high(RAMEND)
		out	SPH,temp
		
		;initialize UART
		cbi	DDRD,PORTD0	;rx: input
		sbi	PORTD,PORTD0	;rx: pull up
		sbi	DDRD,PORTD1	;tx: output
		
		;ldi	temp,0		;no x2 speed, no multiprocessor comm.
		sts	UCSR0A,temp3
		
		ldi	temp,(1<<RXEN0)+(1<<TXEN0)	;enable rx and tx
		sts	UCSR0B,temp
		
		ldi	temp,(1<<UCSZ01)+(1<<UCSZ00)	;8 bit
		sts	UCSR0C,temp
		
		;ldi	temp,0
		sts	UBRR0H,temp3
		ldi	temp,71		;speed: 9600 (47 for 7.3728, 51 for 8M, 71 for 11.0592M)
		sts	UBRR0L,temp
		
		lds	temp,UDR0		;flush receiver
		lds	temp,UDR0
		lds	temp,UDR0
		
		;print banner
		ldi	ZL,low(boot_banner1<<1)
		ldi	ZH,high(boot_banner1<<1)
		rcall	boot_print
		
		;wait for keypress
boot_wait:
		rcall	boot_rx_char	;get char from uart
		brcs	boot_end	;go to end if timeout

		cpi	temp,'B'	;B?
		brne	boot_end	;no second chance
		
		;menu
boot_menu:
		ldi	ZL,low(boot_banner3<<1)
		ldi	ZH,high(boot_banner3<<1)
		rcall	boot_print
boot_menu1:
		lds	temp,UCSR0A	;wait for char
		sbrs	temp,RXC0
		rjmp	boot_menu1
		lds	temp,UDR0	;read char
		
		cpi	temp,'P'
		brne	boot_end
;
; ########## upload new firmware  #########
; #
boot_firmware:
		;upload new firmware
		clr	ZL		;set FLASH address to 0
		clr	ZH
		ldi	block,1		;set block counter
xmodem_start:
		;start xmodem transmission
		ldi	response,xmodem_NAK	;send initial NAK
xmodem_start1:
		mov	temp,response
		rcall	boot_tx_char
		rcall	boot_rx_char	;wait for char
		brcs	xmodem_start1	;time out - wait again

		cpi	temp,xmodem_SOH	;check for start of header
		breq	xmodem_receive
		
		cpi	temp,xmodem_EOT	;check for end of transmission
		breq	xmodem_end
		
		rjmp	xmodem_start1
		
xmodem_receive:
		;get packet
		rcall	boot_rx_char	;get block number
		mov	rblock,temp
		rcall	boot_rx_char	;get inverse block number
		mov	rblocki,temp
		
		ldi	YL,low(REC_BUF)	;prepare buffer address
		ldi	YH,high(REC_BUF)
		clr	cksum		;clear checksum counter
		ldi	temp2,128	;prepare to receive 128 chars
xmodem_receive1:
		rcall	boot_rx_char	;receive byte
		st	Y+,temp		;store in ram
		add	cksum,temp	;checksum
		dec	temp2
		brne	xmodem_receive1
		
		rcall	boot_rx_char	;get checksum
		
		;checks
		cp	temp,cksum	;check checksum
		brne	xmodem_start
		cp	block,rblock	;check for block number
		brne	xmodem_start
		com	rblocki		;check for block and 255-block fields
		cp	rblocki,rblock
		brne	xmodem_start
		
		;block received ok
		ldi	YL,low(REC_BUF)	;prepare buffer address
		ldi	YH,high(REC_BUF)
		ldi	temp,128		;how many bytes are to write
		rcall	boot_block_write	;write buffer to flash
		
		inc	block		;get next block
		ldi	response,xmodem_ACK	;send ACK
		rjmp	xmodem_start1
xmodem_end:
		ldi	temp,xmodem_ACK
		rcall	boot_tx_char		
		rjmp	boot_menu
; ### end of new firmware
;

boot_end:
		;time out - boot original application
		ldi	ZL,low(boot_banner2<<1)
		ldi	ZH,high(boot_banner2<<1)
		rcall	boot_print
		
boot_jump0:	clr	ZL
		clr	ZH
		ijmp		;end of bootloader - jump to 0


;
; ########## subroutines ###########
; #

;
; send chars stored in flash to UART
boot_print:
		lpm	temp,Z+
		tst	temp
		breq	boot_print1
		rcall	boot_tx_char
		rjmp	boot_print
boot_print1:
		ret
;


;
; transmit char from temp to UART
boot_tx_char:
		lds	temp3,UCSR0A
		sbrs	temp3,UDRE0	;wait for empty buffer
		rjmp	boot_tx_char
		sts	UDR0,temp
		ret
;


;
; # wait for char (about 1s timeout)
boot_rx_char:
		push	temp2
		ldi	looplo,low(boot_rx_timeout)	;maximum time to wait
		ldi	loophi,high(boot_rx_timeout)
		clr	temp2			;second wait loop
boot_rx_char1:
		lds	temp3,UCSR0A						;2
		sbrc	temp3,RXC0		;skip if nothing to read	;2
		rjmp	boot_rx_char2
		
		dec	temp2			;end of small loop		;1
		brne	boot_rx_char1						;2/1 (5*256)
		
		sbiw	looplo,1		;end of main loop		;2
		brne	boot_rx_char1						;2
		
		sec				;set carry=1 : time out
		rjmp	boot_rx_char3
boot_rx_char2:
		lds	temp,UDR0
		clc				;clear carry, temp<-char received
boot_rx_char3:
		pop	temp2
		ret
;


;
; # write blocks to flash
; - Z : flash address (bytes)
; - Y : ram address
; - temp : number of bytes to write
; modified after run:
;  - r0, r1, spmcrval (r20), looplo (r24), temp (r16), temp2 (r17), Z, Y
boot_block_write:

; # fill buffer with data
boot_fill_page:
		;transfer data from RAM to FLASH buffer
		ldi	looplo,PAGESIZE	;number of WORDS in page to write
boot_fill_page1:
		ld	r0,Y+		;get word from ram
		ld	r1,Y+
		ldi	spmcrval,(1<<SELFPRGEN)	;write word to buffer
		rcall	boot_spm
		adiw	ZL,2		;next flash address
		subi	temp,2		;2 bytes written
		dec	looplo		;whole page written?
		brne	boot_fill_page1

		;restore Z to point correct page
		subi	ZL,low(PAGESIZE<<1)
		sbci	ZH,high(PAGESIZE<<1)
		
; # erase page
; - Z : flash address (bytes)
; - temp : use 0 for one page
; modified after run:
;  - spmcrval (r20), temp2 (r17), Z
boot_erase_page:
		;page erase
		ldi	spmcrval,(1<<PGERS)+(1<<SELFPRGEN)
		rcall	boot_spm
		
		;reenable RWW section (it also erases temporary buffer!)
		;ldi	spmcrval,(1<<RWWSRE)+(1<<SELFPRGEN)
		;rcall	boot_spm

; # write page
; - Z : flash address (bytes)
; - temp : use 0 for one page
; modified after run:
;  - spmcrval (r20), temp2 (r17), Z
boot_write_page:
		ldi	spmcrval,(1<<PGWRT)+(1<<SELFPRGEN)	;write page
		rcall	boot_spm
		
		;calculate next page address
		ldi	temp2,low(PAGESIZE<<1)
		add	ZL,temp2
		ldi	temp2,high(PAGESIZE<<1)
		adc	ZH,temp2
		
		;reenable RWW section
		ldi	spmcrval,(1<<RWWSRE)+(1<<SELFPRGEN)
		rcall	boot_spm
		
		tst	temp		;all bytes saved?
		brne	boot_block_write
		ret
;
		

;
; # make real spm
boot_spm:
		in	temp2,SPMCSR	;wait for previous spm complete
		sbrc	temp2,SELFPRGEN
		rjmp	boot_spm
		
		out	SPMCSR,spmcrval
		spm
		ret
;

	
;
; ########## static data ###########
; #		
boot_banner1:
		.db	13,10,"Bootloader v.1.3 (C) Marek Wodzinski",13,10
		.db	"Press B for options or wait 2s for normal boot.",13,10,0
boot_banner2:
		.db	"booting....",13,10,0
boot_banner3:
		.db	"Press P for firmware update (XMODEM) or any other key to continue booting",13,10,0
