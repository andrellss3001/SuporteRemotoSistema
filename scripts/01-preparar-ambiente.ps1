<#
.SYNOPSIS
  Prepara uma máquina Windows 10/11 x64 para compilar o RustDesk 1.5.1 (base do Suporte Remoto).

.DESCRIPTION
  Versões copiadas do CI oficial do RustDesk na tag 1.5.1
  (.github/workflows/flutter-build.yml e bridge.yml):
    Rust 1.75 | LLVM 15.0.6 | Flutter 3.24.5 (+ engine customizada RustDesk)
    vcpkg commit 9e593bb18ea69cc5095e012465dcd675a822ed0d | triplet x64-windows-static
    flutter_rust_bridge_codegen 1.80.1 | cargo-expand 1.0.95

  O script é idempotente: pode ser executado de novo se algo falhar.
  Execute em um PowerShell normal (não precisa ser administrador, exceto o winget,
  que pode pedir elevação via UAC).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\01-preparar-ambiente.ps1
#>
param(
  [string]$ToolsDir = "C:\sr-tools",
  [switch]$SkipWinget
)

$ErrorActionPreference = "Stop"

$RUST_VERSION        = "1.75"
$LLVM_VERSION        = "15.0.6"
$FLUTTER_VERSION     = "3.24.5"
$VCPKG_COMMIT_ID     = "9e593bb18ea69cc5095e012465dcd675a822ed0d"
$FRB_VERSION         = "1.80.1"
$CARGO_EXPAND_VERSION = "1.0.95"
$ENGINE_URL          = "https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip"

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$RustDeskDir = Join-Path $RepoRoot "rustdesk"
$FlutterDir = Join-Path $ToolsDir "flutter"
$VcpkgDir   = Join-Path $ToolsDir "vcpkg"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Run($exe, [string[]]$argv) {
  & $exe @argv
  if ($LASTEXITCODE -ne 0) { throw "Falhou ($LASTEXITCODE): $exe $($argv -join ' ')" }
}
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [Environment]::GetEnvironmentVariable("Path", "User")
}

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

# 1. Ferramentas de sistema via winget -----------------------------------------
if (-not $SkipWinget) {
  Step "Instalando ferramentas do sistema com winget"
  $pkgs = @(
    @{ id = "Git.Git" },
    @{ id = "Python.Python.3.12" },
    @{ id = "Rustlang.Rustup" },
    @{ id = "LLVM.LLVM"; ver = $LLVM_VERSION },
    @{ id = "Microsoft.VisualStudio.2022.BuildTools";
       override = "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.CMake.Project --includeRecommended" }
  )
  foreach ($p in $pkgs) {
    $wargs = @("install", "--id", $p.id, "-e", "--accept-package-agreements", "--accept-source-agreements")
    if ($p.ver) { $wargs += @("--version", $p.ver) }
    if ($p.override) { $wargs += @("--override", $p.override) }
    Write-Host "winget $($wargs -join ' ')"
    & winget @wargs
    # winget retorna código != 0 quando o pacote já está instalado; não é erro fatal.
  }
  Refresh-Path
}

if (-not (Test-Path "C:\Program Files\LLVM\bin\libclang.dll")) {
  throw ("LLVM não encontrado em C:\Program Files\LLVM. Instale manualmente: " +
         "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/LLVM-$LLVM_VERSION-win64.exe")
}
[Environment]::SetEnvironmentVariable("LIBCLANG_PATH", "C:\Program Files\LLVM\bin", "User")
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"

# 2. Rust ----------------------------------------------------------------------
Step "Rust $RUST_VERSION (x86_64-pc-windows-msvc)"
if (-not (Have rustup)) { $env:Path += ";$env:USERPROFILE\.cargo\bin" }
Run rustup @("toolchain", "install", $RUST_VERSION, "--profile", "minimal", "-c", "rustfmt", "--target", "x86_64-pc-windows-msvc")
Push-Location $RustDeskDir
Run rustup @("override", "set", $RUST_VERSION)
Pop-Location

# 3. vcpkg ---------------------------------------------------------------------
Step "vcpkg no commit $VCPKG_COMMIT_ID"
if (-not (Test-Path (Join-Path $VcpkgDir ".git"))) {
  Run git @("clone", "https://github.com/microsoft/vcpkg", $VcpkgDir)
}
Push-Location $VcpkgDir
Run git @("fetch", "origin", $VCPKG_COMMIT_ID)
Run git @("checkout", "--force", $VCPKG_COMMIT_ID)
Run ".\bootstrap-vcpkg.bat" @("-disableMetrics")
Pop-Location
[Environment]::SetEnvironmentVariable("VCPKG_ROOT", $VcpkgDir, "User")
$env:VCPKG_ROOT = $VcpkgDir

# 4. Flutter -------------------------------------------------------------------
Step "Flutter $FLUTTER_VERSION"
if (-not (Test-Path (Join-Path $FlutterDir "bin\flutter.bat"))) {
  Run git @("clone", "--depth", "1", "-b", $FLUTTER_VERSION, "https://github.com/flutter/flutter.git", $FlutterDir)
}
$env:Path = "$FlutterDir\bin;$env:Path"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$FlutterDir\bin*") {
  [Environment]::SetEnvironmentVariable("Path", "$FlutterDir\bin;$userPath", "User")
}
Run flutter @("config", "--no-analytics")
Run flutter @("config", "--enable-windows-desktop")
Run flutter @("precache", "--windows")

Step "Patch oficial do RustDesk para o DropdownMenu do Flutter 3.24"
$patch = Join-Path $RustDeskDir ".github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff"
Push-Location $FlutterDir
# PS 5.1 + EAP=Stop transformaria o stderr do git em erro fatal; o código de saída decide.
$ErrorActionPreference = "Continue"
& git apply --check $patch 2>$null
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -eq 0) { Run git @("apply", $patch) } else { Write-Host "Patch já aplicado (ou não aplicável) — ignorando." }
Pop-Location

Step "Engine Flutter customizada do RustDesk (flutter/flutter#155685)"
$engineDst = Join-Path $FlutterDir "bin\cache\artifacts\engine\windows-x64-release"
$marker = Join-Path $engineDst ".rustdesk-engine"
if (-not (Test-Path $marker)) {
  $zip = Join-Path $ToolsDir "windows-x64-release.zip"
  $tmp = Join-Path $ToolsDir "windows-x64-release"
  Invoke-WebRequest -Uri $ENGINE_URL -OutFile $zip
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  Expand-Archive -Path $zip -DestinationPath $tmp
  Copy-Item -Recurse -Force (Join-Path $tmp "*") $engineDst
  Set-Content -Path $marker -Value $ENGINE_URL
}

# 5. Gerador da ponte Flutter <-> Rust -----------------------------------------
Step "flutter_rust_bridge_codegen $FRB_VERSION e cargo-expand $CARGO_EXPAND_VERSION"
Push-Location $ToolsDir
Run cargo @("+$RUST_VERSION", "install", "cargo-expand", "--version", $CARGO_EXPAND_VERSION, "--locked")
Run cargo @("+$RUST_VERSION", "install", "flutter_rust_bridge_codegen", "--version", $FRB_VERSION, "--features", "uuid", "--locked")
Pop-Location

Step "Verificação"
rustc "+$RUST_VERSION" --version
flutter --version
& "$VcpkgDir\vcpkg.exe" version | Select-Object -First 1
& "C:\Program Files\LLVM\bin\clang.exe" --version | Select-Object -First 1
python --version
Write-Host "`nAmbiente pronto. Abra um NOVO terminal e execute scripts\02-compilar.ps1" -ForegroundColor Green
