@echo off
rem Release build for Android, optimised for size.
rem  --split-per-abi : one APK per CPU type instead of one fat APK with all three
rem  --obfuscate --split-debug-info : smaller Dart code (libapp.so); symbols go to build\debug-info
rem Output (build\app\outputs\flutter-apk):
rem  app-arm64-v8a-release.apk   - almost every phone/tablet from the last ~8 years
rem  app-armeabi-v7a-release.apk - old 32-bit phones
rem  app-x86_64-release.apk      - emulators / Chromebooks
rem To read an obfuscated crash stack trace:
rem  flutter symbolize -i stacktrace.txt -d build\debug-info\app.android-arm64.symbols

flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build\debug-info %*
