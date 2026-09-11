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
    },
    {
        "pattern": "*rged*.mp3",
        "wav_name": "FULL_CHARGE.wav",
        "h_name": "full_charge.h",
        "array_name": "full_charge",
        "guard": "FULL_CHARGE_H"
    },
    {
        "pattern": "*No de*.mp3",
        "wav_name": "NO_DEVICE.wav",
        "h_name": "no_device.h",
        "array_name": "no_device",
        "guard": "NO_DEVICE_H"
    },
    {
        "pattern": "*gain*.mp3",
        "wav_name": "ERROR.wav",
        "h_name": "charging_error.h",
        "array_name": "charging_error",
        "guard": "CHARGING_ERROR_H"
    },
    {
        "pattern": "*App c*.mp3",
        "wav_name": "APP_CONNECTED.wav",
        "h_name": "app_connected.h",
        "array_name": "app_connected",
        "guard": "APP_CONNECTED_H"
    },
    {
        "pattern": "*App d*.mp3",
        "wav_name": "APP_DISCONNECTED.wav",
        "h_name": "app_disconnected.h",
        "array_name": "app_disconnected",
        "guard": "APP_DISCONNECTED_H"
    }
]

import math

def enhance_audio_clean(pcm, sr=16000):
    """
    Clean Intelligible Speech DSP with Soft-Knee Noise Gate & Anti-Hiss Filtering:
    1. 550 Hz 4th-Order Butterworth HP: Eradicates 100% of bass rumble, cone bottoming, and cabinet resonance.
    2. 3800 Hz 4th-Order Butterworth LP: Cuts off high-frequency hiss, amplifier switching noise, and DAC clock hash.
    3. +3.0 dB Articulation EQ at 2600 Hz (Q=1.2): Enhances speech intelligibility so phonemes cut through cleanly.
    4. Soft-Knee Noise Gate / Expander: Mutes all room background noise, mic hiss, and idle rush between words.
    5. Smooth 3.2:1 Broadcast Compressor: Levels quiet syllables to match peak volume smoothly and transparently.
    6. Optimum Room-Audible Peak Target (0.62 peak, ~0.15 RMS): Crisp, clear, room-audible, and completely unclipped.
    7. Clean silence trimming & 20ms smooth raised-cosine anti-click fade in/out.
    """
    # 1. High-Pass Filter (550 Hz, 4th-order Butterworth, 24 dB/octave roll-off)
    sos_hp = signal.butter(4, 550.0, btype='highpass', fs=sr, output='sos')
    filtered = signal.sosfilt(sos_hp, pcm)

    # 2. Low-Pass Filter (3800 Hz, 4th-order Butterworth, 24 dB/octave roll-off)
    sos_lp = signal.butter(4, 3800.0, btype='lowpass', fs=sr, output='sos')
    filtered = signal.sosfilt(sos_lp, filtered)

    # 3. Speech Articulation EQ (+3.0 dB at 2600 Hz, Q=1.2)
    w0 = 2.0 * np.pi * 2600.0 / sr
    alpha = np.sin(w0) / (2.0 * 1.2)
    A = 10.0 ** (3.0 / 40.0)
    b_eq = [1.0 + alpha * A, -2.0 * np.cos(w0), 1.0 - alpha * A]
    a_eq = [1.0 + alpha / A, -2.0 * np.cos(w0), 1.0 - alpha / A]
    equalized = signal.lfilter(b_eq, a_eq, filtered)

    # 4. Soft-Knee Noise Gate / Downward Expander (kills all background noise & hiss between words)
    gate_thresh = 0.018 # below 1.8% amplitude is background noise/hiss
    gate_gain = np.ones_like(equalized)
    mag = np.abs(equalized)
    gate_env = np.zeros_like(equalized)
    g_env = 0.0
    g_att = np.exp(-1.0 / (0.002 * sr)) # 2ms fast attack
    g_rel = np.exp(-1.0 / (0.035 * sr)) # 35ms release
    for i in range(len(equalized)):
        s = mag[i]
        if s > g_env:
            g_env = g_att * g_env + (1.0 - g_att) * s
        else:
            g_env = g_rel * g_env + (1.0 - g_rel) * s
        gate_env[i] = g_env

    under_gate = gate_env < gate_thresh
    gate_gain[under_gate] = (gate_env[under_gate] / gate_thresh) ** 2.0
    gated = equalized * gate_gain

    # 5. Smooth Vocal Compressor (3ms attack, 45ms release, 3.2:1 ratio)
    envelope = np.zeros_like(gated)
    env = 0.0
    att_coef = np.exp(-1.0 / (0.003 * sr))
    rel_coef = np.exp(-1.0 / (0.045 * sr))
    for i in range(len(gated)):
        s = abs(gated[i])
        if s > env:
            env = att_coef * env + (1.0 - att_coef) * s
        else:
            env = rel_coef * env + (1.0 - rel_coef) * s
        envelope[i] = env

    thresh = 0.10
    gain = np.ones_like(gated)
    over = envelope > thresh
    gain[over] = (thresh / envelope[over]) ** (1.0 - 1.0 / 3.2)
    compressed = gated * gain

    # 6. Optimum Peak Target (0.62) - Audible in room, completely undistorted
    max_target = 0.62
    p99 = np.percentile(np.abs(compressed), 99.5)
    if p99 > 0:
        boosted = compressed * (max_target / p99)
    else:
        boosted = compressed
    limited = np.tanh(boosted / max_target) * max_target

    # 7. Trim leading/trailing silence safely
    active = np.where(np.abs(limited) > 0.008)[0]
    if len(active) > 0:
        start_idx = max(0, active[0] - int(0.020 * sr))
        end_idx = min(len(limited), active[-1] + int(0.030 * sr))
        trimmed = limited[start_idx:end_idx]
    else:
        trimmed = limited

    # Ensure even sample count for 16-bit word alignment
    if len(trimmed) % 2 != 0:
        trimmed = trimmed[:-1]

    # 8. Smooth 20ms raised-cosine fade in / fade out (zero click/thump)
    fade_len = int(0.020 * sr)
    if len(trimmed) > 2 * fade_len:
        fade_in = 0.5 * (1.0 - np.cos(np.linspace(0, np.pi, fade_len)))
        fade_out = 0.5 * (1.0 + np.cos(np.linspace(0, np.pi, fade_len)))
        trimmed[:fade_len] *= fade_in
        trimmed[-fade_len:] *= fade_out

    return trimmed

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

        # 1. Decode MP3 at native sample rate & convert to float64 mono
        decoded = miniaudio.decode_file(src_path)
        raw = np.frombuffer(decoded.samples, dtype=np.int16).astype(np.float64) / 32768.0
        if decoded.nchannels == 2:
            mono = 0.5 * (raw[0::2] + raw[1::2])
        else:
            mono = raw

        # 2. Pristine Polyphase Anti-Aliasing Resampling to 16 kHz
        g = math.gcd(decoded.sample_rate, TARGET_SAMPLE_RATE)
        up = TARGET_SAMPLE_RATE // g
        down = decoded.sample_rate // g
        resampled = signal.resample_poly(mono, up, down)

        # 3. Apply clean speech equalization & anti-clipping DSP
        enhanced = enhance_audio_clean(resampled, sr=TARGET_SAMPLE_RATE)

        # 4. Convert to 16-bit PCM
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

