@echo off
rem Release build for Google Play: Android App Bundle (.aab).
rem Play builds the per-device APKs from it, so no --split-per-abi here.
rem Needs android\key.properties + the upload keystore, otherwise the bundle
rem is signed with the debug key and Play rejects it.
rem  --obfuscate --split-debug-info : smaller Dart code; symbols go to build\debug-info
rem    (keep that folder for every uploaded version - it is needed to read crash reports:
rem     flutter symbolize -i stacktrace.txt -d build\debug-info\app.android-arm64.symbols)
rem Output: build\app\outputs\bundle\release\app-release.aab
rem Before each upload raise the version in pubspec.yaml (version: 1.0.0+1 -> 1.0.1+2);
rem the number after + must always grow.

flutter build appbundle --release --obfuscate --split-debug-info=build\debug-info %*
