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
; 2009.07.10	- ADC init, start
;		- get values from adc, calculate with calibration data and store to channels space
;		- add digital filter for adc (no, x2, x4 - depends of status register, default x2)
; 2009.07.12	- small rewrite of adc interrupt (it triggers now ppm), adc is triggered every 20ms
;			from timer2 interrupt
;		- start ppm code
; 2009.07.13	- finish ppm code, it works! :-)
; 2009.07.14	- added basic model data with rules for blocks, channels and descriptions
;		- some cleanups
;		- added limits for generated ppm pulses (0.8...2.2ms)


.nolist
.include "m88def.inc"		;standard header for atmega88

.define DEBUG

; ******** STA£E *********
.equ	ZEGAR=11059200
.equ	ZEGAR_MAX=ZEGAR/64/1000
.equ	LCD_PWM=150000
.equ	DEFAULT_SPEED=ZEGAR/16/9600-1
.equ	CHANNELS_MAX=256
.equ	BLOCKS_MAX=128		;253 is absolute max
.equ	VERSION=1		;must be changed if eeprom format will change
.equ	TRIM_BYTES=10		;how much bytes are used to trim each a/c channel to produce -1..1 result
.equ	PPM_INTERVAL=20		;20ms for each frame
.equ	PPM_SYNC=ZEGAR*3/10000	;0.3ms
.equ	PPM_FRAME=ZEGAR*PPM_INTERVAL/1000	;20ms
.equ	PPM_CHANNELS=8		;number of output channels
.equ	PPM_MIN=ZEGAR*8/10000	;0.8ms - absolute minimum
.equ	PPM_MAX=ZEGAR*22/10000	;2.2ms - absolute maximum
;numbers
.equ	L_ZERO=0
.equ	L_JEDEN=0b0000010000000000	;1 in 6.10
.equ	L_MJEDEN=0b1111110000000000	;-1 in 6.10
;keyboard
.equ	KBD_DELAY=15		;debounce time for keyboard (*2ms)
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
; bits in status register
.equ	ADC_RUN=0
.equ	ADC_READY=1
.equ	ADC_FILTER=2
.equ	ADC_FILTER4=3
.equ	ADC_ON=4
.equ	PPM_ON=5
.equ	PPM_POL=6
.equ	MODEL_CHANGED=7
; status

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
		rjmp	t1cm	;Timer1 CompareB
		reti		;Timer1 Overflow
		reti		;Timer0 Compare MAtch A
		reti		;Timer0 Compare Match B
		reti		;Timer0 Overflow
		reti		;SPI transfer complete
		reti		;USART RX complete
		reti		;USART data register empty (UDRE)
		reti		;USART TX complete
		rjmp	adcc	;ADC conversion complete
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
		ldi	status,(1<<ADC_FILTER)		;set default values for status register
		
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
		ldi	temp,high(PPM_SYNC*2)
		sts	OCR1AH,temp
		ldi	temp,low(PPM_SYNC*2)
		sts	OCR1AL,temp
		ldi	temp,high(PPM_SYNC)
		sts	OCR1BH,temp
		ldi	temp,low(PPM_SYNC)
		sts	OCR1BL,temp
		ldi	temp,(1<<COM1B1)+(1<<COM1B0)+(1<<WGM11)+(1<<WGM10)	;non inverting ppm, fast pwm with ctc on OCR1A
		sts	TCCR1A,temp
		ldi	temp,(1<<WGM13)+(1<<WGM12)+(1<<CS10)
		sts	TCCR1B,temp
		ldi	temp,(1<<OCIE1B)	;enable interrupts from OC1B
		sts	TIMSK1,temp
		ldi	temp,8			;write 8'th channel, so it should stop at first interrupt
		sts	ppm_channel,temp
		sbi	DDRB,PB2		;output
		
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

		;ADC
		ldi	temp,0b00111111	;disable digital circuit on adc inputs
		sts	DIDR0,temp
		ldi	temp,(1<<REFS0)	;AVCC as reference voltage for ADC
		sts	ADMUX,temp
		ldi	temp,(1<<ADEN)+(1<<ADIE)+(1<<ADPS2)+(1<<ADPS1)	;enable adc, enable interrupts, prescaler /64
		sts	ADCSRA,temp
		sts	adc_channel,zero
		
		;enable interrupts
		sei

		;initialize lcd
		sbi	DDRB,PB2	;SS - must be output
		;sbi	DDRB,PB5	;SCK: output
		;sbi	DDRB,PB3	;MOSI: output
		;sbi	LCD_DDR_LED,LCD_LED	;backlight: output
		
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


		ori	status,(1<<ADC_ON)+(1<<PPM_ON)	;enable adc and ppm
main_loop:
		;copy input to output
		ldi	XL,low(channels)
		ldi	XH,high(channels)
		ldi	ZL,low(channels+32)
		ldi	ZH,high(channels+32)
		ldi	temp2,16
l1:
		ld	temp,X+
		st	Z+,temp
		dec	temp2
		brne	l1

.ifdef DEBUG
		rcall	kbd_debug
		waitms	5
		rcall	adc_debug
		waitms	5
		rcall	status_debug
		waitms	5
		rcall	ppm_debug
.endif


		rjmp	main_loop
banner:		.db	"(C) 2007-2009 Marek Wodzinski",0



; ######### SUBROUTINES ###########
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
		rcall	mem_debug

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
;

;
;
adc_debug:
		m_lcd_text_pos	0,7
		ldi	XL,low(adc_buffer)
		ldi	XH,high(adc_buffer)
		ldi	temp2,16
		rcall	mem_debug
		ret
;

;
;
ppm_debug:
		m_lcd_text_pos	0,11
		ldi	XL,low(ppm_debug_val)
		ldi	XH,high(ppm_debug_val)
		ldi	temp2,2
		rcall	mem_debug
		ret
;

;
;
status_debug:
		m_lcd_text_pos	0,10
		mov	temp,status
		swap	temp
		rcall	tohex
		sts	lcd_arg1,temp
		rcall	lcd_char
		mov	temp,status
		rcall	tohex
		sts	lcd_arg1,temp
		rcall	lcd_char
		ret
;


; X - memory address
; temp2 - number of bytes
mem_debug:
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
		brne	mem_debug
		ret
;
.endif
;	



;
; ####### math #########
.dseg
math_buf:	.byte	8
.cseg

.equ	math_arg1=math_buf
.equ	math_arg2=math_buf+2
.equ	math_arg3=math_buf+4
.equ	math_arg4=math_buf+6

;
; mul without sign
math_mul_simple:
;
; #
; ########## END SUBROUTINES ##########

;
; ############ INTERRUPTS ################
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
		lds	itemp,count20ms		;check for 20ms
		inc	itemp
		sts	count20ms,itemp
		cpi	itemp,PPM_INTERVAL
		brcs	t2cm_3
		;we are here every 20ms
		sts	count20ms,zero		;set counter to 0
		
		sbrs	status,ADC_ON		;check if ADC should be on
		rjmp	t2cm_2
		
		;start adc conversion
		andi	status,~(1<<ADC_READY)	;set status flags
		ori	status,(1<<ADC_RUN)
		
		sts	adc_channel,zero

		ldi	itemp,(1<<REFS0)	;reference source AVCC, channel=0
		sts	ADMUX,itemp
		
		lds	itemp,ADCSRA		;start new conversion
		ori	itemp,(1<<ADSC)
		sts	ADCSRA,itemp
		rjmp	t2cm_3
t2cm_2:
		;if adc is off, ppm must be triggered here
		sbrs	status,PPM_ON
		rjmp	t2cm_3
		;trigger ppm - TODO: copy buffer here?
		sts	ppm_channel,zero
		rcall	ppm_calc
		ldi	itemp,(1<<WGM13)+(1<<WGM12)+(1<<CS10)	;start clock again
		sts	TCCR1B,itemp

t2cm_3:
		;keyboard
		sbrc	mscountl,0	;call only on even miliseconds
		rcall	kbd_scan
r2cm_e:
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
count20ms:	.byte	1	;counter for counting 20ms
.cseg

;
; ADC conversion complete
adcc:
		in	itemp,SREG
		push	itemp
		
		;get last value
		lds	itemp3,ADCL
		lds	itemp4,ADCH
		
		;trigger next conversion if necessary
		lds	itemp,adc_channel	;check last channel number
		cpi	itemp,7			;if not last, trigger new conversion
		breq	adcc_1
		
		inc	itemp			;change mux to next channel
		ori	itemp,(1<<REFS0)	;add reference info
		sts	ADMUX,itemp
		
		lds	itemp,ADCSRA		;start new conversion
		ori	itemp,(1<<ADSC)
		sts	ADCSRA,itemp
adcc_1:
		;calculate channel value
		push	ZL
		push	ZH
		push	r0
		push	r1
		push	r3
		push	XL
		push	XH

		ldi	ZL,low(ch_trims<<1)	;calculate data start for current channel
		ldi	ZH,high(ch_trims<<1)
		lds	itemp,adc_channel
adcc_2:
		tst	itemp
		breq	adcc_4
adcc_3:
		adiw	ZL,TRIM_BYTES			;10 bytes per channel
		dec	itemp
		brne	adcc_3
adcc_4:
		lpm	itemp,Z+		;compare with center value
		lpm	itemp2,Z+
		cp	itemp,itemp3
		cpc	itemp2,itemp4
		brcc	adcc_5
		adiw	ZL,4			;skip values for lower half
adcc_5:
		lpm	itemp,Z+		;multiply by a
		lpm	itemp2,Z+
		clr	XH
		clr	XL
		mul	itemp,itemp3
		mov	r3,r1
		mul	itemp,itemp4
		add	r3,r0
		adc	XL,r1
		mul	itemp2,itemp3
		add	r3,r0
		adc	XL,r1
		adc	XH,zero
		mul	itemp2,itemp4
		add	XL,r0
		adc	XH,r1
		lsr	XH			;get right result (>>2)
		ror	XL
		ror	r3
		lsr	XH
		ror	XL
		ror	r3
		
		lpm	itemp,Z+		;and add b
		lpm	itemp2,Z+
		add	itemp,r3
		adc	itemp2,XL
		
		;store value to buffer
		ldi	ZL,low(adc_buffer-2)	;calculate address
		ldi	ZH,high(adc_buffer-2)
		lds	itemp3,adc_channel
		inc	itemp3
adcc_6:
		adiw	ZL,2
		dec	itemp3
		brne	adcc_6
		
		;digital filter
		sbrs	status,ADC_FILTER
		rjmp	adcc_8
		ld	itemp3,Z+		;filter x2
		ld	itemp4,Z+
		add	itemp,itemp3
		adc	itemp2,itemp4
		sbrs	status,ADC_FILTER4	;filter x4?
		rjmp	adcc_7
		add	itemp,itemp3
		adc	itemp2,itemp4
		add	itemp,itemp3
		adc	itemp2,itemp4
		asr	itemp2
		ror	itemp
adcc_7:
		asr	itemp2
		ror	itemp
		st	-Z,itemp2
		st	-Z,itemp
		rjmp	adcc_9
adcc_8:
		st	Z+,itemp		;no filter
		st	Z+,itemp2
adcc_9:
		;next channel
		lds	itemp,adc_channel	;calculate next channel
		inc	itemp
		sts	adc_channel,itemp
		
		;end?
		cpi	itemp,PPM_CHANNELS
		brne	adcc_e
		
		;last channel processed, set ready flag, etc
		ldi	ZL,low(adc_buffer)	;copy adc buffer to channels space
		ldi	ZH,high(adc_buffer)
		ldi	XL,low(channels)
		ldi	XH,high(channels)
		ldi	itemp2,16
adcc_10:
		ld	itemp,Z+
		st	X+,itemp
		dec	itemp2
		brne	adcc_10

		ldi	XL,low(out_buffer)	;copy output channels to ppm buffer
		ldi	XH,high(out_buffer)
		ldi	ZL,low(channels+32)	;output channels are 16-23
		ldi	ZH,high(channels+32)
		ldi	itemp2,16
adcc_11:
		ld	itemp,Z+
		st	X+,itemp
		dec	itemp2
		brne	adcc_11
		
		andi	status,~(1<<ADC_RUN)	;ready
		ori	status,(1<<ADC_READY)

		sbrs	status,PPM_ON		;trigger ppm if enabled
		rjmp	adcc_e
		;PPM first pulse
		sts	ppm_channel,zero
		rcall	ppm_calc
		ldi	itemp,(1<<WGM13)+(1<<WGM12)+(1<<CS10)	;start clock again
		sts	TCCR1B,itemp
adcc_e:
		pop	XH
		pop	XL
		pop	r3
		pop	r1
		pop	r0
		pop	ZH
		pop	ZL
		
		pop	itemp
		out	SREG,itemp
		reti
.dseg
adc_channel:	.byte	1	;current channel being processed
adc_buffer:	.byte	8*2	;buffer for processed adc values (values must be copied at once)
.cseg
;


;
; timer 1 compare B match (middle of pwm)
t1cm:
		in	itemp,SREG
		push	itemp
		
		lds	itemp,ppm_channel
		cpi	itemp,PPM_CHANNELS+1	;end?
		brne	t1cm_1
		;last channel, stop counter
		ldi	itemp,(1<<WGM13)+(1<<WGM12)
		sts	TCCR1B,itemp
		rjmp	t1cm_e
t1cm_1:
		;process new value
		rcall	ppm_calc
t1cm_e:
		pop	itemp
		out	SREG,itemp
		reti
.dseg
ppm_channel:	.byte	1
out_buffer:	.byte	8*2	;buffer for generating ppm
.cseg


; PPM: _________   ______   _________   _____   ______
;               |_|      |_|         |_|     |_|
;
;     - start --->|<-1 ch->|<- 2 ch  ->|    >|-|<-0.3ms
;
; timer clock: 11059200
; sync pulse:	0.3ms ~= 3318 clk
; minimum:	   1ms = 11059 clk
; center:	 1.5ms = 16589 clk
; max:		   2ms = 22118 clk
; counter max=(value+1024)*5.3999+11059=(value+3072)*5.3999

;
; calculate next counter value
ppm_calc:
		push	r0
		push	r1
		push	XL
		push	XH
		
		;get channel number to process
		lds	itemp,ppm_channel	;get buffer address
		cpi	itemp,PPM_CHANNELS	;last fake/synchro channel?
		breq	ppm_calc_2
		
		;get value
		lsl	itemp
		ldi	XL,low(out_buffer)
		ldi	XH,high(out_buffer)
		add	XL,itemp
		adc	XH,zero
		
		ld	itemp3,X+		;get value
		ld	itemp4,X+
		
		;recalculate
		ldi	itemp,high(3072)	;make 2..4 from -1..1
		add	itemp4,itemp
		
		ldi	itemp,low(5529)		;5.3994
		ldi	itemp2,high(5529)
		
		
		mul	itemp3,itemp		;multiply shifted value by 5.3994
		mov	XL,r1			;forget about r0, it's out of precision
		
		clr	XH
		mul	itemp3,itemp2
		clr	itemp3			;we can reuse itemp3, as all operations with it's value are done
		add	XL,r0
		adc	XH,r1
		adc	itemp3,zero
		
		mul	itemp4,itemp
		add	XL,r0
		adc	XH,r1
		adc	itemp3,zero
		
		mul	itemp4,itemp2
		add	XH,r0
		adc	itemp3,r1
		
		lsr	itemp3			;shift 2 bit right to skip fraction part (8 bits skipped at beginning of multiplication)
		ror	XH
		ror	XL
		lsr	itemp3
		ror	XH
		ror	XL
		
		;check min and max limits for pulse
		ldi	itemp,low(PPM_MIN)	;min
		ldi	itemp2,high(PPM_MIN)
		cp	XL,itemp
		cpc	XH,itemp2
		brcc	ppm_calc_0
		movw	XL,itemp	;copy minimum
		rjmp	ppm_calc_1
ppm_calc_0:
		ldi	itemp,low(PPM_MAX)	;max
		ldi	itemp2,high(PPM_MAX)
		cp	XL,itemp
		cpc	XH,itemp2
		brcs	ppm_calc_1
		movw	XL,itemp

		;program timer
ppm_calc_1:
		sts	OCR1AH,XH		;set new maximum time for next cycle
		sts	OCR1AL,XL
.ifdef DEBUG
		sts	ppm_debug_val,XH
		sts	ppm_debug_val+1,XL
.endif	
		lds	itemp,ppm_channel
		inc	itemp
		sts	ppm_channel,itemp
		
		pop	XH
		pop	XL
		pop	r1
		pop	r0
		ret
ppm_calc_2:
		;synchro pulse 
		ldi	XH,high(PPM_SYNC*2)	;short to make wake up also short
		ldi	XL,low(PPM_SYNC*2)
		rjmp	ppm_calc_1
;
.dseg
ppm_debug_val:	.byte	2
.cseg


; #
; ############ END INTERRUPTS ############
;


; ############ D A T A ##############
; #
flash_data:
		.db	0,84,0,0	;header
ch_trims:	.dw	0x01FF		;center position for channel 0
		.dw	0x0800		;a=2
		.dw	0xFC00		;b=-1
		.dw	0x0800,0xFC00	;a,b for second half
		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 1
		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 2
		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 3
		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 4
		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 5
		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 6
		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 7


.include "models.asm"
flash_pos:
		.dw	0

;.include "version.inc"		;include svn version as firmware version
.include "bootloader.inc"	;needed for flash reprogramming


; ############ VARIABLES ####################
.dseg
channels:	.byte	CHANNELS_MAX*2	;memory for channel values
blocks:		.byte	BLOCKS_MAX*2	;pointers to blocks
sequence:	.byte	2		;pointer to processing sequence block
cur_model:		.byte	1		;current model
;wr_tmp:		.byte	64	;buffer for flash write (2 pages for mega88)
;
; ############ EEPROM #####################
; #
.eseg
.org	0
eesig:		.db	0x55,0xaa	;signature
		.db	VERSION		;eeprom variables version
last_model:	.db	1
data_start:	.db	low(flash_data<<1)
		.db	high(flash_data<<1)
data_end:	.db	low(boot_start<<1)
		.db	high(boot_start<<1)
data_pos:	.db	low(flash_pos<<1)
		.db	high(flash_pos<<1)
