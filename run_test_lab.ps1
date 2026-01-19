# Script para enviar APK para o Firebase Test Lab
# Requer Google Cloud SDK (gcloud) instalado

$PROJECT_ID = "cardapyia-service-2025"
$APK_PATH = "build/app/outputs/flutter-apk/app-debug.apk"

# Verifica se gcloud está instalado
if (!(Get-Command "gcloud" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Google Cloud SDK (gcloud) não encontrado." -ForegroundColor Red
    Write-Host "Por favor, instale o Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
    Write-Host "Após instalar, execute: gcloud auth login"
    exit 1
}

# Verifica se o APK existe
if (!(Test-Path $APK_PATH)) {
    Write-Host "⚠️ APK não encontrado. Compilando..." -ForegroundColor Yellow
    flutter build apk --debug
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Falha na compilação." -ForegroundColor Red
        exit 1
    }
}

Write-Host "🚀 Enviando APK para o Firebase Test Lab (Robo Test)..." -ForegroundColor Cyan

# Define o projeto
gcloud config set project $PROJECT_ID

# Envia para o Test Lab
# Tipo: robo (automático, sem script de teste)
# Dispositivo: Pixel 2, API 30 (Exemplo)
gcloud firebase test android run `
    --app $APK_PATH `
    --device model=Pixel2,version=30,locale=pt_BR,orientation=portrait `
    --timeout 90s

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Teste iniciado com sucesso! Verifique o console do Firebase para os resultados." -ForegroundColor Green
} else {
    Write-Host "❌ Erro ao iniciar o teste." -ForegroundColor Red
}
