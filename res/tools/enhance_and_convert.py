import os
import glob
import wave
import math
import numpy as np
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
    },
    {
        "pattern": "*ere*.mp3",
        "wav_name": "SYSTEM_ACTIVATED.wav",
        "h_name": "system_activated.h",
        "array_name": "system_activated",
        "guard": "SYSTEM_ACTIVATED_H"
    }
]

# ==============================================================================
# PURE NUMPY BIQUAD IIR FILTER ENGINE (Cookbook Audio EQ by Robert Bristow-Johnson)
# ==============================================================================

def biquad_hp(fc, fs, Q):
    w0 = 2.0 * math.pi * fc / fs
    alpha = math.sin(w0) / (2.0 * Q)
    cosw0 = math.cos(w0)
    b0 = (1.0 + cosw0) / 2.0
    b1 = -(1.0 + cosw0)
    b2 = (1.0 + cosw0) / 2.0
    a0 = 1.0 + alpha
    a1 = -2.0 * cosw0
    a2 = 1.0 - alpha
    return np.array([b0/a0, b1/a0, b2/a0], dtype=np.float64), np.array([1.0, a1/a0, a2/a0], dtype=np.float64)

def biquad_lp(fc, fs, Q):
    w0 = 2.0 * math.pi * fc / fs
    alpha = math.sin(w0) / (2.0 * Q)
    cosw0 = math.cos(w0)
    b0 = (1.0 - cosw0) / 2.0
    b1 = 1.0 - cosw0
    b2 = (1.0 - cosw0) / 2.0
    a0 = 1.0 + alpha
    a1 = -2.0 * cosw0
    a2 = 1.0 - alpha
    return np.array([b0/a0, b1/a0, b2/a0], dtype=np.float64), np.array([1.0, a1/a0, a2/a0], dtype=np.float64)

def biquad_peaking(fc, fs, gain_db, Q):
    A = 10.0 ** (gain_db / 40.0)
    w0 = 2.0 * math.pi * fc / fs
    alpha = math.sin(w0) / (2.0 * Q)
    cosw0 = math.cos(w0)
    b0 = 1.0 + alpha * A
    b1 = -2.0 * cosw0
    b2 = 1.0 - alpha * A
    a0 = 1.0 + alpha / A
    a1 = -2.0 * cosw0
    a2 = 1.0 - alpha / A
    return np.array([b0/a0, b1/a0, b2/a0], dtype=np.float64), np.array([1.0, a1/a0, a2/a0], dtype=np.float64)

def apply_biquad(b, a, x):
    """Direct Form II Transposed IIR Filter implementation."""
    y = np.zeros_like(x, dtype=np.float64)
    b0, b1, b2 = b[0], b[1], b[2]
    a1, a2 = a[1], a[2]
    w1, w2 = 0.0, 0.0
    for i in range(len(x)):
        xi = x[i]
        yi = b0 * xi + w1
        w1 = b1 * xi - a1 * yi + w2
        w2 = b2 * xi - a2 * yi
        y[i] = yi
    return y

def enhance_audio_clean(pcm, sr=16000):
    """
    Clean Intelligible Speech DSP optimized for an 8-ohm 0.5-Watt Miniature Speaker:
    1. 600 Hz 4th-Order Butterworth High-Pass Filter:
       Completely eliminates bass rumble below 600 Hz, preventing speaker cone
       bottoming, frame buzzing, and muffled boxiness.
    2. 4200 Hz 4th-Order Butterworth Low-Pass Filter:
       Rolls off ultrasonic switching hash while preserving natural consonant sibilance ('s', 't', 'k').
    3. +3.5 dB Articulation Peaking EQ at 2800 Hz (Q=1.1):
       Boosts human speech presence and intelligibility so the voice cuts through crisp and clear.
    4. Soft-Knee Downward Expander / Noise Gate (threshold 0.014):
       Mutes background room hiss and breath noise during speech pauses.
    5. Vocal Dynamics Compressor (ratio 3.0:1):
       Smooths dynamic range for consistent clarity across words.
    6. Reduced Target Volume (0.36 peak, ~0.08 RMS):
       Noticeably softer and gentler on 0.5W miniature speakers, completely unclipped.
    7. Clean silence trimming & 20ms raised-cosine anti-pop fade in/out.
    """
    # Butterworth 4th-order stages Q-factors:
    q1 = 0.541196100146197
    q2 = 1.3065629648763765

    # 1. 600 Hz 4th-order High-Pass Filter (2 cascaded 2nd-order biquads)
    b_hp1, a_hp1 = biquad_hp(600.0, sr, q1)
    b_hp2, a_hp2 = biquad_hp(600.0, sr, q2)
    filtered = apply_biquad(b_hp1, a_hp1, pcm)
    filtered = apply_biquad(b_hp2, a_hp2, filtered)

    # 2. 4200 Hz 4th-order Low-Pass Filter (2 cascaded 2nd-order biquads)
    b_lp1, a_lp1 = biquad_lp(4200.0, sr, q1)
    b_lp2, a_lp2 = biquad_lp(4200.0, sr, q2)
    filtered = apply_biquad(b_lp1, a_lp1, filtered)
    filtered = apply_biquad(b_lp2, a_lp2, filtered)

    # 3. Speech Articulation EQ (+3.5 dB at 2800 Hz, Q=1.1)
    b_eq, a_eq = biquad_peaking(2800.0, sr, 3.5, 1.1)
    equalized = apply_biquad(b_eq, a_eq, filtered)

    # 4. Soft-Knee Downward Expander / Noise Gate
    gate_thresh = 0.014
    gate_gain = np.ones_like(equalized)
    mag = np.abs(equalized)
    g_env = 0.0
    g_att = math.exp(-1.0 / (0.002 * sr)) # 2ms fast attack
    g_rel = math.exp(-1.0 / (0.035 * sr)) # 35ms release
    for i in range(len(equalized)):
        s = mag[i]
        if s > g_env:
            g_env = g_att * g_env + (1.0 - g_att) * s
        else:
            g_env = g_rel * g_env + (1.0 - g_rel) * s
        if g_env < gate_thresh:
            gate_gain[i] = (g_env / gate_thresh) ** 2.0

    gated = equalized * gate_gain

    # 5. Smooth Vocal Compressor (3ms attack, 45ms release, 3.0:1 ratio)
    envelope = np.zeros_like(gated)
    env = 0.0
    att_coef = math.exp(-1.0 / (0.003 * sr))
    rel_coef = math.exp(-1.0 / (0.045 * sr))
    for i in range(len(gated)):
        s = abs(gated[i])
        if s > env:
            env = att_coef * env + (1.0 - att_coef) * s
        else:
            env = rel_coef * env + (1.0 - rel_coef) * s
        envelope[i] = env

    thresh = 0.09
    gain = np.ones_like(gated)
    over = envelope > thresh
    gain[over] = (thresh / envelope[over]) ** (1.0 - 1.0 / 3.0)
    compressed = gated * gain

    # 6. Reduced Peak Target (0.36) for 8-ohm 0.5W Speaker
    # Reduced from 0.48 to provide comfortable, gentle, clean listening volume
    max_target = 0.36
    p99 = float(np.percentile(np.abs(compressed), 99.5))
    if p99 > 0:
        boosted = compressed * (max_target / p99)
    else:
        boosted = compressed
    limited = np.tanh(boosted / max_target) * max_target

    # 7. Trim leading/trailing silence safely
    active = np.where(np.abs(limited) > 0.006)[0]
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
    print("Speaker Target: 8-ohm 0.5-Watt Miniature Dynamic Driver")
    print("Acoustic Profile: 600 Hz HPF, 4200 Hz LPF, +3.5dB @ 2.8kHz EQ, 0.36 Peak Limit")
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

        # 1. Decode MP3 directly to 16 kHz Mono Float32
        decoded = miniaudio.decode_file(
            src_path,
            output_format=miniaudio.SampleFormat.FLOAT32,
            nchannels=1,
            sample_rate=TARGET_SAMPLE_RATE
        )
        mono = np.array(decoded.samples, dtype=np.float64)

        # 2. Apply clean speech equalization & anti-clipping DSP
        enhanced = enhance_audio_clean(mono, sr=TARGET_SAMPLE_RATE)

        # 3. Convert to 16-bit PCM
        pcm16 = np.clip(enhanced * 32767.0, -32768.0, 32767.0).astype(np.int16)
        pcm16_bytes = pcm16.tobytes()

        # Stats
        peak_val = np.max(np.abs(enhanced))
        rms_val = float(np.sqrt(np.mean(enhanced ** 2)))
        duration_sec = len(pcm16) / TARGET_SAMPLE_RATE

        # Write clean WAV file
        wav_path = os.path.join(AUDIO_OUT_DIR, item["wav_name"])
        with wave.open(wav_path, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(TARGET_SAMPLE_RATE)
            wav_file.writeframes(pcm16_bytes)
        print(f"  [WAV] Saved: {item['wav_name']} ({len(pcm16_bytes)} bytes, {duration_sec:.2f}s, Peak: {peak_val:.2f}, RMS: {rms_val:.3f})")

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
