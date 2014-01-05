;
; ST7735 display library
; (C) 2013 Marek Wodzinski
;
; Changelog
; 2013.03.02	- initial code
;		- init display
; 2013.03.03	- set area code, display dimensions moved here from lcd-s65.asm
; 2013.03.04	- code finished


; commands definitions
.define		orient_normal		; normal orientation
;.define	orient_90		; rotated 90

;screen dimensions
.ifdef lcd_rotated
	.equ		DISP_W=160
	.equ		DISP_H=128
.else
	.equ		DISP_W=128
	.equ		DISP_H=160
.endif

; ##### MACRO ##############################################
; #

;send command to lcd
.macro		m_lcd_cmd_const
		ldi	temp2,@1
		ldi	ZL,low(@0<<1)
		ldi	ZH,high(@0<<1)
		rcall	lcd_cmd_const
.endmacro

;send command
.macro		m_lcd_cmd
		cbi     LCD_PORT_RS,LCD_RS
		ldi	temp,@0
		rcall	spi_tx
.endmacro

;send data
.macro		m_lcd_data
		sbi     LCD_PORT_RS,LCD_RS
		ldi	temp,@0
		rcall	spi_tx
.endmacro
		
; #
; ##### END OF MACRO #######################################


; ##### CODE ###############################################
; #


;
; # send commands stored in flash
; # 	temp2: number of bytes to send
; # 	Z: flash address with data
; # 	temp: destroyed
lcd_cmd_const:
		cbi     LCD_PORT_RS,LCD_RS	;first byte is command
		lpm	temp,Z+
		rcall	spi_tx

		sbi     LCD_PORT_RS,LCD_RS	;other bytes are params
lcd_cmd_const_1:
		dec	temp2
		brne	lcd_cmd_const_2
		ret
lcd_cmd_const_2:
		lpm	temp,Z+
		rcall	spi_tx
		rjmp	lcd_cmd_const_1
;


;
; # LCD init
lcd_init:
		rcall	lcd_port_init
		rcall	lcd_spi_init
		
		waitms	10				;wait 10ms
		sbi	LCD_PORT_RS,LCD_RS		;RS=1 (data mode)
		sbi	LCD_PORT_CS,LCD_CS		;CS=1 (/chip select)

		cbi	LCD_PORT_RESET,LCD_RESET	;RESET=0 (reset)
		waitms	100				;150ms (must be >120ms)
		sbi	LCD_PORT_RESET,LCD_RESET	;RESET=1 (/reset)
		waitms	150				;120ms


		cbi	LCD_PORT_CS,LCD_CS	;CS=0 (select display)
		
		;soft reset
		;m_lcd_cmd	0x01
		;waitms		150
		
		;sleep exit
		m_lcd_cmd	0x11
		waitms	200			;wait for lcd to wake up
		
		;set frame control
		m_lcd_cmd_const	lcd_init_FRMCTR1,4
		m_lcd_cmd_const	lcd_init_FRMCTR2,4
		m_lcd_cmd_const	lcd_init_FRMCTR3,7

		;display inversion control
		m_lcd_cmd	0xb4
		m_lcd_data	0x07
		
		;power sequence
		m_lcd_cmd_const	lcd_init_PWCTR1,4
		
		m_lcd_cmd	0xc1	;PWCTL2
		m_lcd_data	0xc5
		
		m_lcd_cmd	0xc2	;PWCTL3
		m_lcd_data	0x0a
		m_lcd_data	0x00
		
		m_lcd_cmd	0xC3	;PWCTL4
		m_lcd_data	0x8A
		m_lcd_data	0x2A
		
		m_lcd_cmd	0xC4	;PWCTL5
		m_lcd_data	0x8A
		m_lcd_data	0xEE
		
		m_lcd_cmd	0xc5	;VMCTR1
		m_lcd_data	0x0e	;there shoule be 2 params here...
		
		;MADCTL - inverse, color order etc
		m_lcd_cmd	0x36
		;m_lcd_data	0xc8	;MY=1,MX=1,MV=0,ML=0,RGB=1,MH=0
		m_lcd_data	0x00	;MY=0,MX=0,MV=0,ML=0,RGB=0,MH=0
		
		;set 16bit color mode
		m_lcd_cmd	0x3a
		m_lcd_data	0x05
		
		;CASET
		m_lcd_cmd_const	lcd_init_CASET,5
		
		;RASET
		m_lcd_cmd_const	lcd_init_RASET,5

		;gamma
		m_lcd_cmd_const	lcd_init_GMCTRP1,17
		m_lcd_cmd_const	lcd_init_GMCTRN1,17

		
		;extension command
		;m_lcd_cmd	0xf0
		;m_lcd_data	0x01
		
		;disable ram power save
		;m_lcd_cmd	0xf6
		;m_lcd_data	0x00
		
		;display on
		m_lcd_cmd	0x29
		waitms	100
		
		;noron
		;m_lcd_cmd	0x13
		;waitms	10
		
		sbi	LCD_PORT_CS,LCD_CS	;deselect display

		rcall	lcd_cls			;clear screen
		ret
;

;
; # power off
lcd_off:
		rcall	lcd_spi_init
		
		cbi	LCD_PORT_CS,LCD_CS	;select display
		rcall	lcd_cls
		ret
;

;
; # set fill area
; arg1=x
; arg2=y
; arg3=dx
; arg4=dy
; return:
;	temp,temp2=?
lcd_set_area:
		rcall	lcd_spi_init
		
		cbi	LCD_PORT_CS,LCD_CS	;chip select

.ifdef lcd_rotated
		;rotated
		m_lcd_cmd	0x2a	;CASET
		m_lcd_data	0x00	;high byte

		ldi	temp,DISP_H		;x1=DISP_H-y-dy
		lds	temp2,lcd_arg2
		sub	temp,temp2
		lds	temp2,lcd_arg4
		sub	temp,temp2
		rcall	spi_tx
		
		m_lcd_data	0x00	;high byte
		
		ldi	temp,DISP_H-1		;x2=DISP_H-1-y
		lds	temp2,lcd_arg2
		sub	temp,temp2
		rcall	spi_tx
		
		;second axis
		m_lcd_cmd	0x2b	;RASET
		m_lcd_data	0x00
		
		lds	temp,lcd_arg1		;y1=x
		rcall	spi_tx
		
		m_lcd_data	0x00
		lds	temp2,lcd_arg1		;y2=x+dx-1
		lds	temp,lcd_arg3
		add	temp,temp2
		dec	temp
		rcall	spi_tx
.else
		;normal
		.error	"TODO!"
		ldi	temp,0x08		;x1
		rcall	spi_tx
		lds	temp,lcd_arg1
		rcall	spi_tx
		
		lds	temp2,lcd_arg3		;x2=x1+dx-1
		lds	temp,lcd_arg1
		add	temp2,temp
		dec	temp2
		ldi	temp,0x09
		rcall	spi_tx
		mov	temp,temp2
		rcall	spi_tx
		
		ldi	temp,0x0A		;y1
		rcall	spi_tx
		lds	temp,lcd_arg2
		rcall	spi_tx
		
		lds	temp2,lcd_arg4		;y2=y1+dy-1
		lds	temp,lcd_arg2
		add	temp2,temp
		dec	temp2
		ldi	temp,0x0B
		rcall	spi_tx
		mov	temp,temp2
		rcall	spi_tx
.endif

		m_lcd_cmd	0x2c	;RAMWR
		sbi	LCD_PORT_RS,LCD_RS	;data
		sbi	LCD_PORT_CS,LCD_CS	;chip select
		
		ret
;



;
; LCD static data
;
lcd_init_FRMCTR1:	.db	0xb1,0x01,0x2c,0x2d
lcd_init_FRMCTR2:	.db	0xb2,0x01,0x2c,0x2d
lcd_init_FRMCTR3:	.db	0xb3,0x01,0x2c,0x2d,0x01,0x2c,0x2d   ,0
lcd_init_PWCTR1:	.db	0xc0,0xa2,0x02,0x84
lcd_init_CASET:		.db	0x2a,0x00,0x00,0x00,0x7f   ,0
lcd_init_RASET:		.db	0x2b,0x00,0x00,0x00,0x9f   ,0
lcd_init_GMCTRP1:	.db	0xe0,0x0f,0x1a,0x0f,0x18,0x2f,0x28,0x20,0x22,0x1f,0x1b,0x23,0x37,0x00,0x07,0x02,0x10   ,0
lcd_init_GMCTRN1:	.db	0xe1,0x0f,0x1b,0x0f,0x17,0x33,0x2c,0x29,0x2e,0x30,0x30,0x39,0x3f,0x00,0x07,0x03,0x10   ,0


