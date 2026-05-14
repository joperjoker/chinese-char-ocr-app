# Chinese Character OCR App

A Flutter application that uses Google ML Kit to recognize Chinese characters from camera input and provides Pinyin pronunciation verification using the CEDICT dictionary.

## Features

- 📷 **Real-time OCR**: Capture Chinese characters using your device camera
- 🎯 **Accurate Recognition**: Uses Google ML Kit optimized for Chinese text
- 📖 **Pinyin Verification**: Cross-references recognized text with CEDICT dictionary
- 🔊 **Pronunciation Guide**: Displays tone-marked Hanyu Pinyin for each character
- 📱 **Full-screen Camera**: Immersive camera experience for better scanning
- 🎨 **Clean UI**: Minimalist interface focused on the camera feed

## Installation

### Prerequisites

- Flutter SDK (>= 3.0.0)
- Android Studio (for building APK)
- Android device with camera (API level 21+)

### Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/joperjoker/chinese-char-ocr-app.git
   cd chinese-char-ocr-app
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run on device**:
   ```bash
   flutter run
   ```

### Building APK

1. **Configure signing** (one-time setup):
   ```bash
   # Create keystore
   keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias chinese-ocr-app
   
   # Edit android/app/build.gradle and add signing config
   ```

2. **Build release APK**:
   ```bash
   flutter build apk --release
   ```

3. **Find your APK**:
   ```
   build/app/outputs/flutter-apk/app-release.apk
   ```

## Usage

1. **Launch the app** on your Android device
2. **Grant camera permissions** when prompted
3. **Point camera** at Chinese text or characters
4. **Wait for recognition** - valid Chinese characters will appear with Pinyin
5. **Pause/Resume** scanning using the bottom controls
6. **Clear results** to start fresh

## Technical Details

### Dependencies

- `google_mlkit_text_recognition`: Google ML Kit for Chinese OCR
- `camera`: Flutter camera plugin
- `lpinyin`: Pinyin conversion library
- `cedictJSON.json`: CEDICT dictionary (simplified Chinese)

## Troubleshooting

### No Camera Available
- Ensure your device has a working camera
- Check camera permissions in device settings
- Restart the app after granting permissions

### Recognition Not Working
- Ensure good lighting conditions
- Hold device steady for clear text
- Make sure text is in focus
- Check that CEDICT dictionary loaded successfully

### Pinyin Not Displaying
- Verify internet connection (if using online dictionary)
- Check that text is valid Chinese characters
- Ensure CEDICT dictionary is properly loaded

## License

This project is licensed under the MIT License - see the LICENSE file for details.