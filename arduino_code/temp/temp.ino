#include <Modulino.h>
#include "WiFiS3.h"
#include <Firebase.h>
#include "secrets.h"

ModulinoThermo thermo;
ModulinoBuzzer buzzer;

int frequency = 440;
int duration = 1000;

int humedadExtraPin = A0;  // Pin donde está conectado el sensor de humedad (puedes usar A1 u otro pin analógico libre)
int humedadExtra;          // Variable para almacenar el valor de humedad

WiFiServer server(80);
Firebase fb(REFERENCE_URL);

void setup() {

  Serial.begin(115200);
  delay(1000);

  // Conectar a WiFi
  while (WiFi.begin(WIFI_SSID, WIFI_PASSWORD) != WL_CONNECTED) {
    Serial.println("Conectando...");
    delay(1000);
  }

  Modulino.begin();
  thermo.begin();
  buzzer.begin();

  // Configurar el pin A1 (o el que hayas elegido) como entrada
  pinMode(humedadExtraPin, INPUT);
}

unsigned long lastAutoMeasurement = 0;
const unsigned long AUTO_MEASURE_INTERVAL = 3600000UL; // 1 hora en milisegundos (1 * 60 * 60 * 1000)

void loop() {
  unsigned long currentMillis = millis();

  // Comprobar si ha llegado el momento de medir
  bool shouldMeasure = (currentMillis - lastAutoMeasurement >= AUTO_MEASURE_INTERVAL) || (lastAutoMeasurement == 0);

  if (shouldMeasure) {
    // SIEMPRE reiniciar la conexión WiFi antes de medir para evitar conexiones fantasma (congelamiento)
    Serial.println("Reiniciando WiFi para asegurar conexion fresca con Firebase...");
    if (WiFi.status() == WL_CONNECTED) {
      WiFi.disconnect();
      delay(1000);
    }
    
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    
    // Esperar hasta 15 segundos a que conecte para no bloquear infinitamente
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 15) {
      delay(1000);
      attempts++;
      Serial.print(".");
    }
    Serial.println();

    // Solo procedemos si la conexión WiFi está activa
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nTomando medicion...");
      
      float celsius = thermo.getTemperature();
      float humidity = thermo.getHumidity();

      // Leer el valor del sensor ICQUANZX
      humedadExtra = analogRead(humedadExtraPin);

      // Convertir la lectura analógica del sensor ICQUANZX a un valor de humedad en porcentaje
      float humedadExtraPorcentaje = map(humedadExtra, 0, 1023, 100, 0); 

      fb.setFloat("sensors/temperature", celsius);
      fb.setFloat("sensors/humidity", humidity);
      fb.setFloat("sensors/humidityExtra", humedadExtraPorcentaje);
      fb.setInt("sensors/timestamp", currentMillis);

      Serial.print("Temperatura: ");
      Serial.print(celsius);
      Serial.print(" C, Humedad: ");
      Serial.print(humidity);
      Serial.print(" %, Humedad Extra (Suelo): ");
      Serial.print(humedadExtraPorcentaje);
      Serial.println(" %");

    } else {
      Serial.println("No se pudo conectar a WiFi. Se reintentará en el próximo ciclo.");
    }
    
    // Actualizamos el temporizador siempre, para no quedarnos en bucle infinito
    lastAutoMeasurement = currentMillis;
  }
  
  delay(1000); // Revisar el temporizador cada segundo
}


