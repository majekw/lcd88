;
; Siemens S65 LCD (L2F50126) library
; (C) 2007 Marek Wodzinski
; lcd_init, lcd_fill rect, lcd_dat0, lcd_cmd based on C sources
;	from Christian Kranz (L2F50_display4.02)
; other based on L2F50052T01 documentation
;
; Changelog
; 2007.11.14	- fork from lcd-s65 to support only model specific functions
; 2007.11.15	- finished most of porting
;		- moved back lcd_char to main file

; commands definitions
.define		orient_normal		; normal orientation
;.define	orient_90		; rotated 90


; ##### MACRO ##############################################
; #

;send command to lcd
.macro		m_lcd_cmd_const
		ldi	temp2,@1
		ldi	ZL,low(@0<<1)
		ldi	ZH,high(@0<<1)
		rcall	lcd_cmd_const
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
		lpm	temp,Z+
		rcall	spi_tx
		dec	temp2
		brne	lcd_cmd_const
		ret
;


;
; # LCD init
lcd_init:
		rcall	lcd_port_init
		rcall	lcd_spi_init
		
		waitms	10				;wait 10ms
		sbi	LCD_PORT_RS,LCD_RS		;RS=1 (command mode)
		sbi	LCD_PORT_CS,LCD_CS		;CS=1 (/chip select)
		cbi	LCD_PORT_RESET,LCD_RESET	;RESET=0 (reset)
		waitms	10				;10ms
		sbi	LCD_PORT_RESET,LCD_RESET	;RESET=1 (/reset)
		waitms	50				;50ms

		cbi	LCD_PORT_CS,LCD_CS	;CS=0 (select display)
		sbi	LCD_PORT_RS,LCD_RS	;command mode
		
		;init magic sequences
		m_lcd_cmd_const	lcd_init1,4	;first reset
		waitms	68
		
		m_lcd_cmd_const	lcd_init2,20	;first sequence
		waitms	7
		
		m_lcd_cmd_const	lcd_init3,40
		waitms	50
		
		m_lcd_cmd_const	lcd_init4,6
		
		cbi	LCD_PORT_RS,LCD_RS	;data mode

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
		sbi	LCD_PORT_RS,LCD_RS	;command
		m_lcd_cmd_const	lcd_memwr,8
		
		ldi	temp,0x08		;y1
		rcall	spi_tx
		lds	temp,lcd_arg1
		rcall	spi_tx
		
		lds	temp2,lcd_arg3		;y2=y1+dy-1
		add	temp2,temp
		dec	temp2
		ldi	temp,0x09
		rcall	spi_tx
		mov	temp,temp2
		rcall	spi_tx
		
		ldi	temp,0x0A		;x1
		rcall	spi_tx
		lds	temp,lcd_arg2
		rcall	spi_tx
		
		lds	temp2,lcd_arg4		;x2=x1+dx-1
		add	temp2,temp
		dec	temp2
		ldi	temp,0x0B
		rcall	spi_tx
		mov	temp,temp2
		rcall	spi_tx
		
		cbi	LCD_PORT_RS,LCD_RS	;data
		
		sbi	LCD_PORT_CS,LCD_CS	;chip select
		
		ret
;



;
; LCD static data
;
lcd_init1:	.db	0xFD, 0xFD, 0xFD, 0xFD
lcd_init2:	.db	0xEF, 0x00, 0xEE, 0x04
		.db	0x1B, 0x04, 0xFE, 0xFE, 0xFE, 0xFE, 0xEF, 0x90
		.db	0x4A, 0x04, 0x7F, 0x3F, 0xEE, 0x04, 0x43, 0x06
lcd_init3:	.db	0xEF, 0x90, 0x09, 0x83, 0x08, 0x00, 0x0B, 0xAF
		.db	0x0A, 0x00, 0x05, 0x00, 0x06, 0x00, 0x07, 0x00
		.db	0xEF, 0x00, 0xEE, 0x0C, 0xEF, 0x90, 0x00, 0x80
		.db	0xEF, 0xB0, 0x49, 0x02, 0xEF, 0x00, 0x7F, 0x01
		.db	0xE1, 0x81, 0xE2, 0x02, 0xE2, 0x76, 0xE1, 0x83
lcd_init4:	.db	0x80, 0x01, 0xEF, 0x90, 0x00, 0x00
.ifdef orient_normal
lcd_memwr:	.db	0xEF, 0x90, 0x05, 0x00, 0x06, 0x00, 0x07, 0x00
.endif
.ifdef orient_90
lcd_memwr:	.db	0xEF, 0x90, 0x05, 0x04, 0x06, 0x00, 0x07, 0x00
.endif


