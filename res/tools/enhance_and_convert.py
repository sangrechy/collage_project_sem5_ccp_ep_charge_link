import os
import glob
import wave
import numpy as np
import scipy.signal as signal
import miniaudio

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW_DIR = os.path.join(BASE_DIR, "res", "audio", "raw")
AUDIO_OUT_DIR = os.path.join(BASE_DIR, "res", "audio")
FIRMWARE_OUT_DIR = os.path.join(BASE_DIR, "firmware", "SmartChargeBox")

TARGET_SAMPLE_RATE = 16000

MAPPING = [
    {
        "pattern": "*rted*.mp3",
        "wav_name": "cst-gtcrn-enhanced.wav",
        "h_name": "charging_started.h",
        "array_name": "charging_started",
        "guard": "CHARGING_STARTED_H"
    },
    {
        "pattern": "*pped*.mp3",
        "wav_name": "cs-gtcrn-enhanced.wav",
        "h_name": "charging_stopped.h",
        "array_name": "charging_stopped",
        "guard": "CHARGING_STOPPED_H"
    },
    {
        "pattern": "*ched*.mp3",
        "wav_name": "pl-gtcrn-enhanced.wav",
        "h_name": "power_limit.h",
        "array_name": "power_limit",
        "guard": "POWER_LIMIT_H"
    }
]

def enhance_audio_clean(pcm, sr=16000):
    """
    Professional Speech DSP Equalization & Cleaning for 3W Loudspeaker & ESP32 DAC:
    1. 160 Hz Butterworth HP: Removes speaker cone bottoming & DC offset.
    2. 5000 Hz Butterworth LP: Cuts off 8-bit quantization hiss & ultrasonic hash.
    3. +2.0 dB Peaking EQ at 2200 Hz: Optimizes vocal formant intelligibility for small speakers.
    4. Smooth Envelope Compressor: Broadcast vocal presence without waveform distortion.
    5. Clean silence trimming & 10ms raised-cosine anti-click fade in/out.
    6. Bounded 0.80 peak (-1.9 dBFS): Prevents amplifier input clipping and supply sag.
    """
    # 1. High-Pass Filter (160 Hz, 2nd-order Butterworth)
    sos_hp = signal.butter(2, 160.0, btype='highpass', fs=sr, output='sos')
    filtered = signal.sosfilt(sos_hp, pcm)

    # 2. Low-Pass Filter (5000 Hz, 3rd-order Butterworth)
    # Human speech bandwidth is <4.5 kHz. Cutting above 5 kHz eliminates quantization hiss.
    sos_lp = signal.butter(3, 5000.0, btype='lowpass', fs=sr, output='sos')
    filtered = signal.sosfilt(sos_lp, filtered)

    # 3. Speech Presence EQ (+2.0 dB at 2200 Hz, Q=1.0)
    w0 = 2.0 * np.pi * 2200.0 / sr
    alpha = np.sin(w0) / (2.0 * 1.0)
    A = 10.0 ** (2.0 / 40.0) # +2 dB
    b_eq = [1.0 + alpha * A, -2.0 * np.cos(w0), 1.0 - alpha * A]
    a_eq = [1.0 + alpha / A, -2.0 * np.cos(w0), 1.0 - alpha / A]
    equalized = signal.lfilter(b_eq, a_eq, filtered)

    # 4. Smooth Envelope Compressor (5ms attack, 60ms release)
    # Operates on signal envelope - zero harmonic distortion or wave chopping!
    envelope = np.zeros_like(equalized)
    env = 0.0
    att_coef = np.exp(-1.0 / (0.005 * sr))
    rel_coef = np.exp(-1.0 / (0.060 * sr))
    for i in range(len(equalized)):
        s = abs(equalized[i])
        if s > env:
            env = att_coef * env + (1.0 - att_coef) * s
        else:
            env = rel_coef * env + (1.0 - rel_coef) * s
        envelope[i] = env

    thresh = 0.16
    gain = np.ones_like(equalized)
    over = envelope > thresh
    gain[over] = (thresh / envelope[over]) ** (1.0 - 1.0 / 2.5) # 2.5:1 ratio
    compressed = equalized * gain * 1.25 # 1.25x makeup gain

    # 5. Trim leading/trailing silence safely
    active = np.where(np.abs(compressed) > 0.01)[0]
    if len(active) > 0:
        start_idx = max(0, active[0] - int(0.025 * sr))
        end_idx = min(len(compressed), active[-1] + int(0.035 * sr))
        trimmed = compressed[start_idx:end_idx]
    else:
        trimmed = compressed

    # Ensure even sample count for 16-bit word alignment
    if len(trimmed) % 2 != 0:
        trimmed = trimmed[:-1]

    # 6. Smooth 10ms raised-cosine fade in / fade out (zero click/thump)
    fade_len = int(0.010 * sr)
    if len(trimmed) > 2 * fade_len:
        fade_in = 0.5 * (1.0 - np.cos(np.linspace(0, np.pi, fade_len)))
        fade_out = 0.5 * (1.0 + np.cos(np.linspace(0, np.pi, fade_len)))
        trimmed[:fade_len] *= fade_in
        trimmed[-fade_len:] *= fade_out

    # 7. Safe peak normalization to 0.80 (-1.9 dBFS)
    # Leaves 20% voltage margin so 3W amplifier (PAM8403 / 8002 / LM386) never clips
    pk = np.max(np.abs(trimmed))
    if pk > 0:
        final = (trimmed / pk) * 0.80
    else:
        final = trimmed

    return final

def process_all():
    print("=== CHARGELINK CLEAN SPEECH EQUALIZATION & CONVERSION ===")
    os.makedirs(AUDIO_OUT_DIR, exist_ok=True)
    os.makedirs(FIRMWARE_OUT_DIR, exist_ok=True)

    for item in MAPPING:
        pattern = os.path.join(RAW_DIR, item["pattern"])
        matches = glob.glob(pattern)
        if not matches:
            raise FileNotFoundError(f"No file matching pattern: {pattern}")
        src_path = matches[0]
        base_name = os.path.basename(src_path)
        print(f"\nProcessing: {base_name} -> {item['array_name']}")

        # Decode MP3 to 16kHz Mono float
        decoded = miniaudio.decode_file(src_path, nchannels=1, sample_rate=TARGET_SAMPLE_RATE)
        raw_pcm = np.frombuffer(decoded.samples, dtype=np.int16).astype(np.float32) / 32768.0

        # Apply clean speech equalization & anti-clipping DSP
        enhanced = enhance_audio_clean(raw_pcm, sr=TARGET_SAMPLE_RATE)

        # Convert to 16-bit PCM
        pcm16 = np.clip(enhanced * 32767.0, -32768.0, 32767.0).astype(np.int16)
        pcm16_bytes = pcm16.tobytes()

        # Write clean WAV file
        wav_path = os.path.join(AUDIO_OUT_DIR, item["wav_name"])
        with wave.open(wav_path, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(TARGET_SAMPLE_RATE)
            wav_file.writeframes(pcm16_bytes)
        print(f"  [WAV] Saved: {item['wav_name']} ({len(pcm16_bytes)} bytes, {len(pcm16)/TARGET_SAMPLE_RATE:.2f}s)")

        # Generate C PROGMEM header
        h_path = os.path.join(FIRMWARE_OUT_DIR, item["h_name"])
        array_name = item["array_name"]
        guard = item["guard"]

        hex_lines = []
        for i in range(0, len(pcm16_bytes), 16):
            chunk = pcm16_bytes[i:i+16]
            hex_str = ", ".join(f"0x{b:02X}" for b in chunk)
            if i + 16 < len(pcm16_bytes):
                hex_str += ", "
            hex_lines.append(f"  {hex_str}")
        content = "\n".join(hex_lines)

        with open(h_path, "w") as f:
            f.write(f"#ifndef {guard}\n")
            f.write(f"#define {guard}\n\n")
            f.write(f"const unsigned char {array_name}[] PROGMEM = {{\n")
            f.write(content)
            f.write(f"\n}};\n\n")
            f.write(f"const unsigned int {array_name}_len = {len(pcm16_bytes)};\n\n")
            f.write(f"#endif\n")

        print(f"  [HEADER] Generated: {item['h_name']} ({len(pcm16_bytes)} bytes)")

    print("\nAll audio files cleaned, equalized, and firmware headers generated successfully!")

if __name__ == "__main__":
    process_all()

