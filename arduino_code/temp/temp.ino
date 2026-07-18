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
const unsigned long AUTO_MEASURE_INTERVAL = 14400000UL; // 4 horas en milisegundos (4 * 60 * 60 * 1000)

void loop() {
  unsigned long currentMillis = millis();
  
  // Leer el disparador de Firebase (asumiendo getBool o getInt)
  // Intentamos obtener el valor del trigger. Si es 1 o true, disparamos la medición.
  int trigger = 0;
  fb.getInt("commands/trigger_measurement", trigger); 
  
  bool shouldMeasure = (trigger == 1) || (currentMillis - lastAutoMeasurement >= AUTO_MEASURE_INTERVAL) || (lastAutoMeasurement == 0);

  if (shouldMeasure) {
    Serial.println("\nTomando medicion...");
    
    float celsius = thermo.getTemperature();
    float humidity = thermo.getHumidity();

    // Leer el valor del sensor ICQUANZX
    humedadExtra = analogRead(humedadExtraPin);

    // Convertir la lectura analógica del sensor ICQUANZX a un valor de humedad en porcentaje
    float humedadExtraPorcentaje = map(humedadExtra, 0, 1023, 100, 0); 

    fb.setFloat("sensors/temperature", celsius); // Establece el valor de temperatura en Firebase
    fb.setFloat("sensors/humidity", humidity); // Establece el valor de humedad en Firebase
    fb.setFloat("sensors/humidityExtra", humedadExtraPorcentaje); // Establece el valor de humedad extra en Firebase
    
    // Opcional: registrar una marca de tiempo en milisegundos del sistema para indicar que es una nueva lectura
    fb.setInt("sensors/timestamp", currentMillis);

    Serial.print("Temperatura: ");
    Serial.print(celsius);
    Serial.print(" C, Humedad: ");
    Serial.print(humidity);
    Serial.print(" %, Humedad Extra (Suelo): ");
    Serial.print(humedadExtraPorcentaje);
    Serial.println(" %");

    // Limpiar el trigger en Firebase
    if (trigger == 1) {
      fb.setInt("commands/trigger_measurement", 0);
    }
    
    lastAutoMeasurement = currentMillis;
  }
  
  delay(2000); // Esperar 2 segundos antes de volver a verificar el trigger
}

