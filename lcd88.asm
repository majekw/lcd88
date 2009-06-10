; (C) 2009 Marek Wodzinski
; new ppm coder with color lcd
;
; Changelog
; 2009.05.31	- initial code
; 2009.06.01	- added lcd code (non working)
; 2009.06.08	- timer0 and 2 section, working pwm for lcd backlight
; 2009.06.10	- working lcd code, added rotated mode, fixed brightness of backlight

.nolist
.include "m88def.inc"		;standardowy nag³ówek do atmega8


; ******** STA£E *********
;.equ	ZEGAR=8000000		;clock speed (CLK!)
;.equ	ZEGAR=7372800		;docelowo!
.equ	ZEGAR=11059200
.equ	ZEGAR_MAX=ZEGAR/64/1000
.equ	LCD_PWM=150000
.equ	DEFAULT_SPEED=ZEGAR/16/9600-1

;.equ	LCD_X=176
;.equ	LCD_Y=132
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
		
		;initialize timers
		;Timer0 - pwm dla pod¶wietlenia LCD, 150kHz, 25% wypelnienia, wyjscie przez OC0B, no prescaling
		ldi	temp,(ZEGAR/LCD_PWM)	;150kHz
		out	OCR0A,temp
		ldi	temp,(ZEGAR/LCD_PWM*75/100)	;25%
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
		m_lcd_fill_rect	122,0,10,176
		
		m_lcd_set_bg	COLOR_BLACK
		m_lcd_set_fg	COLOR_CYAN

		m_lcd_text_pos	0,0
		m_lcd_text	banner
;
		
		m_lcd_set_bg	COLOR_WHITE	;set default colors
		m_lcd_set_fg	COLOR_BLACK



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
; ############ PRZERWANIA ################
; #

;
; timer2 compare match A : time counting
t2cm:
		in	itemp,SREG

		inc	mscountl		;licznik milisekund dla mswait
		brne	t2cm_1
		inc	mscounth
t2cm_1:		
		out	SREG,itemp
		reti
; #
; ############ END PRZERWANIA ############
;



banner:		.db	"(C) 2007-2009 Marek Wodzinski",0


;.include "version.inc"		;include svn version as firmware version
.include "bootloader.inc"	;needed for flash reprogramming


; ############ ZMIENNE ####################
.dseg

;
; ############ EEPROM #####################
; #
.eseg
.org	0
ee_sig:		.db	0x55,0xAA
.org	256
eeconfig:
rs_speed:	.db	DEFAULT_SPEED	;9600
dupa:		.db	ZEGAR_MAX
