\# CHARGE LINK — ESP32 API Contract



\## Communication



BLE ONLY.



Wi-Fi is not used.



\## Architecture



Phone App

↓

BLE

↓

ESP32 Smart Charge Box



\## ESP32 → App



\### DEVICE\_STATUS



\- connected

\- deviceId

\- deviceName

\- firmwareVersion

\- charging

\- relayState

\- faultStatus



\### POWER\_DATA



\- voltage\_V

\- current\_A

\- power\_W

\- sessionEnergy\_Wh



\### CHARGING\_CONFIG



\- limitPercent



\### TEMPERATURE



\- temperature\_C

\- nullable when unavailable



\### ENERGY\_DATA



\- sessionEnergyWh

\- totalEnergyWh



\## App → ESP32



\### START\_CHARGING



Request charging start.



\### STOP\_CHARGING



Request charging stop.



\### SET\_CHARGING\_LIMIT



Parameter:



percent



Example:



80



The ESP32 remains the final authority for charging control and safety.



\### GET\_STATUS



Request current device status.



\### GET\_POWER\_DATA



Request current power data.



\### GET\_ENERGY\_DATA



Request current energy data.



\## Live Data



Preferred:



ESP32 → BLE Notification → App



Fallback:



App → BLE Request → ESP32 → Response



\## Measurement



ESP32 performs INA219 measurement approximately every 1 second or faster.



ESP32 maintains accumulated session energy internally.



The mobile application stores approximately one combined sample every 30 seconds.



\## Session Ownership



The mobile application creates and manages charging session IDs.



The ESP32 provides measurements and device state only.



\## Temperature



Temperature is part of the API.



Until an ESP32 temperature sensor exists:



temperature\_C = unavailable



The application must not display a fabricated value.



\## Important Separation



ESP32/INA219:



Charger-side electrical measurement.



Phone:



Battery-side information.



The ESP32 must not claim to directly measure the phone's internal battery energy.

