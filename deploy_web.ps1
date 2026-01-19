Write-Host "🚀 Iniciando Deploy Web para Produção..."

# 1. Build do Flutter Web com a URL da API de Produção
Write-Host "📦 Construindo aplicativo web..."
flutter build web --release --dart-define "API_URL=https://projeto-central-backend.carrobomebarato.workers.dev/api"

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Erro no build do Flutter. Abortando deploy."
    exit $LASTEXITCODE
}

# 2. Deploy para o Firebase Hosting
Write-Host "🔥 Enviando para o Firebase Hosting..."
firebase deploy --only hosting

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Deploy concluído com sucesso!"
    Write-Host "🌐 Acesse em: https://cardapyia-service-2025.web.app"
} else {
    Write-Error "❌ Erro ao enviar para o Firebase."
}
