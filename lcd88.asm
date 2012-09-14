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

;TODO
; - stage 1
;   - sticks calibration
;   - backup/restore
;   - model change
;   - trims/reverse
; - stage 2
;   - rest...


.nolist
;standard header for atmega88 or mega168
.ifndef M168
.include "m88def.inc"
.else
.include "m168def.inc"
.endif


;.define DEBUG

; ******** CONSTANTS *********
.equ	ZEGAR=11059200
.equ	ZEGAR_MAX=ZEGAR/64/1000
.equ	LCD_PWM=150000
.equ	DEFAULT_SPEED=ZEGAR/16/9600-1
.equ	CHANNELS_MAX=256
.equ	BLOCKS_MAX=128		;253 is absolute max
.equ	EE_SIG1=0xaa		;first byte of eeprom signature
.equ	EE_SIG2=0x55		;second byte of eeprom signature
.equ	EE_VERSION=1		;must be changed if eeprom format will change
.equ	TRIM_BYTES=10		;how much bytes are used to trim each a/c channel to produce -1..1 result
.equ	PPM_INTERVAL=20		;20ms for each frame
.equ	PPM_SYNC=ZEGAR*3/10000	;0.3ms
.equ	PPM_FRAME=ZEGAR*PPM_INTERVAL/1000	;20ms
.equ	PPM_CHANNELS=8		;number of output channels
.equ	PPM_MIN=ZEGAR*8/10000	;0.8ms - absolute minimum
.equ	PPM_MAX=ZEGAR*22/10000	;2.2ms - absolute maximum
.equ	MODEL_DELETED=5		;5th bit in header means that block is deleted
.equ	CHANNEL_OUT=16		;first output channel
.equ	CHANNEL_ZERO=24		;channel with constant 0
.equ	CHANNEL_ONE=25		;channel with 1
.equ	CHANNEL_MONE=26		;channel with -1
.equ	CHANNEL_USERMOD=27	;first channel that can be modified by user
;numbers
.equ	L_ZERO=0
.equ	L_ONE= 0b0000010000000000	;1 in 6.10
.equ	L_MONE=0b1111110000000000	;-1 in 6.10
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
; statush
.equ	MATH_OV=0		;overflow flag
.equ	MATH_SIGN=1		;sign of result
.equ	BAR_OV=2		;needed for showing bars
.equ	EXTENDER=3		;extender present?
.equ	MENU_REDRAW=4		;menu needs redrawing?
.equ	MENU_CHANGED=5		;menu item changed
.equ	FMS_OUT=6		;output FMS PIC compatible frames via rs
.equ	STATUS_CHANGED=7	;if set, redraw all status line

; registers
.def		zero=r2
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

;
; #
; #############################
; ######## END OF MACROS ######
; #############################



; # important global ram variables
.dseg
ram_temp:	.byte	11	;general purpose temporary space, used also in LCD(11B) and MATH
.cseg



;
; ##########################################################################
; ########### MAIN CODE ####################################################
; ##########################################################################
; #

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


; # LCD code
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
		;ldi	status,(1<<ADC_FILTER)		;set default values for status register
		
		;clear ram
		ldi	XL,low(SRAM_START)
		ldi	XH,high(SRAM_START)
		ldi	YL,low(SRAM_SIZE)
		ldi	YH,high(SRAM_SIZE)
reset_1:
		st	X+,zero
		dec	YL
		brne	reset_1
		dec	YH
		brne	reset_1
		
		;get some data from eeprom (initialize also status register)
		rcall	eeprom_init

		;initialize timers
		;Timer0 - pwm for LCD backlight, 150kHz, 75% duty, output via OC0B, no prescaling
		ldi	temp,(ZEGAR/LCD_PWM)	;150kHz
		out	OCR0A,temp
		ldi	temp,(ZEGAR/LCD_PWM*75/100)	;75%
		out	OCR0B,temp
		ldi	temp,(1<<COM0B1)+(1<<WGM01)+(1<<WGM00)	;OC0B out, fast PWM with CTC
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
		ldi	temp,ZEGAR_MAX	;counting up to ZEGAR_MAX
		sts	OCR2A,temp
		sts	ASSR,zero	;na pewno synchroniczny
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

		;enable interrupts
		sei

		;initialize lcd
		rcall	lcd_initialize

		rcall	trims_find		;find trim data for sticks
		
		ldi	temp,3			;HACK
		sts	cur_model,temp
		rcall	model_load		;load last used model

		ori	statush,(1<<STATUS_CHANGED)
		rcall	show_status

		ori	status,(1<<ADC_ON)+(1<<PPM_ON)	;enable adc and ppm (it also enables multitasking)

		;init menu
		ldi	temp,1				;set initial menu positin
		sts	menu_item,temp
		ori	statush,(1<<MENU_REDRAW)	;force redraw menu on first call


		; #################### MAIN LOOP #####################
main_loop:

.ifdef DEBUG
		rcall	kbd_debug
		waitms	5
		rcall	adc_debug
		waitms	5
		rcall	status_debug
		waitms	5
		rcall	ppm_debug
		waitms	5
		rcall	out_debug
		waitms	5
.endif

		rcall	show_out_bars
		sbrs	statush,MENU_CHANGED
		rcall	show_menu
		sbrs	statush,MENU_CHANGED
		rjmp	main_loop_xx
		
		;we are on the leaf
		rcall	menu_bar_clear	;clear header
		rcall	menu_copy_item	;draw name of choosen item
		rcall	menu_find_item
		rcall	menu_bar_text
		rcall	menu_body_clear	;and clear body
main_loop_xx:

		lds	temp,keys	;wait for ESC
		sbrc	temp,KEY_ESC
		ori	statush,(1<<MENU_REDRAW)
		andi	statush,~(1<<MENU_CHANGED)

		
		rjmp	main_loop

		; ################### END OF MAIN LOOP ################




; ####################################################################
; ############    SUBROUTINES    #####################################
; ####################################################################
; #

;
; helpers for drawing/using menu area
menu_bar_clear:
		m_lcd_set_fg	COLOR_DKRED	;set upper part (for menu name)
		m_lcd_fill_rect	0,0,DISP_W,8
		ret
;
menu_bar_text:
		m_lcd_set_bg	COLOR_DKRED
		m_lcd_set_fg	COLOR_WHITE
		m_lcd_text_pos	0,0
		rcall	lcd_text
		ret
;
menu_body_clear:
		m_lcd_set_fg	COLOR_WHITE	;clear rest of screen
		m_lcd_fill_rect	0,8,DISP_W,12*8
		ret
;


;
; draw menu
show_menu:
		;repaint whole menu?
		sbrs	statush,MENU_REDRAW
		rjmp	show_menu_key
		
		;repainting menu
		rcall	menu_bar_clear
		
		;submenu name
		lds	temp,menu_item	;copy menu item for finding
		sts	menu_itemf,temp
		rcall	menu_find_item
		brcc	show_menu_00
		rjmp	show_menu_key	;if not found (error!), skip the rest
show_menu_00:
		sbiw	ZL,1		;get parent id
		lpm	temp,Z
		sts	menu_itemf,temp	;find parent name
		rcall	menu_find_item
		brcc	show_menu_01
		rjmp	show_menu_key	;if not found (error!), skip the rest
show_menu_01:
		rcall	menu_bar_text
		rcall	menu_body_clear
		
		;draw menu
		m_lcd_text_pos	0,1		;set position of first menu item
		rcall	menu_find_child	;find first child of parent
show_menu_1:
		brcs	show_menu_key	;check for end of loop
		
		sbiw	ZL,2		;need to get menu item id to identify current position
		lpm	temp3,Z
		lds	temp4,menu_item
		cp	temp3,temp4
		brne	show_menu_2	;no -> go forward
		m_lcd_set_bg	COLOR_BLACK	;set inversed colors
		m_lcd_set_fg	COLOR_WHITE
		rjmp	show_menu_3
show_menu_2:
		m_lcd_set_bg	COLOR_WHITE	;set normal colors
		m_lcd_set_fg	COLOR_BLACK
show_menu_3:
		adiw	ZL,2		;get text address
		rcall	lcd_text	;draw chars
		
		lds	temp,lcd_txt_y	;go to new line
		inc	temp
		sts	lcd_txt_y,temp
		ldi	temp,0		;x
		sts	lcd_txt_x,temp
		
		ldi	temp,0		;find next item
		ldi	temp2,0xff
		rcall	menu_find_next
		brcc	show_menu_1	;loop if not last
		
		
show_menu_key:	;key handling - menu navigation
		andi	statush,~((1<<MENU_REDRAW)|(1<<MENU_CHANGED))	;don't redraw again
		
		;check for key press
		lds	temp,keys
		tst	temp		;any key?
		brne	show_menu_key_1
		ret

		;wait for key release
show_menu_key_1:
		lds	temp2,keys		;this part blocks drawing bars in real time
		tst	temp2
		brne	show_menu_key_1
		
		rcall	menu_copy_item	;find item
		;check what key was pressed
		sbrc	temp,KEY_UP
		rjmp	show_menu_key_up
		sbrc	temp,KEY_DOWN
		rjmp	show_menu_key_down
		sbrc	temp,KEY_ESC
		rjmp	show_menu_key_esc
		sbrc	temp,KEY_ENTER
		rjmp	show_menu_key_enter
		rjmp	show_menu_key_e		;if nothing found -> end
show_menu_key_up:
		rcall	menu_find_upper
show_menu_key_ee:
		sbiw	ZL,2
		lpm	temp,Z
		sts	menu_item,temp
		rjmp	show_menu_key_e
show_menu_key_down:
		rcall	menu_find_lower
		rjmp	show_menu_key_ee
show_menu_key_esc:
		rcall	menu_find_item
		sbiw	ZL,1			;get parent id
		lpm	temp,Z
		tst	temp			;check if we are already at top level?
		breq	show_menu_key_e		;if yes, do nothing
		sts	menu_item,temp		;update menu item
		rjmp	show_menu_key_e

show_menu_key_enter:
		rcall	menu_find_child
		brcs	show_menu_key_en_1	;child not found = we are on leaf!
		sbiw	ZL,2			;next menu item = child id
		lpm	temp,Z
		sts	menu_item,temp
		rjmp	show_menu_key_e
show_menu_key_en_1:
		ori	statush,(1<<MENU_CHANGED)	;leaf
		ret

show_menu_key_e:
		ori	statush,(1<<MENU_REDRAW)	;redraw menu
		ret

;
; search for menu item
; args:
;	temp: mask for item
;	temp2: mask for parent item
; destroys: temp3, temp4, X
; return: Z points to first character of menu item name
menu_find:
		ldi	ZL,low(menu_data<<1)	;start of menu definition
		ldi	ZH,high(menu_data<<1)
menu_find_next:
		ldi	XL,low(menu_data_end<<1)	;end of menu definition
		ldi	XH,high(menu_data_end<<1)
menu_find_next_1:
		movw	WL,ZL		;save Z for future use
		;check for end
		cp	ZL,XL
		cpc	ZH,XH
		brcs	menu_find_next_2
		sec			;set carry - not found
		ret
menu_find_next_2:
		lpm	temp3,Z+		;check menu item
		lds	temp4,menu_itemf
		and	temp3,temp
		and	temp4,temp
		cp	temp3,temp4
		brne	menu_find_next_e
		lpm	temp3,Z+		;check parent item
		lds	temp4,menu_itemf
		and	temp3,temp2
		and	temp4,temp2
		cp	temp3,temp4
		brne	menu_find_next_e
		;found
		;movw	ZL,WL		;restore Z
		clc			;clear carry - OK
		ret
menu_find_next_e:
		movw	ZL,WL
		adiw	ZL,2
menu_find_next_e1:
		lpm	temp3,Z+	;get char
		tst	temp3
		brne	menu_find_next_e1	;exit if =0
		rjmp	menu_find_next_1
;


;
; #### some usefull finds ####
; find item
menu_find_item:
		ldi	temp,0xff	;find item
		ldi	temp2,0		;ignore parent item
		rjmp	menu_find	;find menu item
;

;
; find first child
menu_find_child:
		ldi	temp,0		;ignore item id
		ldi	temp2,0xff	;check parent id
		rjmp	menu_find
;

;
; find upper item
menu_find_upper:
		rcall	menu_copy_item	;find item
		rcall	menu_find_item
		
		sbiw	ZL,1		;get parent
		lpm	temp,Z
		sts	menu_itemf,temp
		rcall	menu_find_child	;find first menu item on the same level
		brcs	menu_find_upper_e	;error?
menu_find_upper_1:
		sbiw	ZL,2		;get id of found block
		lpm	temp3,Z
		lds	temp4,menu_item	;get last id
		cp	temp3,temp4	;if equal then this is the end
		breq	menu_find_upper_e
		;not equal, update r0
		mov	r0,temp3
		adiw	ZL,2
		rcall	menu_find_next_e1	;hack to skip name and search next
		brcc	menu_find_upper_1	;loop if not end/error
menu_find_upper_e:
		sts	menu_itemf,r0	;in r0 is last item id
		rjmp	menu_find_item	;find this and return
;

;
; find lower item
menu_find_lower:
		rcall	menu_copy_item	;find item
		rcall	menu_find_item
		brcs	menu_find_lower_e
		sbiw	ZL,1		;get parent id
		lpm	temp,Z
		adiw	ZL,1		;restore Z
		sts	menu_itemf,temp	;we will search first item with the same parent id
		ldi	temp,0		;ignore item id
		ldi	temp2,0xff	;search for parent id
		rcall	menu_find_next_e1	;hack - jump to end of search loop, X is set by last call of menu_find
		brcc	menu_find_lower_e	;if not out of range - exit
		;out of range
		rcall	menu_copy_item
		rcall	menu_find_item
menu_find_lower_e:
		ret
;

;
; copy byte from menu_item to menu_itemf
menu_copy_item:
		lds	r0,menu_item
		sts	menu_itemf,r0
		ret
;

.dseg
menu_item:	.byte	1	;parameter for showing menu
menu_itemf:	.byte	1	;used to find menu item
.cseg
; MENU STRUCTURE:
; - trim (1)
; - reverse (2)
; - model (3)
;   - save (4)
;   - load (5)
;   - copy (6)
;   - edit (7)
;     - blocks (8)
;       - add (9)
;       - remove (10)
;       - connect (11)
;       - description (12)
;     - channels (13)
;       - value (14)
;       - description (15)
;     - model name (16)
;   - delete (17)
; - extra (18)
;   - stoper (19)
; - setup (20)
;   - info (21)
;   - debug (22)
;   - backup (23)
;   - restore (24)
;   - calibrate sticks (25)
;     - channel0 (47)
;     - channel1 (48)
;     - channel2 (49)
;     - channel3 (50)
;     - channel4 (51)
;     - channel5 (52)
;     - channel6 (53)
;     - channel7 (54)
;     - reset all (55)
;   - clean-up memory (26)
;   - output polarization (27)
;     - normal (56)
;     - inverted (57)
;   - adc filtering (28)
;     - none (29)
;     - x2 (30)
;     - x4 (31)
;   - send FMSPIC frames via rs (disable extender) (32)
;     - disable (33)
;     - enable (34)
;   - pwm duty for LCD (35)
;     - power from 1S LiIon (36)
;     - power from 5V (37)
;     - custom (38)
;   - reset to defaults (eeprom_init) (39)
;     - no (40)
;     - yes (41)
;   - extender (42)
;     - enable (44)
;     - disable (45)
;     - calibrate sticks (43)
;     - trainer mode (46)
; last=57
;
; # menu data format
; 0 - item id
; 1 - parent item id (top level=0)
; 2... - name (0 terminated)
; # hints
; 0 - item id
; 1 - length of hint
; 2... - hint (max 44 chars) (0 terminated)

menu_data:
		.db	0,255,"Main Menu",0
		.db	1,0,"Trim",0,2,0,"Reverse",0,3,0,"Model",0,4,3,"Load",0
		.db	5,3,"Save",0,6,3,"Copy",0
		.db	7,3,"Edit",0,8,7,"Blocks",0
		.db	9,8,"Add",0
		.db	10,8,"Remove",0,11,8,"Connect",0,12,8,"Description",0,13,7,"Channels",0
		.db	14,13,"Value",0
		.db	15,13,"Description",0
		.db	16,7,"Model name",0,17,3,"Delete",0
		.db	18,0,"Extra",0
		.db	19,18,"Stoper",0,20,0,"Setup",0,21,20,"Info",0
		.db	22,20,"Debug",0
		.db	23,20,"Backup ",0,24,20,"Restore",0,25,20,"Calibrate",0
		.db	47,25,"Channel 0",0
		.db	48,25,"Channel 1",0
		.db	49,25,"Channel 2",0
		.db	50,25,"Channel 3",0
		.db	51,25,"Channel 4",0
		.db	52,25,"Channel 5",0
		.db	53,25,"Channel 6",0
		.db	54,25,"Channel 7",0
		.db	55,25,"Reset all",0
		.db	26,20,"Clean-up memory",0
		.db	27,20,"PPM polarization",0,56,27,"Normal",0
		.db	57,27,"Inverted",0,28,20,"ADC filtering",0,29,28,"None",0
		.db	30,28,"x2",0,31,28,"x4",0
		.db	32,20,"FMS-PIC out",0
		.db	33,32,"Disable",0
		.db	34,32,"Enable",0,35,20,"Backlight",0,36,35,"1S LiIon",0
		.db	37,35,"5V",0,38,35,"Custom",0
		.db	39,20,"Reset to defaults",0
		.db	40,39,"NO",0,41,39,"Yes",0,0xff,0xff,0
;		.db	42,20,8,"Extender",44,42,6,"Enable"
;		.db	45,42,7,"Disable"
;		.db	43,42,16,"Calibrate sticks",46,42,12,"Trainer mode"
menu_data_end:
menu_hints:

;
; redraw status line
.equ	STATUS_LINE_Y=13*8
show_status:
		sbrs	statush,STATUS_CHANGED
		ret
		;set background
		m_lcd_set_fg	COLOR_BLACK
		m_lcd_fill_rect	0,STATUS_LINE_Y,DISP_W,3*8+4
		
		;model name
		rcall	show_model_name
		
		;output bars
		rcall	show_out_bars
		
		ret
;


;
; show model name
show_model_name:
		m_lcd_set_fg	COLOR_DKBLUE
		m_lcd_fill_rect	0,STATUS_LINE_Y,DISP_W,8

		m_lcd_text_pos	0,13
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
.equ		OUT_BARS_X=14*8-1
.equ		OUT_BARS_Y=8*14+1
.equ		OUT_BARS_WIDTH=6
.equ		OUT_BARS_SPACE=2
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

		;draw some garbage on lcd
;		m_lcd_set_bg	COLOR_YELLOW
;		m_lcd_set_fg	COLOR_RED
;		m_lcd_fill_rect	10,10,20,20
		
;		m_lcd_set_fg	COLOR_BLUE
;		m_lcd_fill_rect	64,64,50,50

;		m_lcd_set_fg	COLOR_BLACK
;		m_lcd_fill_rect	0,0,176,10
		
;		m_lcd_set_bg	COLOR_BLACK
;		m_lcd_set_fg	COLOR_CYAN

		m_lcd_text_pos	0,0
		m_lcd_text	banner
;
		
		m_lcd_set_bg	COLOR_WHITE	;set default colors
		m_lcd_set_fg	COLOR_BLACK
		ret
banner:		.db	"(C) 2007-2012 Marek Wodzinski",0
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
		push	temp2
		ldi	temp2,7
		add	temp,temp2
		pop	temp2
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
; ########### eeprom routines ###########

;
; check eeprom, if empty: initialize; if valid: load data from eeprom
eeprom_init:
		;check for correct eeprom signature and version
		out	EEARH,zero	;first byte
		out	EEARL,zero
		sbi	EECR,EERE
		in	temp,EEDR
		cpi	temp,EE_SIG1
		brne	eeprom_init_1
		
		ldi	temp,1		;second byte
		out	EEARL,temp
		sbi	EECR,EERE
		in	temp,EEDR
		cpi	temp,EE_SIG2
		brne	eeprom_init_1
		
		ldi	temp,2		;version
		out	EEARL,temp
		sbi	EECR,EERE
		in	temp,EEDR
		cpi	temp,EE_VERSION
		brne	eeprom_init_1
		rjmp	eeprom_init_1	;HACK
		
		;read some values from eeprom
		m_eeprom_read	ee_last_model		;restore last used model
		sts	cur_model,temp

		;default values for status register
		m_eeprom_read	ee_status
		andi	temp,(1<<ADC_FILTER)|(1<<ADC_FILTER4)|(1<<PPM_POL)	;mask only runtime bits bits
		mov	status,temp

		m_eeprom_read	ee_statush
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
		
		;initialize end of flash data position
		ldi	temp,low(storage_end<<1)
		m_eeprom_write	ee_storage_end
		adiw	XL,1
		ldi	temp,high(storage_end<<1)
		rcall	eeprom_write
		
		;status registers
		ldi	temp,(1<<ADC_FILTER)|(1<<PPM_POL)
		mov	status,temp
		m_eeprom_write	ee_status
		
		ldi	temp,0
		m_eeprom_write	ee_statush

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
; ########### storage management routines #############
;


;
; get storage end from eeprom and store it in X
; destroyed: temp
storage_get_end:
		m_eeprom_read	ee_storage_endl		;end of data in flash
		mov	XL,temp
		m_eeprom_read	ee_storage_endh
		mov	XH,temp
		ret
;

;
; get beginning of storage
storage_get_start:
		ldi	ZL,low(storage_start<<1)	;start of flash
		ldi	ZH,high(storage_start<<1)
		ret
;


;
; skip current container
storage_skip_current:
		adiw	ZL,1		;get block length
		lpm	temp3,Z
		tst	temp3		;just in case that block length=0 (corrupted data)
		breq	storage_skip_current_ee
		sbiw	ZL,1		;calculate next address
		add	ZL,temp3	;add block length
		adc	ZH,zero
		cp	ZL,XL		;check if memory end
		cpc	ZH,XH
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
;	temp:  value
;	temp2: mask

storage_find:
		clr	WL		;prepare result
		clr	WH
		push	temp
		rcall	storage_get_start
		rcall	storage_get_end
		pop	temp
storage_find_1:
		lpm	r0,Z		;get id
		mov	r1,temp
		and	r0,temp2	;clear unimportant bits
		and	r1,temp2
		cp	r0,r1
		brne	storage_find_2
		;found
		movw	WL,ZL		;save Z
storage_find_2:
		rcall	storage_skip_current
		brcc	storage_find_1
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
		rcall	storage_get_end
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
		brne	model_load_4
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
		ldi	YL,low(channels)	;calculate address of channels in table
		ldi	YH,high(channels)
		adiw	ZL,2
		lpm	temp,Z			;get channel_id
		add	YL,temp			;calculate channel address
		adc	YH,zero
		add	YL,temp
		adc	YH,zero

		adiw	ZL,2
		lpm	temp,Z			;copy channel value
		st	Y,temp
		adiw	ZL,1
		lpm	temp,Z
		std	Y+1,temp
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
		ldi	temp2,0xff
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
		
		cpi	temp,1		;trim
		breq	task_calc_add
		cpi	temp,12		;add
		breq	task_calc_add
		cpi	temp,2		;reverse
		breq	task_calc_mul
		cpi	temp,4		;multiply
		breq	task_calc_mul
		cpi	temp,3		;limit
		breq	task_calc_limit
		cpi	temp,5		;digital input
		breq	task_calc_digin
		cpi	temp,6		;multiplexer
		breq	task_calc_mux
		cpi	temp,7		;limit detector
		breq	task_calc_det
		cpi	temp,8		;minimum
		breq	task_calc_min
		cpi	temp,9		;maximum
		breq	task_calc_max
		cpi	temp,10		;delta mixer
		breq	task_calc_delta
		cpi	temp,11		;substract
		breq	task_calc_sub
		cpi	temp,13		;compare
		breq	task_calc_compare
		cpi	temp,14		;absolute value
		breq	task_calc_abs
		cpi	temp,15
		breq	task_calc_neg
		rjmp	task_calc_99	;default = do nothing
task_calc_99:	;end of main loop
		pop	ZH
		pop	ZL
		pop	temp
		dec	temp
		brne	task_calc_1
task_calc_e:
		rjmp	task_switch_to_main	;end of this task
		
		;calculating... W=address of block for processing
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

task_calc_neg:
		movw	ZL,WL
		adiw	ZL,7
		lpm	temp,Z+
		rcall	math_push_channel
		rcall	math_neg
		lpm	temp,Z
		rcall	math_pop_channel
		rjmp	task_calc_99

task_calc_limit:
task_calc_digin:
task_calc_mux:
task_calc_det:
task_calc_min:
task_calc_max:
task_calc_delta:
task_calc_sub:
task_calc_compare:
task_calc_abs:
		rjmp	task_calc_99
;


;
; #####################  MATH ROUTINES  ###########################

;generic math
.include "math-6-10.asm"

;special cases

;
; push channel (temp) value on the stack
math_push_channel:
		ldi	XL,low(channels)
		ldi	XH,high(channels)
		add	XL,temp
		adc	XH,zero
		add	XL,temp
		adc	XH,zero
		rcall	math_get_sp
		adiw	YL,2
		rcall	math_set_sp
		sbiw	YL,2
		ld	temp,X+
		st	Y+,temp
		ld	temp,X+
		st	Y+,temp
		ret
;

;
; pop channel (temp) from the stack
math_pop_channel:
		ldi	XL,low(channels)
		ldi	XH,high(channels)
		add	XL,temp
		adc	XH,zero
		add	XL,temp
		adc	XH,zero
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
;
.endif
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
; but with other interrupts enabled). After that, it trigger task switch to 'main'.
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

; ####### INCLUDE HARDCODED MODEL DEFINITIONS #############
.include "models.asm"
storage_end:
		.dw	0xffff

;
; #
; #############################################################
; #############    END OF FLASH DATA    #######################
; #############################################################


;.include "version.inc"		;include svn version as firmware version

; ####### BOOTLOADER HEADER (include boot_block_write sub) ######
.org	SECONDBOOTSTART
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
cur_model:		.byte	1	;current model
trims:			.byte	2	;pointer to trims data
model_name:		.byte	2	;pointer to model name
wr_tmp:		.byte	PAGESIZE*2	;buffer for flash write (2 pages for mega88)
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
eesig:		.db	EE_SIG1,EE_SIG2	;signature
		.db	EE_VERSION		;eeprom variables version
ee_last_model:	.db	1
ee_storage_end:	
ee_storage_endl: .db	low(storage_end<<1)
ee_storage_endh: .db	high(storage_end<<1)
ee_status:	.db	0
ee_statush:	.db	0

; #
; ################################################################
; ##############      E      N      D        #####################
; ################################################################
