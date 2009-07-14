; some basic definitions of models
;
; channels:
; 0-7  - analog inputs
; 8-15 - digital/external inputs
; 16-23 - outputs
; 24 - 0
; 25 - 1
; 26 - -1
;
; containter definition:
; 1 - model id + deleted + content type
;	- 0-4	model id
;	- 5	deleted
;	- 6-7	type
;		0 - block
;		1 - block processing order
;		2 - channels
;		3 - descriptions
; 2 - length
; 3 - id
; 4 - content...

; types of blocks:		inputs	outputs	input types	remark
; 1 - trim			2	1	(in+trim)	=adder but special treatment of trim input
; 2 - reverse			2	1	(in+reverse)	=multiplier but a.a.
; 2 - adder			2	1	(2x in)
; 3 - limit			3	1	(in+min+max)
; 4 - multiplier		2	1	(2x in)
; 5 - digital input		1	1	(in)		kind of shootky gate: returns only -1,0,1
; 6 - multiplexer		4	1	(3x in+control)
; 7 - limit detector		1	1	(in)		returns number to multiply by to stay in -1...1 range (if exceeded, else 1)
; 8 - min			2	1	(2x in)		returns lower value
; 9 - max			2	1	(2x in)		returns higher value

; specific blocks:
; 0 - block
;	model_id+(deleted<<5)+(0<<6)
;	length = block specific
;	block_id
;	description_id
;	block_type
;	inputs		(count)
;	outputs
;	input1		(channel)
;	input2
;	...
;	output1
;	output2
;	...
;
; 1 - block processing order
;	model_id+(1<<6)
;	length
;	block_id
;	block_id
;	...
;
; 2 - channels
;	model_id+(deleted<<5)+(2<<6)
;	length=6
;	channel_id
;	description_id
;	value_h
;	value_l
;
; 3 - description
;	model_id+(deleted<<5)+(3<<6)
;	length
;	description_id	(0 = model name)
;	chars,0

.cseg

; basic 4 ch model - no mixers, just dumb way to copy sticks to output channels
;
.set		model=1
		;channels
		.db	model+(2<<6),6,0,1,0,0		;adc0 input
		.db	model+(2<<6),6,1,2,0,0		;adc1 input
		.db	model+(2<<6),6,2,3,0,0		;adc2 input
		.db	model+(2<<6),6,3,4,0,0		;adc3 input
		.db	model+(2<<6),6,16,5,0,0		;ch0 out
		.db	model+(2<<6),6,17,6,0,0		;ch1 out
		.db	model+(2<<6),6,18,7,0,0		;ch2 out
		.db	model+(2<<6),6,19,8,0,0		;ch3 out
		.db	model+(2<<6),6,27,9,0,0		;ch0 trim (default 0)
		.db	model+(2<<6),6,28,10,0,0	;ch1 trim
		.db	model+(2<<6),6,29,11,0,0	;ch2 trim
		.db	model+(2<<6),6,30,12,0,0	;ch3 trim
		.db	model+(2<<6),6,31,13,0,4	;ch0 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,32,14,0,4	;ch1 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,33,15,0,4	;ch2 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,34,16,0,4	;ch3 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,35,0,0,0	;ch0 connection between trim and inverse
		.db	model+(2<<6),6,36,0,0,0	;ch1 connection between trim and inverse
		.db	model+(2<<6),6,37,0,0,0	;ch2 connection between trim and inverse
		.db	model+(2<<6),6,38,0,0,0	;ch3 connection between trim and inverse

		;blocks
		.db	model+(0<<6),10,1,21,1,2,1,0,27,35	;trim for ch0
		.db	model+(0<<6),10,2,22,1,2,1,1,28,36	;trim for ch1
		.db	model+(0<<6),10,3,23,1,2,1,2,29,37	;trim for ch2
		.db	model+(0<<6),10,4,24,1,2,1,3,30,38	;trim for ch3
		.db	model+(0<<6),10,5,25,2,2,1,35,31,16	;reverse for ch0
		.db	model+(0<<6),10,6,26,2,2,1,36,32,17	;reverse for ch1
		.db	model+(0<<6),10,7,27,2,2,1,37,33,18	;reverse for ch2
		.db	model+(0<<6),10,8,28,2,2,1,38,34,19	;reverse for ch3
		
		;block processing order
		.db	model+(1<<6),10,1,2,3,4,5,6,7,8
		
		;decriptions
		.db	model+(3<<6),14,0,"Basic 4CH",0,0
		.db	model+(3<<6),12,1,"input 1",0,0
		.db	model+(3<<6),12,2,"input 2",0,0
		.db	model+(3<<6),12,3,"input 3",0,0
		.db	model+(3<<6),12,4,"input 4",0,0
		.db	model+(3<<6),12,5,"output 1",0
		.db	model+(3<<6),12,6,"output 2",0
		.db	model+(3<<6),12,7,"output 3",0
		.db	model+(3<<6),12,8,"output 4",0
		.db	model+(3<<6),12,9,"ch1 trim",0
		.db	model+(3<<6),12,10,"ch2 trim",0
		.db	model+(3<<6),12,11,"ch3 trim",0
		.db	model+(3<<6),12,12,"ch4 trim",0
		.db	model+(3<<6),16,13,"ch1 reverse",0,0
		.db	model+(3<<6),16,14,"ch2 reverse",0,0
		.db	model+(3<<6),16,15,"ch3 reverse",0,0
		.db	model+(3<<6),16,16,"ch4 reverse",0,0
		.db	model+(3<<6),16,21,"trim for ch1",0
		.db	model+(3<<6),16,22,"trim for ch2",0
		.db	model+(3<<6),16,23,"trim for ch3",0
		.db	model+(3<<6),16,24,"trim for ch4",0
		.db	model+(3<<6),20,25,"reverse for ch1",0,0
		.db	model+(3<<6),20,26,"reverse for ch2",0,0
		.db	model+(3<<6),20,27,"reverse for ch3",0,0
		.db	model+(3<<6),20,28,"reverse for ch4",0,0

; simple 2 channel delta - NOT FINISHED!
.set	model=2
		;channels
		.db	model+(2<<6),6,0,1,0,0		;adc0 input
		.db	model+(2<<6),6,1,2,0,0		;adc1 input
		.db	model+(2<<6),6,27,0,0,0		;ch0 trim (default 0)
		.db	model+(2<<6),6,28,0,0,0		;ch1 trim
		.db	model+(2<<6),6,29,0,0,4		;ch0 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,30,0,0,4		;ch1 reverse (default 1 = no reverse)
		;blocks
		.db	model+(0<<6),10,1,0,1,2,1,0,27,35	;trim for ch0
		.db	model+(0<<6),10,2,0,1,2,1,1,28,36	;trim for ch1
		;decriptions
		.db	model+(3<<6),14,0,"Alula 2CH",0,0
		.db	model+(3<<6),12,1,"aileron",0,0
		.db	model+(3<<6),12,2,"elevator",0
