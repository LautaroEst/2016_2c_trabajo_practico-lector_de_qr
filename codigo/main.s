	.include "m328Pdef.inc"
	.include "macros.inc"

	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; SE DEFINE UN REGISTRO DE I/O, SCANNER, CON LOS FLAGS NECESARIOS PARA EL ESCANEO
.equ 	SCANNER = GPIOR0
.equ 	COLOR = 0		; Negro=1, Blanco=0
.equ 	ESCANEANDO = 1
.equ	CAMBIO_COLOR = 2
.equ	FIN_COLUMNA = 3
.equ	AVANZO_CASILLA = 4
.equ	FLAG_BLUETOOTH = 5
.equ	FLAG_BLUETOOTH_VACIO = 6

	
;;; SE DEFINE UN REGISTRO, MOTORES, CON LOS FLAGS NECESARIOS PARA VIGILAR EL ESTADO DE LOS MOTORES
.def 	MOTORES = r31
.equ 	MOTOR_A_ENABLE = 0
.equ 	MOTOR_A_STOP_FLAG = 1
.equ 	MOTOR_A_DIR = 2		;DIR=FORWARD=1,	DIR=REVERSE=0
.equ 	MOTOR_B_ENABLE = 3
.equ 	MOTOR_B_STOP_FLAG = 4
.equ 	MOTOR_B_DIR = 5

;;; REGISTROS Y CONSTANTES PERSONALIZADOS
.equ 	LIMITE_FLANCOS = 255
.equ 	TAMANIO_CASILLA = 13
.equ	CORTE_POR_REDONDEO = TAMANIO_CASILLA - 9 ; (o 10 u 11)
.equ	CANTIDAD_FILAS = 21
.equ	CANTIDAD_COLUMNAS = 21
.equ	ULTIMO_BIT_DE_FILA = CANTIDAD_COLUMNAS - 1
.equ	ULTIMO_BIT_DE_COLUMNA = CANTIDAD_FILAS - 1
.equ	BAUD_RATE = 0x67 ;Este es el valor que debe ponerse para tener un baud rate de 9600, que es el que usa el hc 05.
.equ	CARACTER_FIN = '/' ;Caracter con el que terminará el código QR
.equ	INICIO_TABLA = 0x0100 
	
.def	CERO = r0
.def	UNO = r1
.def	CANT = r3	
.def 	SIZE = r4
.def 	SIZE_2 = r5

.def	rtemp1 = r16
.def	rtemp2 = r17
.def 	BIT_ACTUAL = r18
.def	POS_INICIAL = r8
.def	POS_FINAL = r9


;;; REGISTROS PARA LA DECODIFICACIÓN
.def 	CONT_H = r19
.def	CANT_LETRAS_LEIDAS = r6
.def	LENGTH = r7
.def 	ACUM1 = r23 ;La idea de estos acumuladores es ir sosteniendo los valores ya procesados, que luego se meteran en SRAM
.def 	ACUM2 = r24 ;Uso dos ya que tengo que mantener lo que leo porque cada letra son 2 pasadas de columna
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

.equ    LED_PRUEBA_PORT_DIR =  DDRB
.equ    LED_PRUEBA_PORT     =  PORTB
.equ    LED_PRUEBA_PIN      =  5


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; COMIENZO DEL PROGRAMA

	;; Tabla de interrupciones
.org 0x0000
	rjmp inicio
.org OC1Aaddr
	rjmp counter1_int_handler
.org OC0Aaddr
	rjmp counter0_int_handler
.org ADCCaddr
	rjmp adc_int_handler
.org URXCaddr
	rjmp urx_int_handler ;Interrupción producida por la recepción de datos
.org UDREaddr
	rjmp udre_int_handler
.org INT_VECTORS_SIZE
	

inicio:
	;; INICIALIZACIÓN DEL SP
	ldi rtemp1,HIGH(RAMEND)			
	out sph,rtemp1				
	ldi rtemp1,LOW(RAMEND)			
	out spl,rtemp1


	;; CONFIGURACIONES VARIAS
	rcall configurar_puertos
	rcall configurar_adc
	rcall configurar_contadores
	

	;; SE INICIALIZAN LOS REGISTROS QUE SE VAN A UTILIZAR
inicializacion_registros:
	ldi XL, LOW(INICIO_TABLA) 	;Puntero a la tabla donde se guarda el código	
	ldi XH, HIGH(INICIO_TABLA)

	ldi rtemp1,'0'			;Ascii para cero y uno
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

	EOR ACUM1, ACUM1		;Registros para la decodificación
	EOR ACUM2, ACUM2
	EOR ACUM3, ACUM3
	EOR ACUM4, ACUM4
	EOR ACUM5, ACUM5
	EOR ACUM6, ACUM6
	ldi rtemp1,0x00
	mov CANT_LETRAS_LEIDAS, rtemp1
	ldi rtemp1,0x1A
	mov LENGTH, rtemp1 ;Inicializo el valor de length con la mayor cantidad de datos que puedo llegar a leer.

	
	;; HABILITACIÓN GLOBAL DE INTERRUPCIONES
	sei

	
	;; INICIO DEL PROGRAMA: PREPARACIÓN DEL ADC Y PRIMERA LECTURA
primera_conversion_adc:					
	sbi SCANNER,ESCANEANDO			
	lds rtemp1,ADCSRA				
	sbr rtemp1,1<<ADSC					
	sts ADCSRA,rtemp1				
esperar_primera_conversion:			
	sbic SCANNER,ESCANEANDO	; Si no terminó la conversión del ADC, ESCANEANDO=1
	rjmp esperar_primera_conversion		
	sbi SCANNER,ESCANEANDO
	rcall leer_datos_adc	; Con esto, se configura el color que se está leyendo cuando empieza a leer
	cbi SCANNER,CAMBIO_COLOR

	;; SE ESPERA QUE SE RECIBA LA SEÑAL DE INICIAR EL ESCANEO
esperar_recibir_datos:
	sbic  SCANNER,FLAG_BLUETOOTH ; Espero a recibir datos del bluetooth por interrupción
	rjmp RECIBIR_DATOS
	rjmp esperar_recibir_datos

	
	;; FUNCIONES PARA CONTROLAR EL BLUETOOTH
RECIBIR_DATOS:
	cbi SCANNER,FLAG_BLUETOOTH
	LOAD rtemp2, UDR0 ;Levanto en R17 el valor recibido por puerto serie.
	CPI rtemp2, 'r' ;La app envía el caracter 'r' si solicita recibir datos. En caso de ser así, va a ENVIAR_DATOS
	BREQ ENVIAR_DATOS
	CPI rtemp2, '1' ;La app envía el caracter '1' si desea encender motores.
	breq leer_columna
	;; breq decodificacion_de_prueba
	rjmp esperar_recibir_datos

VOLVER_A_ENVIAR:
	sbis SCANNER,FLAG_BLUETOOTH_VACIO
	rjmp VOLVER_A_ENVIAR
	LDI rtemp1, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;Deshabilito la interrupción de UDRE0.
	STORE UCSR0B, rtemp1
	cbi SCANNER,FLAG_BLUETOOTH_VACIO
ENVIAR_DATOS:
	ld rtemp2,X+
	cpi rtemp2,CARACTER_FIN
	breq SALIR
	STORE UDR0, rtemp2 ;Carga en UDR0 el valor a enviar
	LDI rtemp1, (1<<RXEN0)|(1<<TXEN0)|(1<<UDRIE0)|(1<<RXCIE0) ;Habilita la interrupción de UDRE0 vacío
	STORE UCSR0B, rtemp1 ;Carga el valor de la configuración
	RJMP VOLVER_A_ENVIAR

SALIR:
	LDI rtemp2, ' '
	STORE UDR0, rtemp2 ;Cargo este caracter para darle un cierre al mensaje.
	LDI rtemp1, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;Deshabilito la interrupción de UDRE0 para que no enloquezca.
	STORE UCSR0B, rtemp1
	ldi XL,LOW(INICIO_TABLA)
	ldi XH,HIGH(INICIO_TABLA)
	cbi SCANNER,FLAG_BLUETOOTH
	rjmp esperar_recibir_datos
;; PRENDER_LED:
;; 	SBI LED_PRUEBA_PORT, LED_PRUEBA_PIN
;; 	cbi SCANNER,FLAG_BLUETOOTH
;; 	RJMP WAIT_HERE


decodificacion_de_prueba:
 	LDI R20, 0b00001100 ;Pruebas
 	LDI R21, 0b10010011 ;Pruebas
 	LDI R22, 0b11111000 ;Pruebas
	cbi SCANNER,FLAG_BLUETOOTH
 	rcall decodificar_linea
 	LDI R20, 0b10001010 ;Pruebas
 	LDI R21, 0b10101010 ;Pruebas
 	LDI R22, 0b00001000 ;Pruebas
	cbi SCANNER,FLAG_BLUETOOTH
 	rcall decodificar_linea
 	LDI R20, 0b01000101 ;Pruebas
 	LDI R21, 0b01110010 ;Pruebas
 	LDI R22, 0b11101000 ;Pruebas
	cbi SCANNER,FLAG_BLUETOOTH
 	rcall decodificar_linea	;


	
 	;; LDI R20, 0b00110100 ;Pruebas
 	;; LDI R21, 0b01101010 ;Pruebas
 	;; LDI R22, 0b11101000 ;Pruebas
 	;; rcall decodificar_linea
	;; LDI R20, 0b00000001 ;Pruebas
 	;; LDI R21, 0b00010010 ;Pruebas
 	;; LDI R22, 0b11101000 ;Pruebas
 	;; rcall decodificar_linea
	;; LDI R20, 0b11010101 ;Pruebas
 	;; LDI R21, 0b00111010 ;Pruebas
 	;; LDI R22, 0b00001000 ;Pruebas
 	;; rcall decodificar_linea
 	;; LDI R20, 0b10011001 ;Pruebas
 	;; LDI R21, 0b00000011 ;Pruebas
 	;; LDI R22, 0b11111000 ;Pruebas
 	;; rcall decodificar_linea
 	;; LDI R20, 0b01100111 ;Pruebas
 	;; LDI R21, 0b01001000 ;Pruebas
 	;; LDI R22, 0b00000000 ;Pruebas
 	;; rcall decodificar_linea
 	;; LDI R20, 0b10101010 ;Pruebas
 	;; LDI R21, 0b00101011 ;Pruebas
 	;; LDI R22, 0b10001000 ;Pruebas	
 	;; rcall decodificar_linea
 	;; LDI R20, 0b01110010 ;Pruebas
;; 	LDI R21, 0b11110100 ;Pruebas
;; 	LDI R22, 0b01010000 ;Pruebas
;; 	rcall decodificar_linea
;; 	LDI R20, 0b11101000 ;Pruebas
;; 	LDI R21, 0b11100111 ;Pruebas
;; 	LDI R22, 0b10000000 ;Pruebas
;; 	rcall decodificar_linea
;; 	LDI R20, 0b00110001 ;Pruebas
;; 	LDI R21, 0b01101001 ;Pruebas
;; 	LDI R22, 0b00101000 ;Pruebas
;; 	rcall decodificar_linea	
;; 	LDI R20, 0b11111011 ;Pruebas
;; 	LDI R21, 0b11101011 ;Pruebas
;; 	LDI R22, 0b01010000 ;Pruebas
;; 	rcall decodificar_linea		;CUANDO CORRA ESTA DECODIFICACION, VA A PONER EL CARACTER FIN

;;  	inc XL
;;  	inc XL
;; buscar_fin_mensaje:		;Si el byte que se lee empieza con 0000 significa que ahí es donde debería estar el caracter final
;;    	ld rtemp1,X+
;;    	cpi rtemp1,16
;;    	brsh buscar_fin_mensaje
;; encontrado:
;;   	dec XL
;;  	cpi XL,0xff
;;   	breq decrementar_parte_baja
;; guardar_caracter:	
;;    	ldi rtemp1,CARACTER_FIN
;;   	st X,rtemp1
;;   	ldi XL,LOW(INICIO_TABLA)
;;   	ldi XH,HIGH(INICIO_TABLA)
;;   	SBI LED_PRUEBA_PORT, LED_PRUEBA_PIN ;Prendo el led para avisar que ya está.
;;   	cbi SCANNER,FLAG_BLUETOOTH
;;   	rjmp esperar_recibir_datos
;; decrementar_parte_baja:
;;   	dec XH
;;   	rjmp guardar_caracter



	
 	SBI LED_PRUEBA_PORT, LED_PRUEBA_PIN
 	cbi SCANNER,FLAG_BLUETOOTH
	rjmp esperar_recibir_datos
	
	;; FUNCIÓN QUE REALIZA EL ESCANEO DE UNA COLUMNA.
leer_columna:
	eor BIT_ACTUAL,BIT_ACTUAL
	eor r20,r20
	eor r21,r21
	eor r22,r22
	rcall guardar_primer_bit ; Se guarda el primer bit de la columna, mientras el carro está quieto
	ldi rtemp1,0x00
	sts TCNT1H,rtemp1
	sts TCNT1L,rtemp1
	rcall motor_A_reverse
avanzar_con_motor_A:
	sbic SCANNER,FIN_COLUMNA
	rjmp leer_ultimos_bit
	rcall leer_datos_adc
	sbis SCANNER,CAMBIO_COLOR
	rjmp avanzar_con_motor_A
	lds POS_FINAL,TCNT1L
	cbi SCANNER,CAMBIO_COLOR
	rcall calcular_bits_leidos
	mov POS_INICIAL,POS_FINAL
	rcall guardar_bits_en_registros
	rjmp avanzar_con_motor_A

leer_ultimos_bit:
	rcall motor_A_stop
	ldi rtemp1,LIMITE_FLANCOS
	mov POS_FINAL,rtemp1
	rcall calcular_bits_leidos
	mov POS_INICIAL,POS_FINAL
	ldi rtemp1,(1<<COLOR)	;toggle del color para seguir guardando con la misma lógica
	in rtemp2,SCANNER
	eor rtemp2,rtemp1
	out SCANNER,rtemp2	
	rcall guardar_bits_en_registros
	lsl r22
	lsl r22
	lsl r22
volver_a_inicio:
	cbi SCANNER,FIN_COLUMNA
	ldi rtemp1,0x00
	sts TCNT1H,rtemp1
	sts TCNT1L,rtemp1
	rcall motor_A_forward
seguir_retrocediendo:
	sbis SCANNER,FIN_COLUMNA
	rjmp seguir_retrocediendo

	rcall motor_A_stop
	cbi SCANNER,FIN_COLUMNA

	;; cpi CONT_H,0
	;; breq cargar_columna_0
	;; cpi CONT_H,1
	;; breq cargar_columna_1
	;; cpi CONT_H,2
	;; breq cargar_columna_2

;; comparar_r20:	
;; 	cpi r20,0b00001100
;; 	breq r20_ok
;; comparar_r21:	
;; 	cpi r21,0b10010011
;; 	breq r21_ok
;; comparar_r22:
;; 	cpi r22,0b11111000
;; 	breq r22_ok
;; 	rjmp seguir

;; r20_ok:
;; 	sbi LED_PRUEBA_PORT,LED_PRUEBA_PIN
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	cbi LED_PRUEBA_PORT,LED_PRUEBA_PIN
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rjmp comparar_r21
;; r21_ok:
;; 	sbi LED_PRUEBA_PORT,LED_PRUEBA_PIN
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	cbi LED_PRUEBA_PORT,LED_PRUEBA_PIN
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rjmp comparar_r22

;; r22_ok:
;; 	sbi LED_PRUEBA_PORT,LED_PRUEBA_PIN
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	cbi LED_PRUEBA_PORT,LED_PRUEBA_PIN
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
;; 	rcall retardo_500ms
	
seguir:	
	rcall decodificar_linea
	cbi SCANNER,FLAG_BLUETOOTH
	rjmp esperar_recibir_datos


cargar_columna_0:	
	LDI R20, 0b00001100 ;Pruebas
 	LDI R21, 0b10010011 ;Pruebas
 	LDI R22, 0b11111000 ;Pruebas
	rjmp seguir

cargar_columna_1:
	LDI R20, 0b10001010 ;Pruebas
 	LDI R21, 0b10101010 ;Pruebas
 	LDI R22, 0b00001000 ;Pruebas
	rjmp seguir
	
cargar_columna_2:	
	LDI R20, 0b01000101 ;Pruebas
 	LDI R21, 0b01110010 ;Pruebas
 	LDI R22, 0b11101000 ;Pruebas
	rjmp seguir
	
	;; FUNCION PARA CARGAR LOS VALORES LEÍDOS EN LA TABLA
;; 	ldi rtemp1,8 ;Necesario para hacer la carga de la tabla
;; cargar_en_tabla:
;;  	sbrc r20,7
;;  	st X+,UNO
;;  	sbrs r20,7
;;  	st X+,CERO
;;  	lsl r20
;;  	dec rtemp1
;;  	brne cargar_en_tabla
;;  	ldi rtemp1,8
;; seguir_cargando:
;;   	sbrc r21,7
;;    	st X+,UNO
;;    	sbrs r21,7
;;    	st X+,CERO
;;    	lsl r21
;;    	dec rtemp1
;;      	brne seguir_cargando
;;  	ldi rtemp1,5
;; terminar_de_cargar:
;;     	sbrc r22,7
;;    	st X+,UNO
;;     	sbrs r22,7
;;     	st X+,CERO
;;     	lsl r22
;;  	dec rtemp1
;;     	brne terminar_de_cargar
;;  	ldi rtemp1,CARACTER_FIN
;;  	st X,rtemp1
;;  	LDI XL, LOW(INICIO_TABLA)
;;  	LDI XH, HIGH(INICIO_TABLA)
;; 	cbi SCANNER,FLAG_BLUETOOTH
;; 	rjmp esperar_recibir_datos



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FUNCIONES AUXILIARES
	
guardar_primer_bit:
	set
	sbis SCANNER,COLOR
	clt
	bld r20,0
	eor POS_INICIAL,POS_INICIAL
	ret

	
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


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; FUNCIONES DE CONFIGURACIÓN DE LOS PUERTOS UTILIZADOS, DEL ADC Y DE LOS CONTADORES
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
	;; MOTOR A (MUEVE EL CARRITO)
	sbi MOTOR_A_OUT1_PORT_DIR,MOTOR_A_OUT1_PIN 	;Output = motor A
	sbi MOTOR_A_OUT2_PORT_DIR,MOTOR_A_OUT2_PIN
	sbi MOTOR_A_ENABLE_PORT_DIR,MOTOR_A_ENABLE_PIN
	rcall motor_A_stop				
	sbi MOTOR_A_ENABLE_PORT_DIR,MOTOR_A_ENABLE_PIN
	;; MOTOR B (MUEVE EL RODILLO)
	sbi MOTOR_B_OUT1_PORT_DIR,MOTOR_B_OUT1_PIN 	;Output = motor B
	sbi MOTOR_B_OUT2_PORT_DIR,MOTOR_B_OUT2_PIN
	sbi MOTOR_B_ENABLE_PORT_DIR,MOTOR_B_ENABLE_PIN
	rcall motor_B_stop
	sbi MOTOR_B_ENABLE_PORT_DIR,MOTOR_B_ENABLE_PIN
	;; BLUETOOTH Y PUERTO SERIE
	ldi rtemp1, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;habilito como transmisor, receptor y habilito interrupciones de recepcion
	store UCSR0B, rtemp1
;*******************************************************************************************
; Setear el bit rxcie0 habilita la interrupción del flag rxc del ucsr0a.
; Al completar la recepcìón, rxc se setea a high.
; Si rxcie0 = 1, cambiar rxc a uno fuerza la interrupción.
;
; Setear el bit udrie0 (usart dara register empty interrupt enable.
; Cuando el udr0 esta listo para recibir nuevos datos, el UDRE (usart data register empty flag) se pone en 1.
; Si UDRIE0 = 1 y si se pone UDRE en 1, fuerza la interrupción.
;*******************************************************************************************
	LDI rtemp1, (1<<UCSZ01)|(1<<UCSZ00)|(1<<UMSEL01) ;8 bit data, sin paridad y 1 bit de parada.
	STORE UCSR0C, rtemp1
	LDI rtemp1, BAUD_RATE ;9600 baud rate
	STORE UBRR0L, rtemp1
	pop rtemp1
	ret


configurar_adc:
	push rtemp1
	ldi rtemp1,(1<<REFS0)|0x01					;Referencia=VCC. Entrada=ADC1=PC1.
	sts ADMUX,rtemp1						;Ajustado a izquierda
	ldi rtemp1,(1<<ADEN)|(1<<ADIE)|(1<<ADATE)|0x04		;Habilitar ADC. Habilitar interrupcion.
	sts ADCSRA,rtemp1						;Prescaler=ck/128.
	ldi rtemp1,0
	sts ADCSRB,rtemp1
	pop rtemp1
	ret
	

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
	ldi rtemp1,1				
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

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; CONFIGURACIÓN DE LAS INTERRUPCIONES

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
	RETI

urx_int_handler:
	sbi SCANNER,FLAG_BLUETOOTH
	RETI
	

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
	
motor_A_reverse:
	cbi MOTOR_A_OUT1_PORT,MOTOR_A_OUT1_PIN
	sbi MOTOR_A_OUT2_PORT,MOTOR_A_OUT2_PIN
	sbr MOTORES,1<<MOTOR_A_DIR
	cbr MOTORES,1<<MOTOR_A_STOP_FLAG
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



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; DECODIFICACIÓN QR

desenmascarar:
	ldi rtemp1,0xff
	eor r20,rtemp1
	eor r21,rtemp1
	eor r22,rtemp1
	rjmp continuar_sin_mascara
	
;Veo en que columna estoy parado y en base a eso llamo al método para decodificar
decodificar_linea:

	CP LENGTH, CANT_LETRAS_LEIDAS
	BREQ salto_a_fin

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
	CPI CONT_H, 0x00 ;Es primera columna (col 0)
	BRNE no_es_cero
	;LDI R20, 0b10000001 ;Pruebas
	;LDI R21, 0b11011000 ;Pruebas
	;LDI R22, 0b10000000 ;Pruebas
	JMP leo_tipo_1A 
salto_a_fin:
	JMP FIN
no_es_cero:
	CPI CONT_H, 0x01 ;Es segunda columna (col 1)
	BRNE no_es_uno
	;LDI R20, 0b01111010 ;Pruebas
	;LDI R21, 0b11101101 ;Pruebas
	;LDI R22, 0b00100000 ;Pruebas
	JMP leo_tipo_1B
no_es_uno:
	CPI CONT_H, 0x02 ;Es tercera columna (col 2)
	BRNE no_es_dos
	;LDI R20, 0b01101000 ;Pruebas
	;LDI R21, 0b10010000 ;Pruebas
	;LDI R22, 0b00000000 ;Pruebas
	JMP leo_tipo_2A
no_es_dos:
	CPI CONT_H, 0x03 ;Es cuarta columna (col 3)
	BRNE no_es_tres	
	;LDI R20, 0b00101110 ;Pruebas
	;LDI R21, 0b01111000 ;Pruebas
	;LDI R22, 0b00000000 ;Pruebas
	JMP leo_tipo_2B
no_es_tres:
	CPI CONT_H, 0x04 ;Es quinta columna (col 4)
	BRNE no_es_cuatro
	;LDI R20, 0b10000001 ;Pruebas
	;LDI R21, 0b11011000 ;Pruebas
	;LDI R22, 0b10000000 ;Pruebas
	JMP leo_tipo_1A 
no_es_cuatro:
	CPI CONT_H, 0x05 ;Es sexta columna (col 5)
	BRNE no_es_cinco
	;LDI R20, 0b01111010 ;Pruebas
	;LDI R21, 0b11101101 ;Pruebas
	;LDI R22, 0b00100000 ;Pruebas
	JMP leo_tipo_1B
no_es_cinco:
	CPI CONT_H, 0x06 ;Es septima columna (col 6)
	BRNE no_es_seis
	;LDI R20, 0b01101000 ;Pruebas
	;LDI R21, 0b10010000 ;Pruebas
	;LDI R22, 0b00000000 ;Pruebas
	JMP leo_tipo_2A
no_es_seis:
	CPI CONT_H, 0x07 ;Es octava columna (col 7)
	BRNE no_es_siete
	;LDI R20, 0b00101110 ;Pruebas
	;LDI R21, 0b01111000 ;Pruebas
	;LDI R22, 0b00000000 ;Pruebas
	JMP leo_tipo_2B
no_es_siete:
	CPI CONT_H, 0x08 ;Es novena columna (col 8)
	BRNE no_es_ocho
	;LDI R20, 0b10000001 ;Pruebas
	;LDI R21, 0b11011000 ;Pruebas
	;LDI R22, 0b10001000 ;Pruebas
	JMP leo_tipo_1A
no_es_ocho:
	CPI CONT_H, 0x09 ;Es decima columna (col 9) 
	BRNE no_es_nueve
	;LDI R20, 0b01111010 ;Pruebas
	;LDI R21, 0b11101101 ;Pruebas
	;LDI R22, 0b00110000 ;Pruebas
	JMP leo_tipo_1B
no_es_nueve:
	CPI CONT_H, 0x0A ;Es onceava columna (col 10) 
	BRNE no_es_diez
	;LDI R20, 0b01101000 ;Pruebas
	;LDI R21, 0b10000001 ;Pruebas
	;LDI R22, 0b11010000 ;Pruebas
	JMP leo_tipo_2A
no_es_diez:
	CPI CONT_H, 0x0B ;Es doceava columna (col 11) 
	BRNE no_es_once
	;LDI R20, 0b00101110 ;Pruebas
	;LDI R21, 0b01011101 ;Pruebas
	;LDI R22, 0b10101000 ;Pruebas
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
	

;*************************************************************************************************************
; ACÁ EMPIEZA LO REFERIDO A LA DECODIFICACIÓN QR
;LA REGLA ES: EL METODO DE BRCC HACE REFERENCIA AL ORDEN DE LECTURA (VER EXCEL), Y EL SBR HACE REFERENCIA AL BIT A SETEAR
;*************************************************************************************************************

;*************************************************************************************************************
;La columna tipo 1A tiene dos variantes, la primera es la que llega hasta la fila 12, la segunda finaliza en la 21
;*************************************************************************************************************
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
;*************************************************************************************************************
;Se terminó la lectura de la primera columna, acá se debería esperar a que se vuelvan a llenar R20, R21 y R22
;Si es tipo 1 C o D, debo seguir guardando en el acumulador el bit vertical, sino salto al final
;*************************************************************************************************************
chequeo_fila:	
	CPI CONT_H, 0x08
	BRNE fin_columna1
;*************************************************************************************************************
;ESTA PARTE CORRESPONDE A SI LA COLUMNA ES LA NUMERO 8
;HAY QUE HACER OTRAS COSAS CON LOS ACUMULADORES
;*************************************************************************************************************
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
	;JMP decodificar_linea
	RET
;*************************************************************************************************************
;SEGUNDO METODO DE LECTURA
;*************************************************************************************************************
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
;*************************************************************************************************************
;ESTA PARTE CORRESPONDE A SI LA COLUMNA ES LA NUMERO 9
;HAY QUE HACER OTRAS COSAS CON LOS ACUMULADORES
;*************************************************************************************************************
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
;*************************************************************************************************************
;Se terminó la lectura de la columna, ahora hay que guardar los valores leidos en los acumuladores en SRAM	
;Guardo los valores que ya fueron completados en memoria ram.
;Acá reviso que no esté en tipo 1 sección D
;*************************************************************************************************************
fin_columna2:
	CPI CONT_H, 0x01 ;Si es la segunda columna, tengo que guardar acum2 en length, sino en sram
	BRNE guardo_en_ram
	MOV LENGTH, ACUM2
	;; ADD LENGTH, CANT_LETRAS_LEIDAS ;Como las letras empiezan a partir de la 3ra letra, tengo que hacer esta maniobra para luego comparar
	INC LENGTH
	;; 	INC LENGTH
	;; 	INC LENGTH
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

	;JMP decodificar_linea
	RET
;*************************************************************************************************************
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
;*************************************************************************************************************
;Se terminó la lectura de la tercer columna, acá se debería esperar a que se vuelvan a llenar R20, R21 y R22
;Empiezo cuarta columna
;Reviso que no sea tipo 2 sección C
;*************************************************************************************************************
chequeo_fila3:	
	CPI CONT_H, 0xA
	BRNE fin_columna3
;*************************************************************************************************************
;ESTA PARTE CORRESPONDE A SI LA COLUMNA ES LA NUMERO 10
;HAY QUE HACER OTRAS COSAS CON LOS ACUMULADORES
;*************************************************************************************************************
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

	;JMP decodificar_linea
	RET
;*************************************************************************************************************
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
;*************************************************************************************************************
;Se terminó la lectura de la cuarta columna, acá se debería esperar a que se vuelvan a llenar R20, R21 y R22
;Empiezo quinta columna
;Reviso que no sea tipo 2 sección D
;*************************************************************************************************************
chequeo_fila4:	
	CPI CONT_H, 0x0B 
	BRNE fin_columna4
;*************************************************************************************************************
;ESTA PARTE CORRESPONDE A SI LA COLUMNA ES LA NUMERO 10
;HAY QUE HACER OTRAS COSAS CON LOS ACUMULADORES
;*************************************************************************************************************
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
	
	;JMP decodificar_linea
	RET
;*************************************************************************************************************
; MÉTODOS AUXILIARES
;*************************************************************************************************************	

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














	

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; DELAY CASERO

	
retardo_500ms:
	push r18
	eor  r18, r18
loop_retardo_500ms:
	rcall retardo_10ms
	inc r18
	cpi r18,40
	brne loop_retardo_500ms
	pop r18
	ret
	
retardo_10ms:
	push r19
	eor     R19, R19                ;1 CM
loop_retardo_10ms:
	rcall   retardo_100us           ;3 CM del rcall
	inc     r19                     ;1 CM
	cpi     r19,94                  ;1 CM
	brne    loop_retardo_10ms       ;2 CM
	pop r19
	ret            

	
retardo_100us:
	push r20
	eor     R20, R20                ;1 CM
loop_retardo_100us:
	inc     r20                     ;1 CM
	cpi     r20,24                  ;1 CM
	brne    loop_retardo_100us      ;2 CM 
                                ;1 CM El brne suma 1CM cuando es verdadero
	pop r20
	ret                             ;4 CM


delay_calibracion:
	push r16
	eor r16,r16
loop_delay_calibracion:
	rcall retardo_100us
	inc r16
	cpi r16,60
	brne loop_delay_calibracion
	pop r16
	ret
