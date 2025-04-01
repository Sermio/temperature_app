#include <Modulino.h>
#include "WiFiS3.h"
#include <Firebase.h>
#include "secrets.h"

ModulinoThermo thermo;

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
}

void loop() {

    float celsius = thermo.getTemperature();
    float humidity = thermo.getHumidity();

    fb.setFloat("sensors/temperature", celsius); // Establece el valor de temperatura en Firebase
    fb.setFloat("sensors/humidity", humidity); // Establece el valor de humedad en Firebase

}
