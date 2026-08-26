import asyncio
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from bleak import BleakScanner, BleakClient


# ============================================================
# CHARGE LINK - VERIFIED BLE UUIDs
# ============================================================

SERVICE_UUID = "7f4a0001-6d3b-4a91-9c21-123456789001"

COMMAND_UUID = "7f4a0002-6d3b-4a91-9c21-123456789001"

RESPONSE_UUID = "7f4a0003-6d3b-4a91-9c21-123456789001"

LIVE_DATA_UUID = "7f4a0004-6d3b-4a91-9c21-123456789001"

HISTORY_UUID = "7f4a0005-6d3b-4a91-9c21-123456789001"


# ============================================================
# LOCAL WEB SERVER
# ============================================================

WEB_HOST = "0.0.0.0"
WEB_PORT = 8765


# ============================================================
# GLOBAL STATE
# ============================================================

ble_client = None
ble_loop = None

request_id = 0

state_lock = threading.Lock()

state = {
    "connected": False,
    "device_name": None,
    "address": None,

    "live": None,
    "last_response": None,

    "history_packets": [],

    "last_error": None,

    "last_command": None,
}


# ============================================================
# REQUEST ID
# ============================================================

def get_next_request_id():

    global request_id

    request_id += 1

    return request_id


# ============================================================
# SAFE JSON DECODER
# ============================================================

def decode_json(data):

    try:

        text = data.decode(
            "utf-8",
            errors="replace"
        )

        return json.loads(text)

    except Exception as e:

        return {
            "raw": data.decode(
                "utf-8",
                errors="replace"
            ),
            "decode_error": str(e)
        }


# ============================================================
# RESPONSE NOTIFICATION
# ============================================================

def response_handler(sender, data):

    packet = decode_json(data)

    with state_lock:

        state["last_response"] = packet

    print()
    print("=" * 65)
    print("ESP32 RESPONSE")
    print("=" * 65)

    print(
        json.dumps(
            packet,
            indent=2
        )
    )


# ============================================================
# LIVE DATA NOTIFICATION
# ============================================================

def live_handler(sender, data):

    packet = decode_json(data)

    with state_lock:

        state["live"] = packet

    if "data" not in packet:

        return

    d = packet["data"]

    print()
    print("-" * 65)
    print("LIVE DATA")
    print("-" * 65)

    print(
        "Voltage        :",
        d.get("voltage_v"),
        "V"
    )

    print(
        "Current        :",
        d.get("current_a"),
        "A"
    )

    print(
        "Power          :",
        d.get("power_w"),
        "W"
    )

    print(
        "Charging       :",
        d.get("charging")
    )

    print(
        "Path enabled   :",
        d.get("path_enabled")
    )

    print(
        "Charging limit :",
        d.get("charging_limit"),
        "%"
    )

    print(
        "INA219         :",
        d.get("ina219_available")
    )

    print(
        "Session energy :",
        d.get("session_energy_wh"),
        "Wh"
    )

    print(
        "Total energy   :",
        d.get("total_energy_wh"),
        "Wh"
    )

    print(
        "Timestamp      :",
        d.get("timestamp")
    )

    print("-" * 65)


# ============================================================
# HISTORY NOTIFICATION
# ============================================================

def history_handler(sender, data):

    packet = decode_json(data)

    with state_lock:

        state["history_packets"].append(packet)

        if len(state["history_packets"]) > 100:

            state["history_packets"] = \
                state["history_packets"][-100:]

    print()
    print("=" * 65)
    print("HISTORY PACKET")
    print("=" * 65)

    print(
        json.dumps(
            packet,
            indent=2
        )
    )


# ============================================================
# FIND CHARGE LINK
# ============================================================

async def find_charge_link():

    print()
    print("=" * 65)
    print("SCANNING FOR CHARGE LINK")
    print("=" * 65)

    print()
    print("Service UUID:")
    print(SERVICE_UUID)

    print()
    print("Scanning for 15 seconds...")

    devices = await BleakScanner.discover(
        timeout=15,
        return_adv=True
    )

    for address, pair in devices.items():

        device, advertisement = pair

        service_uuids = [
            uuid.lower()
            for uuid in advertisement.service_uuids
        ]

        if SERVICE_UUID.lower() in service_uuids:

            print()
            print("=" * 65)
            print("CHARGE LINK FOUND")
            print("=" * 65)

            print(
                "Name    :",
                device.name
            )

            print(
                "Address :",
                device.address
            )

            print(
                "RSSI    :",
                advertisement.rssi
            )

            return device

    print()
    print("Charge Link was not found.")

    return None


# ============================================================
# CONNECT
# ============================================================

async def connect_ble():

    global ble_client

    device = await find_charge_link()

    if device is None:

        return False

    print()
    print("=" * 65)
    print("CONNECTING TO CHARGE LINK")
    print("=" * 65)

    client = BleakClient(device)

    await client.connect()

    if not client.is_connected:

        print("BLE connection failed.")

        return False

    ble_client = client

    with state_lock:

        state["connected"] = True

        state["device_name"] = device.name

        state["address"] = device.address

        state["last_error"] = None

    print()
    print(
        "Connected:",
        client.is_connected
    )

    print(
        "Subscribing RESPONSE..."
    )

    await client.start_notify(
        RESPONSE_UUID,
        response_handler
    )

    print(
        "Subscribing LIVE_DATA..."
    )

    await client.start_notify(
        LIVE_DATA_UUID,
        live_handler
    )

    print(
        "Subscribing HISTORY..."
    )

    await client.start_notify(
        HISTORY_UUID,
        history_handler
    )

    print()
    print("=" * 65)
    print("BLE READY")
    print("=" * 65)

    return True


# ============================================================
# SEND BLE COMMAND
# ============================================================

async def send_command(
    command,
    data=None
):

    if ble_client is None:

        raise RuntimeError(
            "BLE client is not available."
        )

    if not ble_client.is_connected:

        raise RuntimeError(
            "Charge Link is disconnected."
        )

    command_id = get_next_request_id()

    packet = {
        "id": command_id,
        "command": command
    }

    if data is not None:

        packet["data"] = data

    text = json.dumps(
        packet,
        separators=(",", ":")
    )

    print()
    print(
        "[COMMAND]",
        text
    )

    with state_lock:

        state["last_command"] = packet

    await ble_client.write_gatt_char(
        COMMAND_UUID,
        text.encode("utf-8"),
        response=True
    )

    return command_id


# ============================================================
# RUN COROUTINE FROM WEB THREAD
# ============================================================

def run_ble_command(
    command,
    data=None
):

    if ble_loop is None:

        raise RuntimeError(
            "BLE event loop is not ready."
        )

    future = asyncio.run_coroutine_threadsafe(
        send_command(
            command,
            data
        ),
        ble_loop
    )

    return future.result(
        timeout=10
    )


# ============================================================
# WEB PAGE
# ============================================================

WEB_PAGE = r"""
<!DOCTYPE html>

<html>

<head>

<meta charset="UTF-8">

<meta
name="viewport"
content="width=device-width, initial-scale=1.0"
>

<title>Charge Link Control</title>

<style>

* {
    box-sizing: border-box;
}

body {

    margin: 0;

    padding: 20px;

    background: #101010;

    color: white;

    font-family:
        Arial,
        Helvetica,
        sans-serif;
}

.container {

    max-width: 800px;

    margin: auto;
}

.card {

    background: #1d1d1d;

    border-radius: 18px;

    padding: 20px;

    margin-bottom: 16px;

    box-shadow:
        0 4px 20px
        rgba(0,0,0,0.25);
}

h1 {

    margin-top: 0;

    font-size: 30px;
}

h2 {

    font-size: 20px;
}

.connection {

    padding: 14px;

    border-radius: 10px;

    background: #292929;

    margin-bottom: 15px;
}

.status {

    font-size: 28px;

    font-weight: bold;

    margin-top: 5px;
}

.grid {

    display: grid;

    grid-template-columns:
        repeat(2, 1fr);

    gap: 12px;
}

.metric {

    background: #272727;

    padding: 16px;

    border-radius: 12px;
}

.label {

    color: #aaa;

    font-size: 14px;
}

.value {

    font-size: 25px;

    font-weight: bold;

    margin-top: 5px;
}

button {

    width: 100%;

    padding: 17px;

    margin-top: 10px;

    border: none;

    border-radius: 12px;

    font-size: 18px;

    font-weight: bold;

    cursor: pointer;

    color: white;
}

.start {

    background: #168a4a;
}

.stop {

    background: #c0392b;
}

.refresh {

    background: #444;
}

button:active {

    transform: scale(0.98);
}

pre {

    background: #080808;

    padding: 14px;

    border-radius: 10px;

    overflow-x: auto;

    white-space: pre-wrap;

    word-break: break-word;
}

.warning {

    color: #ffcc66;

    font-size: 14px;

    line-height: 1.5;
}

@media(max-width:600px) {

    .grid {

        grid-template-columns:
            1fr;
    }

}

</style>

</head>


<body>


<div class="container">


<div class="card">

<h1>CHARGE LINK</h1>

<div
id="connection"
class="connection"
>

BLE CONNECTING...

</div>


<div>

<div class="label">
CHARGING STATE
</div>

<div
id="charging"
class="status"
>

--

</div>

</div>

</div>


<div class="card">

<h2>LIVE MEASUREMENTS</h2>


<div class="grid">


<div class="metric">

<div class="label">
VOLTAGE
</div>

<div
id="voltage"
class="value"
>

-- V

</div>

</div>


<div class="metric">

<div class="label">
CURRENT
</div>

<div
id="current"
class="value"
>

-- A

</div>

</div>


<div class="metric">

<div class="label">
POWER
</div>

<div
id="power"
class="value"
>

-- W

</div>

</div>


<div class="metric">

<div class="label">
SESSION ENERGY
</div>

<div
id="energy"
class="value"
>

-- Wh

</div>

</div>


<div class="metric">

<div class="label">
PATH
</div>

<div
id="path"
class="value"
>

--

</div>

</div>


<div class="metric">

<div class="label">
LIMIT
</div>

<div
id="limit"
class="value"
>

-- %

</div>

</div>


</div>

</div>


<div class="card">

<h2>CHARGING CONTROL</h2>

<p class="warning">

These buttons directly operate the ESP32 relay.

STOP opens the charging path.

START enables the charging path.

</p>


<button
class="start"
onclick="startCharging()"
>

START CHARGING

</button>


<button
class="stop"
onclick="stopCharging()"
>

STOP CHARGING

</button>


<button
class="refresh"
onclick="refresh()"
>

REFRESH

</button>

</div>


<div class="card">

<h2>RAW BLE DATA</h2>

<pre id="raw">
Waiting for ESP32...
</pre>

</div>


</div>


<script>


async function postCommand(url) {

    try {

        const response =
            await fetch(
                url,
                {
                    method: "POST"
                }
            );

        const data =
            await response.json();

        if (!data.success) {

            alert(
                data.error ||
                "Command failed"
            );

        }

        setTimeout(
            refresh,
            500
        );

    }

    catch(error) {

        alert(
            "Web bridge error: " +
            error
        );

    }

}


async function startCharging() {

    if (
        !confirm(
            "Enable the charging path?"
        )
    ) {

        return;
    }

    await postCommand(
        "/api/start"
    );

}


async function stopCharging() {

    if (
        !confirm(
            "Stop charging?"
        )
    ) {

        return;
    }

    await postCommand(
        "/api/stop"
    );

}


async function refresh() {

    try {

        const response =
            await fetch(
                "/api/status"
            );

        const state =
            await response.json();


        const connection =
            document.getElementById(
                "connection"
            );


        if (state.connected) {

            connection.textContent =
                "BLE CONNECTED — CHARGE LINK";

        }

        else {

            connection.textContent =
                "BLE DISCONNECTED";

        }


        const packet =
            state.live;


        const data =
            packet &&
            packet.data
                ? packet.data
                : {};


        document.getElementById(
            "charging"
        ).textContent =

            data.charging === true
                ? "CHARGING"
                : data.charging === false
                    ? "NOT CHARGING"
                    : "--";


        document.getElementById(
            "voltage"
        ).textContent =

            data.voltage_v != null
                ? data.voltage_v + " V"
                : "-- V";


        document.getElementById(
            "current"
        ).textContent =

            data.current_a != null
                ? data.current_a + " A"
                : "-- A";


        document.getElementById(
            "power"
        ).textContent =

            data.power_w != null
                ? data.power_w + " W"
                : "-- W";


        document.getElementById(
            "energy"
        ).textContent =

            data.session_energy_wh != null
                ? data.session_energy_wh + " Wh"
                : "-- Wh";


        document.getElementById(
            "path"
        ).textContent =

            data.path_enabled === true
                ? "ENABLED"
                : data.path_enabled === false
                    ? "DISABLED"
                    : "--";


        document.getElementById(
            "limit"
        ).textContent =

            data.charging_limit != null
                ? data.charging_limit + " %"
                : "-- %";


        document.getElementById(
            "raw"
        ).textContent =

            JSON.stringify(
                state.live ||
                state.last_response ||
                state,
                null,
                2
            );

    }

    catch(error) {

        document.getElementById(
            "connection"
        ).textContent =
            "LOCAL WEB BRIDGE UNAVAILABLE";

    }

}


refresh();

setInterval(
    refresh,
    1000
);

</script>


</body>

</html>
"""


# ============================================================
# HTTP HANDLER
# ============================================================

class WebHandler(
    BaseHTTPRequestHandler
):

    def log_message(
        self,
        format,
        *args
    ):

        return


    def send_json(
        self,
        status,
        obj
    ):

        body = json.dumps(
            obj,
            indent=2
        ).encode(
            "utf-8"
        )

        self.send_response(
            status
        )

        self.send_header(
            "Content-Type",
            "application/json"
        )

        self.send_header(
            "Access-Control-Allow-Origin",
            "*"
        )

        self.send_header(
            "Cache-Control",
            "no-store"
        )

        self.send_header(
            "Content-Length",
            str(len(body))
        )

        self.end_headers()

        self.wfile.write(
            body
        )


    def do_GET(self):

        if self.path == "/":

            body = WEB_PAGE.encode(
                "utf-8"
            )

            self.send_response(
                200
            )

            self.send_header(
                "Content-Type",
                "text/html; charset=utf-8"
            )

            self.send_header(
                "Content-Length",
                str(len(body))
            )

            self.end_headers()

            self.wfile.write(
                body
            )

            return


        if self.path == "/api/status":

            with state_lock:

                response = dict(
                    state
                )

                response[
                    "history_packets"
                ] = list(
                    state[
                        "history_packets"
                    ]
                )

            self.send_json(
                200,
                response
            )

            return


        self.send_error(
            404
        )


    def do_POST(self):

        routes = {

            "/api/start":
                (
                    "start_charging",
                    None
                ),

            "/api/stop":
                (
                    "stop_charging",
                    None
                ),

            "/api/status-command":
                (
                    "get_status",
                    None
                ),

            "/api/power":
                (
                    "get_power",
                    None
                ),

            "/api/session":
                (
                    "get_session",
                    None
                ),

            "/api/energy":
                (
                    "get_energy",
                    None
                ),

            "/api/sample":
                (
                    "get_sample",
                    None
                ),

            "/api/history":
                (
                    "get_history",
                    {
                        "limit": 100
                    }
                ),

        }


        if self.path not in routes:

            self.send_error(
                404
            )

            return


        command, data = \
            routes[
                self.path
            ]


        try:

            rid = run_ble_command(
                command,
                data
            )

            self.send_json(
                200,
                {
                    "success": True,
                    "request_id": rid,
                    "command": command
                }
            )

        except Exception as e:

            self.send_json(
                500,
                {
                    "success": False,
                    "error": str(e)
                }
            )


# ============================================================
# WEB SERVER THREAD
# ============================================================

def start_web_server():

    server = ThreadingHTTPServer(
        (
            WEB_HOST,
            WEB_PORT
        ),
        WebHandler
    )

    print()
    print("=" * 65)
    print("WEB CONTROL SERVER")
    print("=" * 65)

    print(
        "Open on this PC:"
    )

    print(
        f"http://127.0.0.1:{WEB_PORT}"
    )

    print()

    print(
        "For another device on the same Wi-Fi,"
    )

    print(
        "use this PC's IP address:"
    )

    print(
        f"http://<YOUR-PC-IP>:{WEB_PORT}"
    )

    print(
        "=" * 65
    )

    server.serve_forever()


# ============================================================
# TERMINAL MENU
# ============================================================

def print_menu():

    print()
    print("=" * 65)
    print("CHARGE LINK TERMINAL TEST")
    print("=" * 65)

    print(
        "1  - Device info"
    )

    print(
        "2  - Status"
    )

    print(
        "3  - Power"
    )

    print(
        "4  - Charging state"
    )

    print(
        "5  - Charging limit"
    )

    print(
        "6  - Set charging limit"
    )

    print(
        "7  - START charging"
    )

    print(
        "8  - STOP charging"
    )

    print(
        "9  - Energy"
    )

    print(
        "10 - Session"
    )

    print(
        "11 - Sample"
    )

    print(
        "12 - Temperature"
    )

    print(
        "13 - History"
    )

    print(
        "14 - Clear session"
    )

    print(
        "15 - Full read-only test"
    )

    print(
        "0  - Exit"
    )

    print(
        "=" * 65
    )


# ============================================================
# FULL READ-ONLY TEST
# ============================================================

async def full_read_only_test():

    commands = [

        (
            "get_device_info",
            None
        ),

        (
            "get_status",
            None
        ),

        (
            "get_power",
            None
        ),

        (
            "get_charging_state",
            None
        ),

        (
            "get_charging_limit",
            None
        ),

        (
            "get_energy",
            None
        ),

        (
            "get_session",
            None
        ),

        (
            "get_sample",
            None
        ),

        (
            "get_temperature",
            None
        ),

        (
            "get_history",
            {
                "limit": 20
            }
        ),

    ]


    print()
    print("=" * 65)
    print("FULL READ-ONLY TEST")
    print("=" * 65)


    for command, data in commands:

        print()
        print(
            "TEST:",
            command
        )

        await send_command(
            command,
            data
        )

        await asyncio.sleep(
            1
        )


    print()
    print("=" * 65)
    print("READ-ONLY TEST FINISHED")
    print("=" * 65)


# ============================================================
# TERMINAL MENU LOOP
# ============================================================

async def terminal_menu():

    while True:

        print_menu()

        choice = input(
            "Select: "
        ).strip()


        if choice == "1":

            await send_command(
                "get_device_info"
            )


        elif choice == "2":

            await send_command(
                "get_status"
            )


        elif choice == "3":

            await send_command(
                "get_power"
            )


        elif choice == "4":

            await send_command(
                "get_charging_state"
            )


        elif choice == "5":

            await send_command(
                "get_charging_limit"
            )


        elif choice == "6":

            value = input(
                "Charging limit 0-100: "
            ).strip()

            try:

                percentage = int(
                    value
                )

            except ValueError:

                print(
                    "Invalid number."
                )

                continue


            if not 0 <= percentage <= 100:

                print(
                    "Must be 0-100."
                )

                continue


            await send_command(
                "set_charging_limit",
                {
                    "percentage":
                        percentage
                }
            )


        elif choice == "7":

            print()
            print(
                "This will ENABLE the charging path."
            )

            confirm = input(
                "Type START: "
            ).strip()


            if confirm == "START":

                await send_command(
                    "start_charging"
                )

            else:

                print(
                    "Cancelled."
                )


        elif choice == "8":

            print()
            print(
                "This will DISABLE the charging path."
            )

            confirm = input(
                "Type STOP: "
            ).strip()


            if confirm == "STOP":

                await send_command(
                    "stop_charging"
                )

            else:

                print(
                    "Cancelled."
                )


        elif choice == "9":

            await send_command(
                "get_energy"
            )


        elif choice == "10":

            await send_command(
                "get_session"
            )


        elif choice == "11":

            await send_command(
                "get_sample"
            )


        elif choice == "12":

            await send_command(
                "get_temperature"
            )


        elif choice == "13":

            await send_command(
                "get_history",
                {
                    "limit": 100
                }
            )


        elif choice == "14":

            print()
            print(
                "WARNING: This resets the current session."
            )

            confirm = input(
                "Type CLEAR: "
            ).strip()


            if confirm == "CLEAR":

                await send_command(
                    "clear_session"
                )

            else:

                print(
                    "Cancelled."
                )


        elif choice == "15":

            await full_read_only_test()


        elif choice == "0":

            print(
                "Exiting."
            )

            return


        else:

            print(
                "Invalid option."
            )


        await asyncio.sleep(
            0.5
        )


# ============================================================
# BLE WORKER
# ============================================================

async def ble_worker():

    global ble_loop

    ble_loop = asyncio.get_running_loop()


    print()
    print("=" * 65)
    print("CHARGE LINK BLE + WEB TEST")
    print("=" * 65)


    connected = await connect_ble()


    if not connected:

        print()
        print(
            "Could not connect to Charge Link."
        )

        return


    # ========================================================
    # START WEB SERVER
    # ========================================================

    web_thread = threading.Thread(
        target=start_web_server,
        daemon=True
    )

    web_thread.start()


    print()
    print("=" * 65)
    print("SYSTEM READY")
    print("=" * 65)

    print()
    print(
        "WEB:"
    )

    print(
        f"http://127.0.0.1:{WEB_PORT}"
    )

    print()
    print(
        "Terminal commands are also available."
    )

    print()
    print(
        "Live BLE data will continue automatically."
    )


    # ========================================================
    # RUN READ-ONLY TEST FIRST
    # ========================================================

    await full_read_only_test()


    # ========================================================
    # TERMINAL MENU
    # ========================================================

    await terminal_menu()


# ============================================================
# MAIN
# ============================================================

def main():

    try:

        asyncio.run(
            ble_worker()
        )

    except KeyboardInterrupt:

        print()
        print(
            "Stopped."
        )

    except Exception as e:

        print()
        print("=" * 65)
        print("FATAL ERROR")
        print("=" * 65)

        print(
            type(e).__name__,
            ":",
            e
        )


# ============================================================
# START
# ============================================================

if __name__ == "__main__":

    main()