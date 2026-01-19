@echo off
REM Script para conectar automaticamente o Moto G34 via Wi-Fi
echo Conectando ao dispositivo via Wi-Fi...
adb connect 192.168.1.4:5555
echo.
echo Dispositivos conectados:
adb devices
echo.
echo Pronto! Agora você pode executar: flutter run -d 192.168.1.4:5555
pause
