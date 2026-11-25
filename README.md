# RawDenoise

Native SwiftUI app for **iOS / iPadOS 18.0 and above**. Select multiple RAW images from Files, then process them **one image at a time**, on device, with a bundled RawForge Core ML model.

## Run

GitHub Actions builds, tests, and releases every push to `master`. It reads the remote version tags, increments the latest patch version (for example, `v1.0` → `v1.0.1`), and publishes a new tag and release only after validation succeeds. The app version and IPA filename match that version. Existing releases are preserved. Manual version-tag builds are also supported. The **unsigned IPA** requires signing through a compatible sideloading tool before installation. No signing credentials are stored in this repository.

1. Open `RawDenoise.xcodeproj` in Xcode 16 or newer on a Mac.
2. Select the **RawDenoise** target. Set your signing team and a unique bundle identifier under Signing & Capabilities.
3. Select your iPhone or iPad running iOS 18 or later and run.
4. Tap **Select RAW files**, select the files, choose **DNG** or **TIFF** under Output, and tap **Denoise queued images**.

No Python, network access, server, or model download is required by the app. The converted model is checked in.

## Saved files

Open **Files → Browse → On My iPhone / On My iPad → RawDenoise → denoised**. The folder is created automatically in the app's Documents directory, which is exposed to Files through `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`.

The default output is full-resolution **16-bit linear DNG**. This contains demosaiced, denoised Rec.2020 RGB samples with DNG LinearRaw tags, a D65 color matrix, neutral white balance, and explicit black/white levels. It preserves the processed linear data for RAW editors; it does not reconstruct the camera's original sensor mosaic. Source camera matrices are deliberately not copied because the pixel color space has changed. TIFF remains available with an embedded linear Rec.2020 profile.

Names follow `original-denoised.dng` or `original-denoised.tiff`, with numeric suffixes for repeat exports. Original files are preserved. Removing the app also removes its local Documents folder; copy exports elsewhere in Files if needed.

Keep the app in the foreground. Cancellation stops between tiles and before committing an export. Entering the background requests cancellation; an unfinished image remains queued for retry. A failed image shows its error and the queue continues with the next image. Clear the list and select a failed file again to retry it. Existing exports remain available after relaunch; the transient selection queue does not persist.

## Pipeline and boundaries

- RAW selection uses a native Files picker in copy/import mode with multiple selection. Generic data files are selectable to accommodate camera extensions that providers do not label as RAW; non-RAW extensions are rejected with an error. Files materializes provider documents before handing over local copies. After the picker dismisses, a background worker stages files sequentially in chunks with progress and cancellation, without a second coordinated provider read.
- Apple `CIRAWFilter` decodes at full size with tone boosts, sharpening, and supported noise reduction controls disabled. The model receives clipped linear Rec.2020 RGB, not an embedded JPEG preview. RAW/camera compatibility follows Apple's decoder on the installed OS.
- The bundled model is RawForge **TreeNetDenoiseSuperLight**, converted from the official signed `ShadowWeightedL1_super_light.pt` release. Inputs are float32 NCHW `[1,3,256,256]` and conditioning `[1,1] = min(ISO,65535)/6400`. Missing ISO metadata defaults to ISO 100.
- Core ML uses `.all` compute units, allowing the system to choose available hardware. This does not promise Neural Engine placement. Model arithmetic is float32 to prioritize fidelity.
- Each image is processed with 256-pixel tiles, 64-pixel overlap, normalized edge blending, and replicated padding for small images. A disk-backed RGB16 accumulator avoids a full floating-point image allocation. The decoder and TIFF encoder still use memory; large RAW files require substantial storage and device validation. Dimensions above 150 megapixels or 30,000 pixels per side are rejected.
- Apple demosaicing, camera color handling, and white balance differ from RawForge's Python `RawHandler` / Malvar2004 front end. This is an iOS port of RawForge's model and tensor contract, **not a claim of pixel-identical output to its desktop CLI**. X-Trans-specific and six-channel JDD models are not included.

## Validation

Performed in the Linux development environment:

- Verified the source weights against RawForge's upstream RSA-PSS signature and pinned SHA-256.
- Converted the real model to an iOS 18 ML Program and inspected its input/output names, shapes, and float32 types.
- Executed the upstream PyTorch denoiser on a deterministic test image and generated a binary reference for the simulator's Core ML comparison.

The [v1.0 GitHub Actions run](https://github.com/Azusalina/o3/actions/runs/44650314064) compiled and archived successfully using Xcode 16.4 and passed all four original simulator tests. The DNG workflow additionally compiles the real Swift writer into a command-line fixture generator, verifies its tags and pixel data using `tifffile` and LibRaw, and tests opening its output with Apple's RAW decoder in the simulator.

**Physical-device RAW camera samples, Files visibility, visual quality in third-party editors, and device memory use remain unverified.** The local development environment has no Apple SDK or simulator; current Apple-platform validation runs through GitHub Actions.

Run tests on a Mac with **Product → Test**, or:

```sh
xcodebuild -project RawDenoise.xcodeproj -scheme RawDenoise \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

Choose an installed simulator name. Tests cover awkward tile sizes and normalized overlap, TIFF bit depth and row/channel order, real Core ML inference against the upstream PyTorch reference, DNG decoding, and pre-cancelled processing. Before distribution, also test camera RAWs and ProRAW, portrait/landscape orientation, provider imports, mixed valid/invalid batches, repeat filenames, cancellation, low storage, and representative large images on a physical iOS 18 device.

## Reproduce the model

Use Python 3.11:

```sh
python3.11 -m venv .venv
. .venv/bin/activate
pip install -r scripts/requirements-model.txt
python scripts/convert_model.py
```

The converter downloads only the official weights and rejects a SHA-256 mismatch. To compare converted predictions with PyTorch on macOS, add `--verify`. To regenerate the checked-in test reference, run `python scripts/generate_reference.py .model-cache/model.pt`. `python3 scripts/generate_project.py` regenerates the checked-in Xcode project without XcodeGen or CocoaPods.

## Sources and attribution

- [RawForge source and model registry](https://github.com/rymuelle/RawForge/tree/79f17700c29765b28a4cf5bd1b6d90bc7e3eb7f2), MIT, © 2025 rymuelle. License included in app resources at `RawDenoise/RawForge-LICENSE.txt`.
- [Official source model release](https://github.com/rymuelle/RawRefinery/releases/tag/v1.2.1-alpha). SHA-256: `e05e460e02fbeb745ab2984edf4f4898c5035f6a475183be4ee16f52226b45b1`.
- [Apple CIRAWFilter](https://developer.apple.com/documentation/coreimage/cirawfilter) and [Core ML conversion documentation](https://apple.github.io/coremltools/docs-guides/source/convert-to-ml-program.html).
- [Adobe Digital Negative specification](https://helpx.adobe.com/content/dam/help/en/photoshop/pdf/DNG_Spec_1_7_1_0.pdf). The writer uses a DNG 1.4 header with backward compatibility 1.3 and uncompressed RGB16 strips.
