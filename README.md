# Atrio

Atrio is a native iPhone app that uses the camera and flashlight to capture fingertip pulse signals and explore heart rhythm patterns associated with atrial fibrillation (AFib).

## Features

- Guided finger placement, with optional attachment instructions.
- Live camera-based PPG recording in 30-second and 60-second modes.
- Signal-quality checks, pulse-rate estimates, and annotated waveforms.
- On-device rhythm classification with SHAP feature explanations.
- Local measurement history, trends, repeat comparisons, and CSV/PDF exports.
- Heart-health education and Apple Maps searches for cardiologists or ECG clinics.

## Technologies

- **Swift:** SwiftUI, AVFoundation, CoreMedia, CoreVideo, Core ML, Swift Charts, UIKit, and PDFKit.
- **Python:** XGBoost, NumPy, SciPy, scikit-learn, and coremltools for data preparation, training, evaluation, and model conversion.
- **Development:** Xcode, iOS 17+, native Swift tests, and Python tests. No third-party UI framework.

## Model and results

The XGBoost model was trained on **16,798 ten-second PPG segments from 34 participants**, with 12 separate validation participants and 45 held-out test participants. Data came from [Liu PPGArrhythmiaDetection](https://github.com/zdzdliu/PPGArrhythmiaDetection); the original validation cohort was repurposed for training/validation in this new experiment.

On 22,360 retained source-dataset test segments, ROC AUC was **0.941**, with **97.3% sensitivity** and **78.1% specificity** at a 0.5 evaluation cutoff. The app uses different thresholds: 51.8% of retained test segments were inconclusive, and none received a positive AFib classification. Full metrics, exclusions, and split provenance are in `Research/Model/artifacts/`.

Atrio has not been clinically validated and cannot diagnose or rule out AFib, predict stroke, or estimate anemia. ECG-reference validation on iPhone recordings, systematic device testing, and attachment evaluation remain pending. The optional CNN comparison is not implemented. Dataset/model redistribution terms remain unresolved.

## Run the app

Open **`Atrio.xcodeproj`**, select the **`Atrio`** scheme, choose your signing team and a connected iPhone, then press **⌘R**. The project, scheme, app package, and installed app are named **Atrio**. The existing bundle identifier is retained so updates preserve saved recordings.

Real capture requires a physical iPhone. Camera access is requested when starting a measurement. Keep Device Hub screen sharing off during capture; it interfered with frames on the tested iPhone 13.

## Source and verification

App source is in `Atrio.swiftpm/Atrio/`, organized into App, Views, Components, Theme, Models, ViewModels, Services, and Resources. Model tools live in `Research/`; tests live in `Verification/`. Recordings remain local unless the user exports them.

```sh
swift test
python3 -m unittest discover -s Verification -p 'test_*.py'
bash Verification/run-phase2-checks.sh
```

For model reproduction on a Mac with Xcode, install `Research/Model/requirements-lock.txt` in an isolated Python environment, download the data with `Research/Dataset/fetch_liu.py`, and run `Research/Model/reproduce.sh <dataset-path> <python-executable>`. Reproduction overwrites local model artifacts and bundled model resources.
