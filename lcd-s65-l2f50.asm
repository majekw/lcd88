;
; Siemens S65 LCD (L2F50126) library
; (C) 2007-2013 Marek Wodzinski
; lcd_init, lcd_fill rect, lcd_dat0, lcd_cmd based on C sources
;	from Christian Kranz (L2F50_display4.02)
; other based on L2F50052T01 documentation
;
; Changelog
; 2007.11.14	- fork from lcd-s65 to support only model specific functions
; 2007.11.15	- lcd_char moved back to main lcd library
; 2007.12.16	- clear screen after init
; 2013.03.03	- display dimensions moved here from lcd-s65.asm

; commands definitions
.equ		DATCTL=0xBC         ; Data Control (data handling in RAM)
.equ		DISCTL=0xCA         ; Display Control
.equ		GCP64=0xCB          ; pulse set for 64 gray scale
.equ		GCP16=0xCC          ; pulse set for 16 gray scale
.equ		OSSEL=0xD0          ; Oscillator select
.equ		GSSET=0xCD          ; set for gray scales
.equ		ASCSET=0xAA         ; aerea scroll setting
.equ		SCSTART=0xAB        ; scroll start setting
.equ		DISON=0xAF          ; Display ON (no parameter)
.equ		DISOFF=0xAE         ; Display OFF (no parameter)
.equ		DISINV=0xA7         ; Display Invert (no parameter)
.equ		DISNOR=0xA6         ; Display Normal (no parameter)
.equ		SLPIN =0x95         ; Display Sleep (no parameter)
.equ		SLPOUT=0x94         ; Display out of sleep (no parameter)
.equ		RAMWR=0x5C          ; Display Memory write
.equ		PTLIN=0xA8          ; partial screen write

.equ		CASET=0x15        ; column address setting
.equ		PASET=0x75        ; page address setting

;screen dimensions
.ifdef lcd_rotated
	.equ		DISP_W=176
	.equ		DISP_H=132
.else
	.equ		DISP_W=132
	.equ		DISP_H=176
.endif

; ##### MACRO ##############################################
; #

;send command to lcd
.macro		m_lcd_cmd
		ldi	temp,@0
		rcall	lcd_cmd
.endmacro

; #
; ##### END OF MACRO #######################################


; ##### CODE ###############################################
; #

; #dat0?
lcd_dat0:
		rcall	spi_tx		;send first char as is
		mov	temp,zero
		rjmp	spi_tx		;send 0
;

;
; # send command to LCD
lcd_cmd:
		cbi	LCD_PORT_RS,LCD_RS
		rcall	lcd_dat0
		sbi	LCD_PORT_RS,LCD_RS
		ret
;

;
;

;
; # LCD init
lcd_init:
		rcall	lcd_port_init
		rcall	lcd_spi_init
		
		sbi	LCD_PORT_RS,LCD_RS
		sbi	LCD_PORT_CS,LCD_CS
		cbi	LCD_PORT_RESET,LCD_RESET	;reset
		waitms	10
		sbi	LCD_PORT_RESET,LCD_RESET
		waitms	35

		cbi	LCD_PORT_CS,LCD_CS	;select display
		
		m_lcd_cmd DATCTL
		ldi	temp,0x2A	;select 565 color mode, 16bit
		rcall	lcd_dat0
		sbi	LCD_PORT_CS,LCD_CS	;pulse CS
		nop
		cbi	LCD_PORT_CS,LCD_CS
		
		m_lcd_cmd DISCTL	;magic init sequence #1, display control
		ldi	temp2,9
		ldi	ZH,high(lcd_disctl<<1)
		ldi	ZL,low(lcd_disctl<<1)
lcd_init_1:	lpm	temp,Z+
		rcall	lcd_dat0
		dec	temp2
		brne	lcd_init_1
		
		m_lcd_cmd GCP64	;magic init sequence #2, init display for 64 grayscale
		ldi	temp2,29
		ldi	ZH,high(lcd_gcp64_0<<1)
		ldi	ZL,low(lcd_gcp64_0<<1)
lcd_init_2:	lpm	temp,Z+
		rcall	lcd_dat0
		mov	temp,zero
		rcall	lcd_dat0
		dec	temp2
		brne	lcd_init_2

		ldi	temp2,34	;magic init sequence #3
		ldi	ZH,high(lcd_gcp64_1<<1)	;rest of init 64 gray seq
		ldi	ZL,low(lcd_gcp64_1<<1)
lcd_init_3:	lpm	temp,Z+
		rcall	lcd_dat0
		ldi	temp,0x01
		rcall	lcd_dat0
		dec	temp2
		brne	lcd_init_3

		m_lcd_cmd GCP16	;magic init sequence #4, init display for 16 grayscale
		ldi	temp2,15
		ldi	ZH,high(lcd_gcp64_0<<1)
		ldi	ZL,low(lcd_gcp64_0<<1)
lcd_init_4:	lpm	temp,Z+
		rcall	lcd_dat0
		dec	temp2
		brne	lcd_init_4
		
		m_lcd_cmd GSSET	;set grayscale 64 mode
		mov	temp,zero
		rcall	lcd_dat0
		
		m_lcd_cmd OSSEL	;oscilator select??
		mov	temp,zero
		rcall	lcd_dat0
		
		m_lcd_cmd SLPOUT	;wake up display (turn on voltages etc)
		
		waitms	7
		
		m_lcd_cmd CASET	;set column range
		ldi	temp,0x08	;start column =8
		rcall	lcd_dat0
		ldi	temp,0x01
		rcall	lcd_dat0
		ldi	temp,0x8B	;end column=139
		rcall	lcd_dat0
		ldi	temp,0x01
		rcall	lcd_dat0
		
		m_lcd_cmd PASET	;set page range (Y)
		mov	temp,zero	;0
		rcall	lcd_dat0
		ldi	temp,0x8F	;143
		rcall	lcd_dat0
		
		m_lcd_cmd ASCSET	;set scroll area
		mov	temp,zero	;0 - start page
		rcall	lcd_dat0
		ldi	temp,0xAF	;175 - end page
		rcall	lcd_dat0
		ldi	temp,0xAF	;175 - specified page ???
		rcall	lcd_dat0
		ldi	temp,0x03	;scroll mode: full screen scroll
		rcall	lcd_dat0
		
		m_lcd_cmd SCSTART	;set scroll start page
		mov	temp,zero	;0
		rcall	lcd_dat0
		
		cbi	LCD_PORT_RS,LCD_RS
		ldi	temp,DISON	;display on
		rcall	lcd_dat0
		
		sbi	LCD_PORT_CS,LCD_CS	;deselect display

		rcall	lcd_cls		;clear display		
		ret
;

;
; # power off
lcd_off:
		rcall	lcd_spi_init
		
		cbi	LCD_PORT_CS,LCD_CS	;select display
		
		m_lcd_cmd DISOFF	;display off
		
		waitms	60
		
		m_lcd_cmd SLPIN	;sleep and power off
		
		sbi	LCD_PORT_CS,LCD_CS	;deselect display
		
		waitms	80
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
		
		lds	temp2,lcd_arg1	;get arg1 and add 8
		ldi	temp,8
		add	temp2,temp
		
		m_lcd_cmd CASET	;column range
		mov	temp,temp2	;x1
		rcall	lcd_dat0
		ldi	temp,0x01
		rcall	lcd_dat0
		lds	temp,lcd_arg3	;x2=x+dx-1
		add	temp,temp2
		dec	temp
		rcall	lcd_dat0
		ldi	temp,0x01
		rcall	lcd_dat0

		m_lcd_cmd PASET	;page range
		lds	temp2,lcd_arg2	;y1
		mov	temp,temp2
		rcall	lcd_dat0
		lds	temp,lcd_arg4	;y2=y+dy-1
		add	temp,temp2
		dec	temp
		rcall	lcd_dat0
		
		m_lcd_cmd RAMWR	;ram write
		
		sbi	LCD_PORT_CS,LCD_CS	;chip select
		ret
;


;
; LCD static data
;
lcd_disctl:	.db	0x4C, 0x01, 0x53, 0x00, 0x02, 0xB4, 0xB0, 0x02, 0x00, 0
lcd_gcp64_0:	.db	0x11,0x27,0x3C,0x4C,0x5D,0x6C,0x78,0x84,0x90,0x99,0xA2,0xAA,0xB2,0xBA
                .db	0xC0,0xC7,0xCC,0xD2,0xD7,0xDC,0xE0,0xE4,0xE8,0xED,0xF0,0xF4,0xF7,0xFB,0xFE, 0
lcd_gcp64_1:	.db	0x01,0x03,0x06,0x09,0x0B,0x0E,0x10,0x13,0x15,0x17,0x19,0x1C,0x1E,0x20
		.db	0x22,0x24,0x26,0x28,0x2A,0x2C,0x2D,0x2F,0x31,0x33,0x35,0x37,0x39,0x3B
		.db	0x3D,0x3F,0x42,0x44,0x47,0x5E
lcd_gcp16:	.db	0x13,0x23,0x2D,0x33,0x38,0x3C,0x40,0x43,0x46,0x48,0x4A,0x4C,0x4E,0x50,0x64, 0



