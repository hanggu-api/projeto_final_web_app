Write-Host "--- Building App for Firebase Test Lab ---"

# 1. Build the Debug APK
Write-Host "1. Building Debug APK..."
flutter build apk --debug
if ($LASTEXITCODE -ne 0) { Write-Error "Build Debug APK failed"; exit 1 }

# 2. Build the Android Test APK
Write-Host "2. Building Android Test APK..."
cd android
./gradlew app:assembleAndroidTest
if ($LASTEXITCODE -ne 0) { Write-Error "Build Android Test APK failed"; exit 1 }
cd ..

Write-Host "--- Build Complete! ---"
Write-Host ""
Write-Host "Artifacts:"
Write-Host "   1. App APK:  build/app/outputs/flutter-apk/app-debug.apk"
Write-Host "   2. Test APK: build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
Write-Host ""
Write-Host "To run in Firebase Test Lab:"
Write-Host "   gcloud firebase test android run --type instrumentation --app build/app/outputs/flutter-apk/app-debug.apk --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
