; (C) 2009 Marek Wodzinski
; new ppm coder with color lcd
;
; Changelog
; 2009.05.31	- initial code
; 2009.06.01	- added lcd code (non working)
; 2009.06.08	- timer0 and timer2 section, working pwm for lcd backlight
; 2009.06.10	- working lcd code, added rotated mode, fixed brightness of backlight
; 2009.06.14	- added keyboard scan
; 2009.06.15	- added single keyboard status byte
;		- clear ram on reset
;		- fixed bug (SREG destroyed during keyboard scan)
;		- added some ram reservations for channels and blocks


.nolist
.include "m88def.inc"		;standard header for atmega88

.define DEBUG

; ******** STA£E *********
.equ	ZEGAR=11059200
.equ	ZEGAR_MAX=ZEGAR/64/1000
.equ	LCD_PWM=150000
.equ	DEFAULT_SPEED=ZEGAR/16/9600-1
;keyboard
.equ	KBD_DELAY=32		;debounce time for keyboard (*2ms)
.equ	KBD_PORT_0=PORTD
.equ	KBD_PIN_0=PIND
.equ	KBD_DDR_0=DDRD
.equ	KBD_0=PORTD6
.equ	KBD_PORT_1=PORTD
.equ	KBD_PIN_1=PIND
.equ	KBD_DDR_1=DDRD
.equ	KBD_1=PORTD7
.equ	KBD_PORT_2=PORTB
.equ	KBD_PIN_2=PINB
.equ	KBD_DDR_2=DDRB
.equ	KBD_2=PORTB0
.equ	KEY_UP=0		;keys in keys var
.equ	KEY_DOWN=1
.equ	KEY_LEFT=2
.equ	KEY_RIGHT=3
.equ	KEY_ENTER=4
.equ	KEY_ESC=5

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
;.def		t2fix=r8
;.def		temp5=r9
;.def		temp6=r10
;.def		temp7=r11
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
ram_temp:	.byte	11	;general purpose temporary space, used also in LCD(11B) and MATH
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
		rjmp	t2cm	;Timer2 Compare Match A
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
		clr	status		;clear status register
		
		;clear ram
		ldi	XL,low(SRAM_START)
		ldi	XH,high(SRAM_START)
		ldi	YL,low(SRAM_SIZE)
		ldi	YH,high(SRAM_SIZE)
clear_ram:
		st	X+,zero
		dec	YL
		brne	clear_ram
		dec	YH
		brne	clear_ram
		
		;initialize timers
		;Timer0 - pwm dla pod¶wietlenia LCD, 150kHz, 25% wypelnienia, wyjscie przez OC0B, no prescaling
		ldi	temp,(ZEGAR/LCD_PWM)	;150kHz
		out	OCR0A,temp
		ldi	temp,(ZEGAR/LCD_PWM*75/100)	;75%
		out	OCR0B,temp
		ldi	temp,(1<<COM0B1)+(1<<WGM01)+(1<<WGM00)	;OC0B out, fast PWM z CTC
		out	TCCR0A,temp
		ldi	temp,(1<<WGM02)+(1<<CS00)
		out	TCCR0B,temp
		sbi	DDRD,PD5
		
		;Timer1 - pwm for PPM
		
		;Timer2 - odliczanie czasu, ~1kHz, ctc, przerwania
		ldi	temp,(1<<WGM21)	;ctc
		sts	TCCR2A,temp
		ldi	temp,(1<<CS22)	;/64
		sts	TCCR2B,temp
		ldi	temp,ZEGAR_MAX	;liczymy do ZEGAR_MAX
		sts	OCR2A,temp
		sts	ASSR,zero	;na pewno synchroniczny
		ldi	temp,(1<<OCIE2A)	;przerwanie przy przepelnieniu licznika
		sts	TIMSK2,temp


		sei	;enable interrupts

		;initialize lcd
		sbi	DDRB,PB2	;SS - must be output
		sbi	DDRB,PB5	;SCK: output
		sbi	DDRB,PB3	;MOSI: output
		sbi	LCD_DDR_LED,LCD_LED	;backlight: output
		
		waitms	250
		rcall	lcd_init
		m_lcd_set_bg	COLOR_YELLOW
		m_lcd_set_fg	COLOR_RED
		m_lcd_fill_rect	10,10,20,20
		
		m_lcd_set_fg	COLOR_BLUE
		m_lcd_fill_rect	64,64,50,50

		m_lcd_set_fg	COLOR_BLACK
		m_lcd_fill_rect	0,0,176,10
		
		m_lcd_set_bg	COLOR_BLACK
		m_lcd_set_fg	COLOR_CYAN

		m_lcd_text_pos	0,0
		m_lcd_text	banner
;
		
		m_lcd_set_bg	COLOR_WHITE	;set default colors
		m_lcd_set_fg	COLOR_BLACK



main_loop:
.ifdef DEBUG
		rcall	kbd_debug
		waitms	5
.endif


		rjmp	main_loop
banner:		.db	"(C) 2007-2009 Marek Wodzinski",0



; ######### PODPROGRAMY ###########
; #


;
; # wait X ms
waitms1:
		cli
		;sts	TCNT2,zero
		mov	mscountl,zero
		mov	mscounth,zero
		sei

waitms1_1:
		cp	mscountl,temp2
		brne	waitms1_1

		ret
;


;
; # zamienia liczbe w temp na hexa
tohex:		andi	temp,0x0f
		ori	temp,48
		cpi	temp,58
		brcs	tohex1
		push	temp2
		ldi	temp2,7
		add	temp,temp2
		pop	temp2
tohex1:		ret
;


;
; # wyswietla wartosci z bajtow klawiatury
.ifdef DEBUG
kbd_debug:
		m_lcd_text_pos	0,5
		ldi	XL,low(key_0)
		ldi	XH,high(key_0)
		ldi	temp2,6
kbd_debug_1:
		push	temp2
		
		ld	temp,X
		swap	temp
		rcall	tohex
		sts	lcd_arg1,temp
		rcall	lcd_char
		ld	temp,X+
		rcall	tohex
		sts	lcd_arg1,temp
		rcall	lcd_char
		
		pop	temp2
		dec	temp2
		brne	kbd_debug_1
		
		;chars binary
		lds	temp,keys
		swap	temp
		rcall	tohex
		sts	lcd_arg1,temp
		rcall	lcd_char
		lds	temp,keys
		rcall	tohex
		sts	lcd_arg1,temp
		rcall	lcd_char
		
		ret
.endif
;	


;
; ####### math #########
;
;
; #
; ########## END PODPROGRAMY ##########

;
; ############ PRZERWANIA ################
; #

;
; timer2 compare match A : time counting
t2cm:
		in	itemp,SREG
		push	itemp

		inc	mscountl		;licznik milisekund dla mswait
		brne	t2cm_1
		inc	mscounth
t2cm_1:		
		;TODO: trigger PPM, trigger ADC
		
		;keyboard
		sbrc	mscountl,0	;call only on even milisoconds
		rcall	kbd_scan
		
		pop	itemp
		out	SREG,itemp
		reti
;


;
; keyboard scan
kbd_scan:
		push	XL					;2
		push	XH					;2
		ldi	XL,low(key_0)				;1
		ldi	XH,high(key_0)				;1
		cbi	KBD_PORT_0,KBD_0			
		cbi	KBD_PORT_1,KBD_1			
		cbi	KBD_PORT_2,KBD_2			
		
		lds	itemp2,keys	;load key status
		
		;first variant
		cbi	KBD_DDR_1,KBD_1				;2
		cbi	KBD_DDR_2,KBD_2				;2
		sbi	KBD_DDR_0,KBD_0				;2

		ld	itemp,X		;key_0			;2
		sbis	KBD_PIN_1,KBD_1				;1/2
		rjmp	kbd_scan_0_1				;2
		
		tst	itemp		;juz zero?		;1
		breq	kbd_scan_0_3				;1/2
		dec	itemp					;1
		rjmp	kbd_scan_0_2				;2
kbd_scan_0_3:
		andi	itemp2,~(1<<KEY_UP)
		rjmp	kbd_scan_0_2
kbd_scan_0_1:
		inc	itemp					;1
		cpi	itemp,KBD_DELAY				;1
		brcs	kbd_scan_0_2				;1/2
		ldi	itemp,KBD_DELAY				;1
		ori	itemp2,(1<<KEY_UP)
kbd_scan_0_2:
		st	X+,itemp				;2 = 11/11
		
		ld	itemp,X		;key_1	
		sbis	KBD_PIN_2,KBD_2
		rjmp	kbd_scan_1_1
		
		tst	itemp
		breq	kbd_scan_1_3
		dec	itemp
		rjmp	kbd_scan_1_2
kbd_scan_1_3:
		andi	itemp2,~(1<<KEY_DOWN)
		rjmp	kbd_scan_1_2
kbd_scan_1_1:
		inc	itemp
		cpi	itemp,KBD_DELAY
		brcs	kbd_scan_1_2
		ldi	itemp,KBD_DELAY
		ori	itemp2,(1<<KEY_DOWN)
kbd_scan_1_2:
		st	X+,itemp				;11
		

		;second variant
		cbi	KBD_DDR_0,KBD_0
		cbi	KBD_DDR_2,KBD_2
		sbi	KBD_DDR_1,KBD_1

		ld	itemp,X		;key_2
		sbis	KBD_PIN_0,KBD_0
		rjmp	kbd_scan_2_1
		
		tst	itemp		;juz zero?
		breq	kbd_scan_2_3
		dec	itemp
		rjmp	kbd_scan_2_2
kbd_scan_2_3:
		andi	itemp2,~(1<<KEY_ESC)
		rjmp	kbd_scan_2_2
kbd_scan_2_1:
		inc	itemp
		cpi	itemp,KBD_DELAY
		brcs	kbd_scan_2_2
		ldi	itemp,KBD_DELAY
		ori	itemp2,(1<<KEY_ESC)
kbd_scan_2_2:
		st	X+,itemp				;11
		
		
		ld	itemp,X		;key_3
		sbis	KBD_PIN_2,KBD_2
		rjmp	kbd_scan_3_1
		
		tst	itemp
		breq	kbd_scan_3_3
		dec	itemp
		rjmp	kbd_scan_3_2
kbd_scan_3_3:
		andi	itemp2,~(1<<KEY_LEFT)
		rjmp	kbd_scan_3_2
kbd_scan_3_1:
		inc	itemp
		cpi	itemp,KBD_DELAY
		brcs	kbd_scan_3_2
		ldi	itemp,KBD_DELAY
		ori	itemp2,(1<<KEY_LEFT)
kbd_scan_3_2:
		st	X+,itemp				;11


		;third variant		
		cbi	KBD_DDR_0,KBD_0
		cbi	KBD_DDR_1,KBD_1
		sbi	KBD_DDR_2,KBD_2

		ld	itemp,X		;key_4
		sbis	KBD_PIN_0,KBD_0
		rjmp	kbd_scan_4_1
		
		tst	itemp		;juz zero?
		breq	kbd_scan_4_3
		dec	itemp
		rjmp	kbd_scan_4_2
kbd_scan_4_3:
		andi	itemp2,~(1<<KEY_ENTER)
		rjmp	kbd_scan_4_2
kbd_scan_4_1:
		inc	itemp
		cpi	itemp,KBD_DELAY
		brcs	kbd_scan_4_2
		ldi	itemp,KBD_DELAY
		ori	itemp2,(1<<KEY_ENTER)
kbd_scan_4_2:
		st	X+,itemp				;11
		
		
		ld	itemp,X		;key_5
		sbis	KBD_PIN_1,KBD_1
		rjmp	kbd_scan_5_1
		
		tst	itemp
		breq	kbd_scan_5_3
		dec	itemp
		rjmp	kbd_scan_5_2
kbd_scan_5_3:
		andi	itemp2,~(1<<KEY_RIGHT)
		rjmp	kbd_scan_5_2
kbd_scan_5_1:
		inc	itemp
		cpi	itemp,KBD_DELAY
		brcs	kbd_scan_5_2
		ldi	itemp,KBD_DELAY
		ori	itemp2,(1<<KEY_RIGHT)
kbd_scan_5_2:
		st	X+,itemp				;11
		
		sts	keys,itemp2
		pop	XH					;2
		pop	XL					;2
		ret						;4+3(call)
;								;=117
.dseg
keys:		.byte	1	;all keys
key_0:		.byte	1	;up
key_1:		.byte	1	;down
key_2:		.byte	1	;esc
key_3:		.byte	1	;left
key_4:		.byte	1	;enter
key_5:		.byte	1	;right
.cseg

; #
; ############ END PRZERWANIA ############
;





;.include "version.inc"		;include svn version as firmware version
.include "bootloader.inc"	;needed for flash reprogramming


; ############ ZMIENNE ####################
.dseg
channels:	.byte	512	;max 256 channels
ch_status:	.byte	30
blocks:		.byte	256	;max 127 blocks
wr_tmp:		.byte	128
math_buf:	.byte	16
;
; ############ EEPROM #####################
; #
.eseg
.org	0
