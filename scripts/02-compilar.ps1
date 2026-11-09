<#
.SYNOPSIS
  Compila o RustDesk (original ou personalizado) e gera o executável portátil.

.DESCRIPTION
  Reproduz localmente os passos do CI oficial do RustDesk 1.5.1 para Windows x64:
    1. vcpkg install (dependências C/C++: libvpx, libyuv, opus, aom, ffmpeg...)
    2. Geração da ponte Flutter <-> Rust (flutter_rust_bridge 1.80.1)
    3. python build.py --portable --flutter --skip-portable-pack --hwcodec --vram
    4. Empacotamento portátil oficial (libs/portable/generate.py -> rustdesk-portable-packer)

  Saída (padrão: <raiz>\dist):
    -Original : dist\original\rustdesk-1.5.1-portable.exe   (Etapa 2 — base funcional)
    padrão    : dist\SuporteRemotoSistema.exe               (Etapa 4 — versão personalizada)

.PARAMETER Server
  Endereço do seu hbbs (ex.: suporte.minhaempresa.com.br). Vazio = servidores públicos do RustDesk.
.PARAMETER Key
  Conteúdo do id_ed25519.pub do seu servidor.
.PARAMETER Relay
  Endereço do hbbr (opcional; normalmente o mesmo host do hbbs).
.PARAMETER Assinar
  Assina (Authenticode + carimbo de tempo) os .exe/.dll do aplicativo ANTES de empacotar e o
  executável final DEPOIS. Usa scripts\assinar.ps1; o certificado é conferido antes de compilar.
.PARAMETER CertThumbprint
  Impressão digital do certificado instalado no Windows (token USB, SimplySign...). Sem ela, o
  signtool escolhe o certificado automaticamente.
.PARAMETER PfxPath
  Arquivo .pfx sem senha — somente para TESTE com certificado autoassinado (junto com
  -PermitirCertificadoDeTeste). Não distribua executáveis assinados assim.

.EXAMPLE
  # Etapa 2: RustDesk original, sem modificações (em um clone separado e limpo)
  .\scripts\02-compilar.ps1 -SourceDir C:\src\rustdesk-original -Original

.EXAMPLE
  # Etapa 4: Suporte Remoto usando servidor próprio
  .\scripts\02-compilar.ps1 -Server suporte.minhaempresa.com.br -Key "AbCd...="

.EXAMPLE
  # Mesmo build, assinado com o certificado de assinatura de código instalado no Windows
  .\scripts\02-compilar.ps1 -Server suporte.minhaempresa.com.br -Key "AbCd...=" -Assinar -CertThumbprint "AB12...EF"
#>
param(
  [string]$SourceDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "rustdesk"),
  [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist"),
  [switch]$Original,
  [string]$Server = "",
  [string]$Key = "",
  [string]$Relay = "",
  [switch]$NoHwcodec,
  [switch]$SkipVcpkg,
  [switch]$RegenBridge,
  [switch]$Assinar,
  [string]$CertThumbprint = "",
  [string]$PfxPath = "",
  [string]$TimestampUrl = "http://timestamp.digicert.com",
  [switch]$PermitirCertificadoDeTeste
)

$ErrorActionPreference = "Stop"
$AppExe = "SuporteRemotoSistema.exe"
$Triplet = "x64-windows-static"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Run($exe, [string[]]$argv) {
  Write-Host "> $exe $($argv -join ' ')" -ForegroundColor DarkGray
  & $exe @argv
  if ($LASTEXITCODE -ne 0) { throw "Falhou ($LASTEXITCODE): $exe $($argv -join ' ')" }
}

$SourceDir = (Resolve-Path $SourceDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

if (-not $env:VCPKG_ROOT) { throw "VCPKG_ROOT não definido. Execute scripts\01-preparar-ambiente.ps1 e abra um novo terminal." }
if (-not $env:LIBCLANG_PATH) { $env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin" }
$env:VCPKG_DEFAULT_HOST_TRIPLET = $Triplet

if ($Original) {
  if (Test-Path (Join-Path $SourceDir "src\suporte_remoto.rs")) {
    throw "-Original deve apontar para um clone LIMPO do RustDesk (sem src\suporte_remoto.rs)."
  }
} elseif (-not (Test-Path (Join-Path $SourceDir "src\suporte_remoto.rs"))) {
  throw "Personalização não encontrada em $SourceDir (src\suporte_remoto.rs). Aplique o patch primeiro."
}

# Servidor embutido (lido por option_env! em src/suporte_remoto.rs). Sempre redefinido,
# para que um valor antigo do terminal não vá parar no executável sem querer.
$env:SUPORTE_REMOTO_SERVER = $Server.Trim()
$env:SUPORTE_REMOTO_KEY = $Key.Trim()
$env:SUPORTE_REMOTO_RELAY = $Relay.Trim()
if ($Server) { Write-Host "Servidor próprio: $Server  (relay: $(if ($Relay) { $Relay } else { 'informado pelo hbbs' }))" }
else { Write-Host "Sem servidor próprio: serão usados os servidores públicos do RustDesk." -ForegroundColor Yellow }
if ($Server -and -not $Key) { Write-Warning "Servidor definido sem -Key: a conexão não será verificada contra a chave do seu servidor." }

$signScript = Join-Path $PSScriptRoot "assinar.ps1"
$signOpts = @{ TimestampUrl = $TimestampUrl }
if ($CertThumbprint) { $signOpts.CertThumbprint = $CertThumbprint }
# Caminho absoluto: as assinaturas rodam depois do Push-Location para a pasta do código.
if ($PfxPath) { $signOpts.PfxPath = (Resolve-Path -LiteralPath $PfxPath).Path }
if ($PermitirCertificadoDeTeste) { $signOpts.PermitirCertificadoDeTeste = $true }
if ($Assinar) {
  if (-not $Original) { $signOpts.Descricao = [IO.Path]::GetFileNameWithoutExtension($AppExe) }
  Step "Conferindo signtool e certificado (antes de compilar)"
  & $signScript @signOpts -ChecarConfiguracao
} elseif ($CertThumbprint -or $PfxPath -or $PermitirCertificadoDeTeste) {
  throw "Parâmetros de assinatura informados sem -Assinar."
} else {
  Write-Host "Sem assinatura digital: o Windows SmartScreen mostrará 'Fornecedor desconhecido'." -ForegroundColor Yellow
}

Push-Location $SourceDir
try {
  Step "Versões"
  rustc --version
  flutter --version | Select-Object -First 1
  git log -1 --format="RustDesk: %H (%cs)"
  git describe --tags --always

  if (-not $SkipVcpkg) {
    Step "vcpkg install --triplet $Triplet (a primeira vez demora bastante: compila o ffmpeg)"
    Run "$env:VCPKG_ROOT\vcpkg.exe" @("install", "--triplet", $Triplet, "--x-install-root=$env:VCPKG_ROOT\installed")
  }

  $bridge = Join-Path $SourceDir "flutter\lib\generated_bridge.dart"
  if ($RegenBridge -or -not (Test-Path $bridge)) {
    Step "Gerando a ponte Flutter <-> Rust"
    Push-Location flutter
    try { Run flutter @("pub", "get") } finally { Pop-Location }
    Run flutter_rust_bridge_codegen @(
      "--rust-input", "./src/flutter_ffi.rs",
      "--dart-output", "./flutter/lib/generated_bridge.dart",
      "--c-output", "./flutter/macos/Runner/bridge_generated.h",
      "--llvm-path", "C:\Program Files\LLVM")
    Copy-Item -Force "flutter\macos\Runner\bridge_generated.h" "flutter\ios\Runner\bridge_generated.h"
  }

  Step "Compilando (cargo + flutter) com o build.py oficial"
  $buildArgs = @(".\build.py", "--portable", "--flutter", "--skip-portable-pack")
  if (-not $NoHwcodec) { $buildArgs += @("--hwcodec", "--vram") }
  Run python $buildArgs

  $release = Join-Path $SourceDir "flutter\build\windows\x64\runner\Release"
  if (-not (Test-Path (Join-Path $release "rustdesk.exe"))) { throw "rustdesk.exe não encontrado em $release" }

  Step "Montando a pasta do aplicativo"
  $appDir = Join-Path $OutDir $(if ($Original) { "original\app" } else { "app" })
  if (Test-Path $appDir) { Remove-Item -Recurse -Force $appDir }
  New-Item -ItemType Directory -Force -Path $appDir | Out-Null
  Copy-Item -Recurse -Force (Join-Path $release "*") $appDir
  if ($Original) {
    $innerExe = "rustdesk.exe"
  } else {
    # Mesmo procedimento dos clientes personalizados oficiais: o executável interno
    # recebe o nome do aplicativo (o RustDesk usa current_exe(), não um nome fixo).
    Rename-Item (Join-Path $appDir "rustdesk.exe") $AppExe
    $innerExe = $AppExe
  }

  if ($Assinar) {
    # Assina o que vai dentro do pacote: são esses arquivos que rodam após a extração.
    Step "Assinando os arquivos do aplicativo"
    $inner = @(Get-ChildItem -LiteralPath $appDir -Recurse -File |
      Where-Object { $_.Extension -in @(".exe", ".dll") } | ForEach-Object { $_.FullName })
    & $signScript @signOpts -Path $inner -PularJaAssinados
  }

  Step "Empacotando o executável portátil (libs/portable)"
  $manifest = Join-Path $SourceDir "res\manifest.xml"
  $manifestBak = "$manifest.bak"
  Copy-Item -Force $manifest $manifestBak
  try {
    # Igual ao CI oficial: remove dpiAware do manifesto do empacotador.
    (Get-Content $manifest) | Where-Object { $_ -notmatch "dpiAware" } | Set-Content -Encoding UTF8 $manifest
    Push-Location libs\portable
    try {
      Run python @("-m", "pip", "install", "-r", "requirements.txt")
      Run python @(".\generate.py", "-f", $appDir, "-o", ".", "-e", (Join-Path $appDir $innerExe))
    } finally { Pop-Location }
  } finally {
    Move-Item -Force $manifestBak $manifest
  }

  $packer = Join-Path $SourceDir "target\release\rustdesk-portable-packer.exe"
  if (-not (Test-Path $packer)) { throw "Empacotador não encontrado: $packer" }
  $final = if ($Original) { Join-Path $OutDir "original\rustdesk-1.5.1-portable.exe" } else { Join-Path $OutDir $AppExe }
  # Monta e assina em um arquivo temporário: se algo falhar, não fica um exe sem assinatura
  # (nem com o .sha256 de outro build) no lugar do arquivo de distribuição.
  $staging = "$final.novo.exe"
  Copy-Item -Force $packer $staging
  try {
    if ($Assinar) {
      Step "Assinando o executável final"
      & $signScript @signOpts -Path $staging
    }
    Remove-Item -Force -ErrorAction SilentlyContinue "$final.sha256"
    Move-Item -Force $staging $final
  } finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -Force $staging }
  }

  Step "Concluído"
  $hash = (Get-FileHash -Algorithm SHA256 $final).Hash
  Write-Host "Executável: $final" -ForegroundColor Green
  Write-Host "Tamanho:    $([math]::Round((Get-Item $final).Length / 1MB, 1)) MB"
  Write-Host "SHA-256:    $hash"
  Set-Content -Path "$final.sha256" -Value "$hash  $(Split-Path -Leaf $final)"
} finally {
  Pop-Location
}
