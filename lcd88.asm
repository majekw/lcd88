.nolist
.include "m88def.inc"		;standardowy nag³ówek do atmega8


; ******** STA£E *********
;.equ	ZEGAR=8000000		;clock speed (CLK!)
;.equ	ZEGAR=7372800		;docelowo!
.equ	ZEGAR=11059200
.equ	ZEGARFIX=229
.equ	DEFAULT_SPEED=ZEGAR/16/9600-1
.equ	LCD_X=176
.equ	LCD_Y=132
;.equ	RS_BUF_SIZE=64		;wielkosc bufora dla rs-a


; ***** REJESTRY *****
; r0	roboczy
; r1	roboczy
; r2	zero (0)	;sta³a 0
; r3
; r4	temp3
; r5	temp4
; r6	itemp3
; r7	itemp4
; r8	t2fix		;licznik do korekcji odmierzania ms
; r9	temp5
; r10	temp6
; r11	temp7
; r12	fgcolorl	;kolor pixla
; r13	fgcolorh
; r14	bgcolorl	;kolor tla
; r15	bgcolorh
;
; r16	temp		;rejestry tymczasowe dla normalnej czê¶æi aplikacji (nie przerwañ)
; r17	temp2
; r18
; r19	status		;status
; r20	itemp		;tempy wykorzystywane w przerwaniach
; r21	itemp2
; r22	mscountl	;licznik milisekund dla waitms
; r23	mscounth
; r24	WL
; r25   WH
; r26	XL		;
; r27	XH
; r28	YL		;
; r29	YH
; r30	ZL	- lpm
; r31	ZH

.def		zero=r2
.def		temp3=r4
.def		temp4=r5
.def		itemp3=r6
.def		itemp4=r7
.def		t2fix=r8
.def		temp5=r9
.def		temp6=r10
.def		temp7=r11
;.def		rsptr1=r18
;.def		rsptr2=r11
.def		fgcolorl=r12
.def		fgcolorh=r13
.def		bgcolorl=r14
.def		gbcolorh=r15
.def		temp=r16	;zwykly rejestr tymczasowy
.def		temp2=r17	;drugi temp
.def		status=r19
.def		itemp=r20	;jw. ale do wykorzystania w przerwaniach
.def		itemp2=r21	;drugi temp dla przerwañ
.def		mscountl=r22	;licznik milisekund dla waitms
.def		mscounth=r23
.def		WL=r24
.def		WH=r25

; bity w rejestrze 'status'
; status
.equ		WRAP_LINE=0	;text wrap after whole line
.equ		WRAP_SCR=1	;wrap to first line after last line
.equ		WDT_EN=2	;set if watchdog enabled
.equ		WDT_ANY=3	;set if any char resets watchdog timer, else only special sequence can reset
.equ		CRLF=4		;add lf after cr



; ******** HARDWARE ********


; ###### makra ######
; #

; czeka x ms
.macro		waitms
		push	temp2
		ldi	temp2,low(@0)
		rcall	waitms1
		pop	temp2
.endmacro

; # important global ram variables
.dseg
ram_temp:	.byte	30	;general purpose temporary space, used also in LCD and MATH
.cseg



;****Source code***************************************************
.list
.cseg					;CODE segment
.org 0
		rjmp	reset	;RESET
		reti		;INT0
		reti		;INT1
		reti		;PCINT0
		reti		;PCINT1
		reti		;PCINT2
		reti		;WDT
		reti		;Timer2 Compare Match A
		reti		;Timer2 Compare Match B
		reti		;Timer2 Overflow
		reti		;Timer1 Capture
		reti		;Timer1 CompareA
		reti		;Timer1 CompareB
		reti		;Timer1 Overflow
		reti		;Timer0 Compare MAtch A
		reti		;Timer0 Compare Match B
		reti		;Timer0 Overflow
		reti		;SPI transfer complete
		reti		;USART RX complete
		reti		;USART data register empty (UDRE)
		reti		;USART TX complete
		reti		;ADC conversion complete
		reti		;EEPROM ready
		reti		;Analog comparator
		reti		;Two wire serial interface
		reti		;SPM ready


; # Wy¶wietlacz LCD
.include	"lcd-s65.asm"

; # main program
reset:
		cli				;disable interrupts
		
		;set stack pointer
		ldi	temp,low(RAMEND)
		out	SPL,temp
		ldi	temp,high(RAMEND)
		out	SPH,temp
		
		;initialize variables
		clr	zero
		clr	t2fix		;pozwala odmierzac czas dokladnie
		clr	status		;clear status register

main_loop:
		rjmp	main_loop

;
; # wait X ms
waitms1:
		cli
		sts	TCNT2,zero
		mov	mscountl,zero
		mov	mscounth,zero
		sei

waitms1_1:
		cp	mscountl,temp2
		brne	waitms1_1

		ret
;



;
; ############ FONTS ######################
; #

;8x8
font_8x8_spec:
		.db	low(font_8x8<<1),high(font_8x8<<1),8,0,0,0,0,8,8,32,127,0
font_8x8:
.include "font_8x8r.inc"

;10x18
;font_10x18_spec:
;		.db	low(font_10x18<<1),high(font_10x18<<1),23,3,3,0,0,18,10,32,127,0
;font_10x18:
;.include "font_10x18.inc"

;5x7
;font_5x7_spec:
;		.db	low(font_5x7<<1),high(font_5x7<<1),5,1,2,1,1,7,5,32,127,0
;font_5x7:
;.include "font_5x7_small.inc"

;12x22
;font_12x22_spec:
;		.db	low(font_12x22<<1),high(font_12x22<<1),33,4,0,0,0,22,12,32,127,0
;font_12x22:
;.include "font_sun12x22.inc"


; #
; ############ END FONTS ##################


;.include "version.inc"		;include svn version as firmware version
.include "bootloader.inc"	;needed for flash reprogramming (font storage)


; ############ ZMIENNE ####################
.dseg
;rs_bufor:	.byte	RS_BUF_SIZE	;buffer for rs232
;actual font specification
font_mem_start:	.byte	2	;font address in flash
font_bpc:	.byte	1	;bytes per char
font_margin_x:	.byte	1	;font margin from left
font_margin_y:	.byte	1	;font margin from top
font_space_x:	.byte	1	;horizontal space between chars
font_space_y:	.byte	1	;vertical space between chars
font_h:		.byte	1	;font height
font_w:		.byte	1	;font width
font_char_start: .byte	1	;start char
font_char_end:	.byte	1	;last char in font
font_scale_x:	.byte	1	;scale font xN
font_scale_y:	.byte	1	;
font_x:		.byte	1	;coords of next char (pixel)
font_y:		.byte	1
;bar graphs
bar_graph:	.byte	10*16	;16 bar graphs
				;4 - x1,y1,x2,y2
				;1 - value
				;1 - type (hor/vert, outline)
				;2 - bgcolor
				;2 - fgcolor
font_palette:	.byte	32	;palette cache for bitmap drawing


;
; ############ EEPROM #####################
; #
.eseg
.org	0
ee_sig:		.db	0x55,0xAA
.org	256
eeconfig:
rs_speed:	.db	DEFAULT_SPEED	;9600
font_config:	.db	0,0,0,0,0,0,0,0,0,0,0
		.db	0,0,0,0,0,0,0,0,0,0,0
		.db	0,0,0,0,0,0,0,0,0,0,0
		.db	0,0,0,0,0,0,0,0,0,0,0
