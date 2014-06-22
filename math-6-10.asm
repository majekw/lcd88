; Fixed point math library: 6.10
; (C) 2009-2014 Marek Wodzinski majek@mamy.to
;
; This code is under terms and conditions of GNU GPL v3 license
;
; Changelog:
; 2009.08.16	- start coding:
;			math_init
;			math_add
;			math_neg
;			math_swap
;			math_sign_calc
;			math_mul (not finished)
; 2009.08.17	- math_dup
;		- added cli/sei around storing math_sp to make it multitasking safe
;		- finished math_mul
; 2009.09.13	- math_get_sp
;		- math_set_sp
;		- subroutines updated to use math_set/get_sp
;		- fixed math_calc_sign (wrong byte get to sign calculation)
;		- fixed math_add (typo, but important)
;		- math_compare
;		- math_sub
;		- math_min
;		- math_max
; 2012.12.27	- math_push
;		- math_drop
; 2012.12.28	- fixed functions using math_compare
; 2012.12.29	- math_pop
;		- math_todec
; 2013.01.01	- math_todec_byte (not quite 6.10 but reuses a large amount of code from math_todec)
; 2012.01.05	- small size optimization (saved 24B)
; 2012.01.07	- another size oprimization in math_todec
;		- use mtemp5 instead of global temp3 in math_todec
; 2014.06.22	- added GPL license

;
; initialize math stack pointer
math_init:
		ldi	temp,low(math_stack)
		sts	math_sp,temp
		ldi	temp,high(math_stack)
		sts	math_sp+1,temp
		ret
;

;
; get stack pointer (to Y)
math_get_sp:
		lds	YL,math_sp		;get stack pointer
		lds	YH,math_sp+1
		ret
;


;
; set stack pointer (to Y)
math_set_sp:
		cli
		sts	math_sp,YL		;update stack pointer
		sts	math_sp+1,YH
		sei
		ret
;


;
; add two operands on the stack
math_add:
		rcall	math_get_sp		;get stack pointer

		sbiw	YL,4			;rewind by 4 bytes (2 params)
		
		ld	mtemp1,Y		;get parameters
		ldd	mtemp2,Y+1
		ldd	mtemp3,Y+2
		ldd	mtemp4,Y+3
		
		add	mtemp1,mtemp3		;add
		adc	mtemp2,mtemp4
		brcc	math_add_1		;check for overflow
		ori	statush,(1<<MATH_OV)
math_add_1:
		st	Y+,mtemp1		;store result
		st	Y+,mtemp2

		rjmp	math_set_sp		;update stack pointer
		;ret
;


;
; negate operand on the stack
math_neg:
		rcall	math_get_sp		;get stack pointer

		sbiw	YL,2			;rewind by 2 bytes (1 param)
		ld	mtemp1,Y		;get parameter
		ldd	mtemp2,Y+1
		
		mov	mtemp3,zero		;result=0-A
		mov	mtemp4,zero
		sub	mtemp3,mtemp1
		sbc	mtemp4,mtemp2
		
		st	Y,mtemp3
		std	Y+1,mtemp4
		
		ret
;

;
; swap operand on the stack
math_swap:
		rcall	math_get_sp		;get stack pointer
		sbiw	YL,4
		ld	mtemp1,Y
		ldd	mtemp2,Y+1
		ldd	mtemp3,Y+2
		ldd	mtemp4,Y+3
		st	Y,mtemp3
		std	Y+1,mtemp4
		std	Y+2,mtemp1
		std	Y+3,mtemp2
		ret
;

;
; duplicate operand on the stack
math_dup:
		rcall	math_get_sp		;get stack pointer
		adiw	YL,2			;must be multitasking safe, so update stack pointer at beginning
		rcall	math_set_sp
		sbiw	YL,4
		ld	mtemp1,Y
		ldd	mtemp2,Y+1
		std	Y+2,mtemp1
		std	Y+3,mtemp2
		ret
;


;
; check sign of result in multiply and division, swaps operand on the stack!
math_sign_calc:
		rcall	math_get_sp		;get stack pointer
		sbiw	YL,2
		;check sign
		andi	statush,~(1<<MATH_SIGN)	;clear result sign
		ldd	mtemp1,Y+1
		sbrs	mtemp1,7	;check for sign
		rjmp	math_sign_calc_1
		ori	statush,(1<<MATH_SIGN)	;prepare sign
		rcall	math_neg		;negate operand
math_sign_calc_1:
		rcall	math_swap		;swap operand on the stack

		rcall	math_get_sp		;get stack pointer
		sbiw	YL,2
		ldd	mtemp1,Y+1
		sbrs	mtemp1,7	;check for sign
		ret
		ldi	temp,(1<<MATH_SIGN)
		eor	statush,temp		;prepare sign
		rjmp	math_neg		;negate operand
		;ret
;


;
; multiply two operands on the stack
; 6.10*6.10=12.20 (last 10 bits we must discard)
;                 A   B    (1 0)
;              *  C   D    (3 2)
;             -----------
;                 B * D
;             A * D
;             B * C
;     +   A * C
;     -------------------
;         3   2   1   x
; then >>2 to get right result, so only 2 bits of mtemp3 are significant
math_mul:
		rcall	math_sign_calc		;prepare operands and calulate sign of result

		rcall	math_get_sp		;get stack pointer
		sbiw	YL,4
		
		ld	mtemp1,Y	;B
		ldd	mtemp2,Y+2	;D
		mul	mtemp1,mtemp2	;B*D
		mov	mtemp1,r1	;r0 can be discarded
		
		clr	mtemp3		;prepare mtemp3
		ldd	mtemp4,Y+1	;A
		mul	mtemp4,mtemp2	;A*D
		mov	mtemp2,r1
		add	mtemp1,r0
		adc	mtemp2,zero
		adc	mtemp3,zero
		
		ldd	mtemp4,Y+3	;C
		ld	r0,Y		;B
		mul	r0,mtemp4	;B*C
		add	mtemp1,r0
		adc	mtemp2,r1
		adc	mtemp3,zero
		
		ldd	r0,Y+1		;A
		mul	mtemp4,r0	;A*C
		add	mtemp2,r0
		adc	mtemp3,r1
		
		lsr	mtemp3		;shift right by 2 bits result to fit in 16 bit format
		ror	mtemp2
		ror	mtemp1
		lsr	mtemp3
		ror	mtemp2
		ror	mtemp1
		
		tst	mtemp3		;overflow if something left in mtemp3
		brne	math_mul_1
		ori	statush,(1<<MATH_OV)
math_mul_1:
		sbrc	mtemp2,7	;if MSB is 1, there is also overflow (this is place for sign)
		ori	statush,(1<<MATH_OV)
		
		st	Y+,mtemp1	;store result
		st	Y+,mtemp2
		
		rcall	math_set_sp		;update stack pointer
		
		sbrc	statush,MATH_SIGN	;restore sign
		rjmp	math_neg

		;ret
;


;
; compare arguments on the stack
;	return S if first argument is less than second, use brge or brlt jumps for checking!
math_compare:
		rcall	math_get_sp
		sbiw	YL,4
		ld	mtemp1,Y
		ldd	mtemp2,Y+1
		ldd	mtemp3,Y+2
		ldd	mtemp4,Y+3
		sub	mtemp1,mtemp3
		sbc	mtemp2,mtemp4
		
		ret
;

;
; substract
math_sub:
		rcall	math_compare	;it makes substract indeed but without storing result
		st	Y,mtemp1	;store result
		std	Y+1,mtemp2

		rjmp	math_drop
		;ret
;


;
; minimum
math_min:
		rcall	math_compare
		brge	math_min_1
		rcall	math_swap
math_min_1:
		rjmp	math_drop
		;ret
;

;
; maximum
math_max:
		rcall	math_compare
		brlt	math_max_1
		rcall	math_swap
math_max_1:
		rjmp	math_drop
		;ret
;

;
; division
;math_div:
;		rcall	math_sign_calc		;get sign
;
;		; TODO
;		
;		sbrc	statush,MATH_SIGN	;restore sign
;		rcall	math_neg
;
;		ret
;

;
; push number on the stack
; mtemp1, mtemp2 - value
math_push:
		rcall	math_get_sp
		adiw	YL,2
		rcall	math_set_sp
		sbiw	YL,2
		st	Y+,mtemp1
		st	Y+,mtemp2
		ret
;

;
; pop number from the stack
; out: mtemp1, mtemp2 - value
math_pop:
		rcall	math_get_sp
		sbiw	YL,2
		ld	mtemp1,Y
		ldd	mtemp2,Y+1
		rjmp	math_set_sp
		;ret
;

;
; drop last operand from the stack
math_drop:
		rcall	math_get_sp
		sbiw	YL,2
		rjmp	math_set_sp
		;ret
;

;
; convert to decimal
; it needs max 14 bytes of output (1 sign + 2 number + 1 dot + 10 fraction)
; in fact, 4 digits of fraction should be enough, so total 8 bytes needed
; anyway, using 16 bit to compute it limits number of bcd digits to 4
; in: mtemp1, mtemp2
; out: chars @math_todec_out
; destroyed: temp,temp2,mtemp1..5
.equ	math_todec_out=ram_temp		;use general purpose ram buffer for output
math_todec:
		;get sign
		ldi	temp,'+'
		sbrs	mtemp2,7	;check sign
		rjmp	math_todec_1
		;minus...
		mov	mtemp3,zero	;negate
		mov	mtemp4,zero
		sub	mtemp3,mtemp1
		sbc	mtemp4,mtemp2
		mov	mtemp1,mtemp3	;get result back to proper registers
		mov	mtemp2,mtemp4
		ldi	temp,'-'
math_todec_1:
		sts	math_todec_out,temp	;store sign
		
		push	mtemp1		;save value for later
		push	mtemp2

		;get integer part
		clr	temp		;prepare operand to double-dabble
    		lsl	mtemp2
    		
    		lsl	mtemp2		;shift1
    		rol	temp
    		lsl	mtemp2		;shift2
    		rol	temp
    		lsl	mtemp2		;shift3
    		rol	temp
    		cpi	temp,5		;check if add3 should be performed
    		brcs	math_todec_2
    		subi	temp,-3		;add3
math_todec_2:	lsl	mtemp2		;shift4
		rol	temp
		mov	temp2,temp
		andi	temp2,0x0f
		cpi	temp2,5
		brcs	math_todec_3
		subi	temp,-3
math_todec_3:	lsl	mtemp2		;shift5
		rol	temp
		
		mov	temp2,temp
		swap	temp2		;tens
		andi	temp2,0x0f
		subi	temp2,-48
		sts	math_todec_out+1,temp2
		andi	temp,0x0f
		subi	temp,-48
		sts	math_todec_out+2,temp
		
		;comma
		ldi	temp,'.'
		sts	math_todec_out+3,temp
		
		;get fraction part
		pop	mtemp2
		pop	mtemp1
		ldi	temp,0b00000011	;drop integer part
		and	mtemp2,temp
		rcall	math_push	;push on the stack
		ldi	temp,low(10000)	;prepare second number to multiply
		mov	mtemp1,temp
		ldi	temp,high(10000)
		mov	mtemp2,temp
		rcall	math_push	;push 10000 on the stack
		rcall	math_mul	;multiply
		rcall	math_pop	;get result
		
		;convert fraction to bcd
		ldi	temp,16		;shifts count

math_todec_entry:			;this back entry to loop, for example for
		clr	mtemp3		;prepare result
		clr	mtemp4

		ldi	temp2,3		;prepare operand to add3
		mov	mtemp5,temp2
math_todec_4:
		lsl	mtemp1		;shift
		rol	mtemp2
		rol	mtemp3
		rol	mtemp4
		dec	temp		;check for shift count
		breq	math_todec_e
		;check for add3
		mov	temp2,mtemp3	;first nibble
		andi	temp2,0x0f
		cpi	temp2,5
		brcs	math_todec_5
		add	mtemp3,mtemp5	;add3
		adc	mtemp4,zero
math_todec_5:
		mov	temp2,mtemp3	;second nibble
		swap	temp2
		andi	temp2,0x0f
		cpi	temp2,5
		brcs	math_todec_6
		swap	mtemp5		;add3
		add	mtemp3,mtemp5
		adc	mtemp4,zero
		swap	mtemp5
math_todec_6:
		mov	temp2,mtemp4	;third nibble
		andi	temp2,0x0f
		cpi	temp2,5
		brcs	math_todec_7
		add	mtemp4,mtemp5	;add3
math_todec_7:
		mov	temp2,mtemp4	;last nibble
		swap	temp2
		andi	temp2,0x0f
		cpi	temp2,5
		brcs	math_todec_4
		swap	mtemp5		;add3
		add	mtemp4,mtemp5
		swap	mtemp5

		rjmp	math_todec_4
math_todec_e:
		;store resut
		mov	temp,mtemp4	;high byte
		swap	temp
		andi	temp,0x0f
		subi	temp,-48
		sts	math_todec_out+4,temp
		mov	temp,mtemp4
		andi	temp,0x0f
		subi	temp,-48
		sts	math_todec_out+5,temp
		mov	temp,mtemp3
		swap	temp
		andi	temp,0x0f
		subi	temp,-48
		sts	math_todec_out+6,temp
		mov	temp,mtemp3
		andi	temp,0x0f
		subi	temp,-48
		sts	math_todec_out+7,temp
		sts	math_todec_out+8,zero	;terminating zero
		
		ret
;

;
; # convert only one byte to 2 digits
; in: mtemp2
; out: ascii at math_todec_out+5..7
; destroyed: mtemp1..5,temp,temp2
math_todec_byte:
		;convert fraction to bcd
		ldi	temp,8		;shifts count
		rjmp	math_todec_entry


;
; math stack
.dseg
math_sp:	.byte	2	;math stack pointer
math_stack:	.byte	16	;stack area
.cseg
;


