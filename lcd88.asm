; (C) 2009-2013 Marek Wodzinski
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
; 2009.07.13	- finished ppm code, it works! :-)
; 2009.07.14	- added basic model data with rules for blocks, channels and descriptions
;		- some cleanups
;		- added limits for generated ppm pulses (0.8...2.2ms)
; 2009.07.17	- load model from flash memory
; 2009.07.18	- find trims in storage
;		- use trims found in storage instead of hardcoded flash location
;		- fixed model_load
; 2009.08.15	- simple multitasking code:  (value calulations moved to task_calc)
;		- eeprom_init
;		- clean up source (comments, ascii arts and other useless stuff)
;		- load last model on startup
;		- fixed another ugly bug in model_load
;		- added searching for model description in model_load
; 2009.08.16	- added macros for eeprom read and write
;		- store configuration from status register in eeprom
;		- programmable output ppm polarisation
;		- main block processing loop
;		- started math in separate include
; 2009.08.17	- added storing/restoring math status bits from statush in task switching
;		- continue making math
; 2009.09.13	- some math work
;		- made some comments
;		- drawing output channel bars
; 2009.09.21	- some comments
;		- introduce CHANNEL_OUT constant - it's preparation to make some shift in channels
;		  to make room for extender
; 2009.11.11	- rename flash_data to storage
;		- some cleaning in models.asm to fit in new channel order
;		- use storage_end from eeprom instead of hardcoded value
;		- finished bar drawing (make bar red if overflow)
;		- fixed calculation of x coordinate in bars drawing
;		- more comments in bar graph
; 2009.11.12	- menu concept, data definition, menu structure
; 2009.11.17	- make status line
;		- model name moved to status line
;		- output bars moved to status line
;		- turn off debuging
; 2009.11.19	- start menu coding
;		- changed format of menu definition
; 2009.11.21	- small rewrite of part of menu showing (not finished yet)
; 2009.11.23	- showing menu finished
;		- start coding menu navigation (finding next, previous, upper and lower item)
; 2009.11.25	- menu navigation finished
;		- small size optimization in menu
;		- addedd missing initialization of statush
;		- moved some common code in menu drawing to separate subroutines
;		- moved storage common code out of model_find and trims_find to storage_*
;		- added storage_find
;		- trims_find rewriten (using storage_find)
; 2010.05.28	- some comments
;		- use PAGESIZE instead of hardcoded value
; 2012.09.13	- porting to run on both Mega88 and Mega168
; 2012.12.27	- fix interrupt table for Mega168/328
;		- added support for Atmega328
;		- some changes in math code
;		- calculation of digital input
;		- new block: copy
; 2012.12.28	- whole menu code removed as it was too complicated and not flexible
;		- small optimizations (code size)
; 2012.12.29	- tohex optimized
;		- moved .list to proper place
;		- small fix to clearing memory :-)
;		- show input/output values screen
;		- small optimizations (model_load)
;		- print hex value of channel
;		- print dec value of channel
;		- a small housekeeping
;		- menu_init done
;		- menu_loop done
;		- main menu defined, and works :-)
;		- model select
;		- debug screen
; 2012.01.02	- added menu_ram_* finctions, old menu_* functions changed, so menu_keys is resuable by both menu functions
; 2012.01.05	- trims for my transmitter
; 2012.01.06	- find end of storage instead of reding it from eeprom (it never worked)
;		- removed hack, so eeprom is initialized only after major version change
;		- changing model survives reboot :-)
;		- changed storage_find to not use mask, instead it looks for specific block id
;		- changed storage_skip_current and removed storage_get_end
; 2012.01.07	- menu_ram fixed and changed a little
;		- model_select rewritten using menu_ram
;		- add exception on processing block 0 in task_calc
;		- some numbers replaced by constants
;		- added subroutine to draw channel value and bar
;		- almost finished trims (todo: save values to eeprom)
; 2012.01.09	- added eeprom_read, rewritten code using it (saved 28B)
;		- moved some code to better place:-)
;		- bug fix in menu_trims (generation list of channels)
;		- functions to manage trims in eeprom
;		- storing trims in eeprom now works! :-)
;		- changing reverses
;		- expo
; 2012.01.10	- menu for trimming expo
;		- show credits and memory free
; 2013.03.02	- checked all code parts that depends of F_CPU
;		- added support for Atmega328P with 16MHz cpu clock as in Arduino Pro Mini


;TODO
; - show channel details on separate screen
; - show some info about flash and eeprom usage

.nolist

;cpu specific include headers
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

.list

;.define DEBUG

; ******** CONSTANTS *********

; Arduino have other clock frequency
.ifdef FCK16
    .equ        F_CPU=16000000	;Arduino Pro mini
.else
    .ifdef FCK11
	.equ        F_CPU=11059200	;my board
    .else
	.error	"Unsupported FCK!"
    .endif
.endif
.equ	COUNT_1MS=F_CPU/64/1000	;maximum counter value for 1ms interrupt - works only up to 16MHz!
.equ	LCD_PWM=150000		;LCD boost pwm frequency
;.equ	DEFAULT_SPEED=F_CPU/16/9600-1	;divider for serial interface
.equ	CHANNELS_MAX=252	;maximum number of channels, including internal, limited to 252 because of menu routines
.equ	BLOCKS_MAX=128		;253 is absolute max, each block=2B of ram, so on smaller cpus this value is limited
.equ	EE_SIG1=0xaa		;first byte of eeprom signature
.equ	EE_SIG2=0x55		;second byte of eeprom signature
.equ	EE_VERSION=4		;must be changed if eeprom format will change
.equ	TRIM_BYTES=10		;how much bytes are used to trim each a/c channel to produce -1..1 result
.equ	PPM_INTERVAL=20		;20ms for each frame
.equ	PPM_SYNC=F_CPU*3/10000	;0.3ms
.equ	PPM_FRAME=F_CPU*PPM_INTERVAL/1000	;20ms
.equ	PPM_CHANNELS=8		;number of output channels
.equ	PPM_MIN=F_CPU*8/10000	;0.8ms - absolute minimum
.equ	PPM_MAX=F_CPU*22/10000	;2.2ms - absolute maximum
.equ	MODEL_DELETED=5		;5th bit in header means that block is deleted
.equ	CHANNEL_OUT=16		;first output channel
.equ	CHANNEL_ZERO=24		;channel with constant 0
.equ	CHANNEL_ONE=25		;channel with 1
.equ	CHANNEL_MONE=26		;channel with -1
.equ	CHANNEL_USERMOD=27	;first channel that can be modified by user
; common numbers
.equ	L_ZERO=0
.equ	L_ONE= 0b0000010000000000	; 1 in 6.10
.equ	L_MONE=0b1111110000000000	;-1 in 6.10
.equ	L_M033=0b1111111010101011	;-0.33333
.equ	L_033= 0b0000000101010101	; 0.33333
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
.equ	KEY_UP=0		;keys in 'keys' variable
.equ	KEY_DOWN=1
.equ	KEY_LEFT=2
.equ	KEY_RIGHT=3
.equ	KEY_ENTER=4
.equ	KEY_ESC=5
; bits in status register
.equ	ADC_RUN=0
.equ	ADC_READY=1
.equ	ADC_FILTER=2		;enable x2 average on input channels
.equ	ADC_FILTER4=3		;x4 average, needs ADC_FILTER to work!
.equ	ADC_ON=4
.equ	PPM_ON=5
.equ	PPM_POL=6
.equ	MODEL_CHANGED=7
; statush
.equ	MATH_OV=0		;overflow flag
.equ	MATH_SIGN=1		;sign of result
.equ	BAR_OV=2		;needed for showing bars
.equ	EXTENDER=3		;extender present?
.equ	MENU_REDRAW=4		;menu needs redrawing?
.equ	MENU_CHANGED=5		;menu item selected/esc or enter key pressed
.equ	FMS_OUT=6		;output FMS PIC compatible frames via rs
.equ	STATUS_CHANGED=7	;if set, redraw all status line
;some block types
.equ	BLOCK_TRIM=1
.equ	BLOCK_REVERSE=2
.equ	BLOCK_EXPO=17
;menu constants
.equ	MENU_ESC=0xff	;esc pressed
.equ	MENU_END=0xfe	;end marker
.equ	MENU_NEXT=0xfd	;->
.equ	MENU_PREV=0xfc	;<-
.equ	TRIM_STEP=16	;

; registers
.def		zero=r2
; r3
.def		temp3=r4
.def		temp4=r5
.def		itemp3=r6
.def		itemp4=r7
.def		mtemp1=r8	;temp tegisters used in math
.def		mtemp2=r9
.def		mtemp3=r10
.def		mtemp4=r11
.def		mtemp5=r12
.def		mtemp6=r13
.def		temp5=r14
.def		temp6=r15
.def		temp=r16	;simple temp tegister
.def		temp2=r17	;second temp
.def		statush=r18
.def		status=r19
.def		itemp=r20	;temp register, but used only in interrupts
.def		itemp2=r21	;second interrupt temp
.def		mscountl=r22	;miliseconds counted for waitms
.def		mscounth=r23
.def		WL=r24
.def		WH=r25
; r26	XL		;
; r27	XH
; r28	YL		;
; r29	YH
; r30	ZL	- lpm
; r31	ZH


;
; ##########################
; ######### MACROS #########
; ##########################
; #

; czeka x ms
.macro		waitms
		push	temp2
		ldi	temp2,low(@0)
		rcall	waitms1
		pop	temp2
.endmacro

;write byte to eeprom
.macro		m_eeprom_write
		ldi	XL,low(@0)
		ldi	XH,high(@0)
		rcall	eeprom_write
.endmacro

;read byte from eeprom
.macro		m_eeprom_read
		ldi	temp,high(@0)
		out	EEARH,temp
		ldi	temp,low(@0)
		out	EEARL,temp
		sbi	EECR,EERE
		in	temp,EEDR
.endmacro

;reti but occupying 2 words (M168/328)
.macro		m_reti
		reti
		nop
.endmacro
;
; #
; #############################
; ######## END OF MACROS ######
; #############################



; # important global ram variables
.dseg
ram_temp:	.byte	11	;general purpose temporary space, used also in LCD (11B) and math code
.cseg



;
; ##########################################################################
; ########### MAIN CODE ####################################################
; ##########################################################################
; #

.cseg					;CODE segment
.org 0
.ifdef M88
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
.else
		jmp	reset	;RESET
		m_reti		;INT0
		m_reti		;INT1
		m_reti		;PCINT0
		m_reti		;PCINT1
		m_reti		;PCINT2
		m_reti		;WDT
		jmp	t2cm	;Timer2 Compare Match A
		m_reti		;Timer2 Compare Match B
		m_reti		;Timer2 Overflow
		m_reti		;Timer1 Capture
		m_reti		;Timer1 CompareA
		jmp	t1cm	;Timer1 CompareB
		m_reti		;Timer1 Overflow
		m_reti		;Timer0 Compare MAtch A
		m_reti		;Timer0 Compare Match B
		m_reti		;Timer0 Overflow
		m_reti		;SPI transfer complete
		m_reti		;USART RX complete
		m_reti		;USART data register empty (UDRE)
		m_reti		;USART TX complete
		jmp	adcc	;ADC conversion complete
		m_reti		;EEPROM ready
		m_reti		;Analog comparator
		m_reti		;Two wire serial interface
		m_reti		;SPM ready
.endif

;
; #################### LCD CODE ###############
; # it should be here because of some macros defined inside :-(
.include	"lcd-s65.asm"
;


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
		;ldi	status,(1<<ADC_FILTER)		;set default values for status register
		
		;clear ram
		ldi	XL,low(SRAM_START)
		ldi	XH,high(SRAM_START)
		ldi	YL,low(SRAM_SIZE-2)		;not all ram :-)
		ldi	YH,high(SRAM_SIZE-2)
		rcall	clear_ram
		
		;initialize timers
		;Timer0 - pwm for LCD backlight, 150kHz, 75% duty, output via OC0B, no prescaling
		ldi	temp,(F_CPU/LCD_PWM)	;150kHz
		out	OCR0A,temp
		ldi	temp,(F_CPU/LCD_PWM*75/100)	;75%
		out	OCR0B,temp
		ldi	temp,(1<<COM0B1)+(1<<WGM01)+(1<<WGM00)	;OC0B out, fast PWM with CTC
		out	TCCR0A,temp
		ldi	temp,(1<<WGM02)+(1<<CS00)
		out	TCCR0B,temp
		sbi	DDRD,PD5
		
		;Timer1 - pwm for PPM
		ldi	temp,high(PPM_SYNC*2)	;whole impulse length
		sts	OCR1AH,temp
		ldi	temp,low(PPM_SYNC*2)
		sts	OCR1AL,temp
		ldi	temp,high(PPM_SYNC)	;synchro pulse length
		sts	OCR1BH,temp
		ldi	temp,low(PPM_SYNC)
		sts	OCR1BL,temp
		ldi	temp,(1<<COM1B1)+(1<<WGM11)+(1<<WGM10)	;inverting ppm, fast pwm with ctc on OCR1A
		sbrs	status,PPM_POL
		ori	temp,(1<<COM1B0)	;non inverting ppm
		sts	TCCR1A,temp
		ldi	temp,(1<<WGM13)+(1<<WGM12)+(1<<CS10)
		sts	TCCR1B,temp
		ldi	temp,(1<<OCIE1B)	;enable interrupts from OC1B
		sts	TIMSK1,temp
		ldi	temp,8			;write 8'th channel, so it should stop at first interrupt
		sts	ppm_channel,temp
		sbi	DDRB,PB2		;output
		
		;Timer2 - time counting, ~1kHz, ctc, interrupts
		ldi	temp,(1<<WGM21)	;ctc
		sts	TCCR2A,temp
		ldi	temp,(1<<CS22)	;/64
		sts	TCCR2B,temp
		ldi	temp,COUNT_1MS	;counting up to COUNT_1MS
		sts	OCR2A,temp
		sts	ASSR,zero	;synchronous
		ldi	temp,(1<<OCIE2A)	;interrupt on timer overflow
		sts	TIMSK2,temp

		;ADC
		ldi	temp,0b00111111	;disable digital circuit on adc inputs
		sts	DIDR0,temp
		ldi	temp,(1<<REFS0)	;AVCC as reference voltage for ADC
		sts	ADMUX,temp
		ldi	temp,(1<<ADEN)+(1<<ADIE)+(1<<ADPS2)+(1<<ADPS1)	;enable adc, enable interrupts, prescaler /64
		sts	ADCSRA,temp
		sts	adc_channel,zero

		;initialize math stack pointer
		rcall	math_init

		;initialize end of flash data position
		rcall	storage_find_end

		;get some data from eeprom (initialize also status register)
		rcall	eeprom_init	; it could enable interrupts!

		;enable interrupts
		sei

		;initialize lcd
		rcall	lcd_initialize

		rcall	trims_find		;find trim data for sticks
		
		rcall	model_load		;load last used model (read from eeprom)

		ori	statush,(1<<STATUS_CHANGED)	;draw status bar
		rcall	show_status

		ori	status,(1<<ADC_ON)+(1<<PPM_ON)	;enable adc and ppm (it also enables multitasking)

		ori	statush,(1<<MENU_REDRAW)	;force redraw menu on first call


		; #################### MAIN LOOP #####################
main_loop:

		;rcall	show_out_bars
		;rcall	show_io_values
		
		;rjmp	main_loop

		; ################### END OF MAIN LOOP ################




; ####################################################################
; ############    SUBROUTINES    #####################################
; ####################################################################
; #


;
; main menu
main_menu:
		ldi	ZL,low(main_menu_def<<1)
		ldi	ZH,high(main_menu_def<<1)
		rcall	menu_init
main_menu_1:
		rcall	menu_loop
		sbrs	statush,MENU_CHANGED
		rjmp	main_menu_1
		
		;something pressed!
		lds	temp,menu_pos
		cpi	temp,MENU_ESC	;ESC
		breq	main_menu	;do nothing
		
		cpi	temp,3		;debug
		breq	menu_debug_f
		
		cpi	temp,1
		breq	menu_reverse_f
		
		cpi	temp,0
		breq	menu_trims
		
		cpi	temp,4
		breq	menu_expo_f

		cpi	temp,2		;model select
		breq	model_select_f
		
		cpi	temp,5
		breq	show_info_f
		
		rjmp	main_menu
main_menu_def:	.db	"Main menu",0
		.db	0,"Trims",0,1,"Reverse",0,4,"Expo",0,2,"Model select",0,5,"Info",0,3,"Debug",0,0xff
;

; # far jumps....
model_select_f:	rjmp	model_select
menu_debug_f:	rjmp	menu_debug
menu_reverse_f:	rjmp	menu_reverse
menu_expo_f:	rjmp	menu_expo
show_info_f:	rjmp	show_info
;


;
; # trims
; TODO: max-trims-menu, pages
menu_trims:
		ldi	temp,BLOCK_TRIM		;search for trims
		mov	temp5,temp
		ldi	ZL,low(menu_trims_txt<<1)
		ldi	ZH,high(menu_trims_txt<<1)
		
menu_trim_rev:
		;init menu
		rcall	menu_ram_init

		;preare menu entries - find all trim channels connected to trim block for current model
		ldi	YL,low(menu_ram)
		ldi	YH,high(menu_ram)
		
		lds	ZL,sequence	;get address of processing sequence
		lds	ZH,sequence+1
		
		adiw	ZL,1		;get block length
		lpm	temp3,Z+
		dec	temp3		;- header
		dec	temp3
menu_trims_1:
		lpm	temp,Z+		;get block number
		movw	WL,ZL		;store Z for later
		cpi	temp,0		;last block, zero padded?
		breq	menu_trims_1e
		
		ldi	XL,low(blocks)	;pointer to block
		ldi	XH,high(blocks)
		add	XL,temp		;calculate address
		adc	XH,zero
		add	XL,temp
		adc	XH,zero
		ld	ZL,X+		;get block address
		ld	ZH,X
		adiw	ZL,4		;get block type @+4
		lpm	temp,Z
		cp	temp,temp5	;trim/reverse?
		brne	menu_trims_1e
		
		;trim/reverse
		adiw	ZL,4		;second input channel @+8
		lpm	temp,Z		;get channel id
		st	Y+,temp		;store channel id
		
menu_trims_1e:
		movw	ZL,WL		;restore Z
		dec	temp3		;decrease blocks count
		brne	menu_trims_1

		ldi	temp,MENU_END	;end of menu
		st	Y,temp
		
		rcall	menu_ram_setpos
		
		;check for empty menu!
		lds	temp,menu_ram
		cpi	temp,MENU_END
		brne	menu_trims_2
		;empty menu
		rjmp	main_menu
menu_trims_2:
		;draw all channels (values and bars)
		ldi	XL,low(menu_ram)	;menu
		ldi	XH,high(menu_ram)
		ldi	temp,1
		sts	lcd_txt_y,temp
menu_trims_3:
		ldi	temp,3			;set text coordinates
		sts	lcd_txt_x,temp
		ld	temp,X+		;get channel
		cpi	temp,MENU_END
		breq	menu_trims_4	;all drawed?
		
		rcall	channel_draw	;draw channel
		
		lds	temp,lcd_txt_y	;calculate next Y
		inc	temp
		sts	lcd_txt_y,temp
		
		rjmp	menu_trims_3

menu_trims_4:
		rcall	menu_ram_loop	;make menu loop
		
		lds	temp,keys	;check for left/right keys
		andi	temp,(1<<KEY_LEFT)|(1<<KEY_RIGHT)
		brne	menu_trims_5	;pressed?
		
		sbrs	statush,MENU_CHANGED	;something else pressed?
		rjmp	menu_trims_4
		
		;something pressed
		lds	temp,menu_pos
		cpi	temp,MENU_ESC
		brne	menu_trims_4
		rjmp	main_menu
menu_trims_5:
		;left/right key pressed
		lds	temp2,keys	;wait for key release
		andi	temp2,(1<<KEY_LEFT)|(1<<KEY_RIGHT)
		brne	menu_trims_5
		
		mov	temp3,temp	;for later
		
		lds	temp,menu_pos	;get menu position
		rcall	calc_channel_addrY	;get channel value
		ld	XL,Y+
		ld	XH,Y
		
		sbrs	temp3,KEY_LEFT
		rjmp	menu_trims_6
		;left pressed
		mov	temp,temp5
		cpi	temp,BLOCK_REVERSE	;trim or reverse?
		breq	menu_trims_5a
		;left - trim (or others)
		sbiw	XL,TRIM_STEP
		rjmp	menu_trims_7
menu_trims_5a:
		;left - reverse
		ldi	XL,low(L_MONE)
		ldi	XH,high(L_MONE)
		rjmp	menu_trims_7
menu_trims_6:
		;not left pressed
		sbrs	temp3,KEY_RIGHT
		rjmp	menu_trims_4
		;right pressed
		mov	temp,temp5
		cpi	temp,BLOCK_REVERSE
		breq	menu_trims_6a
		;right - trim
		adiw	XL,TRIM_STEP
		rjmp	menu_trims_7
menu_trims_6a:
		;right - reverse
		ldi	XL,low(L_ONE)
		ldi	XH,high(L_ONE)
menu_trims_7:
		;store back channel value
		sbiw	YL,1
		st	Y+,XL
		st	Y,XH
		
		;store to eeprom
		lds	temp2,menu_pos
		rcall	ee_trim_write
		
		;redraw only one channel
		ldi	YL,low(menu_ram)
		ldi	YH,high(menu_ram)
		ldi	temp,1
		lds	temp3,menu_pos
menu_trims_8:
		ld	temp2,Y+	;get menu item
		cpi	temp2,MENU_END	;end?
		breq	menu_trims_9
		cp	temp2,temp3	;found?
		breq	menu_trims_9
		inc	temp		;next
		rjmp	menu_trims_8
menu_trims_9:
		sts	lcd_txt_y,temp	;set text x/y
		ldi	temp,3
		sts	lcd_txt_x,temp
		mov	temp,temp3	;channel number
		rcall	channel_draw
		
		rjmp	menu_trims_4
menu_trims_txt:	.db	"Trims",0
;menu_trims_txt1: .db	"Not found!",0
;


;
; #
menu_reverse:
		ldi	temp,BLOCK_REVERSE		;search for reverses
		mov	temp5,temp
		ldi	ZL,low(menu_reverse_txt<<1)
		ldi	ZH,high(menu_reverse_txt<<1)
		
		rjmp	menu_trim_rev
menu_reverse_txt: .db	"Reverse",0
;


;
; #
menu_expo:
		ldi	temp,BLOCK_EXPO		;search for expo
		mov	temp5,temp
		ldi	ZL,low(menu_expo_txt<<1)
		ldi	ZH,high(menu_expo_txt<<1)
		
		rjmp	menu_trim_rev
menu_expo_txt:	.db	"Expo ",0
;


;
; # menu debug
menu_debug:
		rcall	show_io_values	;draw something
		rcall	show_out_bars
		
		lds	temp,keys	;check for ESC
		andi	temp,(1<<KEY_ESC)
		breq	menu_debug
menu_debug_1:
		lds	temp,keys	;wait for ESC release
		andi	temp,(1<<KEY_ESC)
		brne	menu_debug_1
		rjmp	main_menu
;


;
; # select model
.equ	MAX_MODELS_MENU=12
model_select:
		;draw menu
		ldi	ZL,low(model_select_def<<1)
		ldi	ZH,high(model_select_def<<1)
		rcall	menu_ram_init
		
		m_lcd_set_bg	COLOR_WHITE
		m_lcd_set_fg	COLOR_BLACK

		;draw model names
		ldi	temp,1	;start at 1 model
		sts	lcd_txt_y,zero	;also at 
		ldi	XL,low(menu_ram)	;get pointer to menu definition
		ldi	XH,high(menu_ram)
model_select_2:
		push	temp
		;model+(3<<6),14,0,"Basic 4CH",0,0
		ori	temp,(3<<6)	;add bits for comment block
		ldi	temp2,0		;block id
		rcall	storage_find	;find block in storage
		pop	temp
		
		mov	temp2,ZL	;found anything?
		or	temp2,ZH
		breq	model_select_3	;not

		;found something
		ldi	temp2,3		;set text position
		sts	lcd_txt_x,temp2
		
		lds	temp2,lcd_txt_y
		cpi	temp2,MAX_MODELS_MENU	;maximum number of models displayed?
		breq	model_select_4
		inc	temp2
		sts	lcd_txt_y,temp2	;next row
		
		st	X+,temp		;save this model id in menu
		
		adiw	ZL,3		;start of text
		push	temp
		rcall	lcd_text	;display model name
		pop	temp
model_select_3:		
		inc	temp
		cpi	temp,32		;max model id?
		brne	model_select_2
model_select_4:
		ldi	temp,MENU_END	;end of menu mark
		st	X,temp
		
		lds	temp,cur_model	;set menu position to current model
		sts	menu_pos,temp

		;menu handling
model_select_1:
		rcall	menu_ram_loop
		sbrs	statush,MENU_CHANGED
		rjmp	model_select_1
		
		;something pressed
		lds	temp,menu_pos
		cpi	temp,MENU_ESC	;ESC
		breq	model_select_e
		
		;set active model!
		sts	cur_model,temp		;change active model
		m_eeprom_write	ee_last_model	;save to eeprom
		rcall	model_load		;load new model

		ori	statush,(1<<STATUS_CHANGED)	;draw status bar
model_select_e:
		rjmp	main_menu
		

model_select_def:	.db	"Select model ",0
;


;
; # show some info
show_info:
		;draw something
		
		;top bar
		rcall	top_bar_clear
		ldi	ZL,low(show_info_txt_1<<1)
		ldi	ZH,high(show_info_txt_1<<1)
		rcall	top_bar_text
		
		;copyright
		rcall	menu_body_clear
		m_lcd_set_bg	COLOR_WHITE
		m_lcd_set_fg	COLOR_BLACK
		ldi	ZL,low(show_info_txt_2<<1)
		ldi	ZH,high(show_info_txt_2<<1)
		rcall	lcd_text
		
		;flash free
		ldi	ZL,low(show_info_txt_3<<1)
		ldi	ZH,high(show_info_txt_3<<1)
		rcall	lcd_text
		
		lds	temp3,storage_end
		lds	temp4,storage_end+1
		ldi	temp,low(flash_end<<1)
		ldi	temp2,high(flash_end<<1)
		sub	temp,temp3
		sbc	temp2,temp4
		push	temp
		mov	temp,temp2
		rcall	print_byte_hex
		pop	temp
		rcall	print_byte_hex
		
		;eeprom free
		ldi	ZL,low(show_info_txt_4<<1)
		ldi	ZH,high(show_info_txt_4<<1)
		rcall	lcd_text

		mov	temp3,zero		;count eeprom free memory
		ldi	XL,low(ee_trims)
		ldi	XH,high(ee_trims)
		ldi	temp2,high(ee_trims_end)
show_info_0:
		rcall	eeprom_read		;get model id
		cpi	temp,0xff		;free?
		brne	show_info_0a
		inc	temp3			;yes
show_info_0a:
		adiw	XL,4
		cpi	XL,low(ee_trims_end)
		cpc	XH,temp2
		brcs	show_info_0
		
		mov	temp,temp3
		rcall	print_byte_hex
		
show_info_1:
		rcall	show_out_bars
		
		lds	temp,keys	;check for ESC
		andi	temp,(1<<KEY_ESC)
		breq	show_info_1
show_info_2:
		lds	temp,keys	;wait for ESC release
		andi	temp,(1<<KEY_ESC)
		brne	show_info_2
		rjmp	main_menu
show_info_txt_1: .db	"Info ",0
show_info_txt_2: .db	13,10,"LCD88 (C) 2009-2013",13
		.db	10,"Marek Wodzinski",13,10,"http://majek.mamy.to",13,10,13,10,0,0
show_info_txt_3: .db	"Flash free:  0x",0
show_info_txt_4: .db	13,10,"Eeprom free: 0x",0
;


;
; helpers for drawing/using menu area
top_bar_clear:
		m_lcd_set_fg	COLOR_DKRED	;set upper part (for menu name)
		m_lcd_fill_rect	0,0,DISP_W,CHAR_H
		ret
;
top_bar_text:
		m_lcd_set_bg	COLOR_DKRED
		m_lcd_set_fg	COLOR_WHITE
		m_lcd_text_pos	0,0
		rcall	lcd_text
		ret
;
.equ	BODY_H=12
menu_body_clear:
		m_lcd_set_fg	COLOR_WHITE	;clear rest of screen
		m_lcd_fill_rect	0,8,DISP_W,BODY_H*CHAR_H
		ret
;


;
; redraw status line
.equ	STATUS_LINE_Y=(1+BODY_H)*CHAR_H		;(status line + body) 
show_status:
		sbrs	statush,STATUS_CHANGED
		ret
		;set background
		m_lcd_set_fg	COLOR_BLACK
		m_lcd_fill_rect	0,STATUS_LINE_Y,DISP_W,DISP_H-STATUS_LINE_Y
		
		;model name
		rcall	show_model_name
		
		;output bars
		rcall	show_out_bars
		
		andi	statush,255-(1<<STATUS_CHANGED)
		ret
;


;
; show model name
show_model_name:
		m_lcd_set_fg	COLOR_DKBLUE
		m_lcd_fill_rect	0,STATUS_LINE_Y,DISP_W,CHAR_H

		m_lcd_text_pos	0,(1+BODY_H)
		m_lcd_set_bg	COLOR_DKBLUE
		m_lcd_set_fg	COLOR_YELLOW
		sbrs	status,MODEL_CHANGED
		rjmp	show_model_name_1
		m_lcd_set_fg	COLOR_RED
show_model_name_1:
		lds	ZL,model_name
		lds	ZH,model_name+1
		adiw	ZL,3
		rcall	lcd_text
		ret
;


;
; draw bars of output channels (height is fixed to 16)
.equ		OUT_BARS_WIDTH=6	;bar width
.equ		OUT_BARS_SPACE=2	;space between bars
.equ		OUT_BARS_X=DISP_W-8*(OUT_BARS_WIDTH+OUT_BARS_SPACE)-1	;X coordinate of first bar
;.equ		OUT_BARS_Y=CHAR_H*(1+BODY_H+1)+1
.equ		OUT_BARS_Y=DISP_H-19
show_out_bars:
		ldi	temp2,PPM_CHANNELS	;8 channels
show_out_bars_1:
		push	temp2
		
		;recalculate channel value to bar height
		ldi	XL,low(channels+CHANNEL_OUT*2-2) ;start of output channels memory
		ldi	XH,high(channels+CHANNEL_OUT*2-2)
		add	XL,temp2		;add channel number*2
		adc	XH,zero
		add	XL,temp2
		adc	XH,zero
		
		ld	temp,X+	;get channel value
		ld	temp2,X
		
		andi	statush,~(1<<BAR_OV)	;reset overflow
		sbci	temp2,-4	;+4
		brpl	show_out_bars_2	;still minus?
		ori	statush,(1<<BAR_OV)	;set overflow
		clr	temp		;clear argument
		clr	temp2
show_out_bars_2:
		add	temp,temp	;x2
		adc	temp2,temp2
		cpi	temp2,17	;check upper limit
		brcs	show_out_bars_3
		ori	statush,(1<<BAR_OV)
		ldi	temp2,16
show_out_bars_3:			;temp2 - value (0..16)
		;caclulate X coordinate of bar
		pop	temp3		;get channel number to temp3
		push	temp3
		
		ldi	temp,OUT_BARS_X-OUT_BARS_WIDTH-OUT_BARS_SPACE
show_out_bars_4:
		clc
		sbci	temp,-(OUT_BARS_WIDTH+OUT_BARS_SPACE)
		dec	temp3
		brne	show_out_bars_4
		
		;set dimensions of bar
		sts	lcd_arg1,temp	;x
		ldi	temp,OUT_BARS_Y	;y
		sts	lcd_arg2,temp
		ldi	temp,OUT_BARS_WIDTH	;dx
		sts	lcd_arg3,temp
		ldi	temp,17		;dy - calulate height of background bar
		sub	temp,temp2
		sts	lcd_arg4,temp
		m_lcd_set_fg	COLOR_BLACK
		push	temp2
		rcall	lcd_fill_rect	;draw upper part of bar (white background)
		pop	temp2
		
		m_lcd_set_fg	COLOR_GREEN
		inc	temp2		;dy - bar should have at least one pixel of height
		sts	lcd_arg4,temp2
		
		dec	temp2		;y
		ldi	temp,17
		sub	temp,temp2
		ldi	temp2,OUT_BARS_Y
		add	temp,temp2
		sts	lcd_arg2,temp
		
		sbrs	statush,BAR_OV	;if overflow, set color to red
		rjmp	show_out_bars_6
		m_lcd_set_fg	COLOR_RED
show_out_bars_6:
		rcall	lcd_fill_rect	;draw lower part of bar

		pop	temp2
		dec	temp2
		breq	show_out_bars_5
		rjmp	show_out_bars_1
show_out_bars_5:
		;m_lcd_set_fg	COLOR_BLACK	;restore default color
		ret
;


;
; init lcd screen and draw something on it
lcd_initialize:
		waitms	250
		rcall	lcd_init
		ret
;


;
; show input/output values
.equ	SHOW_IO_Y=2
show_io_values:
		sbrs	statush,MENU_REDRAW	;don't redraw whole screen every time
		rjmp	show_io_values_2
		
		rcall	top_bar_clear	;draw title
		ldi	ZL,low(show_io_txt1<<1)
		ldi	ZH,high(show_io_txt1<<1)
		rcall	top_bar_text
		
		rcall	menu_body_clear	;clear body
		
		m_lcd_set_bg	COLOR_WHITE
		m_lcd_set_fg	COLOR_DKBLUE
		
		m_lcd_text_pos	0,SHOW_IO_Y	;header
		m_lcd_text	show_io_txt2

		m_lcd_set_fg	COLOR_BLACK
		
		;draw channel numbers
                ldi	temp,SHOW_IO_Y+1
show_io_values_1:
                sts     lcd_txt_x,zero	;set position
                sts     lcd_txt_y,temp
                push	temp
                
        	subi	temp,-(47-SHOW_IO_Y)	;make char from position number
                sts	lcd_arg1,temp	;print channel number
                rcall	lcd_char

                pop	temp
                inc	temp
                cpi	temp,SHOW_IO_Y+9
                brne	show_io_values_1
		
		andi	statush,~(1<<MENU_REDRAW)
show_io_values_2:
		;draw values
		m_lcd_set_bg	COLOR_WHITE	;set colors
		m_lcd_set_fg	COLOR_BLACK
		ldi	temp,0			;init channel number
show_io_values_3:
		push	temp
		subi	temp,-(SHOW_IO_Y+1)	;set position
		ldi	temp2,2
		sts	lcd_txt_x,temp2
		sts	lcd_txt_y,temp
		pop	temp
		
		push	temp
		rcall	print_ch_hex		;input channel
		
		lds	temp,lcd_txt_x		;move cursor
		inc	temp
		sts	lcd_txt_x,temp
		pop	temp
		push	temp
		
		subi	temp,-CHANNEL_OUT	;show output channel
		rcall	print_ch_hex		;input channel
		
		lds	temp,lcd_txt_x		;move cursor
		inc	temp
		sts	lcd_txt_x,temp

		pop	temp
		push	temp

		rcall	print_ch_dec		;print dec value of channel
		
		pop	temp
		inc	temp			;end of loop
		cpi	temp,8
		brne	show_io_values_3
		
		ret
show_io_txt1:	.db	"Input/output values",0
show_io_txt2:	.db	"C IN   OUT  IN(dec)",0
;


;
; # in: temp - channel number, text cursor set at right position
.equ	CH_BAR_LEN=81
.equ	CH_BAR_OFFSET=6
channel_draw:
		push	temp
		m_lcd_set_fg	COLOR_BLACK	;text color
		m_lcd_set_bg	COLOR_WHITE
		pop	temp
		
		push	temp
		rcall	print_ch_dec	;print dec value of channel, Y=channel address+2
		pop	temp
		
channel_draw_bar:
		rcall	calc_channel_addrY
		ld	mtemp1,Y+	;get channel value
		ld	mtemp2,Y
		rcall	math_push	;push on math stack
		
		ldi	temp,low(10*1024)	;push 10 on stack
		mov	mtemp1,temp
		ldi	temp,high(10*1024)
		mov	mtemp2,temp
		rcall	math_push
		
		rcall	math_mul	;multiply
		rcall	math_pop	;get result
		
		ldi	temp,40		;scale up
		add	temp,mtemp2
		sbrc	temp,7	;sign
		mov	temp,zero
		cpi	temp,CH_BAR_LEN		;maximum
		brcs	channel_draw_1
		ldi	temp,CH_BAR_LEN
channel_draw_1:
		;temp - length of bar
		mov	temp3,temp
		
		;first bar - full length
		m_lcd_set_fg	COLOR_DKBLUE
		lds	temp,lcd_txt_x	;calculate X axis
		rcall	temp_mul8
		subi	temp,-CH_BAR_OFFSET
		sts	lcd_arg1,temp
		
		lds	temp,lcd_txt_y	;Y
		rcall	temp_mul8
		subi	temp,-1
		sts	lcd_arg2,temp
		
		ldi	temp,CH_BAR_LEN	;dx
		sts	lcd_arg3,temp
		ldi	temp,6		;dy
		sts	lcd_arg4,temp
		
		rcall	lcd_fill_rect	;draw bar
		
		;second bar - length proportional to channel value
		lds	temp,lcd_arg1	;X
		add	temp,temp3
		sts	lcd_arg1,temp
		
		ldi	temp,CH_BAR_LEN+1
		sub	temp,temp3
		sts	lcd_arg3,temp	;dx (y remains the same)
		
		ldi	temp,4		;dy
		sts	lcd_arg4,temp
		
		m_lcd_set_fg	COLOR_WHITE
		rcall	lcd_fill_rect
		
		;center mark
		lds	temp,lcd_txt_x	;x
		rcall	temp_mul8
		subi	temp,-(40+CH_BAR_OFFSET)
		sts	lcd_arg1,temp
		
		ldi	temp,1		;dx
		sts	lcd_arg3,temp
		ldi	temp,6		;dy
		sts	lcd_arg4,temp
		
		m_lcd_set_fg	COLOR_MAGENTA
		rcall	lcd_fill_rect
		
		ret
;


;
; # multiply temp x8
temp_mul8:
		lsl	temp
		lsl	temp
		lsl	temp
		ret
;


;
; print channel value (hex)
; temp - channel number
print_ch_hex:
		call	calc_channel_addrY
		
		ldd	temp,Y+1		;high byte first
		rcall	print_byte_hex

		ld	temp,Y		;low byte
		rjmp	print_byte_hex
;


;
; # print byte in hex from temp
; in: temp
print_byte_hex:
		push	temp
		swap	temp
		rcall	tohex
		sts	lcd_arg1,temp
		rcall	lcd_char
		pop	temp
		rcall	tohex
		sts	lcd_arg1,temp
		rcall	lcd_char
		ret
;


;
; # print channel value (dec)
; in: temp - channel number
print_ch_dec:
		rcall	calc_channel_addrY		;dec!
		ld	mtemp1,Y+
		ld	mtemp2,Y+
		rcall	math_todec
		m_lcd_text_ram	math_todec_out,8
		ret
;


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
		subi	temp,-7
tohex1:		ret
;


;
; clear ram
; X - address
; Y - bytes count
clear_ram:
		st	X+,zero
		dec	YL
		brne	clear_ram
		dec	YH
		brne	clear_ram
		ret
;


;
; # calculate channel address
; in: temp - channel number
; out: X - address
calc_channel_addrX:
		ldi	XL,low(channels)	;start of channels address space
		ldi	XH,high(channels)
		add	XL,temp			;calculate address of this channel
		adc	XH,zero
		add	XL,temp
		adc	XH,zero
		ret
;
;

;
; # calculate channel address
; in: temp - channel number
; out: Y - memory address
calc_channel_addrY:
		ldi	YL,low(channels)	;get channel address
		ldi	YH,high(channels)
		add	YL,temp
		adc	YH,zero
		add	YL,temp
		adc	YH,zero
		ret
;


;
; ############# menu routines ###########

.dseg
menu_pos:	.byte	1	;current menu position, 0xff - esc pressed
menu_def:	.byte	2	;pointer to current menu definition
menu_ram:	.byte	13	;space for menu numbers, should be 0xfe terminated
.cseg
;menu format:
;	0 - header text (null terminated)
;	1 - return value
;	2 - null terminated string
;	3 - return value
;	4 - ...
;	5 - FF - end of menu


;
; # initialize menu/redraw everything from scratch
; in: Z - address to menu definition
menu_init:
		push	ZL
		push	ZH
		rcall	top_bar_clear	;clear top bar (destroys Z)
		pop	ZH
		pop	ZL
		rcall	top_bar_text	;print something in top bar
		sts	menu_def,ZL	;store pointer to real menu
		sts	menu_def+1,ZH
		lpm	temp,Z		;get first menu id
		sts	menu_pos,temp	;and store it as first selected
		rcall	menu_body_clear	;clear body area
		andi	statush,~(1<<MENU_CHANGED)	;clear 'dirty' flag
		ori	statush,(1<<MENU_REDRAW)	;force first menu redraw
menu_loop:
		;here is main loop
		sbrs	statush,MENU_REDRAW	;skip drawing if not needed
		rjmp	menu_keys
		
		;redrawing menu
		ldi	YL,low(menu_ram)	;address of menu items list
		ldi	YH,high(menu_ram)
		ldi	temp2,1		;first Y of menu
		lds	ZL,menu_def	;get address of the rest
		lds	ZH,menu_def+1
menu_loop_1:
		sts	lcd_txt_x,zero	;set position
		sts	lcd_txt_y,temp2
		lpm	temp,Z+		;get menu position id
		st	Y+,temp		;store in buffer for later
		lds	temp3,menu_pos
		cp	temp,temp3	;is it current position?
		breq	menu_loop_2
		;no, default colors
		m_lcd_set_bg	COLOR_WHITE
		m_lcd_set_fg	COLOR_BLACK
		rjmp	menu_loop_3
menu_loop_2:
		m_lcd_set_bg	COLOR_BLACK
		m_lcd_set_fg	COLOR_WHITE
menu_loop_3:
		push	temp2
		rcall	lcd_text
		pop	temp2
		inc	temp2
		lpm	temp,Z
		cpi	temp,0xff	;end of menu?
		brne	menu_loop_1
		
		ldi	temp,MENU_END	;save end of menu mark
		st	Y,temp

menu_keys:
		;check for keys pressed
		lds	temp,keys	;check if any interesting key is pressed?
		andi	temp,(1<<KEY_UP)|(1<<KEY_DOWN)|(1<<KEY_ESC)|(1<<KEY_ENTER)
		brne	menu_keys_1
		;nothing pressed
		rcall	show_out_bars	;we need redraw it every time
		rcall	show_status
		ret
menu_keys_1:
		;wait for key release
		push	temp
		rcall	show_out_bars	;redraw bars waiting for key release
		rcall	show_status
		pop	temp
		lds	temp2,keys
		andi	temp2,(1<<KEY_UP)|(1<<KEY_DOWN)|(1<<KEY_ESC)|(1<<KEY_ENTER)
		brne	menu_keys_1
		
		;key released
		sbrc	temp,KEY_UP
		rjmp	menu_keys_up
		sbrc	temp,KEY_DOWN
		rjmp	menu_keys_down
		sbrc	temp,KEY_ESC
		rjmp	menu_keys_esc
		sbrc	temp,KEY_ENTER
		rjmp	menu_keys_enter
		ret		;ignore other keys

menu_keys_up:
		;now we should find id before current
		ldi	YL,low(menu_ram)
		ldi	YH,high(menu_ram)
		lds	temp3,menu_pos	;get current position
		mov	temp4,temp3	;init last pos
menu_keys_up_1:
		ld	temp,Y+		;get id
		cpi	temp,MENU_END	;check if it's the end
		breq	menu_keys_up_e
		cp	temp,temp3	;check for current id
		breq	menu_keys_up_e
		;not found, skip to next
		mov	temp4,temp	;remember last position
		rjmp	menu_keys_up_1
menu_keys_up_e:
		sts	menu_pos,temp4	;set new position
		ori	statush,(1<<MENU_REDRAW)	;force redraw
		ret

menu_keys_down:
		;we need find id after current one
		ldi	YL,low(menu_ram)
		ldi	YH,high(menu_ram)
		lds	temp3,menu_pos	;get current position
		mov	temp4,temp3
menu_keys_down_1:
		;find current position
		ld	temp,Y+
		cpi	temp,MENU_END	;end of definition?
		breq	menu_keys_down_e
		cp	temp,temp3	;found?
		breq	menu_keys_down_3
		rjmp	menu_keys_down_1
menu_keys_down_3:
		ld	temp,Y		;get next id of end of menu
		cpi	temp,MENU_END
		breq	menu_keys_down_e
		mov	temp4,temp
menu_keys_down_e:
		sts	menu_pos,temp4	;set new position
		ori	statush,(1<<MENU_REDRAW)	;force redraw
		ret		

menu_keys_esc:
		ldi	temp,MENU_ESC	;esc code
		sts	menu_pos,temp
menu_keys_enter:
		ori	statush,(1<<MENU_CHANGED)	;set flag that something happen in menu
		ret
;

;
; # custom menu from ram
; in: Z - address of menu description
menu_ram_init:
		push	ZL
		push	ZH
		rcall	top_bar_clear	;clear top bar (destroys Z)
		pop	ZH
		pop	ZL
		rcall	top_bar_text	;print something in top bar

		rcall	menu_body_clear	;clear body area

		andi	statush,~(1<<MENU_CHANGED)	;clear 'dirty' flag
		ori	statush,(1<<MENU_REDRAW)	;force first menu redraw
		ret
;
menu_ram_setpos:
		lds	temp,menu_ram	;get first id
		sts	menu_pos,temp	;and store it as first selected
		ret
;
menu_ram_loop:
		;here is main loop
		sbrs	statush,MENU_REDRAW	;skip drawing if not needed
		rjmp	menu_keys
		
		;redrawing menu
		ldi	XL,low(menu_ram)	;address of menu items list
		ldi	XH,high(menu_ram)
		ldi	temp2,1		;first Y of menu
menu_ram_loop_1:
		sts	lcd_txt_x,zero	;set position
		sts	lcd_txt_y,temp2
		ld	temp4,X+		;get menu position id
		lds	temp3,menu_pos	;get current position
		cp	temp4,temp3	;is it current position?
		breq	menu_ram_loop_2
		;no, default colors
		m_lcd_set_bg	COLOR_WHITE
		m_lcd_set_fg	COLOR_BLACK
		rjmp	menu_ram_loop_3
menu_ram_loop_2:
		m_lcd_set_bg	COLOR_BLACK
		m_lcd_set_fg	COLOR_WHITE
menu_ram_loop_3:
		;convert menu id into chars
		push	temp2

		mov	mtemp2,temp4	;convert it to ascii
		rcall	math_todec_byte		

		ldi	ZL,low(math_todec_out)	;print output
		ldi	ZH,high(math_todec_out)

		ldd	temp,Z+6
		sts     lcd_arg1,temp
		rcall	lcd_char

		ldd	temp,Z+7
		sts     lcd_arg1,temp
		rcall	lcd_char
		
		pop	temp2
		
		inc	temp2		;inc Y position
		ld	temp,X		;get next id
		cpi	temp,MENU_END	;end of menu?
		brne	menu_ram_loop_1
		
		rjmp	menu_keys
;


;
; ########### eeprom routines ###########

;
; check eeprom, if empty: initialize; if valid: load data from eeprom
eeprom_init:
		;check for correct eeprom signature and version
		ldi	XL,low(ee_sig)		;first byte
		ldi	XH,high(ee_sig)
		rcall	eeprom_read
		cpi	temp,EE_SIG1
		brne	eeprom_init_1
		
		adiw	XL,1		;second byte
		rcall	eeprom_read
		cpi	temp,EE_SIG2
		brne	eeprom_init_1
		
		adiw	XL,1		;version
		rcall	eeprom_read
		cpi	temp,EE_VERSION
		brne	eeprom_init_1
		
		;read some values from eeprom
		ldi	XL,low(ee_last_model)		;last used model
		;ldi	XH,high(ee_last_model)
		rcall	eeprom_read
		sts	cur_model,temp

		;default values for status register
		ldi	XL,low(ee_status)
		;ldi	XH,high(ee_status)
		rcall	eeprom_read
		andi	temp,(1<<ADC_FILTER)|(1<<ADC_FILTER4)|(1<<PPM_POL)	;mask only runtime bits bits
		mov	status,temp

		ldi	XL,low(ee_statush)
		;ldi	XH,high(ee_statush)
		rcall	eeprom_read
		andi	temp,(1<<EXTENDER)|(1<<FMS_OUT)	;mask only runtime bits bits
		mov	status,temp
		
		ret
eeprom_init_1:
		;eeprom not valid - we must initialize it
		
		;write signature and version
		clr	XL		;first byte of signature
		clr	XH
		ldi	temp,EE_SIG1
		rcall	eeprom_write
		
		adiw	XL,1		;second byte of signature
		ldi	temp,EE_SIG2
		rcall	eeprom_write
		
		adiw	XL,1		;eeprom version
		ldi	temp,EE_VERSION
		rcall	eeprom_write
		
		;write first model as last used
		ldi	temp,1
		sts	cur_model,temp		;store also as current model
		m_eeprom_write	ee_last_model
		
		
		;status registers
		ldi	temp,(1<<ADC_FILTER)|(1<<PPM_POL)|(1<<ADC_FILTER4)
		mov	status,temp
		m_eeprom_write	ee_status
		
		ldi	temp,0
		m_eeprom_write	ee_statush

		;clear trims
		ldi	XL,low(ee_trims)
		ldi	XH,high(ee_trims)
		ldi	temp,0xff
		ldi	temp2,high(ee_trims_end)	;check for end of eeprom storage
eeprom_init_2:
		rcall	eeprom_write
		adiw	XL,1	;next cell
		
		cpi	XL,low(ee_trims_end)
		cpc	XH,temp2
		brcs	eeprom_init_2
		
		ret
;

;
; write to eeprom
; temp - value
; X - address
eeprom_write:
		sbic	EECR,EEPE	;wait for last write to complete
		rjmp	eeprom_write
		
		out	EEARH,XH
		out	EEARL,XL
		out	EEDR,temp
		
		brie	eeprom_write_1	;don't do mess with interrupts
		sbi	EECR,EEMPE
		sbi	EECR,EEPE
		ret
eeprom_write_1:
		cli
		sbi	EECR,EEMPE
		sbi	EECR,EEPE
		sei
		ret

;


;
; # read byte from eeprom
; in: X - address
; out: temp - result
eeprom_read:
		out	EEARH,XH
		out	EEARL,XL
		sbi	EECR,EERE
		in	temp,EEDR
		ret
;


;
; ########### storage management routines #############
;


; ####### eeprom storage ##########
;
; # find channel in eeprom
; in: temp - model, temp2 - channel number
; out: X - address of channel in eeprom, carry set if found
; destroys: temp3, temp
ee_trim_find:
		ldi	XL,low(ee_trims)
		ldi	XH,high(ee_trims)
		mov	temp3,temp
ee_trim_find_1:
		rcall	eeprom_read	;get byte
		cp	temp,temp3	;model?
		brne	ee_trim_find_2
		adiw	XL,1		;channel?
		rcall	eeprom_read
		sbiw	XL,1	;get back
		cp	temp,temp2
		brne	ee_trim_find_2
		;found!
		sec
		ret
ee_trim_find_2:
		;loop
		adiw	XL,4	;next cell
		
		ldi	temp,high(ee_trims_end)	;check for end of eeprom storage
		cpi	XL,low(ee_trims_end)
		cpc	XH,temp
		brcs	ee_trim_find_1
		ret
;


;
; # write channel to eeprom
; in: temp2 - channel
; destroys: X, Y, temp, temp3
ee_trim_write:
		mov	temp,temp2
		rcall	calc_channel_addrY	;get channel address

		lds	temp,cur_model
		rcall	ee_trim_find		;get eeprom address
		brcc	ee_trim_write_1
		;found old value
		adiw	XL,2		;skip model and channel
ee_trim_write_0:
		ld	temp,Y+
		rcall	eeprom_write
		adiw	XL,1
		ld	temp,Y+
		rcall	eeprom_write
ee_trim_write_2:
		ret
ee_trim_write_1:
		;not found in eeprom - we need find first empty cell
		push	temp2
		ldi	temp,0xff	;empty cell id
		ldi	temp2,0xff
		rcall	ee_trim_find
		pop	temp2
		brcc	ee_trim_write_2	;end of storage - do nothing
		;found empty place
		lds	temp,cur_model	;first byte: model id
		rcall	eeprom_write
		adiw	XL,1
		mov	temp,temp2	;second byte: channel id
		rcall	eeprom_write
		adiw	XL,1
		rjmp	ee_trim_write_0	;write channel value
;


;
; # get trim value from eeprom
; in: temp2 - channel
; destroys: temp, temp3, X, Y 
ee_trim_read:
		mov	temp,temp2
		rcall	calc_channel_addrY	;get channel address
		lds	temp,cur_model
		rcall	ee_trim_find		;get eeprom address
		brcs	ee_trim_read_1
		ret	;not found
ee_trim_read_1:
		;found
		adiw	XL,2
		rcall	eeprom_read
		st	Y+,temp
		adiw	XL,1
		rcall	eeprom_read
		st	Y+,temp
		ret
;


; ######### Flash storage #############
;
; get beginning of storage
storage_get_start:
		ldi	ZL,low(storage_start<<1)	;start of flash storage
		ldi	ZH,high(storage_start<<1)
		ret
;


;
; find real storage end, 'block' with 0xffff
; out: Z - storage end address
; destroys: temp,temp2
storage_find_end:
		rcall	storage_get_start
storage_find_end_1:
		lpm	temp,Z+
		lpm	temp2,Z+
		cpi	temp,0xff
		brne	storage_find_end_2
		cp	temp,temp2
		brne	storage_find_end_2
		;end found!
		sbiw	ZL,2
		sts	storage_end,ZL
		sts	storage_end+1,ZH
		ret
storage_find_end_2:
		;not found, skip current block and go to next
		sbiw	ZL,2	;restore pointer
		add	ZL,temp2
		adc	ZH,zero
		rjmp	storage_find_end_1
;



;
; skip current container
; return: new Z
; destroys: temp3
storage_skip_current:
		adiw	ZL,1		;get block length
		lpm	temp3,Z
		tst	temp3		;just in case that block length=0 (corrupted data)
		breq	storage_skip_current_ee
		sbiw	ZL,1		;calculate next address
		add	ZL,temp3	;add block length
		adc	ZH,zero
		lds	temp3,storage_end
		cp	ZL,temp3	;check if memory end
		lds	temp3,storage_end+1
		cpc	ZH,temp3
		brcc	storage_skip_current_ee
		clc
		ret
storage_skip_current_ee:
		sec	;error or end of storage
		ret
;


;
; find something in storage
; params:
;	temp:  block definition (model, block type)
;	temp2: block id
; destroys: W,r0
; returns:
;	Z - pointer to last block fulfilling criteria,
;	Z=0 if not found

storage_find:
		clr	WL		;prepare result
		clr	WH
		rcall	storage_get_start
storage_find_1:
		lpm	r0,Z		;get model, block type etc
		cp	r0,temp		;check block type
		brne	storage_find_2
		adiw	ZL,2		;get id
		lpm	r0,Z
		sbiw	ZL,2		;restore Z
		cp	r0,temp2	;check id
		brne	storage_find_2
		;found
		movw	WL,ZL		;save Z
storage_find_2:
		rcall	storage_skip_current
		brcc	storage_find_1	;loop until end of storage
		movw	ZL,WL		;restore last Z
		ret
;


;
; ########### model management routines ################
;

;
; clear channels and initialize special channels with -1,0 and 1
channels_init:
		ldi	XL,low(channels)		;clear channels
		ldi	XH,high(channels)
		ldi	YL,low(CHANNELS_MAX*2)
		ldi	YH,high(CHANNELS_MAX*2)
		rcall	clear_ram

		;sts	channels+(CHANNEL_ZERO*2),zero		;channel with 0
		;sts	channels+(CHANNEL_ZERO*2)+1,zero
		ldi	temp,low(L_ONE)				;channel with 1
		sts	channels+(CHANNEL_ONE*2),temp
		ldi	temp,high(L_ONE)
		sts	channels+(CHANNEL_ONE*2)+1,temp
		ldi	temp,low(L_MONE)			;channel with -1
		sts	channels+(CHANNEL_MONE*2),temp
		ldi	temp,high(L_MONE)
		sts	channels+(CHANNEL_MONE*2)+1,temp
		ret
;


;
; load model indicated by cur_model
model_load:
		;disable adc and data processing
		andi	status,~(1<<ADC_ON)
		waitms	50		;be sure that nothing is working in background

		;clear buffer and channel ram
		rcall	channels_init			;init special channels (with -1,0 and 1)
		
		ldi	XL,low(blocks)			;clear blocks pointers
		ldi	XH,high(blocks)
		ldi	YL,low(BLOCKS_MAX*2)
		ldi	YH,high(BLOCKS_MAX*2)
		rcall	clear_ram
		
		sts	sequence,zero			;clear pointer to block processing sequence
		sts	sequence+1,zero

		rcall	storage_get_start
		lds	temp4,cur_model			;get model_id
		
model_load_1:
		;mail loop
		movw	WL,ZL
		lpm	temp,Z				;get first byte (model+deleted+type)
		andi	temp,0b00011111			;model_id is on 5 bits
		cp	temp,temp4
		breq	model_load_2			;check model_id
model_load_e:
		;calculate next address and loop if not end of storage
		movw	ZL,WL
		rcall	storage_skip_current
		brcc	model_load_1
		;end loading
model_load_e1:
		ori	status,(1<<ADC_ON)	;enable ADC
		ret

model_load_2:
		;found container with proper model_id
		;rjmp	model_load_e
		lpm	temp,Z
		andi	temp,0b11000000		;only bits with block type
		cpi	temp,0b11000000		;description?
		breq	model_load_5		;if yes, go next
		cpi	temp,0b01000000		;block processing order
		brne	model_load_3
		
		;block processing order
		lpm	temp,Z
		sbrc	temp,MODEL_DELETED
		rjmp	model_load_2_1
		sts	sequence,ZL		;block is valid
		sts	sequence+1,ZH
		rjmp	model_load_e
model_load_2_1:
		sts	sequence,zero		;block is invalid and all previos blocks also
		sts	sequence+1,zero
		rjmp	model_load_e

model_load_3:
		cpi	temp,0			;block?
		brne	model_load_4		;channel
		;block
		ldi	YL,low(blocks)		;calculate address in buffer for that block
		ldi	YH,high(blocks)
		adiw	ZL,2
		lpm	temp3,Z			;block_id
		add	YL,temp3		;calculate address of block pointer in table
		adc	YH,zero
		add	YL,temp3
		adc	YH,zero

		movw	ZL,WL
		lpm	temp,Z			;check if block is valid
		sbrc	temp,MODEL_DELETED
		rjmp	model_load_3_1
		st	Y,ZL			;block is valid, store block address in buffer
		std	Y+1,ZH
		rjmp	model_load_e
model_load_3_1:
		st	Y,zero			;block is deleted, clear buffer
		std	Y+1,zero
		rjmp	model_load_e

model_load_4:
		;channel
		adiw	ZL,2
		lpm	temp,Z			;get channel_id
		mov	temp2,temp		;for eeprom

		rcall	calc_channel_addrY		;calculate channel address

		adiw	ZL,2
		lpm	temp,Z+			;copy channel value
		st	Y,temp
		lpm	temp,Z
		std	Y+1,temp
		
		rcall	ee_trim_read		;get channel trim from eeprom if found
		
		rjmp	model_load_e

model_load_5:	;model name
		adiw	ZL,2			;check for description id=0
		lpm	temp,Z
		tst	temp
		brne	model_load_5_2		;workaround for model_load_e (too far)
		movw	ZL,WL
		lpm	temp,Z
		sbrc	temp,MODEL_DELETED
		rjmp	model_load_5_1
		sts	model_name,ZL		;description is valid
		sts	model_name+1,ZH
		rjmp	model_load_e
model_load_5_1:
		sts	model_name,zero		;description is invalid and all previos also
		sts	model_name+1,zero
model_load_5_2:
		rjmp	model_load_e
;


;
; find data with sticks trims and copy pointer to 'trims' variable
; trims container have model_id=0, block type and block_id=0
trims_find:
		ldi	temp,0		;look for block 0
		ldi	temp2,0		;with id 0
		rcall	storage_find
		adiw	ZL,4		;trim data start = container_start+4
		sts	trims,ZL
		sts	trims+1,ZH	;then back to loop, only last container is valid
		ret
;



;
; ######### task for processing all values ###############
task_calc:
		;process block according to block processing order
		lds	ZL,sequence	;get address of block containing processing sequence
		lds	ZH,sequence+1
		
		mov	temp,ZL		;check if address<>0
		or	temp,ZH
		breq	task_calc_e
		
		adiw	ZL,1		;get number of blocks to process (length of processing block-2)
		lpm	temp,Z+
		subi	temp,2
		breq	task_calc_e	;just in case (block length=2, number of blocks=0)
		brcs	task_calc_e

task_calc_1:	;main processing loop (Z points to block number, temp contains number of blocks to process)
		push	temp
		lpm	temp,Z+		;get block number for processing
		push	ZL
		push	ZH
		
		cpi	temp,0		;check if block number is 0 - it's compiler padding at end of block
		breq	task_calc_99	;end if yes
		
		ldi	XL,low(blocks)	;calculate address of pointer stored in blocks table
		ldi	XH,high(blocks)
		add	XL,temp
		adc	XH,zero
		add	XL,temp
		adc	XH,zero
		
		ld	ZL,X+		;get block address
		ld	ZH,X
		mov	temp,ZL		;check for 0
		or	temp,ZH
		breq	task_calc_99
		
		movw	WL,ZL		;save block address for future use
		adiw	ZL,4		;get block type
		lpm	temp,Z
		
		cpi	temp,BLOCK_TRIM	;trim (1)
		breq	task_calc_add
		cpi	temp,12		;add
		breq	task_calc_add
		cpi	temp,BLOCK_REVERSE	;reverse (2)
		breq	task_calc_mul
		cpi	temp,4		;multiply
		breq	task_calc_mul
		;cpi	temp,3		;limit
		;breq	task_calc_limit
		cpi	temp,5		;digital input
		breq	task_calc_digin
		;cpi	temp,6		;multiplexer
		;breq	task_calc_mux
		;cpi	temp,7		;limit detector
		;breq	task_calc_det
		;cpi	temp,8		;minimum
		;breq	task_calc_min
		;cpi	temp,9		;maximum
		;breq	task_calc_max
		;cpi	temp,10		;delta mixer
		;breq	task_calc_delta
		cpi	temp,11		;substract
		breq	task_calc_sub
		;cpi	temp,13		;compare
		;breq	task_calc_compare
		;cpi	temp,14		;absolute value
		;breq	task_calc_abs
		cpi	temp,15		;negation
		breq	task_calc_neg
		cpi	temp,16		;copy
		breq	task_calc_copy_f
		cpi	temp,17		;expo
		breq	task_calc_expo_f

task_calc_99:	;end of main loop
		pop	ZH
		pop	ZL
		pop	temp
		dec	temp
		brne	task_calc_1
task_calc_e:
		rjmp	task_switch_to_main	;end of this task
		;far jumps
task_calc_copy_f: rjmp	task_calc_copy
task_calc_expo_f: rjmp	task_calc_expo
		
		;calculating... W=address of block for processing

task_calc_limit:
task_calc_mux:
task_calc_det:
task_calc_min:
task_calc_max:
task_calc_delta:
task_calc_sub:
task_calc_compare:
task_calc_abs:
		rjmp	task_calc_99
; 0 - block
;	model_id+(deleted<<5)+(0<<6)
;	length = block specific
;	block_id
;	description_id
;	block_type
;	inputs		(count)
;	outputs		(count)
;	input1		(channel)
;	input2
;	...
;	output1
;	output2
;	...
; types of blocks:		inputs	outputs	input types	remark
; * 1 - trim			2	1	(in+trim)	=adder but special treatment of trim input
; * 2 - reverse			2	1	(in+reverse)	=multiplier but a.a.
;   3 - limit			3	1	(in+min+max)
; * 4 - multiplier		2	1	(2x in)		X=A*B
; * 5 - digital input		1	1	(in)		kind of shootky gate: returns only -1,0,1
;   6 - multiplexer		3	1	(2x in+control)
;   7 - limit detector		1	1	(in)		returns number to multiply by to stay in -1...1 range (if exceeded, else 1)
;   8 - min			2	1	(2x in)		X=min(A,B)
;   9 - max			2	1	(2x in)		X=max(A,B)
;   10 - delta			2	2	(2x in)		X=(A+B)/2, Y=(A-B)/2
;   11 - sub			2	1	(2x in)		X=A-B
; * 12 - adder			2	1	(2x in)		X=A+B
;   13 - compare		2	1	(2x in)		X=0 if A=B,X=-1 if A<B, X=1 if A>B
;   14 - abs			1	1	(in)		X=X if X>=0, X=-X if X<0
; * 15 - neg			1	1	(in)		X=-A
; * 16 - copy			1	1	(in)		X=A
;   17 - expo			2	1	(in,rate)	X=A*(B*A*A+1-B)

; 1 - trim, 12 - add
task_calc_add:
		movw	ZL,WL
		adiw	ZL,7
		lpm	temp,Z+
		rcall	math_push_channel
		lpm	temp,Z+
		rcall	math_push_channel
		rcall	math_add
		lpm	temp,Z
		rcall	math_pop_channel
		rjmp	task_calc_99

; 2 - reverse, 4 - mul
task_calc_mul:
		movw	ZL,WL
		adiw	ZL,7
		lpm	temp,Z+
		rcall	math_push_channel
		lpm	temp,Z+
		rcall	math_push_channel
		rcall	math_mul
		lpm	temp,Z
		rcall	math_pop_channel
		rjmp	task_calc_99

; 15 - neg
task_calc_neg:
		movw	ZL,WL
		adiw	ZL,7
		lpm	temp,Z+
		rcall	math_push_channel
		rcall	math_neg
		lpm	temp,Z
		rcall	math_pop_channel
		rjmp	task_calc_99

; 5 - digital in
task_calc_digin:
		movw	ZL,WL
		adiw	ZL,7
		lpm	temp,Z+			;push channel value on the stack
		rcall	math_push_channel
		
		;check against -0.3333
		ldi	temp,low(L_M033)	;push -0.3333 on math stack
		mov	mtemp1,temp
		ldi	temp,high(L_M033)
		mov	mtemp2,temp
		rcall	math_push
		
		rcall	math_compare
		brlt	task_calc_digin_1	;return -1
		
		;check against 0.33333
		rcall	math_drop	;drop last operand from the stack
		ldi	temp,low(L_033)
		mov	mtemp1,temp
		ldi	temp,high(L_033)
		mov	mtemp2,temp
		rcall	math_push
		
		rcall	math_compare
		brlt	task_calc_digin_2	;return 0
		
		;return 1
		ldi	temp,low(L_ONE)
		mov	mtemp1,temp
		ldi	temp,high(L_ONE)
		mov	mtemp2,temp
task_calc_digin_3:
		;clean math stack
		rcall	math_drop
		rcall	math_drop

		;write value to channel and return
		movw	ZL,WL
		adiw	ZL,8
		lpm	temp,Z
		
		rcall	calc_channel_addrX

		st	X+,mtemp1
		st	X+,mtemp2
		
		rjmp	task_calc_99

task_calc_digin_1:
		ldi	temp,low(L_MONE)
		mov	mtemp1,temp
		ldi	temp,high(L_MONE)
		mov	mtemp2,temp
		rjmp	task_calc_digin_3
task_calc_digin_2:
		ldi	temp,low(L_ZERO)
		mov	mtemp1,temp
		ldi	temp,high(L_ZERO)
		mov	mtemp2,temp
		rjmp	task_calc_digin_3
;

; 16 - copy
task_calc_copy:
		movw	ZL,WL
		adiw	ZL,7
		lpm	temp,Z+			;get input channel number
		rcall	calc_channel_addrX

		ld	temp3,X+		;get channel value
		ld	temp4,X+

		lpm	temp,Z+			;get output channel number
		rcall	calc_channel_addrX
		
		st	X+,temp3		;store value
		st	X+,temp4
		
		rjmp	task_calc_99
;


; 17 - expo X=A*(B*A*A+1-B)
task_calc_expo:
		movw	ZL,WL
		adiw	ZL,7
		
		lpm	temp,Z+		;get first channel number
		rcall	math_push_channel	;on stack A
		
		rcall	math_dup	;duplicate A,A
		rcall	math_dup	;again:-) A,A,A
		rcall	math_mul	;A,A*A
		
		lpm	temp,Z
		rcall	math_push_channel	;second channel A,A*A,B
		rcall	math_mul	;A,A*A*B
		
		ldi	temp,low(L_ONE)	;push 1
		mov	mtemp1,temp
		ldi	temp,high(L_ONE)
		mov	mtemp2,temp
		rcall	math_push	;A,A*A*B,1
		
		rcall	math_add	;A,A*A*B+1
		
		lpm	temp,Z+		;once again B on stack
		rcall	math_push_channel	;A,A*A*B+1,B
		
		rcall	math_sub	;A,A*A*B+1-B
		
		rcall	math_mul	;A*(A*A*B+1-B)
		
		lpm	temp,Z		;store result
		rcall	math_pop_channel
		rjmp	task_calc_99
;


; #####################  MATH ROUTINES  ###########################

;generic math
.include "math-6-10.asm"

;special cases

;
; push channel (temp) value on the stack
math_push_channel:
		rcall	calc_channel_addrX
		ld	mtemp1,X+		;get channel value
		ld	mtemp2,X+
		rcall	math_push		;push it on the math stack
		
		ret
;

;
; pop channel (temp) from the stack
math_pop_channel:
		rcall	calc_channel_addrX
		rcall	math_get_sp
		sbiw	YL,2
		ld	temp,Y
		st	X+,temp
		ldd	temp,Y+1
		st	X+,temp
		rcall	math_set_sp
		ret
;



; #####################  DEBUG ROUTINES ############################
;
; # wyswietla wartosci z bajtow klawiatury
.ifdef DEBUG
kbd_debug:
		m_lcd_text_pos	0,4
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
		m_lcd_text_pos	0,5
		ldi	XL,low(adc_buffer)
		ldi	XH,high(adc_buffer)
		ldi	temp2,16
		rcall	mem_debug
		ret
;

;
;
ppm_debug:
		m_lcd_text_pos	0,8
		ldi	XL,low(ppm_debug_val)
		ldi	XH,high(ppm_debug_val)
		ldi	temp2,2
		rcall	mem_debug
		ret
;

;
;
status_debug:
		m_lcd_text_pos	0,7
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


;
;
find_debug:
		m_lcd_text_pos	0,9
		ldi	XL,low(find_debug_val)
		ldi	XH,high(find_debug_val)
		ldi	temp2,2
		rcall	mem_debug
		ldi	XL,low(trims)
		ldi	XH,high(trims)
		ldi	temp2,2
		rcall	mem_debug
		ret
;

;
;
out_debug:
		m_lcd_text_pos	0,10
		ldi	XL,low(channels+CHANNEL_OUT*2)
		ldi	XH,high(channels+CHANNEL_OUT*2)
		ldi	temp2,64
		rcall	mem_debug
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
.endif
;
;	
; ######## END OF DEBUG ROUTINES #########
;
; #
; ###############################################################
; ################# END OF SUBROUTINES ##########################
; ###############################################################
;


;
; ###############################################################
; ####################      INTERRUPTS       ####################
; ###############################################################
; #


;
; ########## TIMER2 (time counting) ##################
; timer2 compare match A : time counting
t2cm:
		in	itemp,SREG
		push	itemp

		inc	mscountl		;miliseconds timer for mswait
		brne	t2cm_1
		inc	mscounth
t2cm_1:		
		lds	itemp,count20ms		;check for 20ms
		inc	itemp
		sts	count20ms,itemp
		cpi	itemp,PPM_INTERVAL
		brcs	t2cm_3
		;we are here every 20ms or PPM_INTERVAL
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
; ################# KEYBOARD ######################
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
; ################### ADC CONVERSION AND CALCULATION ################
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

		lds	ZL,trims		;calculate data start for current channel
		lds	ZH,trims+1
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
		lpm	itemp2,Z+		;itemp2:itemp1 * itemp4:itemp3
		clr	XH			;prepare result
		clr	XL
		mul	itemp,itemp3		
		mov	r3,r1			;store partial result: r1, r0 dropped
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
		ldi	ZL,low(channels+CHANNEL_OUT*2)	;output channels are 16-23
		ldi	ZH,high(channels+CHANNEL_OUT*2)
		ldi	itemp2,PPM_CHANNELS*2
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
		
		sbrc	status,ADC_READY	;perform task switch if all channels processed
		rjmp	task_switch_to_calc
		
		pop	itemp
		out	SREG,itemp
		reti
.dseg
adc_channel:	.byte	1	;current channel being processed
adc_buffer:	.byte	8*2	;buffer for processed adc values (values must be copied at once)
.cseg
;


;
; ################# PWM GENERATING #########################
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
out_buffer:	.byte	PPM_CHANNELS*2	;buffer for generating ppm
.cseg


; PPM: _________   ______   _________   _____   ______
;               |_|      |_|         |_|     |_|
;
;     - start --->|<-1 ch->|<- 2 ch  ->|    >|-|<-0.3ms

; counter max=((value+1024)/2048)*(F_CPU/1000)+(F_CPU/1000) = (F_CPU/1000)*(((value+1024)/2048)+1)=
; = (F_CPU/1000)*(((value+1024)+2048)/2048) = F_CPU/1000/2048*(value+3072)
;
; timer clock: 11059200
; counter max=(value+3072)*5.4
; 5.4 in 6.10 = 5529.6 = 5530

; for Arduino
; timer clock: 16000000
; counter max=(value+3072)*7.8125
; 7.8125 in 6.10 = 8000

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
		
		;get channel value
		lsl	itemp			;output channel must be <128
		ldi	XL,low(out_buffer)	;calculate channel address
		ldi	XH,high(out_buffer)
		add	XL,itemp
		adc	XH,zero
		
		ld	itemp3,X+		;get channel value
		ld	itemp4,X+
		
		;recalculate
		ldi	itemp,high(3072)	;make 2..4 from -1..1
		add	itemp4,itemp
		
.if F_CPU = 11059200
		ldi	itemp,low(5529)		;5.3994
		ldi	itemp2,high(5529)
.else
    .if F_CPU = 16000000
		ldi	itemp,low(8000)		;7.8125
		ldi	itemp2,high(8000)
    .else
	.error "Unsupported F_CPU!"
    .endif
.endif
		
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
; ###########################################################
; #################  END OF INTERRUPTS   ####################
; ###########################################################
;


; ###########################################################
; ###############      MULTITASKING      ####################
; ###########################################################
; #

; Idea:
; 'Main' task is working all the time.
; After last conversion (in interrupt routine), task is switched to 'calc' task.
; 'Calc' task is running until finishes it's job (it's kind of interrupt routine,
; but with other interrupts enabled). After that, it triggers task switch to 'main'.
;
; Switch to 'calc':
; - save all 'main' registers
; - jump to 'calc'
;
; Switch to 'main'
; - restore 'main' registers
; - restore PC, so 'main' can continue
;

;
; switch to main task (lcd, keyboard etc), called directly at end of task_calc
task_switch_to_main:
		;restore registers
		lds	r0,task_space
		lds	r1,task_space+1
		;sts	task_space+1,r2		;zero
		lds	r3,task_space+2
		lds	r4,task_space+3
		lds	r5,task_space+4
		;sts	task_space+1,r6		;itemp3
		;sts	task_space+1,r7		;itemp4
		lds	r8,task_space+5
		lds	r9,task_space+6
		lds	r10,task_space+7
		lds	r11,task_space+8
		lds	r12,task_space+9
		lds	r13,task_space+10
		lds	r14,task_space+11
		lds	r15,task_space+12
		lds	r17,task_space+14
		;sts	task_space+1,r18	;statush
		;sts	task_space+1,r19	;status
		;sts	task_space+1,r20	;itemp
		;sts	task_space+1,r21	;itemp2
		lds	r22,task_space+15
		lds	r23,task_space+16
		lds	r24,task_space+17
		lds	r25,task_space+18
		lds	r26,task_space+19
		lds	r27,task_space+20
		lds	r28,task_space+21
		lds	r29,task_space+22
		lds	r30,task_space+23
		lds	r31,task_space+24
		
		;restore math status in statush register
		lds	temp,task_space+25
		andi	temp,(1<<MATH_OV)|(1<<MATH_SIGN)	;get only important bits
		andi	statush,~((1<<MATH_OV)|(1<<MATH_SIGN))	;destroy these bits in result
		or	statush,temp			;restore bits
		
		;on the stack:
		;	SREG
		;	PC of next operation
		pop	temp
		out	SREG,temp
		lds	temp,task_space+13	;temp=r16
		reti
;

;
; switch to calc task (calulate all blocks), called from ADC interrupt
task_switch_to_calc:
		sts	task_space,r0
		sts	task_space+1,r1
		;sts	task_space+1,r2		;zero
		sts	task_space+2,r3
		sts	task_space+3,r4
		sts	task_space+4,r5
		;sts	task_space+1,r6		;itemp3
		;sts	task_space+1,r7		;itemp4
		sts	task_space+5,r8
		sts	task_space+6,r9
		sts	task_space+7,r10
		sts	task_space+8,r11
		sts	task_space+9,r12
		sts	task_space+10,r13
		sts	task_space+11,r14
		sts	task_space+12,r15
		sts	task_space+13,r16
		sts	task_space+14,r17
		;sts	task_space+1,r18	;statush
		;sts	task_space+1,r19	;status
		;sts	task_space+1,r20	;itemp
		;sts	task_space+1,r21	;itemp2
		sts	task_space+15,r22
		sts	task_space+16,r23
		sts	task_space+17,r24
		sts	task_space+18,r25
		sts	task_space+19,r26
		sts	task_space+20,r27
		sts	task_space+21,r28
		sts	task_space+22,r29
		sts	task_space+23,r30
		sts	task_space+24,r31
		sts	task_space+25,statush	;there is a need to save math status bits
		;on the stack:
		;	SREG
		;	PC of next operation
		sei				;kind of reti, but we leave some info on the stack for
		rjmp	task_calc		;switching back to 'main'
;


.dseg
task_space:	.byte	26
.cseg
; #
; ############################################################
; ##################  END OF MULTITASKING ####################
; ############################################################



; ############################################################
; ###############    FLASH   D A T A    ######################
; ############################################################
; #
; For storage structure see comments at the beginning of models.asm
;
storage_start:
		.db	0,84,0,0	;header
;ch_trims:	.dw	0x01FF		;center position for channel 0
;		.dw	0x0800		;a=2
;		.dw	0xFC00		;b=-1
;		.dw	0x0800,0xFC00	;a,b for second half
;		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 1
;		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 2
;		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 3
;		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 4
;		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 5
;		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 6
;		.dw	0x01ff,0x0800,0xfc00,0x0800,0xfc00	;channel 7

ch_trims:	.dw	544		;center position for channel 0
		.dw	2048+314	;a1
		.dw	65536-1255	;b1
		.dw	2048+648	;a2
		.dw	65536-1432	;b2
		.dw	538		;channel 1
		.dw	2048+242	;a1
		.dw	65536-1203	;b1
		.dw	2048+314	;a2
		.dw	65536-1241	;b2
		.dw	470		;channel 2
		.dw	2048+705	;a1
		.dw	65536-1264	;b1
		.dw	2048+369
		.dw	65536-1109
		.dw	541		;channel 3
		.dw	2048+581
		.dw	65536-1389
		.dw	2048+574
		.dw	65536-1385
		.dw	510		;channel 4
		.dw	2048+9
		.dw	65536-1024
		.dw	2048+5
		.dw	65536-1022
		.dw	510		;channel 5
		.dw	2048+9
		.dw	65536-1024
		.dw	2048+5
		.dw	65536-1022
		.dw	510		;channel 6
		.dw	2048+9
		.dw	65536-1024
		.dw	2048+5
		.dw	65536-1022
		.dw	510		;channel 7
		.dw	2048+9
		.dw	65536-1024
		.dw	2048+5
		.dw	65536-1022

; ####### INCLUDE HARDCODED MODEL DEFINITIONS #############
.include "models.asm"
;storage_end:
		.dw	0xffff

;
; #
; #############################################################
; #############    END OF FLASH DATA    #######################
; #############################################################


;.include "version.inc"		;include svn version as firmware version

; ####### BOOTLOADER HEADER (include boot_block_write sub) ######
.ifdef	M328
    .org	FIRSTBOOTSTART
.else
    .org	SECONDBOOTSTART
.endif
flash_end:

.include "bootloader.inc"	;needed for flash reprogramming


; ##############################################################
; #################    RAM VARIABLES    ########################
; ##############################################################
; #
.dseg
channels:	.byte	CHANNELS_MAX*2	;memory for channel values
blocks:		.byte	BLOCKS_MAX*2	;pointers to blocks
sequence:	.byte	2		;pointer to processing sequence block
cur_model:	.byte	1		;current model
trims:		.byte	2		;pointer to trims data
model_name:	.byte	2		;pointer to model name
storage_end:	.byte	2		;pointer to end of flash storage
;wr_tmp:		.byte	PAGESIZE*2	;buffer for flash write (pagesize is in words, so 2x for bytes!)
;

; #
; ###############################################################
; #############  END OF RAM VARIABLES   #########################
; ###############################################################




; ###############################################################
; ######################    EEPROM DATA   #######################
; ###############################################################
; #
.eseg
.org	0
ee_sig:		.db	EE_SIG1,EE_SIG2	;signature
		.db	EE_VERSION	;eeprom variables version
ee_last_model:	.db	1
ee_status:	.db	0
ee_statush:	.db	0
ee_trims:				;trims storage
.org	EEPROMEND
ee_trims_end:
; #
; ################################################################
; ##############      E      N      D        #####################
; ################################################################
