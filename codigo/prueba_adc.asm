
	;; DETECCIÓN DE LOS BITS DEL CÓDIGO QR. EL PROGRAMA DEBERÍA CAMBIAR 
	;; EL ESTADO DEL LED CADA VEZ QUE DETECTA UN COLOR DISTINTO.
	
.include "m328Pdef.inc"
	
.equ SCANNER = GPIOR0
.equ COLOR = 1		; Negro=1, Blanco=0
.equ CAMBIO_COLOR = 2


.equ LED1_PORT_DIR = DDRC
.equ LED1_PORT = PORTC
.equ LED1_PIN = 3

.equ LED2_PORT_DIR = DDRC
.equ LED2_PORT = PORTC
.equ LED2_PIN = 4

	
	;; Tabla de interrupciones
.org 0x0000
	rjmp inicio
.org 0x0015
	rjmp adc_interrupt
.org INT_VECTORS_SIZE

inicio:
	;; Inicializo el SP
	ldi r16,HIGH(RAMEND)
	out sph,r16
	ldi r16,LOW(RAMEND)
	out spl,r16
	;; Configuración de puertos
	sbi LED1_PORT_DIR,LED1_PIN	;Output=led de prueba
	cbi DDRC,1			;Input_ADC=C1
	sbi LED2_PORT_DIR,LED2_PIN	;Encendido del led de reflexión del sensor
	sbi LED2_PORT,LED2_PIN
	;; Configuración ADC
	sei
	ldi r16,(1<<REFS0)||0x01						;Referencia=VCC. Entrada=ADC1=PC1.
	sts ADMUX,r16								;Ajustado a izquierda
	ldi r16,(1<<ADEN)||(1<<ADIE)||0x07					;Habilitar ADC. Habilitar interrupcion.
	sts ADCSRA,r16								;Prescaler=ck/128.
	;; Pines para hacer el toggle del led
	ldi r17,1<<LED_PIN
	eor r18,r18


	

iniciar_adc:
	lds r16,ADCSRA
	sbr r16,ADSC
	sts ADCSRA,r16
while_1:
	sbic SCANNER,CAMBIO_COLOR
	rcall toggle_led
	rjmp while_1


toggle_led:
	eor r18,r17
	out LED_PORT,r18
	ret
	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Rutina de interrupción del ADC. El pin configurado como adc lee
;; la luz que llega del sensor y en base al nivel de tensión leído,
;; determina si está leyendo el color blanco, el negro, o si llegó
;; al final de la página. Se reservó un registro I/O de uso
;; general, SCANNER, y se definieron los flags CAMBIO_COLOR, COLOR.
	
adc_interrupt:
	push r16
	push r17
	lds r16,ADCL
	lds r17,ADCH
comparar_con_umbral:
	cpi r17,0x02
	breq chequear_blanco		;Si pasa esto, veo si es blanco
	cpi r17,0x03
	breq chequear_negro		;Si pasa esto, veo si es negro
	rjmp terminar_conversion	;Si llegó hasta acá, estoy leyendo ruido
	
chequear_blanco:
	cpi r16,0x7d		;Umbral posible para el blanco
	brlo es_blanco
	rjmp terminar_conversion
	
es_blanco:
	sbic SCANNER,COLOR
	sbi SCANNER,CAMBIO_COLOR
	cbi SCANNER,COLOR
	rjmp terminar_conversion

chequear_negro:
	cpi r16,0x32		;Umbral posible para el negro
	brsh es_negro
	rjmp terminar_conversion
	
es_negro:
	sbis SCANNER,COLOR
	sbi SCANNER,CAMBIO_COLOR
	sbi SCANNER,COLOR
	rjmp terminar_conversion
	
terminar_conversion:	
	lds r16,ADCSRA
	sbr r16,ADSC
	sts ADCSRA,r16		;Empezar una nueva conversión
	pop r16
	pop r17
	reti
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

