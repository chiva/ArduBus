/*
    ArduBus is an Arduino program that eases the task of interfacing
    a new I2C chip by using custom commands, so no programming is
    required.
    Copyright (C) 2010 Santiago Reig
    
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    I2C Wushu is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with ArduBus.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <Wire.h>
#define BUFFSIZ 50                     //Tamaño del buffer del puerto serie lo suficientemente grande
#define BAUD 9600                      //Velocidad puerto serie
boolean error;
boolean echo = true;                   //Hacer echo de la entrada del puerto serie
boolean debug = false;                 //Activar mensajes de depuracion
char buffer[BUFFSIZ];                  //Almacen de la cadena de entrada por puerto serie
char *parseptr;                        //Puntero para recorrer el vector

void setup()
{
  Serial.begin(BAUD);                                            //Iniciamos el puerto serie
  Wire.begin();                                                  //Iniciamos el bus I2C
  
  Serial.println("");                                            //Mensaje de bienvenida
  Serial.println("ArduBus v0.3 BETA");
  Serial.println("KungFu Labs - http://www.kungfulabs.com");
  Serial.println("ArduBus Copyright (C) 2010 Santiago Reig");
  Serial.println("");
  Serial.println("202 I2C READY");
  Serial.println("205 I2C PULLUP ON");
}

void loop()
{
  error = false;                                                 //Limpimos la bandera de error
  parseptr = buffer;
  Serial.print("I2C>");                                          //Escribimos el 'prompt'
  readString();                                                  //Leemos el comando escrito a traves del puerto serie
  startWork();                                                   //Ejecutamos las acciones indicadas
}

void readString() {
  char c;
  int buffSize = 0;
  
  Serial.flush();
  while (true) {
      while (Serial.available() == 0);                           //Esperamos a que llegue otro caracter
      c=Serial.read();
      if (c == 127){
        if (buffSize != 0){                                      //Si borramos un caracter, retrocedemos una posicion
          buffSize--;                                            //Evitamos crear valores negativos
          if (echo){
            Serial.print(c);
          }
        }
        continue;
      }
      if (echo){                                                 //Hacemos echo
        if (c == '\r') Serial.println();                         //Iniciamos una nueva linea
        else Serial.print(c);
      }
      if ((buffSize == BUFFSIZ-1) || (c == '\r')) {              //Leemos hasta detectar el intro
        buffer[buffSize] = 0;                                    //En la ultima posicion escribimos un 0 para definir el final de la cadena
        return;
      }
      buffer[buffSize++] = c;                                    //Guardamos el caracter recibido
  }
}

void startWork(){
  byte address,data,nReads;
  
  if (parseptr[0] == 'E'){                                       //Comando de ECHO
    echo = !echo;
    if (echo) Serial.println("Echo activado");
    else Serial.println("Echo desactivado");
    return;
  }
  else if (parseptr[0] == 'D'){                                  //Comando de DEBUG
    debug = !debug;
    if (debug) Serial.println("Debug activado");
    else Serial.println("Debug desactivado");
    return;
  }
  while (parseptr[0] == '{'){                                    //Mientras haya un comando nuevo...
    parseptr++;                                                  //Avanzamos para analizar el siguiente caracter
    if (debug){
      Serial.print("Analizando cadena: ");
      Serial.println(buffer);
    }
    Serial.println("210 I2C START CONDITION");
    address = parseArgument();                                   //El primer argumento es la direccion
    if (error){
          Serial.println("\r\n--SYNTAX ERROR--");
          return;
    }
    if (parseptr[1] != 'r' && parseptr[2] != 'r'){               //Si el siguiente (r) o el segundo caracter (0r), contando el espacio, es una 'r', modo lectura
      Wire.beginTransmission(address);                           //Abrimos comunicaciones con el esclavo
      Serial.print("220 I2C WRITE: 0x");
      Serial.println(address,HEX);
      while (parseptr[0] != '}' && parseptr[0] != 0){            //Vamos escribiendo datos hasta encontrar la llave de final de comando o se acabe el vector
        data = parseArgument();                                  //Cojemos el valor del dato analizando la cadena de texto
        if (error){
          Wire.endTransmission();
          Serial.println("\r\n--SYNTAX ERROR--");
          return;
        }
        Wire.send(data);                                         //Enviamos dato
        Serial.print("220 I2C WRITE: 0x");
        Serial.println(data,HEX);
      }
      Wire.endTransmission();                                    //Una vez ya escrito todo, finalizamos la conexión
      Serial.println("240 I2C STOP CONDITION");
      parseptr++;
    }
    else {
      nReads = parseArgument();                                  //Leemos el numero de bytes que se quieren leer
      if (error){
        Serial.println("\r\n--SYNTAX ERROR--");
        return;
      }
      Wire.requestFrom(address,nReads);                          //Pedimos los datos al esclavo
      while(Wire.available())                                    //Según los recibimos los vamos escribiendo
      {                                                          //POSIBLE BUG: se lea mas rapido que se recibe y salga del bucle, hacer bucle for con nReads
        Serial.print("230 I2C READ: 0x");
        Serial.println(Wire.receive(),HEX);
      }
      Serial.println("240 I2C STOP CONDITION");
    }
  }
}

byte parseArgument(){
  byte argument;
  
  if (parseptr[0] == ' ' || parseptr[0] == '{' || parseptr[0] == '}'){ //Si detectamos uno de los caracteres los obviamos, ya que las acciones ya se han hecho
    if (debug) Serial.println("Detectado espacio/llave");
    parseptr++;
  }
  if (parseptr[0] >= '1' && parseptr[0] <= '9'){                 //Deteccion para decimales tipo: '15'
    if (debug) Serial.print("Detectado #dec");
    argument = parseDec();
  }
  else if (parseptr[0] == '0'){
    parseptr++;
    if (parseptr[0] == ' ' || parseptr[0] == '}' || parseptr[0] == 0) argument = 0; //Si hay un 0 seguido de uno de esos caracteres, es que es un 0 decimal, no 0xYY,0bYYYYY,...
    else if (parseptr[0] == 'x' || parseptr[0] == 'h'){
      parseptr++;
      if (debug) Serial.print("Detectado #hex");                 //Deteccion para hexadecimales tipo: '0x4F'
      argument = parseHex();
    }
    else if (parseptr[0] == 'b'){
      parseptr++;
      if (debug) Serial.print("Detectado #bin");                 //Deteccion para binarios tipo: '0b110101'
      argument = parseBin();
    }
    else if (parseptr[0] == 'd'){
      parseptr++;
      if (debug) Serial.print("Detectado #dec");                 //Deteccion para decimales tipo: '0d15'
      argument = parseDec();
    }
    else if (parseptr[0] == 'r'){
      parseptr++;
      if (debug) Serial.print("Detectado #read");
      argument = parseDec();                                     //Usamos parseDec ya que 0rXX es un numero decimal
    }
  }
  else if (parseptr[0] == 'r'){                                  //Contabilizacion cadena de 'r' tipo: 'rrrrrrr'
    if (debug) Serial.print("Detectado #read");
    argument = parseRead();
  }
  else{
    error=true;
    parseptr++;
  }
  return argument;
}

byte parseRead(){
  byte result = 0;
  
  while (parseptr[0] == 'r'){
    result++;
    parseptr++;
  }
  if (debug){
    Serial.print(" - 0r");                                       //Mostramos el valor convertido
    Serial.println(result,HEX);
  }
  return result;
}

byte parseHex(){                                                 //Convertimos de texto a numero hexadecimal
  byte result = 0;
  
  while (parseptr[0] != ' ' && parseptr[0] != '}' && parseptr[0] != 0){
    if (parseptr[0] >= '0' && parseptr[0] <= '9'){
      result *= 16;
      result += parseptr[0]-'0';
    }
    else if (parseptr[0] >= 'a' && parseptr[0] <= 'f'){
      result *= 16;
      result += parseptr[0]-'a'+10;
    }
    else if (parseptr[0] >= 'A' && parseptr[0] <= 'F'){
      result *= 16;
      result += parseptr[0]-'A'+10;
    }
    else return result;
    parseptr++;
  }
  if (debug){
    Serial.print(" - 0x");                                       //Mostramos el valor convertido
    Serial.println(result,HEX);
  }
  return result;
}

byte parseDec(){
  byte result = 0;
  
  while (parseptr[0] != ' ' && parseptr[0] != '}' && parseptr[0] != 0){
    if ((parseptr[0] < '0') || (parseptr[0] > '9'))
      return result;
    result *= 10;
    result += parseptr[0]-'0';
    parseptr++;
  }
  if (debug){
    Serial.print(" - 0x");                                       //Mostramos el valor convertido
    Serial.println(result,HEX);
  }
  return result;
}

byte parseBin(){
  byte result = 0;
  
  while (parseptr[0] != ' ' && parseptr[0] != '}' && parseptr[0] != 0){
    if ((parseptr[0] < '0') || (parseptr[0] > '1'))
      return result;
    result *= 2;
    result += parseptr[0]-'0';
    parseptr++;
  }
  if (debug){
    Serial.print(" - 0x");                                       //Mostramos el valor convertido
    Serial.println(result,HEX);
  }
  return result;
}
