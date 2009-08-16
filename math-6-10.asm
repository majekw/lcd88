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
; add two operands on the stack
math_add:
		lds	YL,math_sp		;get stack pointer
		lds	YH,math_sp+1
		sbiw	YL,4
		ld	mtemp1,Y		;get parameters
		ldd	mtemp2,Y+1
		ldd	mtemp3,Y+2
		ldd	mtemp4,Y+3
		add	mtemp1,mtemp2		;add
		adc	mtemp2,mtemp4
		brcc	math_add_1		;check for overflow
		ori	statush,(1<<MATH_OV)
math_add_1:
		st	Y+,mtemp1		;store result
		st	Y+,mtemp2
		sts	math_sp,YL		;update stack pointer
		sts	math_sp+1,YH
math_ret:
		ret
;


;
; negate operand on the stack
math_neg:
		lds	YL,math_sp		;get stack pointer
		lds	YH,math_sp+1
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
		lds	YL,math_sp		;get stack pointer
		lds	YH,math_sp+1
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
		ret
;


;
; check sign of result in multiply and division, swaps operand on the stack!
math_sign_calc:
		lds	YL,math_sp		;get stack pointer
		lds	YH,math_sp+1
		sbiw	YL,2
		;check sign
		andi	statush,~(1<<MATH_SIGN)	;clear result sign
		ld	mtemp1,Y
		sbrs	mtemp1,7	;check for sign
		rjmp	math_sign_calc_1
		ori	statush,(1<<MATH_SIGN)	;prepare sign
		rcall	math_neg		;negate operand
math_sign_calc_1:
		rcall	math_swap		;swap operand on the stack

		lds	YL,math_sp		;get stack pointer
		lds	YH,math_sp+1
		sbiw	YL,2
		ld	mtemp1,Y
		sbrs	mtemp1,7	;check for sign
		ret
		ldi	temp,(1<<MATH_SIGN)
		eor	statush,temp		;prepare sign
		rcall	math_neg		;negate operand
		ret
;


;
; multiply two operands on the stack
math_mul:
		rcall	math_sign_calc		;prepare operands and calulate sign of result

		lds	YL,math_sp		;get stack pointer
		lds	YH,math_sp+1
		sbiw	YL,4


math_mul_x:
		ret
;

;
; math stack
.dseg
math_stack:	.byte	10
math_sp:	.byte	2
.cseg
;


