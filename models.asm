; some basic definitions of models
;
; channels:
; 0-7  - analog inputs
; 8-15 - digital/external inputs
; 16-23 - outputs
; 24 - 0
; 25 - 1
; 26 - -1
; 27 - buzzer
; 28-31 - dedicated channels for trims for sticks 1-4 (can be updated automatically from extender)
; 32-39 - another trims channels
; 40-51 - reverse channels
; 52 - user channels

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
; 3 - limit			3	1	(in+min+max)
; 4 - multiplier		2	1	(2x in)		X=A*B
; 5 - digital input		1	1	(in)		kind of shootky gate: returns only -1,0,1
; 6 - multiplexer		3	1	(2x in+control)
; 7 - limit detector		1	1	(in)		returns number to multiply by to stay in -1...1 range (if exceeded, else 1)
; 8 - min			2	1	(2x in)		X=min(A,B)
; 9 - max			2	1	(2x in)		X=max(A,B)
; 10 - delta			2	2	(2x in)		X=(A+B)/2, Y=(A-B)/2
; 11 - sub			2	1	(2x in)		X=A-B
; 12 - adder			2	1	(2x in)		X=A+B
; 13 - compare			2	1	(2x in)		X=0 if A=B,X=-1 if A<B, X=1 if A>B
; 14 - abs			1	1	(in)		X=X if X>=0, X=-X if X<0
; 15 - neg			1	1	(in)		X=-A
; 16 - copy			1	1	(in)		X=A
; 17 - expo			2	1	(in,rate)	X=A*(B*A*A+1-B)

; specific blocks:
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
;	with comments to each channels (nice example)
;
;.set		model=1
;		;channels
;		.db	model+(2<<6),6,0,1,0,0		;adc0 input
;		.db	model+(2<<6),6,1,2,0,0		;adc1 input
;		.db	model+(2<<6),6,2,3,0,0		;adc2 input
;		.db	model+(2<<6),6,3,4,0,0		;adc3 input
;		.db	model+(2<<6),6,16,5,0,0		;ch0 out
;		.db	model+(2<<6),6,17,6,0,0		;ch1 out
;		.db	model+(2<<6),6,18,7,0,0		;ch2 out
;		.db	model+(2<<6),6,19,8,0,0		;ch3 out
;		.db	model+(2<<6),6,28,9,0,0		;ch0 trim (default 0)
;		.db	model+(2<<6),6,29,10,0,0	;ch1 trim
;		.db	model+(2<<6),6,30,11,0,0	;ch2 trim
;		.db	model+(2<<6),6,31,12,0,0	;ch3 trim
;		.db	model+(2<<6),6,40,13,0,4	;ch0 reverse (default 1 = no reverse)
;		.db	model+(2<<6),6,41,14,0,4	;ch1 reverse (default 1 = no reverse)
;		.db	model+(2<<6),6,42,15,0,4	;ch2 reverse (default 1 = no reverse)
;		.db	model+(2<<6),6,43,16,0,4	;ch3 reverse (default 1 = no reverse)
;		.db	model+(2<<6),6,52,0,0,0	;ch0 connection between trim and inverse
;		.db	model+(2<<6),6,53,0,0,0	;ch1 connection between trim and inverse
;		.db	model+(2<<6),6,54,0,0,0	;ch2 connection between trim and inverse
;		.db	model+(2<<6),6,55,0,0,0	;ch3 connection between trim and inverse
;
;		;blocks
;		.db	model+(0<<6),10,1,21,1,2,1,0,28,52	;trim for ch0
;		.db	model+(0<<6),10,2,22,1,2,1,1,29,53	;trim for ch1
;		.db	model+(0<<6),10,3,23,1,2,1,2,30,54	;trim for ch2
;		.db	model+(0<<6),10,4,24,1,2,1,3,31,55	;trim for ch3
;		.db	model+(0<<6),10,5,25,2,2,1,52,40,16	;reverse for ch0
;		.db	model+(0<<6),10,6,26,2,2,1,53,41,17	;reverse for ch1
;		.db	model+(0<<6),10,7,27,2,2,1,54,42,18	;reverse for ch2
;		.db	model+(0<<6),10,8,28,2,2,1,55,43,19	;reverse for ch3
;		
;		;block processing order
;		.db	model+(1<<6),10,1,2,3,4,5,6,7,8
;		
;		;decriptions
;		.db	model+(3<<6),14,0,"Basic 4CH",0,0
;		.db	model+(3<<6),12,1,"input 1",0,0
;		.db	model+(3<<6),12,2,"input 2",0,0
;		.db	model+(3<<6),12,3,"input 3",0,0
;		.db	model+(3<<6),12,4,"input 4",0,0
;		.db	model+(3<<6),12,5,"output 1",0
;		.db	model+(3<<6),12,6,"output 2",0
;		.db	model+(3<<6),12,7,"output 3",0
;		.db	model+(3<<6),12,8,"output 4",0
;		.db	model+(3<<6),12,9,"ch1 trim",0
;		.db	model+(3<<6),12,10,"ch2 trim",0
;		.db	model+(3<<6),12,11,"ch3 trim",0
;		.db	model+(3<<6),12,12,"ch4 trim",0
;		.db	model+(3<<6),16,13,"ch1 reverse",0,0
;		.db	model+(3<<6),16,14,"ch2 reverse",0,0
;		.db	model+(3<<6),16,15,"ch3 reverse",0,0
;		.db	model+(3<<6),16,16,"ch4 reverse",0,0
;		.db	model+(3<<6),16,21,"trim for ch1",0
;		.db	model+(3<<6),16,22,"trim for ch2",0
;		.db	model+(3<<6),16,23,"trim for ch3",0
;		.db	model+(3<<6),16,24,"trim for ch4",0
;		.db	model+(3<<6),20,25,"reverse for ch1",0,0
;		.db	model+(3<<6),20,26,"reverse for ch2",0,0
;		.db	model+(3<<6),20,27,"reverse for ch3",0,0
;		.db	model+(3<<6),20,28,"reverse for ch4",0,0
;
; simple 2 channel delta - minimalistic scenario without descriptions (and made without delta special block)
; ch0 ------------trim--ch52--reverse--ch53--mul--ch54---add---out0
;                 ch28         ch40          ch32      \   \---------\
;                                                       \            |
; ch1 --expo--61--trim--ch55--reverse--ch56--mul--ch57--add---out1   |
;        ch4      ch29         ch41          ch33   \                |
;                                                    -neg--ch58------/
;
; ch2 --trim--ch59--reverse--out2
;       ch30         ch42
;
; ch3 --trim--ch60--reverse--out2
;       ch31         ch43
;
; ch32=0.5	ch33=0.5
.set	model=2
		;channels
		.db	model+(2<<6),6,28,0,0,0		;ch0 trim (default 0)
		.db	model+(2<<6),6,29,0,0,0		;ch1 trim
		.db	model+(2<<6),6,30,0,0,0		;ch2 trim
		.db	model+(2<<6),6,31,0,0,0		;ch3 trim
		.db	model+(2<<6),6,40,0,0,4		;ch0 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,41,0,0,4		;ch1 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,32,0,0,2		;ch0 x0.5
		.db	model+(2<<6),6,33,0,0,2		;ch1 x0.5
		.db	model+(2<<6),6,42,0,0,4		;ch2 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,43,0,0,4		;ch3 reverse (default 1 = no reverse)
		;blocks
		.db	model+(0<<6),10,1,0,1,2,1,0,28,52	;trim for ch0
		.db	model+(0<<6),10,2,0,1,2,1,61,29,55	;trim for ch1
		.db	model+(0<<6),10,3,0,2,2,1,52,40,56	;rev for ch0
		.db	model+(0<<6),10,4,0,2,2,1,55,41,53	;rev for ch1
		.db	model+(0<<6),10,5,0,4,2,1,53,32,54	;mul for ch0
		.db	model+(0<<6),10,6,0,4,2,1,56,33,57	;mul for ch1
		.db	model+(0<<6),10,7,0,12,2,1,54,58,16	;add for ch0
		.db	model+(0<<6),10,8,0,12,2,1,54,57,17	;add for ch1
		.db	model+(0<<6),10,9,0,15,1,1,57,58,0	;neg for inverse ch1
		.db	model+(0<<6),10,10,0,1,2,1,2,30,59	;trim for ch2
		.db	model+(0<<6),10,11,0,1,2,1,3,31,60	;trim for ch3
		.db	model+(0<<6),10,12,0,2,2,1,59,42,18	;rev for ch2
		.db	model+(0<<6),10,13,0,2,2,1,60,43,19	;rev for ch03
		.db	model+(0<<6),10,14,0,17,2,1,1,4,61	;expo for ch1
		;decription
		.db	model+(3<<6),14,0,"Delta 2CH!",0
		;block processing order
		.db	model+(1<<6),16,14,1,2,3,4,5,6,8,9,7,10,11,12,13

; basic 4 ch model - for auto
;
.set		model=3
		;channels
		;.db	model+(2<<6),6,0,1,0,0		;adc0 input
		;.db	model+(2<<6),6,1,2,0,0		;adc1 input
		;.db	model+(2<<6),6,2,3,0,0		;adc2 input
		;.db	model+(2<<6),6,3,4,0,0		;adc3 input
		;.db	model+(2<<6),6,16,5,0,0		;ch0 out
		;.db	model+(2<<6),6,17,6,0,0		;ch1 out
		;.db	model+(2<<6),6,18,7,0,0		;ch2 out
		;.db	model+(2<<6),6,19,8,0,0		;ch3 out
		.db	model+(2<<6),6,28,9,0,0		;ch0 trim (default 0)
		.db	model+(2<<6),6,29,10,0,0	;ch1 trim
		.db	model+(2<<6),6,30,11,0,0	;ch2 trim
		.db	model+(2<<6),6,31,12,0,0	;ch3 trim
		.db	model+(2<<6),6,40,13,low(L_MONE),high(L_MONE)	;ch0 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,41,14,low(L_ONE),high(L_ONE)	;ch1 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,42,15,low(L_ONE),high(L_ONE)	;ch2 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,43,16,low(L_ONE),high(L_ONE)	;ch3 reverse (default 1 = no reverse)
		;.db	model+(2<<6),6,52,0,0,0	;ch0 connection between trim and inverse
		;.db	model+(2<<6),6,53,0,0,0	;ch1 connection between trim and inverse
		;.db	model+(2<<6),6,54,0,0,0	;ch2 connection between trim and inverse
		;.db	model+(2<<6),6,55,0,0,0	;ch3 connection between trim and inverse

		;blocks
		.db	model+(0<<6),10,1,21,1,2,1,0,28,52	;trim for ch0
		.db	model+(0<<6),10,2,22,1,2,1,1,29,53	;trim for ch1
		.db	model+(0<<6),10,3,23,1,2,1,2,30,54	;trim for ch2
		.db	model+(0<<6),10,4,24,1,2,1,3,31,55	;trim for ch3
		.db	model+(0<<6),10,5,25,2,2,1,52,40,16	;reverse for ch0
		.db	model+(0<<6),10,6,26,2,2,1,53,41,17	;reverse for ch1
		.db	model+(0<<6),10,7,27,2,2,1,54,42,18	;reverse for ch2
		.db	model+(0<<6),10,8,28,2,2,1,55,43,19	;reverse for ch3
		
		;block processing order
		.db	model+(1<<6),10,1,2,3,4,5,6,7,8
		
		;decriptions
		.db	model+(3<<6),10,0,"Auto ",0,0
		;.db	model+(3<<6),12,1,"input 1",0,0
		;.db	model+(3<<6),12,2,"input 2",0,0
		;.db	model+(3<<6),12,3,"input 3",0,0
		;.db	model+(3<<6),12,4,"input 4",0,0
		;.db	model+(3<<6),12,5,"output 1",0
		;.db	model+(3<<6),12,6,"output 2",0
		;.db	model+(3<<6),12,7,"output 3",0
		;.db	model+(3<<6),12,8,"output 4",0
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



; full 8 channels
;
.set		model=4
		;channels
		;.db	model+(2<<6),6,0,1,0,0		;adc0 input
		;.db	model+(2<<6),6,1,2,0,0		;adc1 input
		;.db	model+(2<<6),6,2,3,0,0		;adc2 input
		;.db	model+(2<<6),6,3,4,0,0		;adc3 input
		;.db	model+(2<<6),6,4,1,0,0		;adc4 input
		;.db	model+(2<<6),6,5,2,0,0		;adc5 input
		;.db	model+(2<<6),6,6,3,0,0		;adc6 input
		;.db	model+(2<<6),6,7,4,0,0		;adc7 input
		;.db	model+(2<<6),6,16,5,0,0		;ch0 out
		;.db	model+(2<<6),6,17,6,0,0		;ch1 out
		;.db	model+(2<<6),6,18,7,0,0		;ch2 out
		;.db	model+(2<<6),6,19,8,0,0		;ch3 out
		;.db	model+(2<<6),6,20,5,0,0		;ch4 out
		;.db	model+(2<<6),6,21,6,0,0		;ch5 out
		;.db	model+(2<<6),6,22,7,0,0		;ch6 out
		;.db	model+(2<<6),6,23,8,0,0		;ch7 out
		.db	model+(2<<6),6,28,0,0,0		;ch0 trim (default 0)
		.db	model+(2<<6),6,29,0,0,0		;ch1 trim
		.db	model+(2<<6),6,30,0,0,0		;ch2 trim
		.db	model+(2<<6),6,31,0,0,0		;ch3 trim
		.db	model+(2<<6),6,32,0,0,0		;ch4 trim
		.db	model+(2<<6),6,40,0,low(L_ONE),high(L_ONE)	;ch0 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,41,0,low(L_ONE),high(L_ONE)	;ch1 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,42,0,low(L_ONE),high(L_ONE)	;ch2 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,43,0,low(L_ONE),high(L_ONE)	;ch3 reverse (default 1 = no reverse)
		.db	model+(2<<6),6,44,0,low(L_ONE),high(L_ONE)	;ch4 reverse (default 1 = no reverse)
		;.db	model+(2<<6),6,52,0,0,0	;ch0 connection between trim and inverse
		;.db	model+(2<<6),6,53,0,0,0	;ch1 connection between trim and inverse
		;.db	model+(2<<6),6,54,0,0,0	;ch2 connection between trim and inverse
		;.db	model+(2<<6),6,55,0,0,0	;ch3 connection between trim and inverse
		;.db	model+(2<<6),6,56,0,0,0	;ch4 connection between trim and inverse
		;.db	model+(2<<6),6,57,0,0,0	;ch7 - neg

		;blocks
		.db	model+(0<<6),10,1,0,1,2,1,0,28,52	;trim for ch0
		.db	model+(0<<6),10,2,0,1,2,1,1,29,53	;trim for ch1
		.db	model+(0<<6),10,3,0,1,2,1,2,30,54	;trim for ch2
		.db	model+(0<<6),10,4,0,1,2,1,3,31,55	;trim for ch3
		.db	model+(0<<6),10,9,0,1,2,1,4,32,56	;trim for ch3
		.db	model+(0<<6),10,5,0,2,2,1,52,40,16	;reverse for ch0
		.db	model+(0<<6),10,6,0,2,2,1,53,41,17	;reverse for ch1
		.db	model+(0<<6),10,7,0,2,2,1,54,42,18	;reverse for ch2
		.db	model+(0<<6),10,8,0,2,2,1,55,43,19	;reverse for ch3
		.db	model+(0<<6),10,10,0,2,2,1,56,44,20	;reverse for ch4
		.db	model+(0<<6),10,11,0,5,1,1,5,21,0	;digital input for ch5
		.db	model+(0<<6),10,12,0,5,1,1,6,22,0	;digital input for ch6
		.db	model+(0<<6),10,13,0,5,1,1,7,57,0	;digital input for ch7
		.db	model+(0<<6),10,14,0,15,1,1,57,23,0	;reverse for ch7

		
		;block processing order
		.db	model+(1<<6),16,1,2,3,4,5,6,7,8,9,10,11,12,13,14
		
		;decriptions
		.db	model+(3<<6),14,0,"Full 8 CH",0,0

