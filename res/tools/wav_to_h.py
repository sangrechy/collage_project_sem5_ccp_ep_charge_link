import wave
import os

files = {
    "cst-gtcrn-enhanced.wav": "charging_started.h",
    "cs-gtcrn-enhanced.wav": "charging_stopped.h",
    "pl-gtcrn-enhanced.wav": "power_limit.h"
}

for wav_name, h_name in files.items():

    with wave.open(wav_name, "rb") as wav:
        frames = wav.readframes(wav.getnframes())

    array_name = os.path.splitext(h_name)[0]

    with open(h_name, "w") as f:
        f.write(f"#ifndef {array_name.upper()}_H\n")
        f.write(f"#define {array_name.upper()}_H\n\n")

        f.write(f"const unsigned char {array_name}[] PROGMEM = {{\n")

        for i, byte in enumerate(frames):
            if i % 16 == 0:
                f.write("  ")

            f.write(f"0x{byte:02X}")

            if i != len(frames) - 1:
                f.write(", ")

            if i % 16 == 15:
                f.write("\n")

        f.write(f"\n}};\n\n")
        f.write(f"const unsigned int {array_name}_len = {len(frames)};\n\n")
        f.write("#endif\n")

    print(f"Created: {h_name} ({len(frames)} bytes)")