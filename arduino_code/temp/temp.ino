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

void loop() {
  Serial.print("-");

    float celsius = thermo.getTemperature();
    float humidity = thermo.getHumidity();

    // Leer el valor del sensor ICQUANZX
    humedadExtra = analogRead(humedadExtraPin);

    // Convertir la lectura analógica del sensor ICQUANZX a un valor de humedad en porcentaje
    float humedadExtraPorcentaje = map(humedadExtra, 0, 1023, 100, 0); 

    fb.setFloat("sensors/temperature", celsius); // Establece el valor de temperatura en Firebase
    fb.setFloat("sensors/humidity", humidity); // Establece el valor de humedad en Firebase
    fb.setFloat("sensors/humidityExtra", humedadExtraPorcentaje); // Establece el valor de humedad extra en Firebase

    Serial.print("Humedad: ");
    Serial.println(humedadExtraPin); 

    // if(humidity >= 60){
    //   buzzer.tone(frequency, duration);
    //   delay(500);
    //   // buzzer.tone(0, duration);
    //   buzzer.noTone();
    //   // delay(1000);
    // }

}
