.include "m328pdef.inc"
.include "macros.inc"

;*******************************************************************************************
; Bloque de definiciones
;*******************************************************************************************

.equ    LED_PORT_DIR =  DDRB
.equ    LED_PORT     =  PORTB
.equ    LED_PIN      =  5
.equ	BAUD_RATE = 0x67 ;Este es el valor que debe ponerse para tener un baud rate de 9600, que es el que usa el hc 05.
.equ	CARACTER_FIN = '/' ;Caracter con el que terminará el código QR

.equ CANTIDAD_COLUMNAS = 21
.equ CANTIDAD_FILAS = 21
.equ CANTIDAD_CELDAS = 255

.equ INICIO_TABLA = 0x0100 ;Inicio de la tabla donde guardare los valores en SRAM

;Bits a setear
.equ B7 = 0x80
.equ B6 = 0x40
.equ B5 = 0x20
.equ B4 = 0x10
.equ B3 = 0x08
.equ B2 = 0x04
.equ B1 = 0x02
.equ B0 = 0x01

.equ MASK_VALUE_R20 = 0b10101010
.equ MASK_VALUE_R21 = 0b10101001
.equ MASK_VALUE_R22 = 0b01010000

.def CONT_H = R16 ;Contador horizontal
.def MASCARA = R17

.DEF CANT_LETRAS_LEIDAS = R19 ;Cantidad de letras leidas para saber donde termina el mensaje
.DEF LENGTH = R31 ;Longitud del mensaje

.DEF FLAG = R21

.def ACUM1 = R23 ;La idea de estos acumuladores es ir sosteniendo los valores ya procesados, que luego se meteran en SRAM
.def ACUM2 = R24 ;Uso dos ya que tengo que mantener lo que leo porque cada letra son 2 pasadas de columna
.def ACUM3 = R25
.def ACUM4 = R28
.def ACUM5 = R29
.def ACUM6 = R30

;*******************************************************************************************
; Fin bloque de definiciones
;*******************************************************************************************

;*******************************************************************************************
; Bloque de Interrupciones
;*******************************************************************************************
.CSEG
	rjmp main

.ORG URXCaddr
	rjmp URX_INT_HANDLER ;Interrupción producida por la recepción de datos

.ORG UDREaddr
	rjmp udre_int_handler

.ORG 50

;*******************************************************************************************
; Fin bloque de Interrupciones
;*******************************************************************************************


;*******************************************************************************************
; Inicio del programa
; COMO USAR:
; Luego de configurar todo inicialmente, debe quedar al inicio del programa loopeando en
; WAIT_HERE. Acá, se queda esperando a recibir una orden desde el puerto serie.
; Una vez que desde el bluetooth se envía el valor 1, se debe de iniciar el funcionamiento
; de los motores.
; Cada vez que lee una línea del QR, debe de llamar al método "decodificar_linea", el cual
; se irá encargando de setear los acumuladores.
; Una vez que la lectura llegó a la última columna que debe de ser leída, seteará los punteros
; y volvera a WAIT_HERE, esperando que se reciba la orden de enviar datos desde el micro.
;*******************************************************************************************

main:
	LDI R21, HIGH(RAMEND)
	OUT SPH, R21
	LDI R21, LOW(RAMEND)
	OUT SPL, R21

;*******************************************************************************************
; Configuro el puerto para que no quede el led al aire
;*******************************************************************************************
configure_ports:
	ldi     R20,0xFF
    out     LED_PORT_DIR,R20
    out     LED_PORT,R20
    cbi     LED_PORT,LED_PIN

config_puerto_serie:
	LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;habilito como transmisor, receptor y habilito interrupciones de recepcion
	STORE UCSR0B, R16
;*******************************************************************************************
; Setear el bit rxcie0 habilita la interrupción del flag rxc del ucsr0a.
; Al completar la recepcìón, rxc se setea a high.
; Si rxcie0 = 1, cambiar rxc a uno fuerza la interrupción.
;
; Setear el bit udrie0 (usart dara register empty interrupt enable.
; Cuando el udr0 esta listo para recibir nuevos datos, el UDRE (usart data register empty flag) se pone en 1.
; Si UDRIE0 = 1 y si se pone UDRE en 1, fuerza la interrupción.
;*******************************************************************************************
	LDI R17, 0x00
	LDI R16, (1<<UCSZ01)|(1<<UCSZ00)|(1<<UMSEL01) ;8 bit data, sin paridad y 1 bit de parada.
	STORE UCSR0C, R16
	LDI R16, BAUD_RATE ;9600 baud rate
	STORE UBRR0L, R16
	LDI R21, 0x00
	SEI

configure_punteros:
	LDI R26, LOW(INICIO_TABLA)
	LDI R27, HIGH(INICIO_TABLA)

;Inicializo registros
seteo_registro:
	EOR CONT_H, CONT_H
	EOR ACUM1, ACUM1
	EOR ACUM2, ACUM2
	EOR ACUM3, ACUM3
	EOR ACUM4, ACUM4
	EOR ACUM5, ACUM5
	EOR ACUM6, ACUM6
	LDI CANT_LETRAS_LEIDAS, 0x02
	LDI LENGTH, 0x1A ;Inicializo el valor de length con la mayor cantidad de datos que puedo llegar a leer.

;********************************************BLUETOOTH*********************************************************
; ESTA PARTE CORRESPONDE TODO A BLUETOOTH
; Funcionamiento: Se queda esperando en WAIT_HERE a que reciba un dato. Cuando esto pasa, salta la interrupción
; URX (se recibió un dato), la cual setea R21 en 1.
; El UDR0 va a tener el dato recibido por bluetooth, el cual puede ser el caracter 'r' si es que debe de enviar
; datos el micro, o '1' si debe encender el motor. En otro caso, apaga el motor.
; Si se solicita el envio de datos desde el micro, se carga en R17 el primer valor cargado en sram, incrementa
; el puntero, carga el valor en el UDR0, y setea la interrupción de UDR0 vacío. A partir de esto, cada vez que
; salta la interrupción, se irá cargando el UDR0 y se ira vaciando a medida que se envían los datos. 
; Una vez que en SRAM llega al caracter de fin, setea la interrupción por UDR0 vacío a 0 y vuelve a funcionar
; normalmente.
; 
; Registros involucrados:
; - R16: registro para configurar datos.
; - R17: se utiliza como almacenador de UDR0 y de puntero.
; - R21: se utiliza como flag para saber si se recibieron datos.
; - R26 y R27: puntero a sram.
;
; Registros que no deben de tocarse en el resto del código: ninguno.
; Se debe de tener en cuenta que mientras esta parte del programa está corriendo, no debe de alterarse ninguno
; de estos registros con interrupciones.
;*************************************************************************************************************

;RJMP decodificar_linea ;VOLAR ESTA LINEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA la uso para probar

;Loopea acá 
WAIT_HERE:
	CPI  FLAG, 0x01 ; 0x01 = Recibi datos
	BREQ RECIBIR_DATOS
	RJMP WAIT_HERE 

;Recibo el dato desde bluetooth.
RECIBIR_DATOS:
	LOAD R17, UDR0 ;Levanto en R17 el valor recibido por puerto serie.
	CPI R17, 'r' ;La app envía el caracter 'r' si solicita recibir datos. En caso de ser así, va a ENVIAR_DATOS
	BREQ ENVIAR_DATOS
	CPI R17, '1' ;La app envía el caracter '1' si desea encender motores.
	BREQ PRENDER_LED
	CBI LED_PORT, LED_PIN
	LDI FLAG, 0x0
	RJMP WAIT_HERE

ENVIAR_DATOS:
	LD R17, X+
	CPI R17, CARACTER_FIN ;Revisa que el caracter a enviar no sea el último
	BREQ SALIR
	STORE UDR0, R17 ;Carga en UDR0 el valor a enviar
	LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<UDRIE0)|(1<<RXCIE0) ;Habilita la interrupción de UDRE0 vacío
	STORE UCSR0B, R16 ;Carga el valor de la configuración
	LDI R16, 0x00
	LDI FLAG, 0x00
	RJMP WAIT_HERE ;Vuelve a wait_here

;Inmediatamente llama a la interrupción de UDRE0 vacío.
UDRE_INT_HANDLER:
	LD R17, X+
	CPI R17, CARACTER_FIN
	BREQ SALIR
	STORE UDR0, R17 ;Ya envió dato y puede recibir el siguiente (ya que se vacía una vez que envió el dato).
	LDI FLAG, 0x02 ;Seteo el flag para que envíe hasta llegar al caracter de fin.
	RETI

URX_INT_HANDLER:
	LDI FLAG, 0x01
	RETI

SALIR:
	LDI R17, ' '
	STORE UDR0, R17 ;Cargo este caracter para darle un cierre al mensaje.
	LDI R26, LOW(INICIO_TABLA) ;Seteo el valor del puntero para que vuelva a enviar, sino se queda loco.
	LDI R27, HIGH(INICIO_TABLA)
	LDI FLAG, 0x00
	LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;Deshabilito la interrupción de UDRE0 para que no enloquezca.
	STORE UCSR0B, R16
	LDI R16, 0x00
	RETI

PRENDER_LED:
	SBI LED_PORT, LED_PIN
	LDI FLAG, 0x00
	RJMP WAIT_HERE

;*************************************************************************************************************
; HASTA ACÁ LLEGA LO REFERIDO A LA LECTURA Y ESCRITURA BLUETOOTH
;*************************************************************************************************************

;***************************************IMPORTANTE************************************************************
; EXPLICACIÓN DE COMO LLAMAR A LA DECODIFICACIÓN QR
; Se debe de llamar al método decodificar_linea una vez que se termina de leer una línea de código con el
; escanner. Tener en cuenta de no pisar los registros fundamentales que utiliza para que no se pierda la información.
; Si se quieren hacer pruebas, descomentar las líneas que tienen el comentario "Pruebas".
;
; Una vez que leyó todas las líneas, pasa a la parte bluetooth y se quueda esperando para enviar datos. Luego de
; reiniciar los punteros.
;*************************************************************************************************************


;********************************************DECODIFICACION QR************************************************
; ESTA PARTE CORRESPONDE TODO A DECODIFICACIÓN QR
; Funcionamiento: a través de una variable de control CONT_H, va barriendo los bits leidos del código escanneado,
; el cual se va depositando en R20 (bits 0 a 7), R21 (bits 0 a 7) y R22 (bits 0 a 4).
; Va rolleando los distintos registros secuencialmente, y de acuerdo al valor del carry, y de que letra del código
; esté leyendo, va seteando los valores en los distintos acumuladores.
; CONT_H es quien controla donde se debe de cortar la lectura para luego guardar estos valores en SRAM.

; Ejemplo de funcionamiento: línea 1, rollea R20 a izquierda. Si el carry es 1, setea acum1.7, sino sigue.
; Vuelve a rollear R20, de acuerdo a C, setea Acum3.5. Rollea otra vez, si C = 1, setea Acum2.7 (segunda letra),
; y así sucesivamente.
; Luego pasa a la columna 2, una vez que la finaliza, guarda los valores de ACUM1, ACUM2 Y ACUM3 en SRAM 
; (tener en cuenta que las primeras dos columnas son distintas, entonces va a omitir los caracteres correspondientes
; al encoding y al length. A su vez, el length del código lo almacena en la variable LENGTH, la cual se utilizará como 
; comparador para saber cuando finalizó el mensaje.
; Algunos acumuladores quedan completos luego de la lectura de 4 columnas y no de dos, los mismos se almacenan durante
; mas tiempo. Una vez que cada acumulador se guarda en SRAM, se inicializa en 0.
; Para las columnas 9 a 12, en vez de leer los bytes horizontales, lee los verticales reutilizando el código ya programado,
; a excepción del ACUM6.
; 
; Registros involucrados:
; R14: Se utiliza para guardar los valores que posteriormente se almacenarán en SRAM.
; R16: CONT_H, es el contador horizontal. Variable principal de control
; R17: MASCARA, este registro se va a utilizar para aplicar la máscara cargada
; R19: CANT_LETRAS_LEIDAS, este registro lleva un conteo de la cantidad de las letras leidas para luego comparar con
; R26 y R27: Variables para punteros.
; R31 (LENGTH) para saber cuando finaliza el mensaje.
; R23, R24, R25, R28, R29, R30: ACUMx respectivamente (del 1 al 6).
;
; Registros que no deben de tocarse en el resto del código: 
; R16: INTOCABLE, es fundamental.
; R19: Cantidad de letras leidas, sabe cuando finaliza el código y no lee más.
; R23, R24, R25, R28, R29, R30 : los acumuladores, si se tocan se pierde el mensaje.
; R31: Length del código, tampoco debe de ser tocado.
;*************************************************************************************************************

;Veo en que columna estoy parado y en base a eso llamo al método para decodificar
decodificar_linea:

    CP LENGTH, CANT_LETRAS_LEIDAS
	BREQ salto_a_fin
enmascaro:
	LDI MASCARA, MASK_VALUE_R20
	EOR R20, MASCARA
	LDI MASCARA, MASK_VALUE_R21
	EOR R21, MASCARA
	LDI MASCARA, MASK_VALUE_R22
	EOR R22, MASCARA
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
	LDI R26, LOW(INICIO_TABLA) ;Reinicio punteros
	LDI R27, HIGH(INICIO_TABLA)
	RJMP WAIT_HERE ;Me quedo esperando hasta que reciba la orden de transmitir datos

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
	RETI

;Guarda ACUM2 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum2:
	MOV R14, ACUM2
	ST X+, R14
	EOR ACUM2, ACUM2
	INC CANT_LETRAS_LEIDAS
	RETI

;Guarda ACUM3 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum3:
	MOV R14, ACUM3
	ST X+, R14
	EOR ACUM3, ACUM3
	INC CANT_LETRAS_LEIDAS
	RETI

;Guarda ACUM4 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum4:
	MOV R14, ACUM4
	ST X+, R14
	EOR ACUM4, ACUM4
	INC CANT_LETRAS_LEIDAS
	RETI

;Guarda ACUM5 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum5:
	MOV R14, ACUM5
	ST X+, R14
	EOR ACUM5, ACUM5
	INC CANT_LETRAS_LEIDAS
	RETI

;Guarda ACUM6 en SRAM, lo limpia e incrementa la cantidad de letras leidas.
guardo_acum6:
	MOV R14, ACUM6
	ST X+, R14
	EOR ACUM6, ACUM6
	INC CANT_LETRAS_LEIDAS
	RETI


