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



.org 0x0000
	rjmp inicio


.org INT_VECTORS_SIZE
	

inicio:
	;; INICIALIZACIÓN DEL SP
	ldi rtemp1,HIGH(RAMEND)			
	out sph,rtemp1				
	ldi rtemp1,LOW(RAMEND)			
	out spl,rtemp1

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
	ldi rtemp1,0x02
	mov CANT_LETRAS_LEIDAS, rtemp1
	ldi rtemp1,0x1A
	mov LENGTH, rtemp1 ;Inicializo el valor de length con la mayor cantidad de datos que puedo llegar a leer.


decodificacion_de_prueba:
	LDI R20, 0b00001100 ;Pruebas
	LDI R21, 0b10010011 ;Pruebas
	LDI R22, 0b11111000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b10001010 ;Pruebas
	LDI R21, 0b10101010 ;Pruebas
	LDI R22, 0b00001000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b01000101 ;Pruebas
	LDI R21, 0b01110010 ;Pruebas
	LDI R22, 0b11101000 ;Pruebas	
	rcall decodificar_linea
	LDI R20, 0b00110100 ;Pruebas
	LDI R21, 0b01101010 ;Pruebas
	LDI R22, 0b11101000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b00000001 ;Pruebas
	LDI R21, 0b00010010 ;Pruebas
	LDI R22, 0b11101000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b11010101 ;Pruebas
	LDI R21, 0b00111010 ;Pruebas
	LDI R22, 0b00001000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b10011001 ;Pruebas
	LDI R21, 0b00000011 ;Pruebas
	LDI R22, 0b11111000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b01100111 ;Pruebas
	LDI R21, 0b01001000 ;Pruebas
	LDI R22, 0b00000000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b10101010 ;Pruebas
	LDI R21, 0b00101011 ;Pruebas
	LDI R22, 0b10001000 ;Pruebas	
	rcall decodificar_linea
	LDI R20, 0b01110010 ;Pruebas
	LDI R21, 0b11110100 ;Pruebas
	LDI R22, 0b01010000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b11101000 ;Pruebas
	LDI R21, 0b11100111 ;Pruebas
	LDI R22, 0b10000000 ;Pruebas
	rcall decodificar_linea
	LDI R20, 0b00110001 ;Pruebas
	LDI R21, 0b01101001 ;Pruebas
	LDI R22, 0b00101000 ;Pruebas
	rcall decodificar_linea	
	LDI R20, 0b11111011 ;Pruebas
	LDI R21, 0b11101011 ;Pruebas
	LDI R22, 0b01010000 ;Pruebas
	rcall decodificar_linea		;CUANDO CORRA ESTA DECODIFICACION, VA A PONER EL CARACTER FIN



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
	BRNE FIN
	;LDI R20, 0b00101110 ;Pruebas
	;LDI R21, 0b01011101 ;Pruebas
	;LDI R22, 0b10101000 ;Pruebas
	JMP leo_tipo_2B
FIN:
	LDI ACUM1, CARACTER_FIN ;Guardo caracter de fin para luego saber hasta donde tengo que leer por bluetooth
	RCALL guardo_acum1
	LDI XL, LOW(INICIO_TABLA) ;Reinicio punteros
	LDI XH, HIGH(INICIO_TABLA)
	;; RJMP esperar_recibir_datos ;Me quedo esperando hasta que reciba la orden de transmitir datos
	RET

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
	ADD LENGTH, CANT_LETRAS_LEIDAS ;Como las letras empiezan a partir de la 3ra letra, tengo que hacer esta maniobra para luego comparar
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


