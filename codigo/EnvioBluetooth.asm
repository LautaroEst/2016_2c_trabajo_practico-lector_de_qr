.include "m328pdef.inc"
.include "macros.inc"

.equ    LED_PORT_DIR =  DDRB
.equ    LED_PORT     =  PORTB
.equ    LED_PIN      =  5
.equ	BAUD_RATE = 0x67 ;Este es el valor que debe ponerse para tener un baud rate de 9600, que es el que usa el hc 05.
.equ	INICIO_TABLA = 0x0100 ; 0x0060 es la posición inicial de la general purpose ram
.equ	CARACTER_FIN = '/' ;Caracter con el que terminará el código QR

.CSEG
	rjmp main

.ORG URXCaddr
	rjmp URX_INT_HANDLER ;Interrupción producida por la recepción de datos

.ORG UDREaddr
	rjmp udre_int_handler

;.ORG UTXCaddr
;	rjmp udre_int_handler ;Interrupciòn producida cuando se vacía el udr0

.ORG 50

;*****************************

main:
LDI R21, HIGH(RAMEND)
OUT SPH, R21
LDI R21, LOW(RAMEND)
OUT SPL, R21

;************************
; Configuro el puerto para que no quede el led al aire
;***********************
configure_ports:
	ldi     R20,0xFF
    out     LED_PORT_DIR,R20
    out     LED_PORT,R20
    cbi     LED_PORT,LED_PIN

configure_punteros:
	LDI R26, LOW(INICIO_TABLA)
	LDI R27, HIGH(INICIO_TABLA)

cargar_valores_en_tabla:
	LDI R20, 'H'
	ST X+, R20
	LDI R20, 'O'
	ST X+, R20
	LDI R20, 'L'
	ST X+, R20
	LDI R20, 'A'
	ST X+, R20
	LDI R20, '/'
	ST X, R20
	LDI R26, LOW(INICIO_TABLA)
	LDI R27, HIGH(INICIO_TABLA)

config_puerto_serie:
;LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<TXCIE0)|(1<<RXCIE0) ;habilito como transmisor, receptor y habilito interrupciones de recepcion finalizada y transmision finalizada
;LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<UDRIE0)|(1<<RXCIE0) ;habilito como transmisor, receptor y habilito interrupciones de recepcion y udr0 vacio
;LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<UDRIE0) ;habilito como transmisor, receptor y habilito interrupciones de recepcion y udr0 vacio
LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0) ;habilito como transmisor, receptor y habilito interrupciones de recepcion y udr0 vacio
;LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<TXCIE0)|(1<<RXCIE0)|(1<<UDRIE0) ;habilito como transmisor, receptor y habilito interrupciones de recepcion finalizada y transmision finalizada

STORE UCSR0B, R16

;********************************
; Setear el bit rxcie0 habilita la interrupción del flag rxc del ucsr0a.
; Al completar la recepcìón, rxc se setea a high.
; Si rxcie0 = 1, cambiar rxc a uno fuerza la interrupción.
;
; Setear el bit udrie0 (usart dara register empty interrupt enable.
; Cuando el udr0 esta listo para recibir nuevos datos, el UDRE (usart data register empty flag) se pone en 1.
; Si UDRIE0 = 1 y si se pone UDRE en 1, fuerza la interrupción.
;********************************

LDI R17, 0x00
LDI R16, (1<<UCSZ01)|(1<<UCSZ00)|(1<<UMSEL01) ;8 bit data, sin paridad y 1 bit de parada.
STORE UCSR0C, R16
LDI R16, BAUD_RATE ;9600 baud rate
STORE UBRR0L, R16
LDI R21, 0x00
SEI

WAIT_HERE:
	CPI  R21, 0x01 ; 0x01 = Recibi datos
	BREQ RECIBIR_DATOS
	RJMP WAIT_HERE

RECIBIR_DATOS:
	LOAD R17, UDR0 ;Levanto en R17 el valor recibido por puerto serie.
	CPI R17, 'r'
	BREQ ENVIAR_DATOS
	CPI R17, '1'
	BREQ PRENDER_LED
	CBI LED_PORT, LED_PIN
	LDI R21, 0x0
	RJMP WAIT_HERE

ENVIAR_DATOS:
	LD R17, X+
	CPI R17, CARACTER_FIN
	BREQ SALIR
	STORE UDR0, R17
	LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<UDRIE0)|(1<<RXCIE0)
	STORE UCSR0B, R16
	LDI R21, 0x00
	RJMP WAIT_HERE

UDRE_INT_HANDLER:
	LD R17, X+
	CPI R17, CARACTER_FIN
	BREQ SALIR
	STORE UDR0, R17
	LDI R21, 0x02
	RETI

URX_INT_HANDLER:
	LDI R21, 0x01
	RETI

SALIR:
	LDI R17, ' '
	STORE UDR0, R17
	LDI R26, LOW(INICIO_TABLA) ;Seteo el valor del puntero para que vuelva a enviar, sino se queda loco.
	LDI R27, HIGH(INICIO_TABLA)
	LDI R21, 0x00
	LDI R16, (1<<RXEN0)|(1<<TXEN0)|(1<<RXCIE0)
	STORE UCSR0B, R16
	RETI

PRENDER_LED:
	SBI LED_PORT, LED_PIN
	LDI R21, 0x00
	RJMP WAIT_HERE
