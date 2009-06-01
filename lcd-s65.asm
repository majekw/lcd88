;
; Siemens S65 LCD library
; (C) 2007 Marek Wodzinski
;
; Changelog
; 2007.02.13	- added first LCD code (initialisation)
; 2007.02.14	- lcd code moved from gps.asm to lcd-s65.asm
; 		- added lcd_fill_rect (drawing rectangles)
;		- added lcd_char (drawing chars)
; 2007.02.16	- added lcd_line (drawing lines)
;		- added lcd_circle (drawing circles)
; 2007.03.04	- fixed bug in lcd_fill_rect (+1)
; 2007.03.05	- some comments
; 2007.03.07	- split lcd_fill_rect to lcd_set_area and the rest
; 2007.11.14	- start spliting low level function to support other display types
;		- done
;		- use .define for conditional compile (.equ and .if sometimes doesn't work)
; 2007.11.15	- added lcd_cls (clear screen)
;		- moved back lcd_char from hardware dependend includes
; 2007.12.17	- made text routines optional


; ##### CONFIG FEATURES ####################################
; #
;.define lcd_l2f50	;L2F50
.define lcd_ls020	;LS020B
;.define compile_lcd_test ;draw some pattern on whole screen
;.define compile_circle	;drawing circles
.define compile_line	;drawing lines in any direction
;.define compile_text	;drawing text
;.define soft_spi	;use software spi
; #
; ##### CONFIG FEATURES ####################################



; LCD pins
.equ		LCD_PORT_RS=PORTD
.equ		LCD_DDR_RS=DDRD
.equ		LCD_RS=PORTD2

.equ		LCD_PORT_RESET=PORTD
.equ		LCD_DDR_RESET=DDRD
.equ		LCD_RESET=PORTD3

.equ		LCD_PORT_CS=PORTD
.equ		LCD_DDR_CS=DDRD
.equ		LCD_CS=PORTD4

.equ		LCD_PORT_LED=PORTD
.equ		LCD_DDR_LED=DDRD
.equ		LCD_LED=PORTD5

.equ		LCD_PORT_SCK=PORTB
.equ		LCD_DDR_SCK=DDRB
.equ		LCD_SCK=PORTB5

.equ		LCD_PORT_MOSI=PORTB
.equ		LCD_DDR_MOSI=DDRB
.equ		LCD_MOSI=PORTB3


; text parameters
.equ		DISP_W=132
.equ		DISP_H=176
.equ		CHAR_H=8
.equ		CHAR_W=8
.equ		TEXT_COL=16
.equ		TEXT_ROW=22


; colors
.equ		COLOR_BLACK=	0x0000
.equ		COLOR_WHITE=	0xffff
;.................................rrrrrggggggbbbbb
.equ		COLOR_RED=	0b1111100000000000
.equ		COLOR_DKRED=	0b0111100000000000
.equ		COLOR_GREEN=	0b0000011111100000
.equ		COLOR_DKGREEN=	0b0000001111100000
.equ		COLOR_BLUE=	0b0000000000011111
.equ		COLOR_DKBLUE=	0b0000000000001111
.equ		COLOR_YELLOW=	0b1111111111100000
.equ		COLOR_DKYELLOW=	0b0111101111100000
.equ		COLOR_MAGENTA=	0b1111100000011111
.equ		COLOR_DKMAGENTA=0b0111100000001111
.equ		COLOR_CYAN=	0b0000011111111111
.equ		COLOR_DKCYAN=	0b0000001111101111
.equ		COLOR_GRAY=	0b0111101111101111


; ##### MACRO ##############################################
; #

; set foreground color
.macro		m_lcd_set_fg
		ldi	temp,low(@0)
		sts	lcd_fg_color,temp
		ldi	temp,high(@0)
		sts	lcd_fg_color+1,temp
.endmacro

; set background color
.macro		m_lcd_set_bg
		ldi	temp,low(@0)
		sts	lcd_bg_color,temp
		ldi	temp,high(@0)
		sts	lcd_bg_color+1,temp
.endmacro

; draw filled rectangle
.macro		m_lcd_fill_rect
		ldi	temp,@0
		sts	lcd_arg1,temp
		ldi	temp,@1
		sts	lcd_arg2,temp
		ldi	temp,@2
		sts	lcd_arg3,temp
		ldi	temp,@3
		sts	lcd_arg4,temp
		rcall	lcd_fill_rect
.endmacro

; draw line
.macro		m_lcd_line
		ldi	temp,@0
		sts	lcd_arg1,temp
		ldi	temp,@1
		sts	lcd_arg2,temp
		ldi	temp,@2
		sts	lcd_arg3,temp
		ldi	temp,@3
		sts	lcd_arg4,temp
		rcall	lcd_line
.endmacro

; draw circle
.macro		m_lcd_circle
		ldi	temp,@0
		sts	lcd_arg1,temp
		ldi	temp,@1
		sts	lcd_arg2,temp
		ldi	temp,@2
		sts	lcd_arg3,temp
		rcall	lcd_circle
.endmacro

;set position of text
.macro		m_lcd_text_pos
		ldi	temp,@0
		sts	lcd_txt_x,temp
		ldi	temp,@1
		sts	lcd_txt_y,temp
.endmacro

;send single char
.macro		m_lcd_char
		ldi	temp,@0
		sts	lcd_arg1,temp
		rcall	lcd_char
.endmacro

;send string from program memory
.macro		m_lcd_text
		ldi	ZL,low(@0<<1)
		ldi	ZH,high(@0<<1)
		rcall	lcd_text
.endmacro

;send string from ram
.macro		m_lcd_text_ram
		ldi	ZL,low(@0)
		ldi	ZH,high(@0)
		ldi	temp,@1
		rcall	lcd_text_ram
.endmacro

; #
; ##### END OF MACRO #######################################


; ##### DATA ###############################################
; #
.dseg
lcd_fg_color:	.byte	2
lcd_bg_color:	.byte	2
lcd_txt_x:	.byte	1
lcd_txt_y:	.byte	1
lcd_arg1:	.byte	1
lcd_arg2:	.byte	1
lcd_arg3:	.byte	1
lcd_arg4:	.byte	1
;ram_temp:	.byte	11	;more variables...
.cseg
; #
; ##### DATA ###############################################



; ##### CODE ###############################################
; #

; draw some patterns on whole lcd
.ifdef compile_lcd_test
lcd_test:
		rcall	lcd_test_fill
		
		m_lcd_set_fg	COLOR_RED
		m_lcd_fill_rect	10,10,50,50

		m_lcd_set_fg	COLOR_BLUE
		m_lcd_fill_rect	40,40,50,50
		
		m_lcd_set_fg	COLOR_GREEN
		m_lcd_fill_rect	70,70,50,50
		
		m_lcd_text_pos	0,0
		m_lcd_set_bg	COLOR_BLACK
		m_lcd_set_fg	COLOR_YELLOW
		m_lcd_text	lcd_helo
		
		m_lcd_set_fg	COLOR_BLACK
		m_lcd_line	0,0,130,170

		m_lcd_set_fg	COLOR_BLUE
		m_lcd_line	0,0,130,100

		m_lcd_set_fg	COLOR_WHITE
		m_lcd_line	20,20,130,50
		
		m_lcd_set_fg	COLOR_WHITE
		m_lcd_circle	60,60,50
		m_lcd_set_fg	COLOR_YELLOW
		m_lcd_circle	60,60,30
		m_lcd_set_fg	COLOR_RED
		m_lcd_circle	60,60,10

;		ldi	temp,200	;50s
;lcd_test1:	waitms	250
;		dec	temp
;		brne	lcd_test1
		
;		rcall	lcd_off
		
		ret
;


;
; # testowa procedurka
lcd_test_fill:
		cbi	LCD_PORT_CS,LCD_CS	;chip select
		
		m_lcd_cmd CASET	;column range
		ldi	temp,0x08	;
		rcall	lcd_dat0
		ldi	temp,0x01
		rcall	lcd_dat0
		ldi	temp,0x8B	;
		rcall	lcd_dat0
		ldi	temp,0x01
		rcall	lcd_dat0
		
		m_lcd_cmd PASET	;page range
		ldi	temp,0x00	;0
		rcall	lcd_dat0
		ldi	temp,0xAF	;175
		rcall	lcd_dat0
		
		m_lcd_cmd RAMWR
		
		ldi	ZL,DISP_H
lcd_test_1:	ldi	ZH,DISP_W
lcd_test_2:	mov	temp,ZH
		rcall	spi_tx
		mov	temp,ZL
		rcall	spi_tx
		dec	ZH
		brne	lcd_test_2
		dec	ZL
		brne	lcd_test_1

		sbi	LCD_PORT_CS,LCD_CS	;deselect display
		

		ret
;
lcd_helo:	.db	"AVRGPS 2.0",0,0
.endif



;
; # konfiguracja SPI dla LCD
lcd_spi_init:
.ifndef soft_spi
		;hardware spi
                ldi     temp,(1<<SPE)|(1<<MSTR)	;spi en,master,podzielnik /4 (CLK!)
		out     SPCR,temp
		ldi	temp,(1<<SPI2X)	;spi x2 (CLK!), f=4MHz, 300KB/s
		;mov	temp,zero
		out     SPSR,temp
		in	temp,SPSR	;just in case
.else
		;software spi - nothing to do
.endif
		ret
;

;
; # konfiguracja portów
lcd_port_init:
		sbi	LCD_PORT_RS,LCD_RS	;initialize values
		sbi	LCD_PORT_RESET,LCD_RESET
		sbi	LCD_PORT_CS,LCD_CS
		cbi	LCD_PORT_LED,LCD_LED	;turn off backlight
		
		sbi	LCD_DDR_RS,LCD_RS		;set direction
		sbi	LCD_DDR_RESET,LCD_RESET
		sbi	LCD_DDR_CS,LCD_CS
		sbi	LCD_DDR_LED,LCD_LED

		cbi	LCD_PORT_SCK,LCD_SCK
		sbi	LCD_DDR_SCK,LCD_SCK
		sbi	LCD_PORT_MOSI,LCD_MOSI
		sbi	LCD_DDR_MOSI,LCD_MOSI

		ret
;

;
; #wy¶lij i co¶ po SPI, argumenty w temp
spi_tx:
.ifndef soft_spi
		;hardware spi
		out	SPDR,temp	; send over SPI		;2
spi_tx1:	lds	temp,SPSR
		sbrs	temp,SPIF	; wait for empty SPDR	;2
		rjmp	spi_tx1					;2
.else
		;software spi
		push	temp			;2
		push	temp2			;2
		ldi	temp2,8		;bits count	;1
spi_tx1:
		cbi	LCD_PORT_SCK,LCD_SCK	;2
		sbrc	temp,7			;1
		sbi	LCD_PORT_MOSI,LCD_MOSI	;2
		sbrs	temp,7			;2
		cbi	LCD_PORT_MOSI,LCD_MOSI	;2
		rol	temp			;1
		sbi     LCD_PORT_SCK,LCD_SCK	;2
		dec	temp2			;1
		brne	spi_tx1			;2
						;=13, f=615kHz :-(
		pop	temp2			;2
		pop	temp			;2
.endif
                ret			; done	;4+3    =67KB/s
;


;
; low level lcd commands
.ifdef lcd_l2f50
.include "lcd-s65-l2f50.asm"
.endif

.ifdef lcd_ls020
.include "lcd-s65-ls020.asm"
.endif

;
; # fill rectangle
; arg1=x
; arg2=y
; arg3=dx
; arg4=dy
; return:
;	temp,temp2,Z=?
lcd_fill_rect:
		rcall	lcd_set_area
		
		cbi	LCD_PORT_CS,LCD_CS	;chip select

		lds	temp2,lcd_fg_color
		lds	ZL,lcd_arg3
lcd_fill_rect1:
		lds	ZH,lcd_arg4
lcd_fill_rect2:
		lds	temp,lcd_fg_color+1	;color high byte
		rcall	spi_tx
		mov	temp,temp2		;color low byte
		rcall	spi_tx
		dec	ZH
		brne	lcd_fill_rect2
		dec	ZL
		brne	lcd_fill_rect1
		
		sbi	LCD_PORT_CS,LCD_CS	;deselect display
		ret
;


;
; # clear screen
lcd_cls:
		ser	temp
		sts	lcd_fg_color,temp	;white
		sts	lcd_fg_color+1,temp

		sts	lcd_arg1,zero		;whole screen
		sts	lcd_arg2,zero
		ldi	temp,DISP_W
		sts	lcd_arg3,temp
		ldi	temp,DISP_H
		sts	lcd_arg4,temp
		rcall	lcd_fill_rect
		ret
;


.ifdef compile_text
;
; # print char
; arg1=char
lcd_char:
		push	ZH
		push	ZL
		lds	temp,lcd_arg1	;check for special chars: nl,cr
		cpi	temp,10		;lf
		brne	lcd_char0
		lds	temp,lcd_txt_x	
		lds	temp2,lcd_txt_y
		rjmp	lcd_char41
lcd_char0:
		cpi	temp,13		;cr
		brne	lcd_char01
		lds	temp2,lcd_txt_y
		mov	temp,zero
		rjmp	lcd_char5
lcd_char01:
		push	temp		;remember char, we use lcd_arg1 etc for area setting
		rcall	lcd_spi_init	;really print char
		
		lds	temp2,lcd_txt_x	;x1=x*char_w
		ldi	temp,CHAR_W
		sts	lcd_arg3,temp	;dx
		mul	temp,temp2
		sts	lcd_arg1,r0	;x
		
		lds	temp2,lcd_txt_y	;y1=y*char_h
		ldi	temp,CHAR_H
		sts	lcd_arg4,temp	;dy
		mul	temp,temp2
		sts	lcd_arg2,r0	;y (result in r0)

		rcall	lcd_set_area
		cbi	LCD_PORT_CS,LCD_CS	;chip select
		
		ldi	ZL,low(lcd_font<<1)	;pocz±tek generatora znaków
		ldi	ZH,high(lcd_font<<1)
		
		pop	temp			;restore char

		ldi	temp2,32		;correction for beginning of char table (start from 32, not from 0)
		sub	temp,temp2
		ldi	temp2,CHAR_H		;adres=base+char*char_h
		mul	temp,temp2
		add	ZL,r0
		adc	ZH,r1


		ldi	temp,CHAR_H
		mov	temp3,temp
lcd_char1:
		lpm	r0,Z+
		ldi	temp,CHAR_W
		mov	temp4,temp
lcd_char2:
		rol	r0
		brcc	lcd_char3	;0 czy 1?
		lds	temp,lcd_fg_color+1	;color high byte
		rcall	spi_tx
		lds	temp,lcd_fg_color	;color low byte
		rcall	spi_tx
		rjmp	lcd_char4
lcd_char3:
		lds	temp,lcd_bg_color+1	;color high byte
		rcall	spi_tx
		lds	temp,lcd_bg_color	;color low byte
		rcall	spi_tx
lcd_char4:
		dec	temp4
		brne	lcd_char2
		
		dec	temp3
		brne	lcd_char1
		
		sbi	LCD_PORT_CS,LCD_CS	;deselect display
		
		lds	temp,lcd_txt_x	;calculate position of next char
		lds	temp2,lcd_txt_y
		
		inc	temp
		cpi	temp,TEXT_COL
		brne	lcd_char5
		mov	temp,zero
lcd_char41:	inc	temp2
		cpi	temp2,TEXT_ROW
		brne	lcd_char5
		mov	temp2,zero
lcd_char5:
		sts	lcd_txt_x,temp
		sts	lcd_txt_y,temp2
		
		pop	ZL
		pop	ZH
		ret
;


;
; #print string from eeprom (terminated by 0)
; Z - address of string
lcd_text:
		lpm	temp,Z+
		tst	temp
		breq	lcd_text1
		sts	lcd_arg1,temp
		rcall	lcd_char
		rjmp	lcd_text
lcd_text1:	
		ret
;


;
; #print string from ram
; Z - address of string
; temp - number of chars to print
lcd_text_ram:
		ld	temp2,Z+
		sts	lcd_arg1,temp2
		push	temp
		rcall	lcd_char
		pop	temp
		dec	temp
		brne	lcd_text_ram
		ret
;

lcd_font:
.include	"font_8x8.inc"

.endif


.ifdef compile_line
; Bresenham's algorithm for drawing lines:
;
;function line(x0, x1, y0, y1)
;     boolean steep := abs(y1 - y0) > abs(x1 - x0)
;     if steep then
;         swap(x0, y0)
;         swap(x1, y1)
;     if x0 > x1 then
;         swap(x0, x1)
;         swap(y0, y1)
;     int16 deltax := x1 - x0
;     int16 deltay := abs(y1 - y0)
;     int16 error := 0
;     int ystep
;     int y := y0
;     if y0 < y1 then ystep := 1 else ystep := -1
;     for x from x0 to x1
;         if steep then plot(y,x) else plot(x,y)
;         error := error + deltay
;         if 2×error >= deltax then
;             y := y + ystep
;             error := error - deltax
;

;
; # draw line
; arg1: x0
; arg2: y0
; arg3: x1
; arg4: y1
.equ		l_steep=ram_temp
.equ		l_deltax=ram_temp+1
.equ		l_deltay=ram_temp+3
.equ		l_error=ram_temp+5
.equ		l_ystep=ram_temp+7
.equ		l_y=ram_temp+8
.equ		l_x1=ram_temp+9
.equ		l_x=ram_temp+10
lcd_line:
		lds	temp,lcd_arg4	;abs(y1 - y0)
		lds	temp2,lcd_arg2
		sub	temp,temp2
		brcc	lcd_line1
		neg	temp
lcd_line1:
		mov	temp3,temp

		lds	temp,lcd_arg3	;abs(x1 - x0)
		lds	temp2,lcd_arg1
		sub	temp,temp2
		brcc	lcd_line2
		neg	temp
lcd_line2:
		sub	temp,temp3	;abs(y1 - y0) > abs(x1 - x0)
		rol	temp
		andi	temp,1
		sts	l_steep,temp
		
		tst	temp		;if steep then
		breq	lcd_line3
		lds	temp,lcd_arg1	;swap(x0, y0)
		lds	temp2,lcd_arg2
		sts	lcd_arg1,temp2
		sts	lcd_arg2,temp
		lds	temp,lcd_arg3	;swap(x1, y1)
		lds	temp2,lcd_arg4
		sts	lcd_arg3,temp2
		sts	lcd_arg4,temp
lcd_line3:
		lds	temp,lcd_arg1	;if x0 > x1 then
		lds	temp2,lcd_arg3
		cp	temp2,temp
		brcc	lcd_line4
		lds	temp,lcd_arg1	;swap(x0, x1)
		lds	temp2,lcd_arg3
		sts	lcd_arg1,temp2
		sts	lcd_arg3,temp
		lds	temp,lcd_arg2	;swap(y0, y1)
		lds	temp2,lcd_arg4
		sts	lcd_arg2,temp2
		sts	lcd_arg4,temp
lcd_line4:
		lds	temp,lcd_arg3	;int16 deltax := x1 - x0
		lds	temp2,lcd_arg1
		sub	temp,temp2
		sts	l_deltax,temp
		sts	l_deltax+1,zero
		
		lds	temp,lcd_arg4	;int16 deltay := abs(y1 - y0)
		lds	temp2,lcd_arg2
		sub	temp,temp2
		brcc	lcd_line5
		neg	temp
lcd_line5:	sts	l_deltay,temp
		sts	l_deltay+1,zero
		
		sts	l_error,zero	;int16 error := 0
		sts	l_error+1,zero
		
		lds	temp,lcd_arg2	;int y := y0
		sts	l_y,temp
		
		lds	temp2,lcd_arg4	;if y0 < y1 then ystep := 1 else ystep := -1
		mov	temp3,zero	;ystep=1
		inc	temp3
		cp	temp,temp2
		brcs	lcd_line6
		neg	temp3
lcd_line6:	sts	l_ystep,temp3

		lds	temp,lcd_arg1	;for x from x0 to x1
		sts	l_x,temp
		lds	temp,lcd_arg3	;save x1 because args are overwritten in plot command
		sts	l_x1,temp
lcd_line7:
		lds	temp,l_x	;check looop
		lds	temp2,l_x1
		cp	temp2,temp
		brcc	lcd_line71
		ret
		
lcd_line71:	lds	temp,l_x	;if steep then plot(y,x) else plot(x,y)
		lds	temp2,l_y
		lds	temp3,l_steep
		tst	temp3
		breq	lcd_line8
		sts	lcd_arg1,temp2
		sts	lcd_arg2,temp
		rjmp	lcd_line9
lcd_line8:	sts	lcd_arg1,temp
		sts	lcd_arg2,temp2
lcd_line9:	ldi	temp,1
		sts	lcd_arg3,temp	;1
		sts	lcd_arg4,temp	;1
		rcall	lcd_fill_rect	;plot
		
		lds	temp,l_error	;error := error + deltay
		lds	temp3,l_error+1
		lds	temp2,l_deltay
		lds	temp4,l_deltay+1
		add	temp,temp2
		adc	temp3,temp4
		sts	l_error,temp
		sts	l_error+1,temp3
		
		add	temp,temp	;if 2×error >= deltax then
		adc	temp3,temp3
		
		lds	temp2,l_deltax
		lds	temp4,l_deltax+1
		sub	temp,temp2
		sbc	temp3,temp4
		brcs	lcd_line10
		
		lds	temp,l_y	;y := y + ystep
		lds	temp2,l_ystep
		add	temp,temp2
		sts	l_y,temp
		
		lds	temp,l_error	;error := error - deltax
		lds	temp3,l_error+1
		lds	temp2,l_deltax
		lds	temp4,l_deltax+1
		sub	temp,temp2
		sbc	temp3,temp4
		sts	l_error,temp
		sts	l_error+1,temp3

lcd_line10:	lds	temp,l_x	;end loop
		inc	temp
		sts	l_x,temp
		rjmp	lcd_line7
;
.endif



.ifdef compile_circle
; Bresenham's algorithm for drawing circle
; 
;void rasterCircle(int x0, int y0, int radius)
;{
;   int16 f = 1 - radius;
;   int16 ddF_x = 0;
;   int16 ddF_y = -2 * radius;
;   int x = 0;
;   int y = radius;
; 
;   setPixel(x0, y0 + radius);
;   setPixel(x0, y0 - radius);
;   setPixel(x0 + radius, y0);
;   setPixel(x0 - radius, y0);
; 
;   while(x < y) 
;   {
;     if(f >= 0) 
;     {
;       y--;
;       ddF_y += 2;
;       f += ddF_y;
;     }
;     x++;
;     ddF_x += 2;
;     f += ddF_x + 1;
;
;     setPixel(x0 + x, y0 + y);
;     setPixel(x0 - x, y0 + y);
;     setPixel(x0 + x, y0 - y);
;     setPixel(x0 - x, y0 - y);
;     setPixel(x0 + y, y0 + x);
;     setPixel(x0 - y, y0 + x);
;     setPixel(x0 + y, y0 - x);
;     setPixel(x0 - y, y0 - x);
;  }
; }
;
; # kó³ko
; arg1: x0
; arg2: y0
; arg3: radius
.equ	c_x0=ram_temp
.equ	c_y0=ram_temp+1
.equ	c_radius=ram_temp+2
.equ	c_f=ram_temp+3
.equ	c_ddf_x=ram_temp+5
.equ	c_ddf_y=ram_temp+7
.equ	c_x=ram_temp+9
.equ	c_y=ram_temp+10
lcd_circle:
		lds	temp,lcd_arg1	;store variables
		sts	c_x0,temp
		lds	temp,lcd_arg2
		sts	c_y0,temp
		lds	temp,lcd_arg3
		sts	c_radius,temp
		
		ldi	temp2,1		;int16 f = 1 - radius
		mov	temp3,zero
		sub	temp2,temp
		sbc	temp3,zero
		sts	c_f,temp2
		sts	c_f+1,temp3
		
		sts	c_ddf_x,zero	;int16 ddF_x = 0
		sts	c_ddf_x+1,zero
		
		lds	temp,c_radius	;int16 ddF_y = -2 * radius
		mov	temp3,zero
		add	temp,temp
		adc	temp3,temp3
		mov	temp2,zero
		mov	temp4,zero
		sub	temp2,temp
		sbc	temp4,temp3
		sts	c_ddf_y,temp2
		sts	c_ddf_y+1,temp4
		
		sts	c_x,zero	;int x = 0
		sts	c_x+1,zero
		
		lds	temp,c_radius	;int y = radius
		sts	c_y,temp
		
		lds	temp,c_x0	;setPixel(x0, y0 + radius);
		sts	lcd_arg1,temp
		lds	temp,c_y0
		lds	temp2,c_radius
		add	temp,temp2
		sts	lcd_arg2,temp
		ldi	temp,1		;one time
		sts	lcd_arg3,temp
		sts	lcd_arg4,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_y0	;setPixel(x0, y0 - radius);
		lds	temp2,c_radius
		sub	temp,temp2
		sts	lcd_arg2,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_x0	;setPixel(x0 + radius, y0);
		lds	temp2,c_radius
		add	temp,temp2
		sts	lcd_arg1,temp
		lds	temp,c_y0
		sts	lcd_arg2,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_x0	;setPixel(x0 - radius, y0);
		lds	temp2,c_radius
		sub	temp,temp2
		sts	lcd_arg1,temp
		rcall	lcd_fill_rect
		
lcd_circle1:
		lds	temp,c_x	;while(x < y)
		lds	temp2,c_y
		cp	temp,temp2
		brcs	lcd_circle2
		ret
lcd_circle2:
		lds	temp,c_f+1	;if(f >= 0)
		sbrc	temp,7
		rjmp	lcd_circle3
		
		lds	temp,c_y	;y--
		dec	temp
		sts	c_y,temp
		
		lds	temp,c_ddf_y	;ddF_y += 2;
		lds	temp3,c_ddf_y+1
		ldi	temp2,2
		add	temp,temp2
		adc	temp3,zero
		sts	c_ddf_y,temp
		sts	c_ddf_y+1,temp3
		
		lds	temp2,c_f	;f += ddF_y;
		lds	temp4,c_f+1
		add	temp2,temp
		adc	temp4,temp3
		sts	c_f,temp2
		sts	c_f+1,temp4
lcd_circle3:
		lds	temp,c_x	;x++
		inc	temp
		sts	c_x,temp
		
		lds	temp,c_ddf_x	;ddF_x += 2;
		lds	temp3,c_ddf_x+1
		ldi	temp2,2
		add	temp,temp2
		adc	temp3,zero
		sts	c_ddf_x,temp
		sts	c_ddf_x+1,temp3
		
		ldi	temp2,1		;f += ddF_x + 1;
		add	temp,temp2
		adc	temp3,zero
		lds	temp2,c_f
		lds	temp4,c_f+1
		add	temp2,temp
		adc	temp4,temp3
		sts	c_f,temp2
		sts	c_f+1,temp4
		
		lds	temp,c_x0	;setPixel(x0 + x, y0 + y);
		lds	temp2,c_x
		add	temp,temp2
		sts	lcd_arg1,temp
		lds	temp,c_y0
		lds	temp2,c_y
		add	temp,temp2
		sts	lcd_arg2,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_x0	;setPixel(x0 - x, y0 + y);
		lds	temp2,c_x
		sub	temp,temp2
		sts	lcd_arg1,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_y0	;setPixel(x0 - x, y0 - y);
		lds	temp2,c_y
		sub	temp,temp2
		sts	lcd_arg2,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_x0	;setPixel(x0 + x, y0 - y);
		lds	temp2,c_x
		add	temp,temp2
		sts	lcd_arg1,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_x0	;setPixel(x0 + y, y0 + x);
		lds	temp2,c_y
		add	temp,temp2
		sts	lcd_arg1,temp
		lds	temp,c_y0
		lds	temp2,c_x
		add	temp,temp2
		sts	lcd_arg2,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_x0	;setPixel(x0 - y, y0 + x);
		lds	temp2,c_y
		sub	temp,temp2
		sts	lcd_arg1,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_y0	;setPixel(x0 - y, y0 - x);
		lds	temp2,c_x
		sub	temp,temp2
		sts	lcd_arg2,temp
		rcall	lcd_fill_rect
		
		lds	temp,c_x0	;setPixel(x0 + y, y0 - x);
		lds	temp2,c_y
		add	temp,temp2
		sts	lcd_arg1,temp
		rcall	lcd_fill_rect
		
		rjmp	lcd_circle1
;
.endif



