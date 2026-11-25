RawDenoise supports iOS and iPadOS 18 or later.

This update fixes the Files import handoff: the native picker requests local copies, dismisses before staging starts, and accepts provider files whose camera format is labeled as generic data. App-side staging runs off the main thread with per-file progress, cancellation, and visible errors. Originals remain unchanged.

- Select multiple RAW images from Files and denoise them individually, one at a time.
- Run the bundled RawForge TreeNet Super Light model locally through Core ML.
- Choose **DNG** (default) or **TIFF** for full-resolution 16-bit denoised exports.
- Save to **Files → On My iPhone/iPad → RawDenoise → denoised**.
- Keep originals, avoid overwriting exports, and show progress and per-image errors.
- Cancel between tiles; unfinished images remain queued for retry.

**Installation:** The versioned `RawDenoise-v…-unsigned.ipa` is unsigned and must be signed with your own Apple identity using a compatible sideloading tool. It is not an App Store or TestFlight package.

RAW format support depends on Apple's RAW decoder and the installed iOS version. DNG exports contain demosaiced linear Rec.2020 RGB with matching DNG color metadata; they do not reconstruct the original camera mosaic. Apple decoding differs from RawForge's desktop preprocessing. Keep the app open during processing.

Every push to master automatically increments the latest remote patch version, runs DNG structure/pixel checks through LibRaw and hosted simulator tests, archives for iOS devices, verifies the compiled Core ML model and Files settings, and publishes a new release after success. Physical-device RAW quality, memory use, editor compatibility, and Files integration still require device testing.

RawForge © 2025 rymuelle, MIT License. Source and license: https://github.com/rymuelle/RawForge
