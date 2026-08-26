import asyncio
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from bleak import BleakScanner, BleakClient


# ============================================================
# CHARGE LINK BLE + WEB TESTER
# ============================================================

SERVICE_UUID = "7f4a0001-6d3b-4a91-9c21-123456789001"
COMMAND_UUID = "7f4a0002-6d3b-4a91-9c21-123456789001"
RESPONSE_UUID = "7f4a0003-6d3b-4a91-9c21-123456789001"
LIVE_DATA_UUID = "7f4a0004-6d3b-4a91-9c21-123456789001"
HISTORY_UUID = "7f4a0005-6d3b-4a91-9c21-123456789001"

WEB_HOST = "0.0.0.0"
WEB_PORT = 8765


# ============================================================
# GLOBALS
# ============================================================

ble_client = None
ble_loop = None

request_id = 0
request_id_lock = threading.Lock()

state_lock = threading.Lock()

state = {
    "connected": False,
    "device_name": None,
    "address": None,
    "live": None,
    "last_response": None,
    "last_command": None,
    "last_error": None,
    "history_packets": []
}


# ============================================================
# REQUEST ID
# ============================================================

def get_next_request_id():
    global request_id

    with request_id_lock:
        request_id += 1
        return request_id


# ============================================================
# JSON DECODER
# ============================================================

def decode_json(data):
    try:
        text = data.decode("utf-8", errors="replace")
        return json.loads(text)

    except Exception as error:
        return {
            "decode_error": str(error),
            "raw": data.decode("utf-8", errors="replace")
        }


# ============================================================
# RESPONSE NOTIFICATION
# ============================================================

def response_handler(sender, data):
    packet = decode_json(data)

    with state_lock:
        state["last_response"] = packet

    print()
    print("=" * 70)
    print("ESP32 RESPONSE")
    print("=" * 70)

    print(json.dumps(packet, indent=2))

    print("=" * 70)


# ============================================================
# LIVE DATA NOTIFICATION
# ============================================================

def live_handler(sender, data):
    packet = decode_json(data)

    with state_lock:
        state["live"] = packet

    if not isinstance(packet, dict):
        return

    live_data = packet.get("data", packet)

    if not isinstance(live_data, dict):
        return

    print()
    print("-" * 70)
    print("LIVE DATA")
    print("-" * 70)

    print("Voltage        :", live_data.get("voltage_v"), "V")
    print("Current        :", live_data.get("current_a"), "A")
    print("Power          :", live_data.get("power_w"), "W")
    print("Charging       :", live_data.get("charging"))
    print("Path enabled   :", live_data.get("path_enabled"))
    print("Charging limit :", live_data.get("charging_limit"), "%")
    print("INA219         :", live_data.get("ina219_available"))
    print("Session energy :", live_data.get("session_energy_wh"), "Wh")
    print("Total energy   :", live_data.get("total_energy_wh"), "Wh")
    print("Timestamp      :", live_data.get("timestamp"))

    print("-" * 70)


# ============================================================
# HISTORY NOTIFICATION
# ============================================================

def history_handler(sender, data):
    packet = decode_json(data)

    with state_lock:
        state["history_packets"].append(packet)

        if len(state["history_packets"]) > 100:
            state["history_packets"] = state["history_packets"][-100:]

    print()
    print("=" * 70)
    print("HISTORY PACKET")
    print("=" * 70)

    print(json.dumps(packet, indent=2))

    print("=" * 70)


# ============================================================
# DISCONNECT CALLBACK
# ============================================================

def disconnected_callback(client):
    print()
    print("=" * 70)
    print("BLE DISCONNECTED")
    print("=" * 70)

    with state_lock:
        state["connected"] = False
        state["last_error"] = "BLE device disconnected."


# ============================================================
# FIND CHARGE LINK
# ============================================================

async def find_charge_link():

    print()
    print("=" * 70)
    print("SCANNING FOR CHARGE LINK")
    print("=" * 70)

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
            str(uuid).lower()
            for uuid in advertisement.service_uuids
        ]

        if SERVICE_UUID.lower() in service_uuids:

            print()
            print("=" * 70)
            print("CHARGE LINK FOUND")
            print("=" * 70)

            print("Name    :", device.name)
            print("Address :", device.address)
            print("RSSI    :", advertisement.rssi)
            print("Service :", SERVICE_UUID)

            print("=" * 70)

            return device

    print()
    print("=" * 70)
    print("CHARGE LINK NOT FOUND")
    print("=" * 70)

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
    print("=" * 70)
    print("CONNECTING TO CHARGE LINK")
    print("=" * 70)

    try:

        client = BleakClient(
            device,
            disconnected_callback=disconnected_callback
        )

        await client.connect()

    except Exception as error:

        print()
        print("BLE connection error:", error)

        with state_lock:
            state["last_error"] = str(error)

        return False

    if not client.is_connected:

        print("Connection failed.")
        return False

    ble_client = client

    with state_lock:
        state["connected"] = True
        state["device_name"] = device.name
        state["address"] = device.address
        state["last_error"] = None

    print()
    print("Connected:", client.is_connected)

    # --------------------------------------------------------
    # RESPONSE
    # --------------------------------------------------------

    print("Subscribing RESPONSE...")

    try:

        await client.start_notify(
            RESPONSE_UUID,
            response_handler
        )

    except Exception as error:

        print("Response subscription failed:", error)
        return False

    # --------------------------------------------------------
    # LIVE DATA
    # --------------------------------------------------------

    print("Subscribing LIVE_DATA...")

    try:

        await client.start_notify(
            LIVE_DATA_UUID,
            live_handler
        )

    except Exception as error:

        print("Live data subscription failed:", error)
        return False

    # --------------------------------------------------------
    # HISTORY
    # --------------------------------------------------------

    print("Subscribing HISTORY...")

    try:

        await client.start_notify(
            HISTORY_UUID,
            history_handler
        )

    except Exception as error:

        print("History subscription failed:", error)
        return False

    print()
    print("=" * 70)
    print("BLE READY")
    print("=" * 70)

    return True


# ============================================================
# SEND COMMAND
# ============================================================

async def send_command(command, data=None):

    if ble_client is None:
        raise RuntimeError(
            "BLE client is not connected."
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
    print("[COMMAND]", text)

    with state_lock:
        state["last_command"] = packet
        state["last_error"] = None

    try:

        await ble_client.write_gatt_char(
            COMMAND_UUID,
            text.encode("utf-8"),
            response=True
        )

    except Exception as error:

        with state_lock:
            state["last_error"] = str(error)

        raise

    return command_id


# ============================================================
# WEB -> BLE BRIDGE
# ============================================================

def run_ble_command(command, data=None):

    if ble_loop is None:
        raise RuntimeError(
            "BLE event loop is not ready."
        )

    if ble_client is None:
        raise RuntimeError(
            "BLE client is not connected."
        )

    future = asyncio.run_coroutine_threadsafe(
        send_command(command, data),
        ble_loop
    )

    return future.result(timeout=10)


# ============================================================
# WEB PAGE
# ============================================================

WEB_PAGE = r"""
<!DOCTYPE html>

<html>

<head>

<meta charset="UTF-8">

<meta name="viewport"
content="width=device-width, initial-scale=1.0">

<title>Charge Link</title>

<style>

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    padding: 20px;
    background: #101010;
    color: white;
    font-family: Arial, Helvetica, sans-serif;
}

.container {
    width: 100%;
    max-width: 850px;
    margin: 0 auto;
}

.card {
    background: #1c1c1c;
    border-radius: 18px;
    padding: 20px;
    margin-bottom: 18px;
    box-shadow: 0 4px 20px rgba(0,0,0,0.25);
}

h1 {
    margin: 0 0 15px 0;
    font-size: 30px;
}

h2 {
    margin-top: 0;
    font-size: 20px;
}

.connection {
    padding: 13px;
    border-radius: 10px;
    background: #292929;
    margin-bottom: 20px;
    font-weight: bold;
}

.charging-state {
    font-size: 30px;
    font-weight: bold;
    margin-bottom: 10px;
}

.grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
}

.metric {
    background: #282828;
    border-radius: 12px;
    padding: 16px;
}

.label {
    color: #aaa;
    font-size: 13px;
    text-transform: uppercase;
}

.value {
    font-size: 25px;
    font-weight: bold;
    margin-top: 7px;
}

button {
    width: 100%;
    border: none;
    border-radius: 12px;
    padding: 17px;
    margin-top: 10px;
    font-size: 18px;
    font-weight: bold;
    color: white;
    cursor: pointer;
}

button:active {
    transform: scale(0.98);
}

button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.start {
    background: #178a4b;
}

.stop {
    background: #c0392b;
}

.refresh {
    background: #444;
}

pre {
    background: #080808;
    color: #ddd;
    padding: 14px;
    border-radius: 10px;
    overflow-x: auto;
    white-space: pre-wrap;
    word-break: break-word;
    min-height: 100px;
}

.info {
    color: #aaa;
    font-size: 14px;
    line-height: 1.5;
}

.success {
    color: #65d68c;
}

.error {
    color: #ff6b6b;
}

@media (max-width: 600px) {

    body {
        padding: 10px;
    }

    .grid {
        grid-template-columns: 1fr;
    }

    h1 {
        font-size: 26px;
    }
}

</style>

</head>

<body>

<div class="container">

<div class="card">

<h1>CHARGE LINK</h1>

<div id="connection"
class="connection">
Checking BLE...
</div>

<div id="charging"
class="charging-state">
--
</div>

</div>


<div class="card">

<h2>LIVE MEASUREMENTS</h2>

<div class="grid">


<div class="metric">

<div class="label">
Voltage
</div>

<div id="voltage"
class="value">
-- V
</div>

</div>


<div class="metric">

<div class="label">
Current
</div>

<div id="current"
class="value">
-- A
</div>

</div>


<div class="metric">

<div class="label">
Power
</div>

<div id="power"
class="value">
-- W
</div>

</div>


<div class="metric">

<div class="label">
Session Energy
</div>

<div id="energy"
class="value">
-- Wh
</div>

</div>


<div class="metric">

<div class="label">
Charging Path
</div>

<div id="path"
class="value">
--
</div>

</div>


<div class="metric">

<div class="label">
Charging Limit
</div>

<div id="limit"
class="value">
-- %
</div>

</div>


<div class="metric">

<div class="label">
INA219
</div>

<div id="ina219"
class="value">
--
</div>

</div>


<div class="metric">

<div class="label">
Total Energy
</div>

<div id="total-energy"
class="value">
-- Wh
</div>

</div>


</div>

</div>


<div class="card">

<h2>CHARGING CONTROL</h2>

<p class="info">

START enables the ESP32 charging path.

STOP disables the ESP32 charging path.

The actual charging state is determined by INA219 current measurement.

</p>


<button
id="start-button"
class="start"
onclick="startCharging()">

START CHARGING

</button>


<button
id="stop-button"
class="stop"
onclick="stopCharging()">

STOP CHARGING

</button>


<button
class="refresh"
onclick="refreshStatus()">

REFRESH

</button>


<div
id="command-result"
class="info"
style="margin-top:15px;">

Ready.

</div>

</div>


<div class="card">

<h2>ESP32 DATA</h2>

<pre id="raw">
Waiting for BLE data...
</pre>

</div>

</div>


<script>

let commandBusy = false;


function setCommandResult(text, success) {

    const element =
        document.getElementById(
            "command-result"
        );

    element.textContent = text;

    element.className =
        success
        ? "info success"
        : "info error";
}


async function postCommand(endpoint) {

    if (commandBusy) {
        return;
    }

    commandBusy = true;

    const startButton =
        document.getElementById(
            "start-button"
        );

    const stopButton =
        document.getElementById(
            "stop-button"
        );

    startButton.disabled = true;
    stopButton.disabled = true;

    setCommandResult(
        "Sending command...",
        true
    );

    try {

        const response =
            await fetch(
                endpoint,
                {
                    method: "POST"
                }
            );

        const result =
            await response.json();

        if (result.success) {

            setCommandResult(
                "Command sent. Waiting for ESP32 state update...",
                true
            );

        } else {

            setCommandResult(
                "Command failed: " +
                (result.error || "Unknown error"),
                false
            );
        }

        setTimeout(
            refreshStatus,
            500
        );

    } catch (error) {

        setCommandResult(
            "Web bridge error: " + error,
            false
        );

    } finally {

        commandBusy = false;

        setTimeout(
            function() {

                startButton.disabled = false;
                stopButton.disabled = false;

            },
            700
        );
    }
}


async function startCharging() {

    if (!confirm(
        "Enable the Charge Link charging path?"
    )) {
        return;
    }

    await postCommand(
        "/api/start"
    );
}


async function stopCharging() {

    if (!confirm(
        "Stop charging?"
    )) {
        return;
    }

    await postCommand(
        "/api/stop"
    );
}


async function refreshStatus() {

    try {

        const response =
            await fetch(
                "/api/status",
                {
                    cache: "no-store"
                }
            );

        const status =
            await response.json();

        const connection =
            document.getElementById(
                "connection"
            );

        if (status.connected) {

            connection.textContent =
                "BLE CONNECTED — CHARGE LINK";

        } else {

            connection.textContent =
                "BLE DISCONNECTED";
        }


        const packet =
            status.live;

        let data = {};

        if (
            packet &&
            typeof packet === "object"
        ) {

            if (
                packet.data &&
                typeof packet.data === "object"
            ) {

                data = packet.data;

            } else {

                data = packet;
            }
        }


        const charging =
            document.getElementById(
                "charging"
            );


        if (data.charging === true) {

            charging.textContent =
                "CHARGING";

        } else if (
            data.charging === false
        ) {

            charging.textContent =
                "NOT CHARGING";

        } else {

            charging.textContent =
                "--";
        }


        document.getElementById(
            "voltage"
        ).textContent =
            data.voltage_v != null
            ? Number(data.voltage_v).toFixed(3) + " V"
            : "-- V";


        document.getElementById(
            "current"
        ).textContent =
            data.current_a != null
            ? Number(data.current_a).toFixed(3) + " A"
            : "-- A";


        document.getElementById(
            "power"
        ).textContent =
            data.power_w != null
            ? Number(data.power_w).toFixed(3) + " W"
            : "-- W";


        document.getElementById(
            "energy"
        ).textContent =
            data.session_energy_wh != null
            ? Number(data.session_energy_wh).toFixed(4) + " Wh"
            : "-- Wh";


        document.getElementById(
            "total-energy"
        ).textContent =
            data.total_energy_wh != null
            ? Number(data.total_energy_wh).toFixed(4) + " Wh"
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
            "ina219"
        ).textContent =
            data.ina219_available === true
            ? "AVAILABLE"
            : data.ina219_available === false
            ? "ERROR"
            : "--";


        document.getElementById(
            "raw"
        ).textContent =
            JSON.stringify(
                status,
                null,
                2
            );

    } catch (error) {

        document.getElementById(
            "connection"
        ).textContent =
            "LOCAL WEB SERVER ERROR";

        document.getElementById(
            "raw"
        ).textContent =
            String(error);
    }
}


refreshStatus();

setInterval(
    refreshStatus,
    1000
);

</script>

</body>

</html>
"""


# ============================================================
# HTTP HANDLER
# ============================================================

class WebHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        return


    # --------------------------------------------------------
    # JSON RESPONSE
    # --------------------------------------------------------

    def send_json(self, status_code, obj):

        body = json.dumps(
            obj,
            indent=2
        ).encode("utf-8")

        self.send_response(
            status_code
        )

        self.send_header(
            "Content-Type",
            "application/json; charset=utf-8"
        )

        self.send_header(
            "Cache-Control",
            "no-store"
        )

        self.send_header(
            "Access-Control-Allow-Origin",
            "*"
        )

        self.send_header(
            "Content-Length",
            str(len(body))
        )

        self.end_headers()

        self.wfile.write(body)


    # --------------------------------------------------------
    # GET
    # --------------------------------------------------------

    def do_GET(self):

        if self.path == "/":

            body = WEB_PAGE.encode("utf-8")

            self.send_response(200)

            self.send_header(
                "Content-Type",
                "text/html; charset=utf-8"
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

            self.wfile.write(body)

            return


        if self.path == "/api/status":

            with state_lock:

                response = {
                    "connected": state["connected"],
                    "device_name": state["device_name"],
                    "address": state["address"],
                    "live": state["live"],
                    "last_response": state["last_response"],
                    "last_command": state["last_command"],
                    "last_error": state["last_error"],
                    "history_packets": list(
                        state["history_packets"]
                    )
                }

            self.send_json(
                200,
                response
            )

            return


        self.send_error(404)


    # --------------------------------------------------------
    # POST
    # --------------------------------------------------------

    def do_POST(self):

        routes = {

            "/api/start": (
                "start_charging",
                None
            ),

            "/api/stop": (
                "stop_charging",
                None
            ),

            "/api/status-command": (
                "get_status",
                None
            ),

            "/api/power": (
                "get_power",
                None
            ),

            "/api/session": (
                "get_session",
                None
            ),

            "/api/energy": (
                "get_energy",
                None
            ),

            "/api/sample": (
                "get_sample",
                None
            ),

            "/api/temperature": (
                "get_temperature",
                None
            ),

            "/api/device-info": (
                "get_device_info",
                None
            ),

            "/api/history": (
                "get_history",
                {
                    "limit": 100
                }
            ),

            "/api/clear-session": (
                "clear_session",
                None
            )
        }


        if self.path not in routes:

            self.send_error(404)
            return


        command, data = routes[self.path]


        try:

            command_id = run_ble_command(
                command,
                data
            )

            self.send_json(
                200,
                {
                    "success": True,
                    "request_id": command_id,
                    "command": command
                }
            )

        except Exception as error:

            self.send_json(
                500,
                {
                    "success": False,
                    "error": str(error)
                }
            )


# ============================================================
# WEB SERVER
# ============================================================

def start_web_server():

    try:

        server = ThreadingHTTPServer(
            (
                WEB_HOST,
                WEB_PORT
            ),
            WebHandler
        )

    except OSError as error:

        print()
        print(
            "WEB SERVER ERROR:",
            error
        )

        return


    print()
    print("=" * 70)
    print("LOCAL WEB CONTROL")
    print("=" * 70)

    print()
    print(
        "Open on this computer:"
    )

    print(
        f"http://127.0.0.1:{WEB_PORT}"
    )

    print()
    print(
        "For another device on the same Wi-Fi:"
    )

    print(
        f"http://<YOUR-PC-IP>:{WEB_PORT}"
    )

    print()
    print(
        "START / STOP buttons control the ESP32 relay."
    )

    print("=" * 70)


    try:

        server.serve_forever()

    finally:

        server.server_close()


# ============================================================
# TERMINAL MENU
# ============================================================

def print_menu():

    print()
    print("=" * 70)
    print("CHARGE LINK TERMINAL")
    print("=" * 70)

    print("1  - Device information")
    print("2  - Status")
    print("3  - Power")
    print("4  - Charging state")
    print("5  - Get charging limit")
    print("6  - Set charging limit")
    print("7  - START charging")
    print("8  - STOP charging")
    print("9  - Energy")
    print("10 - Session")
    print("11 - Sample")
    print("12 - Temperature")
    print("13 - History")
    print("14 - Clear session")
    print("15 - FULL READ-ONLY TEST")
    print("0  - Exit")

    print("=" * 70)


# ============================================================
# ASYNC INPUT
# ============================================================

async def async_input(prompt):

    return await asyncio.to_thread(
        input,
        prompt
    )


# ============================================================
# FULL READ-ONLY TEST
# ============================================================

async def full_read_only_test():

    commands = [

        ("get_device_info", None),

        ("get_status", None),

        ("get_power", None),

        ("get_charging_state", None),

        ("get_charging_limit", None),

        ("get_energy", None),

        ("get_session", None),

        ("get_sample", None),

        ("get_temperature", None),

        (
            "get_history",
            {
                "limit": 20
            }
        )
    ]


    print()
    print("=" * 70)
    print("FULL READ-ONLY TEST")
    print("=" * 70)


    for command, data in commands:

        print()
        print(
            "RUNNING:",
            command
        )

        try:

            await send_command(
                command,
                data
            )

        except Exception as error:

            print(
                "COMMAND ERROR:",
                error
            )

        await asyncio.sleep(1)


    print()
    print("=" * 70)
    print("FULL READ-ONLY TEST COMPLETE")
    print("=" * 70)


# ============================================================
# TERMINAL MENU LOOP
# ============================================================

async def terminal_menu():

    while True:

        print_menu()

        choice = (
            await async_input(
                "Select: "
            )
        ).strip()


        # ----------------------------------------------------
        # DEVICE INFO
        # ----------------------------------------------------

        if choice == "1":

            try:

                await send_command(
                    "get_device_info"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # STATUS
        # ----------------------------------------------------

        elif choice == "2":

            try:

                await send_command(
                    "get_status"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # POWER
        # ----------------------------------------------------

        elif choice == "3":

            try:

                await send_command(
                    "get_power"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # CHARGING STATE
        # ----------------------------------------------------

        elif choice == "4":

            try:

                await send_command(
                    "get_charging_state"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # GET LIMIT
        # ----------------------------------------------------

        elif choice == "5":

            try:

                await send_command(
                    "get_charging_limit"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # SET LIMIT
        # ----------------------------------------------------

        elif choice == "6":

            value = (
                await async_input(
                    "Charging limit 0-100: "
                )
            ).strip()


            try:

                percentage = int(value)

            except ValueError:

                print(
                    "Invalid number."
                )

                continue


            if not 0 <= percentage <= 100:

                print(
                    "Charging limit must be 0-100."
                )

                continue


            try:

                await send_command(
                    "set_charging_limit",
                    {
                        "percentage": percentage
                    }
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # START CHARGING
        # ----------------------------------------------------

        elif choice == "7":

            print()
            print(
                "START will enable the ESP32 charging path."
            )

            confirm = (
                await async_input(
                    "Type START to confirm: "
                )
            ).strip()


            if confirm != "START":

                print(
                    "Cancelled."
                )

                continue


            try:

                await send_command(
                    "start_charging"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # STOP CHARGING
        # ----------------------------------------------------

        elif choice == "8":

            print()
            print(
                "STOP will disable the ESP32 charging path."
            )

            confirm = (
                await async_input(
                    "Type STOP to confirm: "
                )
            ).strip()


            if confirm != "STOP":

                print(
                    "Cancelled."
                )

                continue


            try:

                await send_command(
                    "stop_charging"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # ENERGY
        # ----------------------------------------------------

        elif choice == "9":

            try:

                await send_command(
                    "get_energy"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # SESSION
        # ----------------------------------------------------

        elif choice == "10":

            try:

                await send_command(
                    "get_session"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # SAMPLE
        # ----------------------------------------------------

        elif choice == "11":

            try:

                await send_command(
                    "get_sample"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # TEMPERATURE
        # ----------------------------------------------------

        elif choice == "12":

            try:

                await send_command(
                    "get_temperature"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # HISTORY
        # ----------------------------------------------------

        elif choice == "13":

            try:

                await send_command(
                    "get_history",
                    {
                        "limit": 100
                    }
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # CLEAR SESSION
        # ----------------------------------------------------

        elif choice == "14":

            print()
            print(
                "WARNING: this clears the current session."
            )

            confirm = (
                await async_input(
                    "Type CLEAR to confirm: "
                )
            ).strip()


            if confirm != "CLEAR":

                print(
                    "Cancelled."
                )

                continue


            try:

                await send_command(
                    "clear_session"
                )

            except Exception as error:

                print(
                    "ERROR:",
                    error
                )


        # ----------------------------------------------------
        # FULL TEST
        # ----------------------------------------------------

        elif choice == "15":

            await full_read_only_test()


        # ----------------------------------------------------
        # EXIT
        # ----------------------------------------------------

        elif choice == "0":

            print()
            print(
                "Exiting..."
            )

            return


        else:

            print()
            print(
                "Invalid option."
            )


        await asyncio.sleep(0.2)


# ============================================================
# BLE WORKER
# ============================================================

async def ble_worker():

    global ble_loop

    ble_loop = asyncio.get_running_loop()


    print()
    print("=" * 70)
    print("CHARGE LINK BLE + WEB TEST")
    print("=" * 70)


    connected = await connect_ble()


    if not connected:

        print()
        print(
            "Could not connect to Charge Link."
        )

        print()
        print(
            "Check that the ESP32 is powered and advertising."
        )

        return


    # ========================================================
    # WEB SERVER THREAD
    # ========================================================

    web_thread = threading.Thread(
        target=start_web_server,
        daemon=True
    )

    web_thread.start()


    print()
    print("=" * 70)
    print("SYSTEM READY")
    print("=" * 70)

    print()
    print(
        "WEB CONTROL:"
    )

    print(
        f"http://127.0.0.1:{WEB_PORT}"
    )

    print()
    print(
        "BLE live notifications are active."
    )

    print(
        "Terminal input will not block BLE."
    )


    # ========================================================
    # AUTOMATIC READ-ONLY TEST
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
        print()
        print(
            "CHARGE LINK TEST STOPPED."
        )

    except Exception as error:

        print()
        print("=" * 70)
        print("FATAL ERROR")
        print("=" * 70)

        print(
            type(error).__name__
        )

        print(
            str(error)
        )

        print("=" * 70)


# ============================================================
# START
# ============================================================

if __name__ == "__main__":

    main()