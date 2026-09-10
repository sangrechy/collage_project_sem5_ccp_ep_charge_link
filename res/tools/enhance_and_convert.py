import os
import glob
import wave
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
    }
]

def biquad_filter(data, b, a):
    b0, b1, b2 = b[0] / a[0], b[1] / a[0], b[2] / a[0]
    a1, a2 = a[1] / a[0], a[2] / a[0]
    y = np.zeros_like(data)
    x1, x2, y1, y2 = 0.0, 0.0, 0.0, 0.0
    for n in range(len(data)):
        xn = data[n]
        yn = b0 * xn + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        y[n] = yn
        x2, x1 = x1, xn
        y2, y1 = y1, yn
    return y

def spectral_subtraction(audio, sr=16000, frame_len=512, hop_len=128):
    window = np.hanning(frame_len)
    num_frames = (len(audio) - frame_len) // hop_len + 1
    frames = np.lib.stride_tricks.as_strided(
        audio, shape=(num_frames, frame_len),
        strides=(audio.strides[0] * hop_len, audio.strides[0])
    )
    windowed = frames * window
    spectra = np.fft.rfft(windowed, axis=1)
    mag = np.abs(spectra)
    phase = np.angle(spectra)

    energies = np.sum(mag**2, axis=1)
    thresh = np.percentile(energies, 10)
    noise_frames = mag[energies <= thresh]
    if len(noise_frames) > 0:
        noise_profile = np.mean(noise_frames, axis=0, keepdims=True)
    else:
        noise_profile = np.min(mag, axis=0, keepdims=True)

    clean_mag = np.maximum(mag - 1.2 * noise_profile, 0.08 * mag)
    clean_spectra = clean_mag * np.exp(1j * phase)

    clean_frames = np.fft.irfft(clean_spectra, axis=1) * window
    out_len = (num_frames - 1) * hop_len + frame_len
    out_audio = np.zeros(out_len, dtype=np.float32)
    norm_window = np.zeros(out_len, dtype=np.float32)
    for i in range(num_frames):
        start = i * hop_len
        out_audio[start:start + frame_len] += clean_frames[i]
        norm_window[start:start + frame_len] += window**2

    norm_window = np.maximum(norm_window, 1e-6)
    out_audio /= norm_window

    if len(out_audio) < len(audio):
        out_audio = np.pad(out_audio, (0, len(audio) - len(out_audio)))
    else:
        out_audio = out_audio[:len(audio)]
    return out_audio

def enhance_audio_for_loudspeaker(data, sr=16000):
    # 1. Spectral Subtraction Denoising
    denoised = spectral_subtraction(data, sr=sr)
    
    # 2. High-pass filter at 120 Hz (cuts off useless sub-frequencies that cause 3W speaker distortion)
    fc = 120.0 / float(sr)
    w0 = 2.0 * np.pi * fc
    Q = 0.7071
    alpha = np.sin(w0) / (2.0 * Q)
    b_hp = [(1.0 + np.cos(w0)) / 2.0, -(1.0 + np.cos(w0)), (1.0 + np.cos(w0)) / 2.0]
    a_hp = [1.0 + alpha, -2.0 * np.cos(w0), 1.0 - alpha]
    hp_filtered = biquad_filter(denoised, b_hp, a_hp)
    
    # 3. Aggressive Speech Presence EQ: +5.0 dB at 3200 Hz (cuts through ambient room noise)
    f0 = 3200.0 / float(sr)
    gain_db = 5.0
    A = 10.0 ** (gain_db / 40.0)
    Q_eq = 1.0
    w0_eq = 2.0 * np.pi * f0
    alpha_eq = np.sin(w0_eq) / (2.0 * Q_eq)
    b_eq = [1.0 + alpha_eq * A, -2.0 * np.cos(w0_eq), 1.0 - alpha_eq * A]
    a_eq = [1.0 + alpha_eq / A, -2.0 * np.cos(w0_eq), 1.0 - alpha_eq / A]
    peaked = biquad_filter(hp_filtered, b_eq, a_eq)
    
    # 4. Multi-Stage Vocal Compression / Maximizer
    # Raises quieter consonants so every word is loud and clear across the room
    abs_audio = np.abs(peaked)
    threshold = 0.25
    ratio = 3.0
    compressed = np.where(abs_audio > threshold, 
                          np.sign(peaked) * (threshold + (abs_audio - threshold) / ratio), 
                          peaked * 1.3)
            
    # 5. Trim leading/trailing silence safely
    abs_comp = np.abs(compressed)
    active_indices = np.where(abs_comp > 0.02)[0]
    if len(active_indices) > 0:
        start_idx = max(0, active_indices[0] - int(0.020 * sr))
        end_idx = min(len(compressed), active_indices[-1] + int(0.040 * sr))
        compressed = compressed[start_idx:end_idx]

    if len(compressed) % 2 != 0:
        compressed = compressed[:-1]
            
    # 6. Smooth anti-click endpoints (5ms)
    fade_len = int(sr * 0.005)
    fade_in = np.sin(np.linspace(0, np.pi / 2, fade_len)) ** 2
    fade_out = np.cos(np.linspace(0, np.pi / 2, fade_len)) ** 2
    compressed[:fade_len] *= fade_in
    compressed[-fade_len:] *= fade_out
    
    # 7. 100% Full-Scale Normalization (0.999 peak) for maximum physical 3W drive
    peak = np.max(np.abs(compressed))
    if peak > 0:
        compressed = (compressed / peak) * 0.999
        
    return compressed

def process_all():
    print("=== CHARGELINK MAXIMUM-LOUDNESS AUDIO ENHANCEMENT ===")
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
        
        # Decode and resample to 16kHz Mono
        decoded = miniaudio.decode_file(src_path, nchannels=1, sample_rate=TARGET_SAMPLE_RATE)
        raw_pcm = np.frombuffer(decoded.samples, dtype=np.int16).astype(np.float32) / 32768.0
        
        # Apply maximum loudness room-filling DSP
        enhanced = enhance_audio_for_loudspeaker(raw_pcm, sr=TARGET_SAMPLE_RATE)
        
        # Convert to 16-bit PCM
        pcm16 = np.clip(enhanced * 32767.0, -32768.0, 32767.0).astype(np.int16)
        pcm16_bytes = pcm16.tobytes()
        
        # Write enhanced WAV file
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

    print("\nAll audio files maximized and firmware headers generated!")

if __name__ == "__main__":
    process_all()
