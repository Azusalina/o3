RawDenoise v1.0 supports iOS and iPadOS 18 or later.

- Select multiple RAW images from Files and denoise them individually, one at a time.
- Run the bundled RawForge TreeNet Super Light model locally through Core ML.
- Save full-resolution, 16-bit linear Rec.2020 TIFFs to **Files → On My iPhone/iPad → RawDenoise → denoised**.
- Keep originals, avoid overwriting exports, and show progress and per-image errors.
- Cancel between tiles; unfinished images remain queued for retry.

**Installation:** `RawDenoise-v1.0-unsigned.ipa` is unsigned and must be signed with your own Apple identity using a compatible sideloading tool. It is not an App Store or TestFlight package.

RAW format support depends on Apple's RAW decoder and the installed iOS version. Exports are developed TIFF images, not sensor RAW/DNG files. Apple decoding differs from RawForge's desktop preprocessing. Keep the app open during processing.

The release workflow runs hosted simulator tests, archives for iOS devices, and verifies that the compiled Core ML model and Files settings are packaged. Physical-device RAW quality, memory use, and Files integration still require device testing.

RawForge © 2025 rymuelle, MIT License. Source and license: https://github.com/rymuelle/RawForge
