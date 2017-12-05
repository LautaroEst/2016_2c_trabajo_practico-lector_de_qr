
	;; RUTINA DE PRUEBA DEL FUNCIONAMIENTO DEL ENCODER Y DE LOS CONTADORES.
	;; Si la rutina funciona bien, los motores deberían poder recorrer la matriz en orden
	
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
.def	PRESCALER_1 = r3
.def	PRESCALER_2 = r4
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

.equ 	MOTOR_A_OUT1_PORT_DIR = DDRD 		;Motor CARRITO
.equ 	MOTOR_A_OUT1_PORT = PORTD
.equ 	MOTOR_A_OUT1_PIN = 6
.equ 	MOTOR_A_OUT2_PORT_DIR = DDRD
.equ 	MOTOR_A_OUT2_PORT = PORTD
.equ 	MOTOR_A_OUT2_PIN = 7
.equ	MOTOR_A_ENABLE_PORT_DIR = DDRB
.equ	MOTOR_A_ENABLE_PORT = PORTB
.equ	MOTOR_A_ENABLE_PIN = 0

.equ 	MOTOR_B_OUT1_PORT_DIR = DDRD 		;Motor RODILLO	
.equ 	MOTOR_B_OUT1_PORT = PORTD
.equ 	MOTOR_B_OUT1_PIN = 2
.equ 	MOTOR_B_OUT2_PORT_DIR = DDRD
.equ 	MOTOR_B_OUT2_PORT = PORTD
.equ 	MOTOR_B_OUT2_PIN = 3
.equ	MOTOR_B_ENABLE_PORT_DIR = DDRB
.equ	MOTOR_B_ENABLE_PORT = PORTB
.equ	MOTOR_B_ENABLE_PIN = 1
	
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
	rcall configurar_contadores
	sei					; Habilitar interrupciones

	rcall motor_B_forward



aca:
	sbic SCANNER,FIN_COLUMNA
	rjmp leer_otra_columna
	rjmp aca

leer_otra_columna:
	cbi SCANNER,FIN_COLUMNA
	rcall motor_B_stop
wait:	rjmp wait
	
	
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
	sbi MOTOR_A_ENABLE_PORT_DIR,MOTOR_A_ENABLE_PIN

	rcall motor_B_stop
	sbi MOTOR_B_ENABLE_PORT_DIR,MOTOR_B_ENABLE_PIN

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; FALTA CONFIGURAR LOS PINES DEL BLUETOOTH
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	ret

configurar_contadores:
	rcall config_timer1
	rcall config_timer0
	ret
	
config_timer1:
	push r16
	ldi r16,0
	sts TCCR1A,r16
	ldi r16,(1<<WGM12)|(1<<CS12)|(1<<CS11)|(1<<CS10) 	;Configurado en modo CTC, con clock externo en T1
	sts TCCR1B,r16
	ldi r16,(1<<OCIE1A)	 		;Habilitar interrupciones
	sts TIMSK1,r16
	ldi r16,(1<<OCF1A)
	sts TIFR1,r16
						;;;;;;;;;;;;;;;;;;;;;;;;;;
	ldi r16,LOW(200) 			;Umbral.
	sts OCR1AL,r16				;;;;;;;;;;;;;;;;;;;;;;;;;;
	ldi r16,HIGH(200)
	sts OCR1AH,r16
	pop r16
	ret


config_timer0:
	push r16
	ldi r16,0
	sts TCCR0A,r16
	ldi r16,(1<<CS02)|(1<<CS01)|(1<<CS00) 	;Configurado en modo Normal, con clock externo en T0
	sts TCCR0B,r16
	ldi r16,(1<<TOIE0)	 		;Habilitar interrupciones
	sts TIMSK0,r16
						;;;;;;;;;;;;;;;;;;;;;;;;;;
	ldi r16,0x00				;Valor inicial del co
	sts TCNT0,r16				;;;;;;;;;;;;;;;;;;;;;;;;;;
	pop r16
	ret

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; CONFIGURACIÓN DE LAS INTERRUPCIONES

counter1_interrupt:
	sbi SCANNER,FIN_COLUMNA
	reti 

counter0_interrupt:
	sbi SCANNER,FIN_COLUMNA
	reti

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FUNCIONES PARA CONTROLAR LOS MOTORES DEL SCANNER

motor_A_forward:
	sbi MOTOR_A_OUT1_PORT,MOTOR_A_OUT1_PIN
	cbi MOTOR_A_OUT2_PORT,MOTOR_A_OUT2_PIN
	sbr MOTORES,1<<MOTOR_A_DIR
	cbr MOTORES,1<<MOTOR_A_STOP_FLAG
	ret

motor_A_stop:
	cbi MOTOR_A_OUT1_PORT,MOTOR_A_OUT1_PIN
	cbi MOTOR_A_OUT2_PORT,MOTOR_A_OUT2_PIN
	sbr MOTORES,1<<MOTOR_A_STOP_FLAG			
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

