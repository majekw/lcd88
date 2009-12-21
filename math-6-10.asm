; Fixed point math library: 6.10
; (C) 2009 Marek Wodzinski majek@mamy.to
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

		rcall	math_set_sp		;update stack pointer
math_ret:
		ret
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
		rcall	math_neg		;negate operand
		ret
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
		rcall	math_neg

		ret
;


;
; compare arguments on the stack
;	return carry if first argument is less than second
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
		rcall	math_compare
		st	Y,mtemp1
		std	Y+1,mtemp2
		adiw	YL,2
		rcall	math_set_sp
		ret
;


;
; minimum
math_min:
		rcall	math_compare
		brcs	math_min_1
		rcall	math_swap
math_min_1:
		adiw	YL,2
		rcall	math_set_sp
		ret
;

;
; maximum
math_max:
		rcall	math_compare
		brcc	math_max_1
		rcall	math_swap
math_max_1:
		adiw	YL,2
		rcall	math_set_sp
		ret
;


;
; math stack
.dseg
math_sp:	.byte	2
math_stack:	.byte	10
.cseg
;


