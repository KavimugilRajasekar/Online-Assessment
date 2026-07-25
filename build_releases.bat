@echo off
echo ========================================
echo Flutter Cross-Platform Build Script
echo ========================================
echo.

:: Set Flutter path (update if needed)
set FLUTTER_PATH=C:\tools\flutter
set PATH=%FLUTTER_PATH%\bin;%PATH%

:: Clean previous builds
echo [1/6] Cleaning previous builds...
flutter clean
echo.

:: Get dependencies
echo [2/6] Getting dependencies...
flutter pub get
echo.

:: Build for Android (supports multiple ABIs)
echo [3/6] Building for Android...
echo   - Building APK (arm64-v8a, armeabi-v7a, x86_64)
flutter build apk --release --split-per-abi
echo   - Building App Bundle
flutter build appbundle --release
echo.

:: Build for iOS (only on macOS)
echo [4/6] Building for iOS...
if "%OS%"=="Windows_NT" (
    echo   Skipping iOS build (not supported on Windows)
) else (
    flutter build ios --release
)
echo.

:: Build for Web
echo [5/6] Building for Web...
flutter build web --release
echo.

:: Build for Windows
echo [6/6] Building for Windows...
flutter build windows --release
echo.

echo ========================================
echo Build Complete!
echo ========================================
echo.
echo Output locations:
echo   Android APKs: build/app/outputs/flutter-apk/
echo   Android AAB:  build/app/outputs/bundle/release/
echo   Web:          build/web/
echo   Windows:      build/windows/runner/Release/
if not "%OS%"=="Windows_NT" (
    echo   iOS:          build/ios/iphoneos/
)
echo.
pause