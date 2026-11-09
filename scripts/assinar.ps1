<#
.SYNOPSIS
  Assina executáveis e DLLs com Authenticode (signtool) e carimbo de tempo, e confere o resultado.

.DESCRIPTION
  Usado pelo 02-compilar.ps1 (parâmetro -Assinar), mas também funciona sozinho.

  De onde vem o certificado:
    -CertThumbprint  Impressão digital (SHA-1) de um certificado de assinatura de código instalado no
                     Windows (CurrentUser\My ou LocalMachine\My). É assim que aparecem os certificados
                     em token USB e os de nuvem, como o SimplySign da Certum (com o SimplySign Desktop
                     conectado).
    (nenhum)         O signtool escolhe sozinho o melhor certificado de assinatura de código (/a).
    -PfxPath         Arquivo .pfx SEM senha. Apenas para TESTES com certificado autoassinado:
                     certificados públicos emitidos desde junho de 2023 ficam em hardware/nuvem, não em .pfx.

  O carimbo de tempo (-TimestampUrl) mantém a assinatura válida depois que o certificado vencer.

.PARAMETER ChecarConfiguracao
  Só confere se o signtool e o certificado estão disponíveis (não assina nada). O 02-compilar.ps1
  usa isso antes de compilar, para não descobrir o problema só no fim.

.PARAMETER PermitirCertificadoDeTeste
  Aceita assinatura que o Windows não considera confiável (certificado autoassinado de teste).
  Nunca use para distribuir: o SmartScreen trata esse arquivo como não assinado.

.EXAMPLE
  .\scripts\assinar.ps1 -Path dist\SuporteRemotoSistema.exe -CertThumbprint "AB12...EF"
#>
param(
  [string[]]$Path = @(),
  [string]$CertThumbprint = "",
  [string]$PfxPath = "",
  [string]$TimestampUrl = "http://timestamp.digicert.com",
  [string]$Descricao = "",
  [string]$SignTool = "",
  [switch]$PularJaAssinados,
  [switch]$PermitirCertificadoDeTeste,
  [switch]$ChecarConfiguracao
)

$ErrorActionPreference = "Stop"

function Find-SignTool {
  if ($SignTool) {
    if (-not (Test-Path -LiteralPath $SignTool -PathType Leaf)) { throw "signtool não encontrado em: $SignTool" }
    return (Resolve-Path -LiteralPath $SignTool).Path
  }
  $kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
  $found = @(Get-ChildItem -Path $kits -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+(\.\d+){3}$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName "x64\signtool.exe" } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
  if ($found.Count -gt 0) { return $found[0] }
  $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw ("signtool.exe não encontrado. Ele vem com o Windows SDK " +
    "(instalado pelo scripts\01-preparar-ambiente.ps1). Ou informe -SignTool <caminho>.")
}

function Get-SigningCert([string]$thumb) {
  # Machine = $true quando está no repositório da máquina: o signtool então precisa de /sm.
  foreach ($store in "CurrentUser", "LocalMachine") {
    $c = Get-ChildItem -Path "Cert:\$store\My" -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb }
    if ($c) { return @{ Cert = @($c)[0]; Machine = ($store -eq "LocalMachine") } }
  }
  return $null
}

function Assert-CertUsable($cert) {
  if (-not $cert.HasPrivateKey) { throw "O certificado $($cert.Thumbprint) não tem chave privada acessível nesta máquina." }
  if ($cert.NotAfter -lt (Get-Date)) { throw "O certificado $($cert.Thumbprint) venceu em $($cert.NotAfter)." }
  # Confere uso "assinatura de código" e confiança da cadeia já aqui, e não só depois do build.
  $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
  $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
  [void]$chain.ChainPolicy.ApplicationPolicy.Add((New-Object System.Security.Cryptography.Oid "1.3.6.1.5.5.7.3.3"))
  if ($chain.Build($cert)) { return }
  $status = @($chain.ChainStatus)
  $why = ($status | ForEach-Object { $_.StatusInformation.Trim() }) -join " "
  if (@($status | Where-Object { $_.Status -eq "NotValidForUsage" }).Count -gt 0) {
    throw "O certificado $($cert.Thumbprint) não é de assinatura de código: $why"
  }
  if (-not $PermitirCertificadoDeTeste) {
    throw "O Windows não confia no certificado $($cert.Thumbprint): $why (para certificado de teste, use -PermitirCertificadoDeTeste)"
  }
  Write-Warning "Certificado não confiável aceito por -PermitirCertificadoDeTeste."
}

$st = Find-SignTool

if ($CertThumbprint -and $PfxPath) { throw "Use -CertThumbprint OU -PfxPath, não os dois." }

$expectedThumb = ""
$certArgs = @()
if ($CertThumbprint) {
  # Copiar a impressão digital do certmgr costuma trazer espaços e caracteres invisíveis.
  $thumb = ($CertThumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
  if ($thumb.Length -ne 40) { throw "-CertThumbprint inválido: esperava 40 caracteres hexadecimais (SHA-1)." }
  $found = Get-SigningCert $thumb
  if (-not $found) {
    throw ("Certificado $thumb não encontrado em CurrentUser\My nem LocalMachine\My. " +
      "Conecte o token/SimplySign e confira com: Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert")
  }
  $cert = $found.Cert
  Assert-CertUsable $cert
  $expectedThumb = $thumb
  $certArgs = @("/sha1", $thumb)
  if ($found.Machine) { $certArgs += "/sm" }
  Write-Host "Certificado: $($cert.Subject) (vence em $($cert.NotAfter.ToString('dd/MM/yyyy')))"
} elseif ($PfxPath) {
  if (-not (Test-Path -LiteralPath $PfxPath -PathType Leaf)) { throw "Arquivo .pfx não encontrado: $PfxPath" }
  $pfx = (Resolve-Path -LiteralPath $PfxPath).Path
  try {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $pfx, ""
  } catch {
    throw "Não foi possível abrir $pfx sem senha (só .pfx sem senha é aceito): $($_.Exception.Message)"
  }
  Assert-CertUsable $cert
  $expectedThumb = $cert.Thumbprint
  $certArgs = @("/f", $pfx)
  Write-Warning "Assinando com arquivo .pfx (uso de TESTE)."
} else {
  # O signtool /a procura no repositório do usuário; com /sm, no da máquina.
  $valid = { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) }
  $userCerts = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object $valid)
  $machineCerts = @(Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object $valid)
  if ($userCerts.Count -gt 0) {
    $certArgs = @("/a")
    $n = $userCerts.Count
  } elseif ($machineCerts.Count -gt 0) {
    $certArgs = @("/a", "/sm")
    $n = $machineCerts.Count
  } else {
    throw ("Nenhum certificado de assinatura de código válido encontrado no Windows. " +
      "Instale/conecte o certificado ou informe -CertThumbprint.")
  }
  Write-Host "Certificado: escolha automática do signtool (/a) entre $n disponível(is). Prefira -CertThumbprint."
}

Write-Host "signtool: $st"
if ($ChecarConfiguracao) { return }

if ($Path.Count -eq 0) { throw "Informe os arquivos em -Path." }
$files = @()
foreach ($p in $Path) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Arquivo não encontrado: $p" }
  $files += (Resolve-Path -LiteralPath $p).Path
}

if ($PularJaAssinados) {
  # Mantém a assinatura original de componentes de terceiros já assinados (ex.: DLLs da Microsoft).
  $files = @($files | Where-Object {
    $sig = Get-AuthenticodeSignature -LiteralPath $_
    if ($sig.Status -eq "Valid") { Write-Host "  (já assinado por $($sig.SignerCertificate.Subject)) $(Split-Path -Leaf $_)"; $false }
    else { $true }
  })
}
if ($files.Count -eq 0) { Write-Host "Nada a assinar."; return }

$signArgs = @("sign", "/fd", "SHA256", "/tr", $TimestampUrl, "/td", "SHA256") + $certArgs
if ($Descricao) { $signArgs += @("/d", $Descricao) }

# Servidores de carimbo de tempo às vezes falham por instantes: tenta de novo.
$batchSize = 20
for ($i = 0; $i -lt $files.Count; $i += $batchSize) {
  $batch = @($files[$i..([math]::Min($i + $batchSize, $files.Count) - 1)])
  $ok = $false
  for ($try = 1; $try -le 3 -and -not $ok; $try++) {
    Write-Host "> signtool $($signArgs -join ' ') ($($batch.Count) arquivo(s), tentativa $try)" -ForegroundColor DarkGray
    & $st @signArgs @batch
    if ($LASTEXITCODE -eq 0) { $ok = $true }
    elseif ($try -lt 3) { Start-Sleep -Seconds (5 * $try) }
  }
  if (-not $ok) { throw "signtool falhou ao assinar: $($batch -join ', ')" }
}

# Confere cada arquivo de forma independente do signtool.
$untrusted = 0
foreach ($f in $files) {
  $sig = Get-AuthenticodeSignature -LiteralPath $f
  $name = Split-Path -Leaf $f
  if (-not $sig.SignerCertificate -or $sig.Status -in @("NotSigned", "HashMismatch", "NotSupportedFileFormat", "Incompatible")) {
    throw "Assinatura ausente ou inválida em $name ($($sig.Status)): $($sig.StatusMessage)"
  }
  if ($expectedThumb -and $sig.SignerCertificate.Thumbprint -ne $expectedThumb) {
    throw "$name foi assinado com outro certificado ($($sig.SignerCertificate.Thumbprint))."
  }
  if (-not $sig.TimeStamperCertificate) {
    throw "$name ficou sem carimbo de tempo; a assinatura deixaria de valer quando o certificado vencesse."
  }
  if ($sig.Status -ne "Valid") {
    if (-not $PermitirCertificadoDeTeste) {
      throw "Assinatura de $name não é confiável neste Windows ($($sig.Status)): $($sig.StatusMessage)"
    }
    $untrusted++
  }
}
if ($untrusted -gt 0) {
  Write-Warning ("$untrusted arquivo(s) assinado(s) com certificado NÃO confiável (teste). " +
    "Não distribua: para o Windows isso equivale a não ter assinatura.")
}
Write-Host "Assinados e conferidos: $($files.Count) arquivo(s)." -ForegroundColor Green
