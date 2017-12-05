
	;; USO DEL SENSOR DE LUZ PARA DETECTAR PUNTOS BLANCOS Y NEGROS.	
	;; CONECTAR LA SALIDA DEL SENSOR AL PIN 24 (ADC0 O PC1) DEL MICRO.
	
.include "m328Pdef.inc"
	
.def POS = r0
.def CANT = r1
.def SIZE = r2
.def RESTO = r3
.def REGH = r4		;Buffer para guardar los bits leídos
.def REGL = r5
.equ SCANNER = GPIOR0
.equ COLOR = 1		; Negro=1, Blanco=0
.equ CAMBIO_COLOR = 2
.equ FIN_PAGINA = 3
.equ DIRECCION = 4

;; Tabla donde se guardan los bits de la matriz
.dseg
matriz_leida:	.byte 56

.cseg	
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
	sbi DDRD,7		;Output=D7
	cbi DDRC,1		;Input_ADC=C1
	cbi DDRC,4		;Input_encoder_trolley=C4
	;; Configuración ADC
	ldi r16,(0<<REFS1)||(1<<REFS0)||(0<<ADLAR)||0x01			;Referencia=VCC. Entrada=ADC1=PC1.
	sts ADMUX,r16								;Ajustado a izquierda
	eor r16,r16
	ldi r16,(1<<ADEN)||(1<<ADSC)||(1<<ADATE)||(1<<ADIE)||0x07 		;Habilitar ADC. Habilitar interrupcion.
	sts ADCSRA,r16								;Prescaler=ck/128.Comenzar lectura.


	;; Comienza el programa encendiendo los motores. Esto se haría
	;; con una interrupción por bluetooth en el programa final.
	;; Por eso, la función encender_motor no hace nada.
	rcall encender_motor
	
	;; Loop principal. POS es un número que representa la posición
	;; del carrito desde el último cambio de color. Para incrementar
	;; el valor de POS leo por flanco ascendente el encoder del motor,
	;; una vez que éste empezó a andar. Mientras tanto, el loop se
	;; interrumpe cada vez que el ADC termina de convertir. En esa operación
	;; se modifican los flags del registro I/O SCANNER: CAMBIO_COLOR, COLOR,
	;; FIN_PAGINA y cuando se vuelve al loop se chequea el estado de cada uno.
while_1:
	eor POS,POS
	eor RESTO,RESTO		;RESTO y CANT son registros auxiliares para calcular los bits leídos.
	eor CANT,CANT			
keep_polling:				
	sbis PINC,4			
	rjmp keep_polling		
	inc POS				
chequear_cambio_color:			
	sbic SCANNER,CAMBIO_COLOR
	rcall calcular_bits_leidos
	sbic SCANNER,FIN_PAGINA
	rcall configurar_motores
	rjmp while_1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Función de encendido de motores
encender_motor:
	ret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Función para calcular cuántos bits hay entre un cambio de color y otro.
calcular_bits_leidos:
	push r16		;Se guarda el color leído en el bit T del SREG
	push r17
	in r16,SCANNER		
	bst r16,COLOR		
	mov RESTO,POS		; Para obtener la cantidad de bits del mismo color que se leyó se hace la división 
sigo_dividiendo:		; entre la posición (POS) y el tamaño (SIZE) de cada bit.
	sub RESTO,SIZE
	inc CANT
	cp RESTO,SIZE
	brsh sigo_dividiendo
	lsr POS			; POS=POS/2 Esto es para hacer redondeo simétrico.
	cp SIZE,POS
	brsh guardar_datos
	inc CANT
	mov POS,CANT
guardar_datos:
	mov r17,CANT
	cpi r17,9
	brsh guardar_en_dos_bytes
guardar_en_un_byte:
	bld REGL,0
	lsl REGL
	dec CANT
	brne guardar_en_un_byte
guardar_en_SRAM:
	mov CANT,POS
	;;HASTA AHORA TENEMOS DOS REGISTROS, REGH Y REGL, DONDE ESTÁN GUARDADOS
	;;LOS BITS QUE SE LEYERON. COMO EL NÚMERO DE BITS QUE SE GUARDAN EN
	;;ESTOS REGISTROS NO ES FIJO, TENEMOS TAMBIÉN UN REGISTRO, CANT, QUE
	;;TIENE EL NÚMERO DE BITS GUARDADOS.
	;;AHORA, TENEMOS QUE PASAR ESOS BITS A LA SRAM, SIN DEJAR ESPACIOS
	;;CADA VEZ QUE COPIO DESDE LOS REGISTROS. COMO HACEMOS??
	pop r16
	pop r17
	ret
	
guardar_en_dos_bytes:
	bld REGH,0
	lsl REGH
	dec CANT
	mov r17,CANT
	cpi r17,8
	breq guardar_en_un_byte
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	
configurar_motores:
	rjmp while_1
	



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Rutina de interrupción del ADC. El pin configurado como adc lee
;; la luz que llega del sensor y en base al nivel de tensión leído,
;; determina si está leyendo el color blanco, el negro, o si llegó
;; al final de la página. Se reservó un registro I/O de uso
;; general, SCANNER, y se definieron los flags CAMBIO_COLOR, COLOR,
;; y FIN_PAGINA.
	
adc_interrupt:
	push r16
	push r17
	lds r16,ADCL
	lds r17,ADCH
comparar_con_umbral:
	cpi r17,0x00
	breq fin_de_pagina	;Si pasa esto, llegó al final de la página
	cpi r17,0x02
	breq chequear_blanco	;Si pasa esto, veo si es blanco
	cpi r17,0x03
	breq chequear_negro	;Si pasa esto, veo si es negro
	pop r16			;Si llegó hasta acá, estoy leyendo ruido
	pop r17
	reti
	
fin_de_pagina:			;Aviso que llegó al final de la página seteando el bit FIN_PAGINA
	sbi SCANNER,FIN_PAGINA
	pop r16
	pop r17
	reti

chequear_blanco:
	cpi r16,0x7d		;Umbral posible para el blanco
	brlo es_blanco
	pop r16
	pop r17
	reti
es_blanco:
	sbic SCANNER,COLOR
	sbi SCANNER,CAMBIO_COLOR
	cbi SCANNER,COLOR
	pop r16
	pop r17
	reti

chequear_negro:
	cpi r16,0x32		;Umbral posible para el negro
	brsh es_negro
	pop r16
	pop r17
	reti
es_negro:
	sbis SCANNER,COLOR
	sbi SCANNER,CAMBIO_COLOR
	sbi SCANNER,COLOR
	pop r16
	pop r17
	reti
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

