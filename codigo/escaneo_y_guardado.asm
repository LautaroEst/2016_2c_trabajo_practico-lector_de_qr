
	;; DETECCIÓN DE LOS BITS DEL CÓDIGO QR
	
.include "m328Pdef.inc"
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; SE DEFINE UN REGISTRO DE I/O, SCANNER, CON LOS FLAGS NECESARIOS PARA EL ESCANEO
.equ 	SCANNER = GPIOR0
.equ 	COLOR = 1		; Negro=1, Blanco=0
.equ 	CAMBIO_COLOR = 2
.equ 	ESCANEANDO = 3
.equ 	FIN_COLUMNA = 4

;;; SE DEFINE UN REGISTRO, MOTORES, CON LOS FLAGS NECESARIOS PARA VIGILAR EL ESTADO DE LOS MOTORES
.def 	MOTORES = r24
.equ 	MOTOR_A_ENABLE = 0
.equ 	MOTOR_A_STOP_FLAG = 1
.equ 	MOTOR_A_DIR = 2		;DIR=FORWARD=1,	DIR=REVERSE=0
.equ 	MOTOR_B_ENABLE = 3
.equ 	MOTOR_B_STOP_FLAG = 4
.equ 	MOTOR_B_DIR = 5

;;; REGISTROS AUXILIARES PARA CALCULAR LA CANTIDAD DE BITS QUE SE ESTÁN LEYENDO
.def	sizeL = r5
.def	sizeH = r6
.def 	CANT = r7
.def 	auxL = r8
.def	auxH = r9
.def	restoL = r10
.def	restoH = r11
.def	resultadoL = r12
.def	resultadoH = r13
.def	dividendoL = r12
.def	dividendoH = r13
.def	divisorL = r14 
.def	divisorH = r15
.def	dcnt16u	= r16

.def	POS_COLUMNA = r23	

;;; DEFINICIÓN DE LOS PUERTOS
.equ	BLUETOOTH_RX_PORT_DIR = DDRD
.equ	BLUETOOTH_RX_PORT = PORTD
.equ	BLUETOOTH_RX_PIN = 0
.equ	BLUETOOTH_TX_PORT_DIR = DDRD
.equ	BLUETOOTH_TX_PORT = PORTD
.equ	BLUETOOTH_TX_PIN = 1

.equ 	MOTOR_A_OUT1_PORT_DIR = DDRD
.equ 	MOTOR_A_OUT1_PORT = PORTD
.equ 	MOTOR_A_OUT1_PIN = 2
.equ 	MOTOR_A_OUT2_PORT_DIR = DDRD
.equ 	MOTOR_A_OUT2_PORT = PORTD
.equ 	MOTOR_A_OUT2_PIN = 3
.equ	MOTOR_A_ENABLE_PORT_DIR = DDRC
.equ	MOTOR_A_ENABLE_PORT = PORTC
.equ	MOTOR_A_ENABLE_PIN = 5

.equ 	MOTOR_B_OUT1_PORT_DIR = DDRC
.equ 	MOTOR_B_OUT1_PORT = PORTC
.equ 	MOTOR_B_OUT1_PIN = 2
.equ 	MOTOR_B_OUT2_PORT_DIR = DDRC
.equ 	MOTOR_B_OUT2_PORT = PORTC
.equ 	MOTOR_B_OUT2_PIN = 3
.equ	MOTOR_B_ENABLE_PORT_DIR = DDRC
.equ	MOTOR_B_ENABLE_PORT = PORTC
.equ	MOTOR_B_ENABLE_PIN = 4
	
.equ	COUNTER0_PORT_DIR = DDRD
.equ	COUNTER0_PIN = 4

.equ	COUNTER1_PORT_DIR = DDRD
.equ	COUNTER1_PIN = 5
	
.equ 	SENSOR_INPUT_PORT_DIR = DDRC
.equ 	SENSOR_INPUT_PIN = 1

.equ	SENSOR_LED_PORT_DIR = DDRC
.equ	SENSOR_LED_PORT = PORTC
.equ	SENSOR_LED_PIN = 0
	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; COMIENZO DEL PROGRAMA
	
	;; Tabla de interrupciones
.org 0x0000
	rjmp inicio
.org ADCCaddr
	rjmp adc_interrupt
.org OC1Aaddr
	rjmp counter1_interrupt
.org OVF0addr
	rjmp counter0_interrupt
.org INT_VECTORS_SIZE


inicio:
	ldi r16,HIGH(RAMEND)			; Inicialización del SP
	out sph,r16				
	ldi r16,LOW(RAMEND)			
	out spl,r16				
			  			
	rcall configurar_puertos		
	rcall configurar_adc			
	rcall configurar_contadores		
	sei					; Habilitar interrupciones
						 
primera_conversion_adc:					
	sbi SCANNER,ESCANEANDO			
	lds r16,ADCSRA				
	sbr r16,1<<ADSC					
	sts ADCSRA,r16				
esperar_primera_conversion:			
	sbic SCANNER,ESCANEANDO			; Si no terminó la conversión del ADC, ESCANEANDO=1
	rjmp esperar_primera_conversion		
	sbi SCANNER,ESCANEANDO			
	rcall leer_datos_adc			; Con esto, se configura el color que se está leyendo cuando empieza a leer
	cbi SCANNER,CAMBIO_COLOR		
						 
	eor POS_COLUMNA,POS_COLUMNA		
	rcall motor_A_forward			; Comienzan a leerse y a guardarse los datos
main_loop:					
	sbic SCANNER,ESCANEANDO			; Si no terminó la conversión del ADC, ESCANEANDO=1
	rjmp main_loop				
	sbi SCANNER,ESCANEANDO			; Cuando termina, vuelve a empezar la conversión
	rcall leer_datos_adc			; Se leen los datos del adc y se detecta si hubo un cambio de color 
	sbic SCANNER,FIN_COLUMNA		; y si llegó al fin de la columna.
	rjmp leer_nueva_columna			; Si llegó al fin de la columna, vuelve a empezar.
	sbic SCANNER,CAMBIO_COLOR		
	rcall calcular_y_guardar_bits_leidos
	rcall guardar_bits_leidos	
	rjmp main_loop

leer_nueva_columna:
	cbi SCANNER,FIN_COLUMNA
	rcall motor_A_stop
	rcall motor_B_forward
esperar_motor_B:
	sbis SCANNER,MOTOR_B_STOP_FLAG
	rjmp esperar_motor_B
	ldi r16,LOW(0x0000)
	sts TCNT1L,r16
	ldi r16,HIGH(0x0000)
	sts TCNT1H,r16
	rcall motor_A_reverse
esperar_motor_A:
	sbic SCANNER,FIN_COLUMNA
	rjmp esperar_motor_A
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  ACÁ IRÍA LA FUNCIÓN DE DECODIFICACIÓN.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	cbi SCANNER,FIN_COLUMNA
	ldi r16,LOW(0x0000)
	sts TCNT1L,r16
	ldi r16,HIGH(0x0000)
	sts TCNT1H,r16
	rjmp main_loop

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FUNCIONES DE CONFIGURACIÓN DE LOS PUERTOS UTILIZADOS, DEL ADC Y DE LOS CONTADORES
configurar_puertos:
	cbi SENSOR_INPUT_PORT_DIR,SENSOR_INPUT_PIN 	;Input = Sensor de luz 
	sbi SENSOR_LED_PORT_DIR,SENSOR_LED_PIN		;Output = Led del sensor de luz

	sbi SENSOR_LED_PORT,SENSOR_LED_PIN 		;Se configura el estado inicial del led reflectivo en encendido.

	cbi COUNTER0_PORT_DIR,COUNTER0_PIN 		;Input = Encoder del motor A
	cbi COUNTER1_PORT_DIR,COUNTER1_PIN		;Input = Encoder del motor B

	sbi MOTOR_A_OUT1_PORT_DIR,MOTOR_A_OUT1_PIN 	;Output = motor A
	sbi MOTOR_A_OUT2_PORT_DIR,MOTOR_A_OUT2_PIN
	sbi MOTOR_A_ENABLE_PORT_DIR,MOTOR_A_ENABLE_PIN

	sbi MOTOR_B_OUT1_PORT_DIR,MOTOR_B_OUT1_PIN 	;Output = motor B
	sbi MOTOR_B_OUT2_PORT_DIR,MOTOR_B_OUT2_PIN
	sbi MOTOR_B_ENABLE_PORT_DIR,MOTOR_B_ENABLE_PIN

	rcall motor_A_stop				;Se configura el estado inicial de los motores en detenidos.
	sbi MOTOR_A_ENABLE_PORT,MOTOR_A_ENABLE_PIN

	rcall motor_B_stop
	sbi MOTOR_B_ENABLE_PORT,MOTOR_B_ENABLE_PIN

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; FALTA CONFIGURAR LOS PINES DEL BLUETOOTH
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	ret

configurar_adc:
	push r16
	ldi r16,(1<<REFS0)|0x01					;Referencia=VCC. Entrada=ADC1=PC1.
	sts ADMUX,r16						;Ajustado a izquierda
	ldi r16,(1<<ADEN)|(1<<ADIE)|(1<<ADATE)|0x07		;Habilitar ADC. Habilitar interrupcion.
	sts ADCSRA,r16						;Prescaler=ck/128.
	ldi r16,0
	sts ADCSRB,r16
	pop r16
	ret

configurar_contadores:
	rcall config_timer1
	rcall config_timer0
	ret
	
config_timer1:	
	push r16
	ldi r16,0
	sts TCCR1A,r16
	ldi r16,(1<<CS12)|(1<<CS11)|(1<<CS10) 	;Configurado en modo CTC, con clock externo en T1
	sts TCCR1B,r16
	ldi r16,(1<<OCIE1A)|(1<<TOIE1) 		;Habilitar interrupciones
	sts TIMSK1,r16
						;;;;;;;;;;;;;;;;;;;;;;;;;;
	ldi r16,0xff 				;Umbral. FALTA DEFINIR!!!!
	sts OCR1AL,r16				;;;;;;;;;;;;;;;;;;;;;;;;;;
	ldi r16,0xff
	sts OCR1AL,r16
	pop r16
	ret

config_timer0:	
	push r16
	ldi r16,0
	sts TCCR1A,r16
	ldi r16,(1<<CS12)|(1<<CS11)|(1<<CS10) 	;Configurado en modo CTC, con clock externo en T1
	sts TCCR1B,r16
	ldi r16,(1<<TOIE0)	 		;Habilitar interrupciones
	sts TIMSK0,r16
						;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	ldi r16,0x00				;Valor inicial. FALTA DEFINIR!!!!
	sts TCNT0,r16				;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	pop r16
	ret

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; CONFIGURACIÓN DE LAS INTERRUPCIONES

adc_interrupt:
	cbi SCANNER,ESCANEANDO	
	reti

counter1_interrupt:
	sbi SCANNER,FIN_COLUMNA
	reti 

counter0_interrupt:
	rcall motor_B_stop
	reti

	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FUNCIÓNES PARA LEER Y GUARDAR LOS BITS QUE SE VAN LEYENDO
	
calcular_y_guardar_bits_leidos:
	rcall calcular_bits_leidos
	rcall guardar_bits_leidos
	ret

;;; FUNCIÓN QUE CALCULA CUÁNTOS BITS HAY ENTRE UN CAMBIO DE COLOR Y EL OTRO.
calcular_bits_leidos:
	cbi SCANNER,CAMBIO_COLOR
	push dividendoL
	push dividendoH
	push auxL
	push auxH
	push divisorL
	push divisorH
	push dcnt16u
	push restoL
	push restoH
	lds dividendoL,TCNT1L
	lds dividendoH,TCNT1H
	mov auxL,dividendoL
	mov auxH,dividendoH
	mov divisorL,sizeL
	mov divisorH,sizeH
	rcall div16u
	mov CANT,resultadoL	;Es imposible que sean más 255 bits del mismo color, así que sólo
	lsr auxH		;importa la parte baja del resultado.
	ror auxL		
	cp auxL,restoL		;Dividir por dos el dividendo original.
	cpc auxH,restoH		;Si aux es más chico, redondeo para arriba
	brcc terminar_calculo
	inc CANT	
terminar_calculo:	
	pop dividendoL
	pop dividendoH
	pop auxL
	pop auxH
	pop divisorL
	pop divisorH
	pop dcnt16u
	pop restoL
	pop restoH
	ret

;;; FUNCIÓN AUXILIAR PARA DIVIDIR DOS NÚMEROS DE 16 BITS
div16u:	
	clr	restoL			;clear remainder Low byte
	sub	restoH,restoH		;clear remainder High byte and carry
	ldi	dcnt16u,17		;init loop counter
d16u_1:	
	rol	dividendoL		;shift left dividend
	rol	dividendoH
	dec	dcnt16u			;decrement counter
	brne d16u_2			;if done
	ret				;	return
d16u_2:	
	rol	restoL			;shift dividend into remainder
	rol	restoH
	sub	restoL,divisorL		;remainder = remainder - divisor
	sbc	restoH,divisorH		;
	brcc d16u_3			;if result negative
	add	restoL,divisorL		;    restore remainder
	adc	restoH,divisorH
	clc				;    clear carry to be shifted into result
	rjmp	d16u_1			;else
d16u_3:	
	sec				;    set carry to be shifted into result
	rjmp	d16u_1


;;; FUNCIÓN PARA GUARDAR LOS BITS QUE SE VAN LEYENDO EN LOS REGISTROS r20, r21 y r22. EL REGISTRO POS_COLUMNA SIRVE
;;; PARA GUARDAR LA POSICIÓN DE LA COLUMNA EN QUE SE ENCUENTRA.
guardar_bits_leidos:
	set
	sbis SCANNER,COLOR
	clt 			; Se guarda el color leído en flag T.
	
	cpi POS_COLUMNA,0x10
	brsh guardar_en_r22
	cpi POS_COLUMNA,0x08
	brsh guardar_en_r21
guardar_en_r20:
	lsr r20
	bld r20,7
	inc POS_COLUMNA
	dec CANT
	breq terminar_guardado
	cpi POS_COLUMNA,0x08
	breq guardar_en_r21
guardar_en_r22:
	lsr r22
	bld r22,7
	inc POS_COLUMNA
	dec CANT
	breq terminar_guardado
	
guardar_en_r21:
	lsr r21
	bld r21,7
	inc POS_COLUMNA
	dec CANT
	breq terminar_guardado
	cpi POS_COLUMNA,0x10
	breq guardar_en_r22

terminar_guardado:
	ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FUNCIONES PARA CONTROLAR LOS MOTORES DEL SCANNER

motor_A_forward:
	sbi MOTOR_A_OUT1_PORT,MOTOR_A_OUT1_PIN
	cbi MOTOR_A_OUT2_PORT,MOTOR_A_OUT2_PIN
	sbr MOTORES,1<<MOTOR_A_DIR
	cbr MOTORES,1<<MOTOR_A_STOP_FLAG
	ret

motor_A_reverse:
	cbi MOTOR_A_OUT1_PORT,MOTOR_A_OUT1_PIN
	sbi MOTOR_A_OUT2_PORT,MOTOR_A_OUT2_PIN
	cbr MOTORES,1<<MOTOR_A_DIR
	cbr MOTORES,1<<MOTOR_A_STOP_FLAG
	ret

motor_A_stop:
	cbi MOTOR_B_OUT1_PORT,MOTOR_B_OUT1_PIN
	cbi MOTOR_B_OUT2_PORT,MOTOR_B_OUT2_PIN
	sbr MOTORES,1<<MOTOR_B_STOP_FLAG			
	ret

motor_B_forward:
	sbi MOTOR_B_OUT1_PORT,MOTOR_B_OUT1_PIN
	cbi MOTOR_B_OUT2_PORT,MOTOR_B_OUT2_PIN
	sbr MOTORES,1<<MOTOR_B_DIR
	cbr MOTORES,1<<MOTOR_B_STOP_FLAG
	ret

motor_B_reverse:
	cbi MOTOR_B_OUT1_PORT,MOTOR_B_OUT1_PIN
	sbi MOTOR_B_OUT2_PORT,MOTOR_B_OUT2_PIN
	cbr MOTORES,1<<MOTOR_B_DIR
	cbr MOTORES,1<<MOTOR_B_STOP_FLAG
	ret

motor_B_stop:
	cbi MOTOR_B_OUT1_PORT,MOTOR_B_OUT1_PIN
	cbi MOTOR_B_OUT2_PORT,MOTOR_B_OUT2_PIN
	sbr MOTORES,1<<MOTOR_B_STOP_FLAG			
	ret

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FUNCIÓN QUE UTILIZA EL ADC PARA LEER LOS DATOS
	
leer_datos_adc:	
	push r16
	push r17
	lds r16,ADCL
	lds r17,ADCH
comparar_con_umbral:
	cpi r17,0x01
	breq chequear_blanco		;Si pasa esto, veo si es blanco
	cpi r17,0x02
	brsh chequear_negro		;Si pasa esto, veo si es negro
	rjmp terminar_conversion	;Si llegó hasta acá, estoy leyendo ruido
	
chequear_blanco:
	cpi r16,0x85		;Cota inferior de blanco
	brsh es_blanco
	rjmp terminar_conversion
	
es_blanco:
	sbic SCANNER,COLOR
	sbi SCANNER,CAMBIO_COLOR
	cbi SCANNER,COLOR
	rjmp terminar_conversion

chequear_negro:
	cpi r17,0x02
	breq chequear_negro_2
	cpi r16,0x33		;Cota superior de negro
	brlo es_negro
	rjmp terminar_conversion
	
chequear_negro_2:
	cpi r16,0xA3		;Cota inferior de negro
	brsh es_negro
	rjmp terminar_conversion
	
es_negro:
	sbis SCANNER,COLOR
	sbi SCANNER,CAMBIO_COLOR
	sbi SCANNER,COLOR
	rjmp terminar_conversion
	
terminar_conversion:	
	pop r16
	pop r17
	ret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
