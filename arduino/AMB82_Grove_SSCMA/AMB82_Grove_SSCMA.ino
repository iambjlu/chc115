#include <Arduino.h>
// AmebaPro2 4.0.3 macros conflict with the C++ headers used by SSCMA.
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif
// Arduino.h maps printf to dbg_printf, which breaks <cstdio>/<ostream> pulled in by ArduinoJson.
#ifdef printf
#undef printf
#endif
#ifdef sprintf
#undef sprintf
#endif
extern "C" int printf(const char *, ...);
extern "C" int sprintf(char *, const char *, ...);
#include <Seeed_Arduino_SSCMA.h>
#include "BLEDevice.h"

// ---- BLE：把雷達數據以 Notify 傳給 Flutter App（chc115）----
// App 會掃描 BLE_ADV_NAME 並訂閱 BLE_TX_UUID，每筆資料為一行 ASCII（7 欄）：
//   左後距離,右後距離,左後逼近,右後逼近,左前坑,正前坑,右前坑
//   距離：1=遠 2=中 3=近；逼近/坑：1=有 0=沒有；任何欄位 9=錯誤
//   例：3,1,1,0,1,0,1
#define BLE_ADV_NAME     "AMB82-Radar"
#define BLE_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_TX_UUID      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_BUF_SIZE     64
#define BLE_SEND_MS      1000

#if !defined(SERIAL_ONE_UART_MODIFIABLE_BAUD_RATE) || SERIAL_ONE_UART_MODIFIABLE_BAUD_RATE != 1
#error "AmebaPro2 4.0.3 needs the supplied platform.local.txt setting. Restart Arduino IDE after installing it."
#endif

void printHelp();
void connectGrove();
void inferOnce();

SSCMA ai;
bool connected = false;
bool serialStarted = false;
bool needsWarmup = true;
bool continuous = false;
unsigned long lastRun = 0;
unsigned long frameNumber = 0;

BLEService radarService(BLE_SERVICE_UUID);
BLECharacteristic radarTx(BLE_TX_UUID);
BLEAdvertData bleAdv;
BLEAdvertData bleScan;
bool bleNotifyOn = false;
uint8_t bleConnId = 0;
unsigned long lastBleSend = 0;
unsigned long simTick = 0;

void bleNotifyCallback(BLECharacteristic *chr, uint8_t connID, uint16_t cccd) {
  bleNotifyOn = (cccd & GATT_CLIENT_CHAR_CONFIG_NOTIFY) != 0;
  bleConnId = connID;
  Serial.print("BLE_NOTIFY ");
  Serial.println(bleNotifyOn ? "ON" : "OFF");
}

void setupBle() {
  bleAdv.addFlags(GAP_ADTYPE_FLAGS_LIMITED | GAP_ADTYPE_FLAGS_BREDR_NOT_SUPPORTED);
  bleAdv.addCompleteName(BLE_ADV_NAME);
  bleScan.addCompleteServices(BLEUUID(BLE_SERVICE_UUID));

  radarTx.setReadProperty(true);
  radarTx.setNotifyProperty(true);
  radarTx.setBufferLen(BLE_BUF_SIZE);
  radarTx.setCCCDCallback(bleNotifyCallback);
  radarService.addCharacteristic(radarTx);

  BLE.init();
  BLE.configAdvert()->setAdvData(bleAdv);
  BLE.configAdvert()->setScanRspData(bleScan);
  BLE.configServer(1);
  BLE.addService(radarService);
  BLE.beginPeripheral();
  Serial.println("BLE_ADVERTISING name=" BLE_ADV_NAME);
}

// 模擬數據：每秒推進一步，12 步一個循環，涵蓋各種 HUD 狀態。
// 之後接上真實感測（SSCMA 偵測框換算距離等）時，只要改這個函式。
void sendSimulatedRadar() {
  const unsigned long t = simTick++ % 12;
  const int leftDist = (t < 4) ? 1 : (t < 8) ? 2 : 3;      // 遠 -> 中 -> 近
  const int rightDist = 3 - (int)((t / 3) % 3);             // 近 -> 中 -> 遠
  const int leftApproach = (leftDist == 3) ? 1 : 0;
  const int rightApproach = (rightDist == 3) ? 1 : 0;
  const int potholeL = (t == 3) ? 1 : 0;
  const int potholeC = (t == 6 || t == 7) ? 1 : 0;
  const int potholeR = (t == 10) ? 1 : 0;

  char line[BLE_BUF_SIZE];
  snprintf(line, sizeof(line), "%d,%d,%d,%d,%d,%d,%d",
           leftDist, rightDist, leftApproach, rightApproach,
           potholeL, potholeC, potholeR);
  radarTx.writeString(line);
  radarTx.notify(bleConnId);
  Serial.print("BLE_SEND ");
  Serial.println(line);
}

void printHelp() {
  Serial.println("Grove SSCMA UART: i=connect, t=infer once, r=run, s=stop, h=help");
  Serial.println("PC=115200; Grove Serial1=921600; AMB82 TX21->RXD, RX22<-TXD.");
}

void connectGrove() {
  continuous = false;
  needsWarmup = true;
  if (!serialStarted) {
    connected = ai.begin(&Serial1, -1, 921600, 2);
    serialStarted = true;
  } else {
    // begin() would initialize the same Ameba UART pins again. Re-query
    // device identity instead, including after an earlier failed handshake.
    connected = ai.ID(false) && ai.name(false);
  }
  if (!connected) {
    Serial.println("SSCMA_CONNECT_FAILED: check Grove power/UART; send i to retry.");
    return;
  }
  Serial.print("SSCMA_CONNECTED id=");
  Serial.print(ai.ID());
  Serial.print(" name=");
  Serial.println(ai.name());
}

void inferOnce() {
  if (!connected) {
    Serial.println("NOT_CONNECTED: send i first.");
    return;
  }
  if (needsWarmup) {
    Serial.println("WARMUP: acquiring 10 frames before reporting detections.");
    for (int frame = 0; frame < 10; ++frame) {
      const int warmupResult = ai.invoke(1, true, false);
      if (warmupResult != CMD_OK) {
        continuous = false;
        Serial.print("WARMUP_FAILED library_code=");
        Serial.println(warmupResult);
        return;
      }
      delay(50);
    }
    needsWarmup = false;
  }
  // In installed SSCMA 1.0.3 the second argument also sets RESULT_ONLY.
  // true produces AT+INVOKE=1,0,1 (one inference, results only, no JPEG).
  ai.boxes().clear();
  const int result = ai.invoke(1, true, false);
  if (result != CMD_OK) {
    continuous = false;
    Serial.print("INFERENCE_FAILED library_code=");
    Serial.println(result);
    Serial.println("Stopped. This code is from SSCMA; it may hide a device error.");
    return;
  }
  ++frameNumber;
  Serial.print("INFERENCE_OK frame="); Serial.print(frameNumber);
  Serial.print(" boxes="); Serial.print((unsigned int)ai.boxes().size());
  Serial.print(" preprocess_ms="); Serial.print(ai.perf().prepocess);
  Serial.print(" inference_ms="); Serial.print(ai.perf().inference);
  Serial.print(" postprocess_ms="); Serial.println(ai.perf().postprocess);
  for (size_t index = 0; index < ai.boxes().size(); ++index) {
    const boxes_t &box = ai.boxes()[index];
    Serial.print("BOX target="); Serial.print(box.target);
    Serial.print(" score="); Serial.print(box.score);
    Serial.print(" x="); Serial.print(box.x);
    Serial.print(" y="); Serial.print(box.y);
    Serial.print(" w="); Serial.print(box.w);
    Serial.print(" h="); Serial.println(box.h);
  }
  if (ai.boxes().empty()) Serial.println("NO_DETECTIONS: inference completed with no boxes.");
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  printHelp();
  setupBle();
  connectGrove();
}

void loop() {
  if (Serial.available()) {
    const int key = Serial.read();
    switch (key) {
      case 'i': connectGrove(); break;
      case 't': continuous = false; inferOnce(); break;
      case 'r':
        if (connected) { continuous = true; lastRun = millis() - 1000; }
        else Serial.println("NOT_CONNECTED: send i first.");
        break;
      case 's': continuous = false; Serial.println("STOPPED"); break;
      case 'h': printHelp(); break;
    }
  }
  if (bleNotifyOn && millis() - lastBleSend >= BLE_SEND_MS) {
    lastBleSend = millis();
    sendSimulatedRadar();
  }
  if (continuous && millis() - lastRun >= 1000) {
    inferOnce();
    lastRun = millis();
  }
  delay(1);
}
