#include <Arduino.h>
#include "WiFi.h"
#include <HTTPClient.h>

// Pin defines
#define BUTTON1_PIN 19
#define BUTTON2_PIN 18
#define BUTTON3_PIN 5
#define BUTTON4_PIN 17
#define BLUELED_PIN 16

//#define GREENLED_PIN 2

//#define RGBLED_PIN 1

void autoSetUpWiFi();
void sendHTTPRequest(String endpointName);
void checkButtonPress(int buttonPin, String endpointName);



// CHANGE THESE TO YOUR NETWORK DETAILS
const char *ssid = "";
const char *password = "";
const int maxAttempts = 3;
const char *url = "http://IP_ADDRESS/laurenpanel/";

void setup()
{
  // put your setup code here, to run once:
  Serial.begin(115200);
  // Set WiFi to station mode and disconnect from an AP if it was previously connected
  WiFi.mode(WIFI_STA);
  WiFi.setHostname("FitzNet-Remote");
  autoSetUpWiFi();

  // Initialize button pins as INPUT_PULLUP
  pinMode(BUTTON1_PIN, INPUT_PULLUP);
  pinMode(BUTTON2_PIN, INPUT_PULLUP);
  pinMode(BUTTON3_PIN, INPUT_PULLUP);
  pinMode(BUTTON4_PIN, INPUT_PULLUP);

  // Initialize BLUELED_PIN as OUTPUT
  pinMode(BLUELED_PIN, OUTPUT);

  Serial.println("Fitz-OS is running");

}

void loop()
{
  // put your main code here, to run repeatedly:
  checkButtonPress(BUTTON1_PIN,"happy");
  checkButtonPress(BUTTON2_PIN,"sad");
  checkButtonPress(BUTTON3_PIN,"hungry");
  checkButtonPress(BUTTON4_PIN,"love");
  digitalWrite(BLUELED_PIN, LOW);

}

void checkButtonPress(int buttonPin, String endpointName) {
  if (digitalRead(buttonPin) == LOW) {
    Serial.print("Button ");
    Serial.print(buttonPin);
    Serial.println(" pressed");
    digitalWrite(BLUELED_PIN, HIGH);
    delay(200);
    sendHTTPRequest(endpointName);
  }
}

void sendHTTPRequest(String endpointName) {

  HTTPClient http;
  http.begin(url + endpointName);
  Serial.print("Sending HTTP request to: " + String(url + endpointName));
  int httpResponseCode = http.GET();
  Serial.print("HTTP Response code: ");
  Serial.println(httpResponseCode);
  http.end();
  digitalWrite(BLUELED_PIN, LOW);
}

void autoSetUpWiFi()
{
  WiFi.begin(ssid, password);
  Serial.println("Connecting to network: " + String(ssid));
  while (WiFi.status() != WL_CONNECTED)
  {
    // Print network and IP address
    Serial.println("Attempting to connect to network: " + String(ssid) + " ");
    delay(500);
    Serial.print(".");
  }
  Serial.println("");
  Serial.println("WiFi connected");
  Serial.println("IP address: ");
  Serial.println(WiFi.localIP());
}
