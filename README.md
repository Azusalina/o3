# RawDenoise

Native SwiftUI app for **iOS / iPadOS 18.0 and above**. Select multiple RAW images from Files, then process them **one image at a time**, on device, with a bundled RawForge Core ML model.

## Run

GitHub Actions builds and tests every push to `master`. Pushing a version tag such as `v1.0` also publishes a GitHub release with an **unsigned IPA**, release notes, and SHA-256 checksum. The IPA requires signing through a compatible sideloading tool before installation. No signing credentials are stored in this repository.

1. Open `RawDenoise.xcodeproj` in Xcode 16 or newer on a Mac.
2. Select the **RawDenoise** target. Set your signing team and a unique bundle identifier under Signing & Capabilities.
3. Select your iPhone or iPad running iOS 18 or later and run.
4. Tap **Select RAW files**, select the files, and tap **Denoise queued images**.

No Python, network access, server, or model download is required by the app. The converted model is checked in.

## Saved files

Open **Files → Browse → On My iPhone / On My iPad → RawDenoise → denoised**. The folder is created automatically in the app's Documents directory, which is exposed to Files through `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`.

Output is full-resolution **16-bit linear Rec.2020 RGB TIFF**, with an embedded color profile and upright image data. It is a developed image, not a new sensor RAW or DNG. Names follow `original-denoised.tiff`, with numeric suffixes for repeat exports. Original files are preserved. Removing the app also removes its local Documents folder; copy exports elsewhere in Files if needed.

Keep the app in the foreground. Cancellation stops between tiles and before committing an export. Entering the background requests cancellation; an unfinished image remains queued for retry. A failed image shows its error and the queue continues with the next image. Clear the list and select a failed file again to retry it. Existing exports remain available after relaunch; the transient selection queue does not persist.

## Pipeline and boundaries

- RAW selection uses the system Files importer with multiple selection and the RAW image content type. Selected files are copied sequentially into temporary app storage using security-scoped access and file coordination, including provider-backed files.
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

**Xcode build, Core ML inference on Apple hardware, RAW camera samples, Files visibility, visual quality, and device memory use have not been verified here.** This environment has no Apple SDK or simulator. The included GitHub Actions workflow builds the app and runs the hosted XCTest suite on macOS when pushed; it has not been triggered by this work.

Run tests on a Mac with **Product → Test**, or:

```sh
xcodebuild -project RawDenoise.xcodeproj -scheme RawDenoise \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

Choose an installed simulator name. Tests cover awkward tile sizes and normalized overlap, TIFF bit depth and row/channel order, real Core ML inference against the upstream PyTorch reference, and pre-cancelled processing. Before distribution, also test camera RAWs and ProRAW, portrait/landscape orientation, provider imports, mixed valid/invalid batches, repeat filenames, cancellation, low storage, and representative large images on a physical iOS 18 device.

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
