#include <Modulino.h>
#include "WiFiS3.h"
#include <Firebase.h>
#include "secrets.h"

ModulinoThermo thermo;
ModulinoBuzzer buzzer;

int frequency = 440;
int duration = 1000;

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
  buzzer.begin();c:\Users\Sergio\Desktop\git\temperature_app\arduino_code\temp\secrets.h
}

void loop() {

    float celsius = thermo.getTemperature();
    float humidity = thermo.getHumidity();

    fb.setFloat("sensors/temperature", celsius); // Establece el valor de temperatura en Firebase
    fb.setFloat("sensors/humidity", humidity); // Establece el valor de humedad en Firebase

    // if(humidity >= 60){
    //   buzzer.tone(frequency, duration);
    //   delay(500);
    //   // buzzer.tone(0, duration);
    //   buzzer.noTone();
    //   // delay(1000);
    // }

}
