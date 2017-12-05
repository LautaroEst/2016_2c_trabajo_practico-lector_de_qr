
;****************************************************************;
; PROYECTO FINAL: ESCANEO, DECODIFICACIÓN Y ENVÍO DE UN CÓDIGO QR
;****************************************************************;



	
;*********************************************************************************************;
;BLOQUE DE DEFINICIONES

	.include "m328Pdef.inc"
	.include "macros.inc"

;;; SE DEFINE UN REGISTRO DE I/O, "SCANNER", CON LOS FLAGS NECESARIOS PARA EL ESCANEO
.equ 	SCANNER = GPIOR0
.equ 	COLOR = 0		; Negro=1, Blanco=0
.equ 	ESCANEANDO = 1		; Flag para la conversión del ADC
.equ	CAMBIO_COLOR = 2	; Flag para el cálculo de los bits leídos
.equ	FIN_COLUMNA = 3
.equ	AVANZO_CASILLA = 4
.equ	FLAG_BLUETOOTH = 5 	;Flags para la recepción por bluetooth
.equ	FLAG_BLUETOOTH_VACIO = 6
	
;;; SE DEFINE UN REGISTRO, "MOTORES", CON LOS FLAGS NECESARIOS PARA VIGILAR EL ESTADO DE LOS MOTORES
.def 	MOTORES = r31
.equ 	MOTOR_H_ENABLE = 0
.equ 	MOTOR_H_STOP_FLAG = 1
.equ 	MOTOR_H_DIR = 2		;DIR=FORWARD=1,	DIR=REVERSE=0
.equ 	MOTOR_V_ENABLE = 3
.equ 	MOTOR_V_STOP_FLAG = 4
.equ 	MOTOR_V_DIR = 5

;;; REGISTROS Y CONSTANTES PERSONALIZADOS
.equ 	LIMITE_FLANCOS = 255	;Número de flancos que corresponden al tiempo que
				;tarda el motor Horizontal en recorrer el ancho de la página
.equ 	TAMANIO_CASILLA = 13	;Número de flancos que corresponden al largo de una casilla
.equ	CORTE_POR_REDONDEO = TAMANIO_CASILLA - 9 
.equ	CANTIDAD_FILAS = 21
.equ	CANTIDAD_COLUMNAS = 21
.equ	ULTIMO_BIT_DE_FILA = CANTIDAD_COLUMNAS - 1
.equ	ULTIMO_BIT_DE_COLUMNA = CANTIDAD_FILAS - 1
.equ	BAUD_RATE = 0x67 	;Este es el valor que debe ponerse para tener un baud rate de 9600, que es el que usa el hc 05.
.equ	CARACTER_FIN = '/' 	;Caracter con el que terminará el código QR
.equ	INICIO_TABLA = 0x0100 
	
.def	CERO = r0 ;Registros utilizados para una prueba de envío
.def	UNO = r1
.def	CANT = r3 ;Cantidad de bits leídos del mismo color
.def 	SIZE = r4 ;Registro que guarda el tamaño de un bit
.def 	SIZE_2 = r5

.def	rtemp1 = r16 ;Registros auxiliares
.def	rtemp2 = r17
.def 	BIT_ACTUAL = r18 ;Posición actual del motor en una columna.
.def	POS_INICIAL = r8 ;Estos dos registros sirven para calcular la cantidad de bits que se leyeron del mismo color
.def	POS_FINAL = r9

;;; REGISTROS PARA LA DECODIFICACIÓN
.def 	CONT_H = r19 ;Cuenta la cantidad de columnas leídas
.def	CANT_LETRAS_LEIDAS = r6 ;Cuenta la cantidad de letras decodificadas
.def	LENGTH = r7
.def 	ACUM1 = r23 ;La idea de estos acumuladores es ir sosteniendo los valores ya procesados, que luego se guardan en SRAM
.def 	ACUM2 = r24 
.def 	ACUM3 = r25
.def 	ACUM4 = r28
.def 	ACUM5 = r29
.def 	ACUM6 = r30	

.equ 	B7 = 0x80
.equ 	B6 = 0x40
.equ 	B5 = 0x20
.equ 	B4 = 0x10
.equ 	B3 = 0x08
.equ 	B2 = 0x04
.equ 	B1 = 0x02
.equ 	B0 = 0x01
	
;;; DEFINICIÓN DE LOS PUERTOS
.equ 	MOTOR_H_OUT1_PORT_DIR = DDRD 		;Motores HORIZONTAL y VERTICAL.
.equ 	MOTOR_H_OUT1_PORT = PORTD		;Cada motor tiene dos pines (OUT1 y OUT2) que controlan la
.equ 	MOTOR_H_OUT1_PIN = 6			;su movimiento: 
.equ 	MOTOR_H_OUT2_PORT_DIR = DDRD		;	forward --> OUT1=0, OUTT2=1
.equ 	MOTOR_H_OUT2_PORT = PORTD		;	reverse --> OUT1=1, OUT2=0
.equ 	MOTOR_H_OUT2_PIN = 7			;	stop 	--> OUT1=0, OUT2=0	 
.equ	MOTOR_H_ENABLE_PORT_DIR = DDRB		;Además, cada motor tiene un ENABLE que habilita su funcionamiento.
.equ	MOTOR_H_ENABLE_PORT = PORTB
.equ	MOTOR_H_ENABLE_PIN = 0
.equ 	MOTOR_V_OUT1_PORT_DIR = DDRD 		
.equ 	MOTOR_V_OUT1_PORT = PORTD
.equ 	MOTOR_V_OUT1_PIN = 2
.equ 	MOTOR_V_OUT2_PORT_DIR = DDRD
.equ 	MOTOR_V_OUT2_PORT = PORTD
.equ 	MOTOR_V_OUT2_PIN = 3
.equ	MOTOR_V_ENABLE_PORT_DIR = DDRB
.equ	MOTOR_V_ENABLE_PORT = PORTB
.equ	MOTOR_V_ENABLE_PIN = 1
	
.equ	COUNTER0_PORT_DIR = DDRD 		;Configuración de los puertos utilizados como contadores externos,
.equ	COUNTER0_PIN = 4			;conectados a los encoders del motors
.equ	COUNTER1_PORT_DIR = DDRD
.equ	COUNTER1_PIN = 5
	
.equ 	SENSOR_INPUT_PORT_DIR = DDRC 		;Entrada analógica del sensor de luz.
.equ 	SENSOR_INPUT_PIN = 1

.equ	SENSOR_LED_PORT_DIR = DDRC 		;Led que viene con el sensor. No fue necesario su utilización,
.equ	SENSOR_LED_PORT = PORTC			;pero se confugura para mantenerlo apagado.
.equ	SENSOR_LED_PIN = 0

.equ    LED_PRUEBA_PORT_DIR =  DDRB 		;Led de prueba, de la placa de Arduino UNO.
.equ    LED_PRUEBA_PORT     =  PORTB
.equ    LED_PRUEBA_PIN      =  5


	
;*********************************************************************************************;
;COMIENZO DEL PROGRAMA

;; Tabla de interrupciones
.org 0x0000
	rjmp inicio
.org OC1Aaddr
	rjmp counter1_int_handler ;Interrupción del timer1
.org OC0Aaddr
	rjmp counter0_int_handler ;Interrupción del timer0
.org ADCCaddr
	rjmp adc_int_handler	;Interrupción del fin de conversión del ADC
.org URXCaddr
	rjmp urx_int_handler ;Interrupción producida por la recepción de datos
.org UDREaddr
	rjmp udre_int_handler	;Interrupción producida por el vaciado de los datos a enviar
.org INT_VECTORS_SIZE
	

inicio:
;; Configuraciones varias (ver sección "FUNCIONES DE CONFIGURACIÓN")
	ldi rtemp1,HIGH(RAMEND)			
	out sph,rtemp1				
	ldi rtemp1,LOW(RAMEND)			
	out spl,rtemp1
	rcall configurar_puertos
	rcall configurar_adc
	rcall configurar_contadores
;; Inicialización de los registros que se van a utilizar
inicializacion_registros:
	ldi XL, LOW(INICIO_TABLA) 	;Puntero a la tabla donde se guarda el código	
	ldi XH, HIGH(INICIO_TABLA)
	ldi rtemp1,'0'			;Ascii para cero y uno (Esto se utilizó para una prueba de lectura y envío)
	mov CERO,rtemp1
	ldi rtemp1,'1'
	mov UNO,rtemp1
	ldi rtemp1,TAMANIO_CASILLA 	;Esto se usa después para calcular los bits escaneados. Ver "calcular_bits_leidos".
	mov SIZE,rtemp1
	ldi rtemp1,CORTE_POR_REDONDEO
	mov SIZE_2,rtemp1
	eor r20,r20			;Registros varios que se usan en el escaneo. r20, r21 y r22 se usan 
	eor r21,r21			;para guardar los bits de cada columna.
	eor r22,r22
	eor CONT_H,CONT_H
	eor BIT_ACTUAL,BIT_ACTUAL
	eor CANT,CANT
	cbi SCANNER,FLAG_BLUETOOTH 	;Flags varios 
	cbi SCANNER,AVANZO_CASILLA
	cbi SCANNER,FIN_COLUMNA
	eor ACUM1, ACUM1		;Registros para la decodificación
	eor ACUM2, ACUM2
	eor ACUM3, ACUM3
	eor ACUM4, ACUM4
	eor ACUM5, ACUM5
	eor ACUM6, ACUM6
	ldi rtemp1,0x00
	mov CANT_LETRAS_LEIDAS, rtemp1
	ldi rtemp1,0x1A
	mov LENGTH, rtemp1 ;Inicializo el valor de length con la mayor cantidad de datos que puedo llegar a leer.


;; Hasta acá se realizaron las configuraciones necesarias para empezar el programa.
;; Ahora se realiza la primera lectura del ADC.
primera_conversion_adc:
	sei ;Se habilitan las interrupciones.
	sbi SCANNER,ESCANEANDO			
	lds rtemp1,ADCSRA				
	sbr rtemp1,1<<ADSC ;Se indica que el ADC está escaneando, y se habilita para que empiece
	sts ADCSRA,rtemp1				
esperar_primera_conversion:			
	sbic SCANNER,ESCANEANDO	;Si no terminó la conversión del ADC, ESCANEANDO=1
	rjmp esperar_primera_conversion		
	sbi SCANNER,ESCANEANDO
	rcall leer_datos_adc ;Con esto, se configura el color que se está leyendo cuando empieza a leer
	cbi SCANNER,CAMBIO_COLOR

;; Se espera a recibir datos del bluetooth por interrupción. Pueden pasar tres cosas:
;; 1: se pide enviar datos al celular,
;; 2: se pide mover el motor VERTICAL, o
;; 3: se pide mover el motor HORIZONTAL para leer una nueva columna. 
esperar_recibir_datos:
	sbic  SCANNER,FLAG_BLUETOOTH ;Si FLAG_BLUETOOTH=1, se recibieron datos.
	rjmp RECIBIR_DATOS
	rjmp esperar_recibir_datos
RECIBIR_DATOS:
	cbi SCANNER,FLAG_BLUETOOTH
	LOAD rtemp2, UDR0 ;Levanto en R17 el valor recibido por puerto serie.
	CPI rtemp2, 'r' ;La app envía el caracter 'r' si solicita recibir datos. En caso de ser así, va a ENVIAR_DATOS
	BREQ ENVIAR_DATOS
	CPI rtemp2, '1' ;La app envía el caracter '1' si desea encender el motor HORIZONTAL.
	breq leer_columna
	cpi rtemp2,'+' ;La app envía el caracter '+' o '-' si desea avanzar o retroceder el motor VERTICAL.
	breq avanzar_motor_V
	cpi rtemp2,'-'
	breq retroceder_motor_V
	rjmp esperar_recibir_datos
	

;; Opción 1: se pide enviar datos al celular
VOLVER_A_ENVIAR: ;Función para enviar datos al celular
	sbis SCANNER,FLAG_BLUETOOTH_VACIO ;Espera a que el valor se haya enviado.
	rjmp VOLVER_A_ENVIAR
	LDI rtemp1, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;Deshabilito la interrupción de UDRE0.
	STORE UCSR0B, rtemp1
	cbi SCANNER,FLAG_BLUETOOTH_VACIO
ENVIAR_DATOS: ;Se lee la tabla de SRAM hasta el CARACTER_FIN (donde termina el mensaje), y se envían por puerto serie.
	ld rtemp2,X+
	cpi rtemp2,CARACTER_FIN ;Si llegó al final del mensaje, termina el envío.
	breq SALIR 
	STORE UDR0, rtemp2 ;Carga en UDR0 el valor a enviar
	LDI rtemp1, (1<<RXEN0)|(1<<TXEN0)|(1<<UDRIE0)|(1<<RXCIE0) ;Habilita la interrupción de UDRE0 vacío
	STORE UCSR0B, rtemp1 ;Carga el valor de la configuración
	RJMP VOLVER_A_ENVIAR

SALIR:	;Función para deshabilitar el envío de datos. 
	LDI rtemp2, ' '
	STORE UDR0, rtemp2 ;Cargo este caracter para darle un cierre al mensaje.
	LDI rtemp1, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;Deshabilito la interrupción de UDRE0 para que no enloquezca.
	STORE UCSR0B, rtemp1
	ldi XL,LOW(INICIO_TABLA)
	ldi XH,HIGH(INICIO_TABLA)
	cbi SCANNER,FLAG_BLUETOOTH
	rjmp esperar_recibir_datos


;;Opción 2: Se pide mover el motor VERTICAL en alguna dirección, para calibrar la hoja.
avanzar_motor_V:
	cbi SCANNER,AVANZO_CASILLA
	rcall motor_V_forward
esperar_motorV:	
	sbis SCANNER,AVANZO_CASILLA
	rjmp esperar_motorV
	rcall motor_V_stop
	cbi SCANNER,AVANZO_CASILLA
	cbi SCANNER,FLAG_BLUETOOTH
	rjmp esperar_recibir_datos

retroceder_motor_V:
	rcall motor_V_reverse
	rcall delay
	rcall motor_V_stop
	cbi SCANNER,FLAG_BLUETOOTH
	rjmp esperar_recibir_datos


;; Opción 3: se pide leer una nueva columna. Aquí comienza el proceso de escaneo y decodificación.
leer_columna:
	eor BIT_ACTUAL,BIT_ACTUAL
	eor r20,r20		;La columna leída se guarda en los registros r20,r21 y r22 en el orden leído.
	eor r21,r21		;(El r22 se llena hasta el bit 4 inclusive con los datos de la columna)
	eor r22,r22
	rcall guardar_primer_bit ; Se guarda el primer bit de la columna, mientras el carro está quieto
	ldi rtemp1,0x00
	sts TCNT1H,rtemp1
	sts TCNT1L,rtemp1
	rcall motor_H_forward	;Una vez guardado el primer bit, se pide avanzar el motor HORIZONTAL
avanzar_con_motor_H:
	sbic SCANNER,FIN_COLUMNA ;Mientras el motor avanza, se chequea si llegó al final de la columna
	rjmp leer_ultimos_bit	 ;y se decodifican los valores de tensión que lee el ADC para ver el color.
	rcall leer_datos_adc
	sbis SCANNER,CAMBIO_COLOR 	;La función leer_datos_adc también verifica si hubo un cambio de color entre 
	rjmp avanzar_con_motor_H  	;dos conversiones sucesivas.
	lds POS_FINAL,TCNT1L	  	;La cantidad de bits leídos del mismo color se calcula como 
	cbi SCANNER,CAMBIO_COLOR  	; CANT = (POS_FINAL - POS_INICIAL)/size, es decir, como la diferencia
	rcall calcular_bits_leidos 	;de flancos leídos entre cada cambio de color dividido la cantidad de flancos que
	mov POS_INICIAL,POS_FINAL  	;corresponde a un solo bit.
	rcall guardar_bits_en_registros ;Cuando se termina el cálculo, se guarda la información en r20,r21 o r22 según corresponda.
	rjmp avanzar_con_motor_H
leer_ultimos_bit:
	rcall motor_H_stop		;Si el motor llegó al final se guardan los últimos bits de la columna.
	ldi rtemp1,LIMITE_FLANCOS
	mov POS_FINAL,rtemp1
	rcall calcular_bits_leidos
	mov POS_INICIAL,POS_FINAL
	ldi rtemp1,(1<<COLOR)	;toggle del color para seguir guardando con la misma lógica
	in rtemp2,SCANNER
	eor rtemp2,rtemp1
	out SCANNER,rtemp2	
	rcall guardar_bits_en_registros
	lsl r22			;Esto es para que r22 quede ordenado
	lsl r22
	lsl r22
volver_a_inicio:
	cbi SCANNER,FIN_COLUMNA	;Con esto, vuelvo el motor HORIZONTAL al inicio de la hoja
	ldi rtemp1,0x00
	sts TCNT1H,rtemp1
	sts TCNT1L,rtemp1
	rcall motor_H_reverse
seguir_retrocediendo:
	sbis SCANNER,FIN_COLUMNA
	rjmp seguir_retrocediendo
	rcall motor_H_stop
	cbi SCANNER,FIN_COLUMNA
	rcall decodificar_linea
	cbi SCANNER,FLAG_BLUETOOTH
	rjmp esperar_recibir_datos ;Vuelvo a esperar recibir datos por bluetooth

	
;*********************************************************************************************;
;FUNCIONES DE CONFIGURACIÓN 

;; Función para configurar los puertos utilizados. 
configurar_puertos:
	push rtemp1
	;; LED DE PRUEBA
	ldi  rtemp1,0xff
	out  LED_PRUEBA_PORT_DIR,rtemp1
	out  LED_PRUEBA_PORT,rtemp1
	cbi  LED_PRUEBA_PORT,LED_PRUEBA_PIN
	;; INPUT SENSOR
	cbi SENSOR_INPUT_PORT_DIR,SENSOR_INPUT_PIN 	;Input = Sensor de luz 
	sbi SENSOR_LED_PORT_DIR,SENSOR_LED_PIN		;Output = Led del sensor de luz
	cbi SENSOR_LED_PORT,SENSOR_LED_PIN 		;Se configura el estado inicial del led reflectivo en apagado.
	;; CONTADORES
	cbi COUNTER0_PORT_DIR,COUNTER0_PIN 		;Input = Encoder del motor A
	cbi COUNTER1_PORT_DIR,COUNTER1_PIN		;Input = Encoder del motor B
	;; MOTOR HORIZONTAL (MUEVE EL CARRITO)
	sbi MOTOR_H_OUT1_PORT_DIR,MOTOR_H_OUT1_PIN 	;Output = motor horizontal
	sbi MOTOR_H_OUT2_PORT_DIR,MOTOR_H_OUT2_PIN
	sbi MOTOR_H_ENABLE_PORT_DIR,MOTOR_H_ENABLE_PIN
	rcall motor_H_stop				
	sbi MOTOR_H_ENABLE_PORT_DIR,MOTOR_H_ENABLE_PIN
	;; MOTOR VERTICAL (MUEVE EL RODILLO)
	sbi MOTOR_V_OUT1_PORT_DIR,MOTOR_V_OUT1_PIN 	;Output = motor vertical
	sbi MOTOR_V_OUT2_PORT_DIR,MOTOR_V_OUT2_PIN
	sbi MOTOR_V_ENABLE_PORT_DIR,MOTOR_V_ENABLE_PIN
	rcall motor_V_stop
	sbi MOTOR_V_ENABLE_PORT_DIR,MOTOR_V_ENABLE_PIN
	;; BLUETOOTH Y PUERTO SERIE.
	;; Setear el bit rxcie0 habilita la interrupción del flag rxc del ucsr0a.
	;; Al completar la recepcìón, rxc se setea a high.
	;; Si rxcie0 = 1, cambiar rxc a uno fuerza la interrupción.
	;; Setear el bit udrie0 (usart data register empty interrupt enable).
	;; Cuando el udr0 esta listo para recibir nuevos datos, el UDRE (usart data register empty flag) se pone en 1.
	;; Si UDRIE0 = 1 y si se pone UDRE en 1, fuerza la interrupción.
	ldi rtemp1, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;habilito como transmisor, receptor y habilito interrupciones de recepcion
	store UCSR0B, rtemp1
	LDI rtemp1, (1<<UCSZ01)|(1<<UCSZ00)|(1<<UMSEL01) ;8 bit data, sin paridad y 1 bit de parada.
	STORE UCSR0C, rtemp1
	LDI rtemp1, BAUD_RATE ;9600 baud rate
	STORE UBRR0L, rtemp1
	pop rtemp1
	ret

;; Función para configurar el ADC
configurar_adc:
	push rtemp1
	ldi rtemp1,(1<<REFS0)|0x01					;Referencia=VCC. Entrada=ADC1=PC1.
	sts ADMUX,rtemp1						;Ajustado a izquierda
	ldi rtemp1,(1<<ADEN)|(1<<ADIE)|(1<<ADATE)|0x04		;Habilitar ADC. Habilitar interrupcion.
	sts ADCSRA,rtemp1						;Prescaler=ck/16.
	ldi rtemp1,0
	sts ADCSRB,rtemp1
	pop rtemp1
	ret

;; Función de configuración de los timers/contadores.
configurar_contadores:
	rcall config_timer1
	rcall config_timer0
	ret
config_timer1:
	push rtemp1
	ldi rtemp1,HIGH(LIMITE_FLANCOS)
	sts OCR1AH,rtemp1
	ldi rtemp1,LOW(LIMITE_FLANCOS) 				
	sts OCR1AL,rtemp1				
	ldi rtemp1,0
	sts TCCR1A,rtemp1
	ldi rtemp1,(1<<WGM12)|(1<<CS12)|(1<<CS11)|(1<<CS10) 	;Configurado en modo CTC, con clock externo en T1
	sts TCCR1B,rtemp1
	ldi rtemp1,(1<<OCIE1A)	 				;Habilitar interrupciones
	sts TIMSK1,rtemp1
	ldi rtemp1,(1<<OCF1A)
	out TIFR1,rtemp1
	pop rtemp1
	ret
config_timer0:
	push rtemp1
	ldi rtemp1,2				
	out OCR0A,rtemp1
	ldi rtemp1,(1<<WGM01)
	out TCCR0A,rtemp1
	ldi rtemp1,(1<<CS02)|(1<<CS01)|(1<<CS00) 	;Configurado en modo CTC, con clock externo en T0
	out TCCR0B,rtemp1
	ldi rtemp1,(1<<OCIE0A)	 		;Habilitar interrupciones
	sts TIMSK0,rtemp1
	ldi rtemp1,(1<<OCF0A)
	out TIFR0,rtemp1
	pop rtemp1
	ret
	
;; Manejo de las interrupciones
adc_int_handler:
	cbi SCANNER,ESCANEANDO	
	reti
counter1_int_handler:
	sbi SCANNER,FIN_COLUMNA
	reti 
counter0_int_handler:
	sbi SCANNER,AVANZO_CASILLA
	reti
udre_int_handler:
	sbi SCANNER,FLAG_BLUETOOTH_VACIO
	reti
urx_int_handler:
	sbi SCANNER,FLAG_BLUETOOTH
	reti

;*********************************************************************************************;
;FUNCIONES AUXILIARES

;; Rutina de delay usando el Timer2
delay:
	push rtemp2
	eor rtemp2,rtemp2
loop_delay:
	rcall delay_timer2
	inc rtemp2
	cpi rtemp2,3
	brne loop_delay
	pop rtemp2
	ret
delay_timer2:
	push rtemp1
	ldi rtemp1,0
	sts TCNT2, rtemp1    ;Valor inicial
	ldi rtemp1,100
	sts OCR2A,rtemp1    ;Umbral
	ldi rtemp1,(1<<WGM21)
	sts TCCR2A,rtemp1    ;Modo CTC
	ldi rtemp1,(1<<CS22)|(1<<CS21)|(1<<CS20)
	sts TCCR2B,rtemp1
again:
	in rtemp1,TIFR2
	sbrs rtemp1,OCF2A
	rjmp again
	ldi rtemp1,0         ;Detener Timer
	sts TCCR2B,rtemp1
	ldi rtemp1,(1<<OCF2A)
	out TIFR2,rtemp1
	pop rtemp1
	ret
	
;; Funciones para controlar los motores 
motor_H_forward:
	cbi MOTOR_H_OUT1_PORT,MOTOR_H_OUT1_PIN
	sbi MOTOR_H_OUT2_PORT,MOTOR_H_OUT2_PIN
	sbr MOTORES,1<<MOTOR_H_DIR
	cbr MOTORES,1<<MOTOR_H_STOP_FLAG
	ret
motor_H_stop:
	cbi MOTOR_H_OUT1_PORT,MOTOR_H_OUT1_PIN
	cbi MOTOR_H_OUT2_PORT,MOTOR_H_OUT2_PIN
	sbr MOTORES,1<<MOTOR_H_STOP_FLAG			
	ret
motor_H_reverse:
	sbi MOTOR_H_OUT1_PORT,MOTOR_H_OUT1_PIN
	cbi MOTOR_H_OUT2_PORT,MOTOR_H_OUT2_PIN
	sbr MOTORES,1<<MOTOR_H_DIR
	cbr MOTORES,1<<MOTOR_H_STOP_FLAG
	ret
motor_V_forward:
	cbi MOTOR_V_OUT1_PORT,MOTOR_V_OUT1_PIN
	sbi MOTOR_V_OUT2_PORT,MOTOR_V_OUT2_PIN
	sbr MOTORES,1<<MOTOR_V_DIR
	cbr MOTORES,1<<MOTOR_V_STOP_FLAG
	ret
motor_V_stop:
	cbi MOTOR_V_OUT1_PORT,MOTOR_V_OUT1_PIN
	cbi MOTOR_V_OUT2_PORT,MOTOR_V_OUT2_PIN
	sbr MOTORES,1<<MOTOR_V_STOP_FLAG			
	ret
motor_V_reverse:
	sbi MOTOR_V_OUT1_PORT,MOTOR_V_OUT1_PIN
	cbi MOTOR_V_OUT2_PORT,MOTOR_V_OUT2_PIN
	cbr MOTORES,1<<MOTOR_V_DIR
	cbr MOTORES,1<<MOTOR_V_STOP_FLAG
	ret

;; Función para procesar los datos del ADC. Cuando se sale de esta función,
;; se sabe qué color se está leyendo y si hubo un cambio de color con
;; respecto a la última vez que se llamó a esta función. 
leer_datos_adc:	
	push rtemp1
	push rtemp2
	lds rtemp1,ADCL
	lds rtemp2,ADCH
comparar_con_umbral:
	cpi rtemp2,0x01
	breq chequear_blanco
	cpi rtemp2,0x02
	breq chequear_blanco2		;Si pasa esto, veo si es blanco
	cpi rtemp2,0x03
	breq chequear_negro		;Si pasa esto, veo si es negro
	rjmp terminar_conversion	;Si llegó hasta acá, estoy leyendo ruido
chequear_blanco:
	cpi rtemp1,180		;Cota inferior de blanco 
	brsh es_blanco
	rjmp terminar_conversion
chequear_blanco2:
	cpi rtemp1,80
	brlo es_blanco
	rjmp terminar_conversion
es_blanco:
	sbic SCANNER,COLOR
	sbi SCANNER,CAMBIO_COLOR
	cbi SCANNER,COLOR
	rjmp terminar_conversion
chequear_negro:
	cpi rtemp1,0		;Cota inferior negro 
	brsh es_negro
	rjmp terminar_conversion
es_negro:
	sbis SCANNER,COLOR
	sbi SCANNER,CAMBIO_COLOR
	sbi SCANNER,COLOR
	rjmp terminar_conversion
terminar_conversion:	
	pop rtemp1
	pop rtemp2
	ret

;; Función para guardar el primer bit de la columna.
guardar_primer_bit:
	set
	sbis SCANNER,COLOR
	clt
	bld r20,0
	eor POS_INICIAL,POS_INICIAL
	ret

;; Esta función se llama cuando hubo un cambio de color y se utiliza para
;; calcular cuántos bits del mismo color se leyeron. 
calcular_bits_leidos:
	push rtemp1
	mov rtemp1,POS_FINAL
	sub rtemp1,POS_INICIAL
	cp rtemp1,SIZE
	brlo redondear
dividir:
	sub rtemp1,SIZE
	inc CANT
	cp rtemp1,SIZE
	brlo redondear
	rjmp dividir
redondear:	
	cp rtemp1,SIZE_2
	brlo terminar_division
	inc CANT
terminar_division:
	pop rtemp1
	ret

;; Luego de calcular la cantidad de bits que se leyeron y se guardan en CANT,
;; se llama a esta fucnión para guardarlos en r20, r21 y r22.
guardar_bits_en_registros:
	set
	sbic SCANNER,COLOR
	clt 			; Se guarda el color leído en flag T.
donde_estoy:	
	cpi BIT_ACTUAL,0x10
	brsh guardar_en_r22
	cpi BIT_ACTUAL,0x08
	brsh guardar_en_r21
guardar_en_r20:
	tst CANT
	breq terminar_guardado
	lsl r20
	bld r20,0
	dec CANT
	inc BIT_ACTUAL
	rjmp donde_estoy
guardar_en_r21:
	tst CANT
	breq terminar_guardado
	lsl r21
	bld r21,0
	dec CANT
	inc BIT_ACTUAL
	rjmp donde_estoy
guardar_en_r22:
	tst CANT
	breq terminar_guardado
	lsl r22
	bld r22,0
	dec CANT
	inc BIT_ACTUAL
	rjmp donde_estoy
terminar_guardado:	
	ret


;; Función de decodificación QR. (Desde acá hasta el final del código se encuentra la función que se encarga de decodificar).
desenmascarar:
	ldi rtemp1,0xff
	eor r20,rtemp1
	eor r21,rtemp1
	eor r22,rtemp1
	rjmp continuar_sin_mascara
decodificar_linea:
; Lo primero que se hace es sacarle la máscara al código, la cual se conoce previamente.
	cpi CONT_H,20
	breq desenmascarar
	cpi CONT_H,17
	breq desenmascarar
	cpi CONT_H,11
	breq desenmascarar
	cpi CONT_H,8
	breq desenmascarar
	cpi CONT_H,5
	breq desenmascarar
	cpi CONT_H,2
	breq desenmascarar
continuar_sin_mascara:
;Veo en que columna estoy parado y en base a eso llamo al método para decodificar
	CP LENGTH, CANT_LETRAS_LEIDAS
	BREQ salto_a_fin
	CPI CONT_H, 0x00 ;Es primera columna (col 0)
	BRNE no_es_cero
	JMP leo_tipo_1A 
salto_a_fin:
	JMP FIN
no_es_cero:
	CPI CONT_H, 0x01 ;Es segunda columna (col 1)
	BRNE no_es_uno
	JMP leo_tipo_1B
no_es_uno:
	CPI CONT_H, 0x02 ;Es tercera columna (col 2)
	BRNE no_es_dos
	JMP leo_tipo_2A
no_es_dos:
	CPI CONT_H, 0x03 ;Es cuarta columna (col 3)
	BRNE no_es_tres	
	JMP leo_tipo_2B
no_es_tres:
	CPI CONT_H, 0x04 ;Es quinta columna (col 4)
	BRNE no_es_cuatro
	JMP leo_tipo_1A 
no_es_cuatro:
	CPI CONT_H, 0x05 ;Es sexta columna (col 5)
	BRNE no_es_cinco
	JMP leo_tipo_1B
no_es_cinco:
	CPI CONT_H, 0x06 ;Es septima columna (col 6)
	BRNE no_es_seis
	JMP leo_tipo_2A
no_es_seis:
	CPI CONT_H, 0x07 ;Es octava columna (col 7)
	BRNE no_es_siete
	JMP leo_tipo_2B
no_es_siete:
	CPI CONT_H, 0x08 ;Es novena columna (col 8)
	BRNE no_es_ocho
	JMP leo_tipo_1A
no_es_ocho:
	CPI CONT_H, 0x09 ;Es decima columna (col 9) 
	BRNE no_es_nueve
	JMP leo_tipo_1B
no_es_nueve:
	CPI CONT_H, 0x0A ;Es onceava columna (col 10) 
	BRNE no_es_diez
	JMP leo_tipo_2A
no_es_diez:
	CPI CONT_H, 0x0B ;Es doceava columna (col 11) 
	BRNE no_es_once
	JMP leo_tipo_2B
no_es_once:
	CPI CONT_H,21 ;Es doceava columna (col 11) 
	BREQ FIN
	INC CONT_H
	RET
FIN:
	LDI ACUM1, CARACTER_FIN ;Guardo caracter de fin para luego saber hasta donde tengo que leer por bluetooth
	RCALL guardo_acum1
	LDI XL, LOW(INICIO_TABLA) ;Reinicio punteros
	LDI XH, HIGH(INICIO_TABLA)
	INC XL
	INC XL
buscar_fin_mensaje:		;Si el byte que se lee empieza con 0000 significa que ahí es donde debería estar el caracter final
    	ld rtemp1,X+
    	cpi rtemp1,16
    	brsh buscar_fin_mensaje
encontrado:
   	dec XL
  	cpi XL,0xff
   	breq decrementar_parte_baja
guardar_caracter:	
    	ldi rtemp1,CARACTER_FIN
   	st X,rtemp1
   	ldi XL,LOW(INICIO_TABLA)
  	ldi XH,HIGH(INICIO_TABLA)
	RET
decrementar_parte_baja:
   	dec XH
   	rjmp guardar_caracter	

; ACÁ EMPIEZAN LOS MÉTODOS DE LECTURA Y DECODIFICACIÓN. LA REGLA ES: EL METODO DE BRCC
; HACE REFERENCIA AL ORDEN DE LECTURA (VER EXCEL), Y EL SBR HACE REFERENCIA AL BIT A SETEAR.

;PRIMER MÉTODO DE LECTURA 
;La columna tipo 1A tiene dos variantes, la primera es la que llega hasta la fila 12, la segunda finaliza en la 21
leo_tipo_1A:
	ROL R20 ;En c ahora tengo el primer bit
	BRCC quinto_bit_acum1_sigo ;Acum1.3
	SBR ACUM1, B3
quinto_bit_acum1_sigo:
	RCALL incremento_contador_verticalr20
	BRCC septimo_bit_acum1_sigo	;Acum1.1
	SBR ACUM1, B1
	;Acá termina primera parte de acum1 y empieza primera parte de acum2
septimo_bit_acum1_sigo:
	RCALL incremento_contador_verticalr20
	BRCC primer_bit_acum2_sigo ;Acum2.7
	SBR ACUM2, B7 
primer_bit_acum2_sigo:
	RCALL incremento_contador_verticalr20
	BRCC tercer_bit_acum2_sigo ;Acum2.5
	SBR ACUM2, B5
tercer_bit_acum2_sigo:
	RCALL incremento_contador_verticalr20
	BRCC quinto_bit_acum2_sigo ;Acum2.3
	SBR ACUM2, B3
quinto_bit_acum2_sigo:
	RCALL incremento_contador_verticalr20
	BRCC septimo_bit_acum2_sigo ;Acum2.1
	SBR ACUM2, B1
	;Acá termina primera parte de acum2 y empieza primera parte de acum3
septimo_bit_acum2_sigo:
	RCALL incremento_contador_verticalr20
	BRCC primer_bit_acum3_sigo ;Acum3.7
	SBR ACUM3, B7
primer_bit_acum3_sigo:
	RCALL incremento_contador_verticalr20
	BRCC tercer_bit_acum3_sigo ;Acum3.5
	SBR ACUM3, B5
	;Acá termina r20
tercer_bit_acum3_sigo:
	RCALL incremento_contador_verticalr21
	BRCC quinto_bit_acum3_sigo ;Acum3.3
	SBR ACUM3, B3
quinto_bit_acum3_sigo:
	RCALL incremento_contador_verticalr21
	BRCC septimo_bit_acum3_sigo ;Acum3.1
	SBR ACUM3, B1 
	;Acá termina primera parte de acum3 y empieza primera parte de acum4
septimo_bit_acum3_sigo:
	RCALL incremento_contador_verticalr21
	BRCC primer_bit_acum4_sigo ;Acum4.7
	SBR ACUM4, B7 
primer_bit_acum4_sigo:
	RCALL incremento_contador_verticalr21
	BRCC chequeo_fila ;Acum4.5
	SBR ACUM4, B5 
;Se terminó la lectura de la primera columna, acá se debería esperar a que se vuelvan a llenar R20, R21 y R22
;Si es tipo 1 C o D, debo seguir guardando en el acumulador el bit vertical, sino salto al final
chequeo_fila:	
	CPI CONT_H, 0x08
	BRNE fin_columna1	
; Esta parte corresponde a si la columna es la ocho (hay que hacer otras cosas con los acumuladores).
es_columna8:
	RCALL incremento_contador_verticalr21
	BRCC septimo_bit_acum4_sigo_c8 ;Acum4.3
	SBR ACUM4, B3
septimo_bit_acum4_sigo_c8:
	RCALL incremento_contador_verticalr21
	BRCC salto_linea ;Acum4.1
	SBR ACUM4, B1	
salto_linea: ;Linea que no tiene datos
	RCALL incremento_contador_verticalr21 ;Roto un bit que no me interesa
	RCALL incremento_contador_verticalr21
	BRCC primer_bit_acum5_sigo_c8 ;Acum4.7
	SBR ACUM5, B7
primer_bit_acum5_sigo_c8:
	RCALL incremento_contador_verticalr22
	BRCC tercer_bit_acum5_sigo_c8 ;Acum4.5
	SBR ACUM5, B5
	;Acá termina r20
tercer_bit_acum5_sigo_c8:
	RCALL incremento_contador_verticalr22
	BRCC quinto_bit_acum5_sigo_c8 ;Acum4.3
	SBR ACUM5, B3
quinto_bit_acum5_sigo_c8:
	RCALL incremento_contador_verticalr22
	BRCC septimo_bit_acum5_sigo_c8 ;Acum4.1
	SBR ACUM5, B1 	
septimo_bit_acum5_sigo_c8:
	RCALL incremento_contador_verticalr22
	BRCC primer_bit_acum6_sigo_c8 ;Acum6.7
	SBR ACUM6, B7
	;Acá termina r22
primer_bit_acum6_sigo_c8:
	RCALL incremento_contador_verticalr22
	BRCC fin_columna1 ;Acum6.5
	SBR ACUM6, B5		
	;Finalizó toda la columna
fin_columna1:
	INC CONT_H
	RET
	
;SEGUNDO MÉTODO DE LECTURA
leo_tipo_1B:
	ROL R20 ;En c ahora tengo el primer bit
	BRCC sexto_bit_acum1_sigo ;Acum1.2
	SBR ACUM1, B2
sexto_bit_acum1_sigo:
	RCALL incremento_contador_verticalr20
	BRCC octavo_bit_acum1_sigo	;Acum1.0
	SBR ACUM1, B0
	;Acá termina primera parte de acum1 y empieza primera parte de acum2
octavo_bit_acum1_sigo:
	RCALL incremento_contador_verticalr20
	BRCC segundo_bit_acum2_sigo ;Acum2.6
	SBR ACUM2, B6 
segundo_bit_acum2_sigo:
	RCALL incremento_contador_verticalr20
	BRCC cuarto_bit_acum2_sigo ;Acum2.4
	SBR ACUM2, B4
cuarto_bit_acum2_sigo:
	RCALL incremento_contador_verticalr20
	BRCC sexto_bit_acum2_sigo ;Acum2.2
	SBR ACUM2, B2
sexto_bit_acum2_sigo:
	RCALL incremento_contador_verticalr20
	BRCC octavo_bit_acum2_sigo ;Acum2.0
	SBR ACUM2, B0
	;Acá termina primera parte de acum2 y empieza primera parte de acum3
octavo_bit_acum2_sigo:
	RCALL incremento_contador_verticalr20
	BRCC segundo_bit_acum3_sigo ;Acum3.6
	SBR ACUM3, B6
segundo_bit_acum3_sigo:
	RCALL incremento_contador_verticalr20
	BRCC cuarto_bit_acum3_sigo ;Acum3.4
	SBR ACUM3, B4
	;Acá termina r20
cuarto_bit_acum3_sigo:
	RCALL incremento_contador_verticalr21
	BRCC sexto_bit_acum3_sigo ;Acum3.2
	SBR ACUM3, B2
sexto_bit_acum3_sigo:
	RCALL incremento_contador_verticalr21
	BRCC octavo_bit_acum3_sigo ;Acum3.0
	SBR ACUM3, B0 
	;Acá termina primera parte de acum3 y empieza primera parte de acum4
octavo_bit_acum3_sigo:
	RCALL incremento_contador_verticalr21
	BRCC segundo_bit_acum4_sigo ;Acum4.6
	SBR ACUM4, B6 
segundo_bit_acum4_sigo:
	RCALL incremento_contador_verticalr21
	BRCC chequeo_fila2 ;Acum4.4
	SBR ACUM4, B4 
chequeo_fila2:	
	CPI CONT_H, 0x09
	BRNE fin_columna2
; Esta parte corresponde a si la columna es la nueve (hay que hacer otras cosas con los acumuladores).
es_columna9:
	RCALL incremento_contador_verticalr21
	BRCC sexto_bit_acum4_sigo_c9 ;Acum4.2
	SBR ACUM4, B2
sexto_bit_acum4_sigo_c9:
	RCALL incremento_contador_verticalr21
	BRCC salto_linea_c9 ;Acum4.0
	SBR ACUM4, B0
salto_linea_c9: ;Linea que no tiene datos
	RCALL incremento_contador_verticalr21 ;Roto un bit que no me interesa
	RCALL incremento_contador_verticalr21
	BRCC segundo_bit_acum5_sigo_c9 ;Acum5.6
	SBR ACUM5, B6 
segundo_bit_acum5_sigo_c9:
	RCALL incremento_contador_verticalr22
	BRCC cuarto_bit_acum5_sigo_c9 ;Acum5.4
	SBR ACUM5, B4
cuarto_bit_acum5_sigo_c9:
	RCALL incremento_contador_verticalr22
	BRCC sexto_bit_acum5_sigo_c9 ;Acum5.2
	SBR ACUM5, B2
sexto_bit_acum5_sigo_c9:
	RCALL incremento_contador_verticalr22
	BRCC octavo_bit_acum5_sigo_c9 ;Acum5.0
	SBR ACUM5, B0
octavo_bit_acum5_sigo_c9:
	RCALL incremento_contador_verticalr22
	BRCC segundo_bit_acum6_sigo_c9 ;Acum6.6
	SBR ACUM6, B6 
segundo_bit_acum6_sigo_c9:
	RCALL incremento_contador_verticalr22
	BRCC fin_columna2 ;Acum6.4
	SBR ACUM6, B4 
;Se terminó la lectura de la columna, ahora hay que guardar los valores leidos en los acumuladores en SRAM	
;Guardo los valores que ya fueron completados en memoria ram.
;A continuación reviso que no esté en tipo 1 sección D
fin_columna2:
	CPI CONT_H, 0x01 ;Si es la segunda columna, tengo que guardar acum2 en length, sino en sram
	BRNE guardo_en_ram
	MOV LENGTH, ACUM2
	INC LENGTH
guardo_en_ram:
	RCALL guardo_acum1
	RCALL guardo_acum2
	RCALL guardo_acum3
	CPI CONT_H, 0x09
	BRNE empiezo_columna_3 ;Si no es la columna 9, no guardo acumuladores 4 y 5
	RCALL guardo_acum4
	RCALL guardo_acum5
	;Empiezo columna 3
empiezo_columna_3:	
	INC CONT_H
	RET

; TERCER MÉTODO DE LECTURA
leo_tipo_2A:
	ROL R20 ;En c ahora tengo el primer bit
	BRCC tercer_bit_acum1_sigo_c3 ;Acum1.5
	SBR ACUM1, B5
tercer_bit_acum1_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC primer_bit_acum1_sigo_c3	;Acum1.7
	SBR ACUM1, B7
	;Acá termina primera parte de acum1 y empieza primera parte de acum2
primer_bit_acum1_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC septimo_bit_acum2_sigo_c3 ;Acum2.1
	SBR ACUM2, B1 
septimo_bit_acum2_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC quinto_bit_acum2_sigo_c3 ;Acum2.3
	SBR ACUM2, B3
quinto_bit_acum2_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC tercer_bit_acum2_sigo_c3 ;Acum2.5
	SBR ACUM2, B5
tercer_bit_acum2_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC primer_bit_acum2_sigo_c3 ;Acum2.7
	SBR ACUM2, B7
	;Acá termina primera parte de acum2 y empieza primera parte de acum3
primer_bit_acum2_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC septimo_bit_acum3_sigo_c3 ;Acum3.1
	SBR ACUM3, B1
septimo_bit_acum3_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC quinto_bit_acum3_sigo_c3 ;Acum3.3
	SBR ACUM3, B3
	;Acá termina r20
quinto_bit_acum3_sigo_c3:
	RCALL incremento_contador_verticalr21
	BRCC tercer_bit_acum3_sigo_c3 ;Acum3.5
	SBR ACUM3, B5
tercer_bit_acum3_sigo_c3:
	RCALL incremento_contador_verticalr21
	BRCC primer_bit_acum3_sigo_c3 ;Acum3.7
	SBR ACUM3, B7
	;Acá termina primera parte de acum3 y empieza primera parte de acum4
primer_bit_acum3_sigo_c3:
	RCALL incremento_contador_verticalr21
	BRCC septimo_bit_acum4_sigo_c3 ;Acum4.1
	SBR ACUM4, B1
septimo_bit_acum4_sigo_c3:
	RCALL incremento_contador_verticalr21
	BRCC chequeo_fila3 ;Acum4.3
	SBR ACUM4, B3
;Se terminó la lectura de la tercer columna, acá se debería esperar a que se vuelvan a llenar R20, R21 y R22.
;Empiezo cuarta columna. Reviso que no sea tipo 2 sección C
chequeo_fila3:	
	CPI CONT_H, 0xA
	BRNE fin_columna3
; Esta parte corresponde a si la columna es la diez (hay que hacer otras cosas con los acumuladores).
es_columna10:
	RCALL incremento_contador_verticalr21
	BRCC tercer_bit_acum4_sigo_c10 ;Acum4.5
	SBR ACUM4, B5
tercer_bit_acum4_sigo_c10:
	RCALL incremento_contador_verticalr21
	BRCC salto_linea_c10 ;Acum4.7
	SBR ACUM4, B7
	;Acá termina primera parte de Acum4, salto de línea y empieza acum5
salto_linea_c10: ;Linea que no tiene datos
	RCALL incremento_contador_verticalr21 ;Roto un bit que no me interesa
	RCALL incremento_contador_verticalr21
	BRCC septimo_bit_acum5_sigo_c10 ;Acum5.1
	SBR ACUM5, B1
septimo_bit_acum5_sigo_c10:
	RCALL incremento_contador_verticalr22
	BRCC quinto_bit_acum5_sigo_c10 ;Acum5.3
	SBR ACUM5, B3
quinto_bit_acum5_sigo_c10:
	RCALL incremento_contador_verticalr22
	BRCC tercer_bit_acum5_sigo_c10 ;Acum5.5
	SBR ACUM5, B5
tercer_bit_acum5_sigo_c10:
	RCALL incremento_contador_verticalr22
	BRCC primer_bit_acum5_sigo_c10 ;Acum5.7
	SBR ACUM5, B7
	;Acá termina primera parte de Acum5, empieza acum6
primer_bit_acum5_sigo_c10:
	RCALL incremento_contador_verticalr22
	BRCC septimo_bit_acum6_sigo_c10 ;Acum6.1
	SBR ACUM6, B1 
septimo_bit_acum6_sigo_c10:
	RCALL incremento_contador_verticalr22
	BRCC fin_columna3 ;Acum6.3
	SBR ACUM6, B3 
fin_columna3:
	INC CONT_H
	RET

; CUARTO MÉTODO DE LECTURA
leo_tipo_2B:
	ROL R20 ;En c ahora tengo el primer bit
	BRCC cuarto_bit_acum1_sigo_c3 ;Acum1.4
	SBR ACUM1, B4
cuarto_bit_acum1_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC segundo_bit_acum1_sigo_c3	;Acum1.6
	SBR ACUM1, B6
	;Acá termina primera parte de acum1 y empieza primera parte de acum2
segundo_bit_acum1_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC octavo_bit_acum2_sigo_c3 ;Acum2.0
	SBR ACUM2, B0
octavo_bit_acum2_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC sexto_bit_acum2_sigo_c3 ;Acum2.2
	SBR ACUM2, B2
sexto_bit_acum2_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC cuarto_bit_acum2_sigo_c3 ;Acum2.4
	SBR ACUM2, B4
cuarto_bit_acum2_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC segundo_bit_acum2_sigo_c3 ;Acum2.6
	SBR ACUM2, B6
	;Acá termina primera parte de acum2 y empieza primera parte de acum3
segundo_bit_acum2_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC octavo_bit_acum3_sigo_c3 ;Acum3.0
	SBR ACUM3, B0
octavo_bit_acum3_sigo_c3:
	RCALL incremento_contador_verticalr20
	BRCC sexto_bit_acum3_sigo_c3 ;Acum3.2
	SBR ACUM3, B2
	;Acá termina r20
sexto_bit_acum3_sigo_c3:
	RCALL incremento_contador_verticalr21
	BRCC cuarto_bit_acum3_sigo_c3 ;Acum3.4
	SBR ACUM3, B4
cuarto_bit_acum3_sigo_c3:
	RCALL incremento_contador_verticalr21
	BRCC segundo_bit_acum3_sigo_c3 ;Acum3.6
	SBR ACUM3, B6
	;Acá termina primera parte de acum3 y empieza primera parte de acum4
segundo_bit_acum3_sigo_c3:
	RCALL incremento_contador_verticalr21
	BRCC octavo_bit_acum4_sigo_c3 ;Acum4.0
	SBR ACUM4, B0
octavo_bit_acum4_sigo_c3:
	RCALL incremento_contador_verticalr21
	BRCC chequeo_fila4 ;Acum4.2
	SBR ACUM4, B2
;Se terminó la lectura de la cuarta columna. Acá se debería esperar a que se vuelvan a llenar R20, R21 y R22.
;Empiezo quinta columna. Reviso que no sea tipo 2 sección D.
chequeo_fila4:	
	CPI CONT_H, 0x0B 
	BRNE fin_columna4
; Esta parte corresponde a si la columna es la once (hay que hacer otras cosas con los acumuladores).
es_columna11:
	RCALL incremento_contador_verticalr21
	BRCC cuarto_bit_acum4_sigo_c11 ;Acum4.4
	SBR ACUM4, B4
cuarto_bit_acum4_sigo_c11:
	RCALL incremento_contador_verticalr21
	BRCC salto_linea_c11 ;Acum4.6
	SBR ACUM4, B6
	;Acá termina primera parte de Acum4, salto de línea y empieza acum5
salto_linea_c11: ;Linea que no tiene datos
	RCALL incremento_contador_verticalr21 ;Roto un bit que no me interesa
	RCALL incremento_contador_verticalr21
	BRCC octavo_bit_acum5_sigo_c11 ;Acum5.0
	SBR ACUM5, B0
octavo_bit_acum5_sigo_c11:
	RCALL incremento_contador_verticalr22
	BRCC sexto_bit_acum5_sigo_c11 ;Acum5.2
	SBR ACUM5, B2
sexto_bit_acum5_sigo_c11:
	RCALL incremento_contador_verticalr22
	BRCC cuarto_bit_acum5_sigo_c11 ;Acum5.4
	SBR ACUM5, B4
cuarto_bit_acum5_sigo_c11:
	RCALL incremento_contador_verticalr22
	BRCC segundo_bit_acum5_sigo_c11 ;Acum5.6
	SBR ACUM5, B6
	;Acá termina primera parte de Acum5, empieza acum6
segundo_bit_acum5_sigo_c11:
	RCALL incremento_contador_verticalr22
	BRCC octavo_bit_acum6_sigo_c11 ;Acum6.0
	SBR ACUM6, B0 
octavo_bit_acum6_sigo_c11:
	RCALL incremento_contador_verticalr22
	BRCC fin_columna4 ;Acum6.2
	SBR ACUM6, B2 
fin_columna4:
	CPI CONT_H, 0x0B
	BRNE guardo_parcial_sram ;Por como viene el orden, primero se guardan acum6 y acum5
	RCALL guardo_acum6
	RCALL guardo_acum5
guardo_parcial_sram:
	RCALL guardo_acum4
	RCALL guardo_acum3
	RCALL guardo_acum2
	INC CONT_H
	RET

; MÉTODOS AUXILIARES DE LA FUNCIÓN DE DECODIFICACIÓN:
;Rollea R20 a izquierda
incremento_contador_verticalR20:
	ROL R20
	RET
;Rollea R21 a izquierda
incremento_contador_verticalR21:
	ROL R21
	RET
;Rollea R22 a izquierda
incremento_contador_verticalR22:
	ROL R22
	RET
;Incrementa contador horizontal (variable de control)
incremento_contador_horizontal:
	INC CONT_H
	RET
;Guarda ACUM1 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum1:
	MOV R14, ACUM1
	ST X+, R14
	EOR ACUM1, ACUM1
	INC CANT_LETRAS_LEIDAS
	RET
;Guarda ACUM2 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum2:
	MOV R14, ACUM2
	ST X+, R14
	EOR ACUM2, ACUM2
	INC CANT_LETRAS_LEIDAS
	RET
;Guarda ACUM3 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum3:
	MOV R14, ACUM3
	ST X+, R14
	EOR ACUM3, ACUM3
	INC CANT_LETRAS_LEIDAS
	RET
;Guarda ACUM4 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum4:
	MOV R14, ACUM4
	ST X+, R14
	EOR ACUM4, ACUM4
	INC CANT_LETRAS_LEIDAS
	RET
;Guarda ACUM5 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum5:
	MOV R14, ACUM5
	ST X+, R14
	EOR ACUM5, ACUM5
	INC CANT_LETRAS_LEIDAS
	RET
;Guarda ACUM6 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum6:
	MOV R14, ACUM6
	ST X+, R14
	EOR ACUM6, ACUM6
	INC CANT_LETRAS_LEIDAS
	RET
