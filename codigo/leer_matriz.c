
#include <stdlib.h>
#include <stdio.h>

typedef enum {false,true} bool;
typedef enum {subir,bajar} direccion;

static bool M[21][21] = {
    {1,1,1,1,1,1,1,0,0,0,1,0,1,0,1,1,1,1,1,1,1},
    {1,0,0,0,0,0,1,0,1,0,1,0,1,0,1,0,0,0,0,0,1},
    {1,0,1,1,1,0,1,0,1,0,1,1,0,0,1,0,1,1,1,0,1},
    {1,0,1,1,1,0,1,0,0,0,0,0,1,0,1,0,1,1,1,0,1},
    {1,0,1,1,1,0,1,0,1,1,1,1,1,0,1,0,1,1,1,0,1},
    {1,0,0,0,0,0,1,0,1,1,1,0,0,0,1,0,0,0,0,0,1},
    {1,1,1,1,1,1,1,0,1,0,1,0,1,0,1,1,1,1,1,1,1},
    {0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0},
    {1,1,0,1,0,0,1,1,0,0,1,1,1,0,1,1,1,0,1,1,0},
    {1,1,1,1,1,1,0,0,1,0,0,1,0,1,0,1,0,1,1,1,1},
    {0,1,1,0,0,0,1,1,0,1,1,1,0,0,1,1,1,1,1,0,1},
    {1,0,0,1,1,0,0,0,0,0,1,0,1,1,1,1,1,0,0,1,1},
    {0,1,1,0,1,1,1,1,0,0,1,1,0,1,1,1,0,0,1,0,0},
    {0,0,0,0,0,0,0,0,1,1,0,0,0,1,1,0,1,0,1,0,0},
    {1,1,1,1,1,1,1,0,1,1,0,1,1,0,1,0,1,1,0,1,0},
    {1,0,0,0,0,0,1,0,0,1,1,0,0,0,1,0,0,0,1,1,1},
    {1,0,1,1,1,0,1,0,0,0,0,0,1,1,1,0,0,0,1,1,1},
    {1,0,1,1,1,0,1,0,1,0,0,0,0,1,1,1,0,0,0,1,1},
    {1,0,1,1,1,0,1,0,0,1,1,1,0,1,1,1,0,1,1,0,1},
    {1,0,0,0,0,0,1,0,1,0,1,1,1,0,0,1,0,1,0,0,0},
    {1,1,1,1,1,1,1,0,1,0,1,0,0,1,0,1,0,0,1,1,0},
};


// Función que devuelve verdadero si estoy en la matriz y falso si no.
bool estoy_en_M(int i, int j, int p){ 
  if (i>=0 && i<p && j>=0 && j<p)
    return true;
  else
    return false;
}

// Función que devuelve verdadero si el bit en que estoy parado es parte de un caracter, y falso si no.
bool estoy_en_prohibido(int i, int j, int p){
  if(i>=0 && i<=8 && j>=0 && j<=8)
    return true;
  if(i>=0 && i<=8 && j<p && j>=p-8)
    return true;
  if(i<p && i>=p-8 && j>=0 && j<=8)
    return true;
  if(i==6 || j==6)
    return true;
  else
    return false;
}

// Función para recorrer la matriz. Va recorriendo en el orden que dice el código y
// usa las funciones anteriores para ver si el bit que está leyendo es parte de la
// información extra del código o de los caracteres a transmitir.
bool *recorrer_matriz(int p, bool *vec, int *largo){
  int i=20,j=20,k=0;
  int info_extra = (p-17)*2 + 9*9 + 9*8*2;
  direccion dir=subir;
  if( (vec=(bool *)malloc(sizeof(bool)*((p*p)-info_extra)))==NULL )
    return NULL;
  *largo = (p*p)-info_extra;

    while(!(i==0 && j==1)){

    if(j==6)
      j++;

    if(dir==subir){
      if(estoy_en_M(i-1,j,p)){
	if(!estoy_en_prohibido(i,j,p)){
	  vec[k] = M[i][j];
	  k++;}
	if(!estoy_en_prohibido(i,j-1,p)){
	  vec[k] = M[i][j-1];
	  k++;}
	i=i-1;}
      else{
	if(!estoy_en_prohibido(i,j,p)){
	  vec[k] = M[i][j];
	  k++;}
	if(!estoy_en_prohibido(i,j-1,p)){
	  vec[k] = M[i][j-1];
	  k++;}
	j=j-2;
	dir=bajar;}}
    else{
      if(estoy_en_M(i+1,j,p)){
	if(!estoy_en_prohibido(i,j,p)){
	  vec[k] = M[i][j];
	  k++;}
	if(!estoy_en_prohibido(i,j-1,p)){
	  vec[k] = M[i][j-1];
	  k++;}
	i=i+1;}
      else{
	if(!estoy_en_prohibido(i,j,p)){
	  vec[k] = M[i][j];
	  k++;}
	if(!estoy_en_prohibido(i,j-1,p)){
	  vec[k] = M[i][j-1];
	  k++;}
	j=j-2;
	dir=subir;}}}
    return vec;
}

  
int main(void){
  
  int p=21,cont=0,length=0,q=p*p;
  bool *vec=NULL;
  
  vec = recorrer_matriz(p,vec,&length);

  for(cont=0;cont<=length;cont++)
    printf("%d ",vec[cont]);
  printf("\n");

  return 0;
}
