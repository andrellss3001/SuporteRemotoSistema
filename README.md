# Suporte Remoto V1 (Windows 10/11 x64)

Aplicativo de suporte técnico remoto baseado no **RustDesk 1.5.1** (AGPL-3.0), com modificações mínimas:
nome próprio, interface simplificada em português, tema escuro, executável portátil `SuporteRemotoSistema.exe`
e aprovação reforçada (**senha temporária E aceite do cliente**).

> **Status (08/11/2026):**
> - **Compilado:** `dist\SuporteRemotoSistema.exe` (24,1 MB) foi gerado nesta máquina com `scripts\02-compilar.ps1`
>   a partir de `C:\src\DeskATOS`. Verificado: `--version` = 1.5.1, propriedades do arquivo "SuporteRemotoSistema",
>   módulo de personalização presente no `librustdesk.dll`, tela "SUPORTE REMOTO SISTEMA" presente no `app.so`,
>   engine Flutter do RustDesk empacotada.
> - **Servidor próprio configurado:** recompilado com `-Server/-Relay 201.76.43.217` e a chave do hbbs
>   (SHA-256 do `id_ed25519.pub` conferido na VPS). Aberto nesta máquina: status "Pronto para receber
>   suporte.", registro UDP e teste de NAT respondidos por `201.76.43.217` (log em `%APPDATA%\SuporteRemotoSistema\log`).
>   Título da janela e processo: `SuporteRemotoSistema`. Versões anteriores (nome `SuporteRemoto`) em `dist\anterior\`.
> - **Não testado entre dois computadores** (Etapa 5): conexão, aceite, controle e transferência de arquivos
>   ainda precisam ser verificados.
> - **Etapa 2 (RustDesk original) não executada** nesta máquina.
> - **Sem ícone próprio** e `kSuporteRemotoSourceUrl` ainda com o endereço de exemplo.

---

## 1. Estrutura desta pasta

| Caminho | Conteúdo |
|---|---|
| `rustdesk/` | Clone do RustDesk na tag **1.5.1**, já com as modificações aplicadas |
| `patches/suporte-remoto-rustdesk-1.5.1.patch` | As mesmas modificações em forma de patch (para reaplicar em um clone limpo) |
| `scripts/01-preparar-ambiente.ps1` | Instala e configura todas as ferramentas nas versões corretas |
| `scripts/02-compilar.ps1` | Compila e gera o executável portátil (original ou personalizado); `-Assinar` assina |
| `scripts/assinar.ps1` | Assina `.exe`/`.dll` com Authenticode + carimbo de tempo e confere (usado pelo `02`) |
| `servidor/compose.yml` | Servidor próprio RustDesk OSS (hbbs + hbbr) com Docker |
| `servidor/instalar-servidor.sh` | Instala o servidor em uma VPS Ubuntu e mostra a chave pública |
| `dist/` | Executáveis gerados pelo `02-compilar.ps1` |

**No git:** só `patches/`, `scripts/`, `servidor/`, o README e a licença. As pastas `rustdesk/` (4+ GB com o
build) e `dist/` ficam fora (`.gitignore`). Para recriar `rustdesk/` a partir do repositório, clone a tag 1.5.1
e aplique o patch (seção 5.4). Depois de alterar algo em `rustdesk/`, **regenere o patch** antes do commit:

```powershell
cd rustdesk
git add -N src/suporte_remoto.rs flutter/lib/desktop/pages/suporte_remoto_home.dart
git diff > ..\patches\suporte-remoto-rustdesk-1.5.1.patch
git reset -q
```

**Versão base identificada**

- Repositório: https://github.com/rustdesk/rustdesk — tag `1.5.1`
- Commit: `23e5bb471a040d62f0a6ad52591fb30784265b73` (01/11/2026)
- Submódulo `libs/hbb_common`: `fae47e024dd83cef6aaecde0aa7d11731df11649`

> A 1.5.1 é a release mais recente e saiu uma semana antes desta análise. Se preferir uma base com mais tempo
> de uso, o mesmo patch deve se aplicar com poucos ajustes à 1.5.0 — confira com `git apply --check`.

---

## 2. Ferramentas e versões (do CI oficial da tag 1.5.1)

Extraídas de `.github/workflows/flutter-build.yml` e `bridge.yml` do próprio repositório:

| Ferramenta | Versão | Observação |
|---|---|---|
| Visual Studio 2022 Build Tools | carga "Desenvolvimento para desktop com C++" + Windows SDK | MSVC, linker, CMake |
| Rust | **1.75** (`x86_64-pc-windows-msvc`) | O CI do Windows usa 1.75; versões novas podem quebrar |
| LLVM / Clang | **15.0.6** | Necessário para o bindgen (`LIBCLANG_PATH`) |
| Flutter | **3.24.5** (stable) | + engine customizada do RustDesk + patch do DropdownMenu |
| vcpkg | commit **9e593bb18ea69cc5095e012465dcd675a822ed0d** | triplet `x64-windows-static` |
| flutter_rust_bridge_codegen | **1.80.1** (`--features uuid`) | Gera a ponte Dart/Rust |
| cargo-expand | **1.0.95** | Usado pelo gerador da ponte |
| Python | 3.x | Executa `build.py` e o empacotador |
| Git | qualquer recente | |

> **Caminho curto obrigatório.** Com `LongPathsEnabled=0` (padrão do Windows), o `flutter build windows`
> falha com "O sistema não pode encontrar o caminho especificado" ao ler pacotes do Pub quando a pasta do
> projeto é profunda: a partir de `...\Visual Studio 2022\Projetos\Github\DeskATOS\rustdesk\flutter\build\windows\x64\flutter`
> o caminho relativo até o cache do Pub chega a 260 caracteres (verificado em 08/11/2026).
> Compile a partir de um caminho curto, por exemplo `C:\src\DeskATOS`, ou de uma junção:
> `mklink /J C:\sr-build\rustdesk "<pasta>\rustdesk"` e `02-compilar.ps1 -SourceDir C:\sr-build\rustdesk`.
> Se mudar o caminho, apague antes `rustdesk\flutter\build` (o cache do CMake guarda o caminho antigo).

Espaço em disco: reserve **~40 GB** (o vcpkg compila ffmpeg, libvpx, aom etc.).
Tempo da primeira compilação: **1 a 3 horas**, conforme a máquina.

---

## 3. Etapa 1 — Preparar o ambiente

Em um PowerShell, na pasta deste projeto:

```bash
powershell -ExecutionPolicy Bypass -File .\scripts\01-preparar-ambiente.ps1
```

O script (idempotente — pode ser executado de novo):

1. Instala via `winget`: Git, Python 3.12, Rustup, LLVM 15.0.6 e VS 2022 Build Tools (C++).
2. Instala o Rust 1.75 e fixa essa versão na pasta `rustdesk/` (`rustup override set 1.75`).
3. Clona o vcpkg em `C:\sr-tools\vcpkg` no commit exato e define `VCPKG_ROOT`.
4. Clona o Flutter 3.24.5 em `C:\sr-tools\flutter`, aplica o patch oficial
   `.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff` e substitui a engine Windows pela
   engine do RustDesk (mesmo passo do CI; ver flutter/flutter#155685).
5. Instala `cargo-expand 1.0.95` e `flutter_rust_bridge_codegen 1.80.1`.

**Validação:** ao final, o script imprime as versões. Abra um **novo** terminal e confirme:

```bash
rustc --version
```

Dentro de `rustdesk/` deve aparecer `rustc 1.75.x`. Execute também `flutter doctor` — o item
"Visual Studio - develop Windows apps" deve estar OK.

---

## 4. Etapa 2 — Compilar o RustDesk ORIGINAL (base funcional)

Antes de personalizar, prove que o ambiente gera um RustDesk que funciona. Use um clone **limpo**, separado:

```bash
git clone --branch 1.5.1 --recurse-submodules https://github.com/rustdesk/rustdesk.git C:\src\rustdesk-original
```

```bash
cd C:\src\rustdesk-original; rustup override set 1.75
```

```bash
powershell -ExecutionPolicy Bypass -File .\scripts\02-compilar.ps1 -SourceDir C:\src\rustdesk-original -Original
```

O script executa exatamente os passos do CI oficial:

```
vcpkg install --triplet x64-windows-static --x-install-root=%VCPKG_ROOT%\installed
flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h
python build.py --portable --flutter --skip-portable-pack --hwcodec --vram
cd libs/portable && python generate.py -f <Release> -o . -e <Release>/rustdesk.exe
```

**Saída:** `dist\original\rustdesk-1.5.1-portable.exe` (e a pasta descompactada em `dist\original\app\`).

**Validação:**
1. Execute `dist\original\app\rustdesk.exe --version` → deve imprimir `1.5.1`.
2. Abra `rustdesk-1.5.1-portable.exe` em dois PCs e conecte um ao outro pelo ID.

Se a Etapa 2 falhar, o problema é de ambiente, não das modificações. Resolva antes de seguir.

> Dica: se o `vcpkg install` ou o recurso `hwcodec` der problema, `-NoHwcodec` compila sem codecs de
> hardware (usa VP9/AV1 em software — funciona, só consome mais CPU).

---

## 5. Etapa 3 — O que foi modificado (arquivos reais)

Todas as alterações estão em `rustdesk/` e em `patches/suporte-remoto-rustdesk-1.5.1.patch`
(diff: 8 arquivos, 2 novos + 6 existentes com ganchos de 1 a 13 linhas).

| Arquivo | Tipo | O que faz |
|---|---|---|
| `src/suporte_remoto.rs` | **novo** | Toda a personalização em tempo de execução (ver abaixo) |
| `src/lib.rs` | +1 linha | `mod suporte_remoto;` |
| `src/common.rs` | +1 linha | `load_custom_client()` chama `suporte_remoto::apply()` |
| `src/server/connection.rs` | +12/−1 | Exige senha correta **e** clique em "Aceitar" |
| `flutter/lib/desktop/pages/suporte_remoto_home.dart` | **novo** | Tela inicial simplificada em PT-BR |
| `flutter/lib/desktop/pages/desktop_home_page.dart` | +4 linhas | Exibe a tela nova (`kSuporteRemoto = true`) |
| `flutter/windows/runner/Runner.rc` | 6 linhas | Propriedades do executável (nome, descrição, copyright) |
| `libs/portable/Cargo.toml` | 4 linhas | Propriedades do `SuporteRemotoSistema.exe` portátil |

### 5.1 `src/suporte_remoto.rs` — o que é configurado

Usa o mesmo mecanismo interno que os "clientes personalizados" do RustDesk usam
(`APP_NAME`, `HARD_SETTINGS`, `OVERWRITE_SETTINGS`…), só que definido no código, porque o arquivo
`custom.txt` oficial precisa ser assinado com a chave do RustDesk Server Pro (pago).

| Configuração | Valor | Efeito |
|---|---|---|
| `APP_NAME` | `SuporteRemotoSistema` | Título, textos ("RustDesk" → "SuporteRemotoSistema"), pasta de config `%APPDATA%\SuporteRemotoSistema` separada de um RustDesk instalado. Sem espaço porque o RustDesk só aceita letras, números e hífen. |
| `disable-installation` | `Y` | Sem instalação: só modo portátil, sem serviço do Windows |
| `disable-settings`, `disable-ab`, `disable-account` | `Y` | Sem configurações, catálogo de endereços e contas |
| `hide-help-cards` | `Y` | Sem cartões de ajuda/instalação |
| `lang` / `theme` | `pt-br` / `dark` | Português do Brasil e tema escuro forçados |
| `verification-method` | `use-temporary-password` | Só senha temporária — nunca senha permanente (sem acesso não assistido) |
| `approve-mode` | vazio (senha + clique) | Nunca `password`, que esconderia a janela de controle do cliente |
| `enable-tunnel`, `enable-terminal` | `N` | Desliga túnel TCP e terminal remoto (fora do escopo da V1) |
| `allow-remote-config-modification` | `N` | O técnico não altera as configurações do cliente |
| `custom-rendezvous-server`, `relay-server`, `key` | via variáveis de compilação | Servidor próprio (ver seção 9) |

### 5.2 `src/server/connection.rs` — senha **e** autorização

No RustDesk original (modo "senha e clique"), o técnico entra com a senha **ou** o cliente clica em Aceitar.
Na V1, os três ganchos fazem o seguinte:

1. Login **sem senha** → o cliente não recebe nenhum pedido; o técnico vê "Senha necessária".
2. **Senha errada** → mensagem de erro para o técnico; o cliente **não** recebe botão "Aceitar".
3. **Senha correta** → o cliente vê a janela com os botões "Aceitar" / "Dispensar"; o técnico vê
   "Aguarde o lado remoto aceitar sua solicitação…". Só após o clique a sessão começa.

Diferença em relação ao original: o RustDesk guarda uma "sessão recente" após a senha correta, para
reconectar sem nova aprovação por 30 s. Na V1 essa sessão **não é criada** (gancho em `validate_password`),
porque permitiria repetir o login e pular o clique do cliente. Consequência: uma queda de conexão exige
nova senha e novo clique.

### 5.3 Tela inicial

```
SUPORTE REMOTO SISTEMA
┌ MEU COMPUTADOR ─────────────┐  ┌ ACESSAR CLIENTE ─────────────┐
│ Meu ID: 123 456 789         │  │ ID do computador remoto:      │
│ Senha temporária: ********⟳ │  │ [_______________________]     │
│ [Copiar ID] [Mostrar senha] │  │ [        Conectar        ]    │
│ ● Status: Pronto para       │  │ [  Transferir arquivos   ]    │
│   receber suporte.          │  │                               │
└─────────────────────────────┘  └───────────────────────────────┘
```

Durante um atendimento aparece uma faixa vermelha "ATENDIMENTO REMOTO EM ANDAMENTO".
No rodapé: "Baseado no RustDesk (AGPL-3.0). Código-fonte: …" — **edite `kSuporteRemotoSourceUrl`**
em `suporte_remoto_home.dart` com o endereço do seu repositório antes de distribuir.

O que **não** foi reescrito (usa a interface original do RustDesk, já traduzida para PT-BR):

- **Janela da sessão remota**: tela, mouse/teclado, tela cheia, desconectar, botão de transferência de arquivos.
- **Transferência de arquivos**: os dois sentidos, com barra de progresso.
- **Janela de controle do cliente** (gerenciador de conexão): mostra quem está conectado,
  botões Aceitar/Dispensar e **Desconectar** a qualquer momento. É o indicador visível do atendimento.

### 5.4 Aplicar o patch em um clone limpo (manutenção)

```bash
git clone --branch 1.5.1 --recurse-submodules https://github.com/rustdesk/rustdesk.git rustdesk-novo
```

```bash
cd rustdesk-novo; git apply --check ..\patches\suporte-remoto-rustdesk-1.5.1.patch; git apply ..\patches\suporte-remoto-rustdesk-1.5.1.patch
```

Para uma versão futura do RustDesk, se o `--check` falhar, os pontos de conflito serão os poucos ganchos
listados acima; o código novo fica em dois arquivos separados.

---

## 6. Etapa 4 — Gerar o `SuporteRemotoSistema.exe`

### Ícone (antes de distribuir)

O RustDesk vem com o logotipo dele. O nome e o logo "RustDesk" são marcas registradas — substitua
estes arquivos pelo seu ícone, mantendo os mesmos nomes e formatos:

| Arquivo | Onde aparece |
|---|---|
| `rustdesk/res/icon.ico` | `SuporteRemotoSistema.exe` (o arquivo que o cliente baixa) |
| `rustdesk/flutter/windows/runner/resources/app_icon.ico` | Janela e barra de tarefas |
| `rustdesk/res/tray-icon.ico` | Ícone da bandeja |
| `rustdesk/flutter/assets/icon.svg` | Logo dentro do aplicativo (janela de controle etc.) |

### Compilar

Usando os servidores públicos do RustDesk (bom para testar):

```bash
powershell -ExecutionPolicy Bypass -File .\scripts\02-compilar.ps1
```

Usando o seu servidor (recomendado para produção — ver seção 9):

```bash
powershell -ExecutionPolicy Bypass -File .\scripts\02-compilar.ps1 -Server suporte.suaempresa.com.br -Relay suporte.suaempresa.com.br -Key "CONTEUDO_DO_id_ed25519.pub"
```

### Onde fica o executável

| Arquivo | Descrição |
|---|---|
| `dist\SuporteRemotoSistema.exe` | **O arquivo para enviar ao cliente** (portátil, um único arquivo) |
| `dist\SuporteRemotoSistema.exe.sha256` | Hash para conferência |
| `dist\app\` | Pasta descompactada (útil para depuração; tem `SuporteRemotoSistema.exe` + DLLs) |
| `rustdesk\target\release\rustdesk-portable-packer.exe` | Saída bruta do empacotador oficial |

### Como o portátil funciona

O `SuporteRemotoSistema.exe` é o empacotador oficial do RustDesk (`libs/portable`): ele contém a aplicação
compactada, extrai para `%LOCALAPPDATA%\suporteremoto\` (sem precisar de administrador) e executa.
Não cria serviço, não grava no registro de inicialização e não fica rodando depois de fechado
(**confirme isso no teste da Etapa 5**). Nada é instalado: `disable-installation` está ativo.

**Validação da Etapa 4:**
1. Botão direito em `dist\SuporteRemotoSistema.exe` → Propriedades → Detalhes: "SuporteRemotoSistema".
2. Execute: a janela abre em português, tema escuro, com "SUPORTE REMOTO SISTEMA", ID e senha.
3. O status deve passar para "Pronto para receber suporte." em alguns segundos.
4. Não deve existir ícone de Configurações nem opção de instalar.

---

## 7. Etapa 5 — Teste entre dois computadores

Use **dois PCs em redes diferentes** (ex.: um no Wi-Fi da empresa e outro no 4G roteado do celular), ambos
com Windows 10 ou 11 x64. Marque cada item:

**Cliente (PC A)**
- [ ] Abre `SuporteRemotoSistema.exe` sem instalar; aparece ID e senha (oculta).
- [ ] "Mostrar senha" exibe a senha; "Copiar ID" copia sem espaços.
- [ ] Status "Pronto para receber suporte."

**Técnico (PC B)**
- [ ] Digita o ID do PC A → Conectar → aparece pedido de senha.
- [ ] Senha **errada** → erro para o técnico; **nada** aparece no PC A.
- [ ] Senha **correta** → técnico vê "Aguarde o lado remoto aceitar…"; PC A vê "Aceitar" / "Dispensar".
- [ ] PC A clica **Dispensar** → técnico é desconectado.
- [ ] Repetir e PC A clica **Aceitar** → técnico vê a tela.
- [ ] Mouse e teclado funcionam (digitar no Bloco de Notas do PC A).
- [ ] Tela cheia liga/desliga.
- [ ] Transferência de arquivos: enviar um arquivo grande (>100 MB) B→A e outro A→B; a barra de progresso avança.
- [ ] PC A mostra a faixa vermelha "ATENDIMENTO REMOTO EM ANDAMENTO" e a janela de controle.
- [ ] PC A clica **Desconectar** → sessão encerra imediatamente no PC B.
- [ ] Técnico clica Desconectar na barra da sessão → encerra.
- [ ] Fechar o app no PC A → Gerenciador de Tarefas sem processos `SuporteRemotoSistema.exe` restantes.
- [ ] Clicar ⟳ gera nova senha; a senha antiga deixa de funcionar.

**Direto x relay:** na sessão, o indicador de conexão mostra se ela é direta (P2P) ou via relay.
Teste também com um dos PCs em rede corporativa restritiva: deve funcionar via relay, mais lento.

**Janelas de administrador (UAC):** sem elevação, o técnico **não** consegue clicar em janelas
"Executar como administrador" nem no prompt do UAC (limitação de segurança do Windows para
processos não elevados). Teste o caminho oficial:
- [ ] Na janela de controle do PC A, o botão **"Elevar"** (ou o técnico usa "Pedir Elevação" na barra da sessão)
      mostra o prompt do UAC **ao cliente**; o cliente autoriza; o técnico passa a controlar janelas de administrador.
- Alternativa: o cliente executa o `SuporteRemotoSistema.exe` com "Executar como administrador".

Logs para diagnóstico: `%APPDATA%\SuporteRemotoSistema\log\`.

---

## 8. Etapa 6 — Corrigir e preparar a distribuição

1. **Assinatura de código** (fortemente recomendado): sem assinatura, o Windows SmartScreen mostrará
   "O Windows protegeu o computador" e antivírus podem acusar falso positivo (ferramentas de acesso remoto
   são alvo frequente). A assinatura troca "Fornecedor desconhecido" pelo seu nome; o aviso azul vai sumindo
   conforme o arquivo/certificado ganha reputação (nem certificado EV dá reputação imediata desde 2024).

   **Certificado.** Opções viáveis no Brasil: Certum *Open Source Code Signing* (pessoa física, projeto de
   código aberto, a partir de ~€49) ou certificado OV comercial no nome da empresa (Sectigo, DigiCert...).
   O Azure Artifact Signing (antigo Trusted Signing) não aceita o Brasil até o momento. Certificados emitidos
   desde 2023 ficam em token USB ou na nuvem (ex.: SimplySign da Certum) e aparecem no repositório de
   certificados do Windows; desde 27/02/2026 valem no máximo 459 dias.

   **Como assinar.** Com o certificado conectado, descubra a impressão digital:
   ```bash
   powershell -Command "Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-List Subject,Thumbprint,NotAfter"
   ```
   e compile com `-Assinar`:
   ```bash
   powershell -ExecutionPolicy Bypass -File .\scripts\02-compilar.ps1 -SkipVcpkg -Server 201.76.43.217 -Relay 201.76.43.217 -Key "CHAVE" -Assinar -CertThumbprint "IMPRESSAO_DIGITAL"
   ```
   O script confere signtool, certificado (uso "assinatura de código", validade, chave privada e confiança)
   **antes** de compilar; assina os `.exe`/`.dll` do aplicativo **antes** do empacotamento (são eles que
   rodam após a extração) e o `SuporteRemotoSistema.exe` final **depois**, sempre com carimbo de tempo
   (`-TimestampUrl`, padrão DigiCert), e confere cada arquivo com `Get-AuthenticodeSignature`. O executável
   final é montado num arquivo temporário: se a assinatura falhar, nenhum exe sem assinatura fica em `dist\`.
   Para assinar um arquivo avulso: `.\scripts\assinar.ps1 -Path arquivo.exe -CertThumbprint "..."`.

   **Testado** nesta máquina apenas com certificado autoassinado de teste (`-PfxPath` + `-PermitirCertificadoDeTeste`):
   assinatura, carimbo de tempo, verificação, recusa de certificado não confiável ou de outro uso, e o app
   assinado abre e conecta normalmente. **Ainda não testado com um certificado real.**

   Depois de publicar cada versão, envie o executável para análise da Microsoft
   (https://www.microsoft.com/wdsi/filesubmission, opção "Software developer") para acelerar a reputação, e
   evite recompilar sem necessidade: cada build é um arquivo novo.
2. **Publique o código-fonte** (obrigação da AGPL — seção 10) e ajuste `kSuporteRemotoSourceUrl`.
3. Distribua por um link HTTPS seu e informe o SHA-256 aos clientes.
4. Registre a versão: "Suporte Remoto V1 — baseado no RustDesk 1.5.1 (commit 23e5bb4)".

---

## 9. Conexão pela internet: servidor público ou próprio?

O RustDesk usa dois serviços: **hbbs** (registro de ID e intermediação da conexão direta / NAT hole
punching) e **hbbr** (relay, quando a conexão direta não é possível). O cliente **não** precisa abrir portas.

### Servidores públicos do RustDesk

- Funcionam sem configuração (é o padrão se você compilar sem `-Server`) — ótimo para a Etapa 5.
- São gratuitos e compartilhados, **sem SLA, sem garantia de disponibilidade ou desempenho**; o relay público
  costuma ser lento e congestionado.
- Não encontrei na documentação oficial (rustdesk.com/docs e FAQ, consultados em 08/11/2026) termos de uso
  explícitos que permitam ou proíbam uso comercial. A própria documentação recomenda servidor próprio para
  quem quer controlar a infraestrutura. Como sua empresa depende disso para atender clientes, **não é adequado
  para uso profissional**. Recomendação: servidor próprio.

### Servidor próprio RustDesk OSS (gratuito, AGPL-3.0)

Uma VPS Linux pequena (1 vCPU, 1 GB RAM) atende bem; a banda importa mais quando o relay é usado.

1. Libere no firewall do **servidor**: TCP 21115, 21116, 21117 e UDP 21116.
   (21114 é da API do **Server Pro, pago** — não use. 21118/21119 são do cliente web — deixe fechadas.)
2. Instale o Docker e suba o compose deste projeto:
   ```bash
   bash <(wget -qO- https://get.docker.com)
   ```
   ```bash
   mkdir ~/rustdesk && cd ~/rustdesk   # copie servidor/compose.yml para cá
   ```
   ```bash
   sudo docker compose up -d
   ```
3. Pegue a chave pública:
   ```bash
   cat ~/rustdesk/data/id_ed25519.pub
   ```
4. Crie um DNS (ex.: `suporte.suaempresa.com.br`) apontando para o IP do servidor e compile com
   `-Server`, `-Relay` e `-Key` (seção 6). O servidor e a chave ficam embutidos no executável — o cliente
   não precisa configurar nada.
5. **Faça backup de `data/id_ed25519*`**: se a chave mudar, todos os executáveis distribuídos param de conectar.

Alternativa: `servidor/instalar-servidor.sh` faz os passos 2–3 em `/opt/suporte-remoto` (é o que está em uso).

**Avisos esperados no log do cliente com servidor OSS:** `HTTP POST to http://<servidor>:21114/api/sysinfo`
(ou `/api/heartbeat`) `failed ... trying TCP proxy fallback`. O cliente tenta a API do Server Pro, que não
existe no servidor OSS; não afeta ID, senha, conexão nem relay.

Recursos **pagos** (Server Pro) que **não** foram usados: console web, API (21114), contas de usuário,
catálogo de endereços centralizado, logs de auditoria, gerador de cliente personalizado com `custom.txt` assinado.

---

## 10. Licença AGPL-3.0, avisos e marcas

O RustDesk é licenciado sob **AGPL-3.0** (`rustdesk/LICENCE`). Ao distribuir o `SuporteRemotoSistema.exe`:

1. **Código-fonte correspondente:** quem recebe o executável tem direito ao código-fonte completo **da
   versão distribuída**, incluindo suas modificações e scripts de build. Forma simples: publique este projeto
   (pasta `rustdesk/` modificada ou clone + patch, e `scripts/`) em um repositório público e informe o link no
   aplicativo (rodapé) e na página de download.
2. **Mesma licença:** a obra derivada também é AGPL-3.0. Você não pode adicionar restrições (ex.: proibir
   engenharia reversa) para quem recebe o programa.
3. **Avisos:** não remova avisos de copyright/licença existentes. Os arquivos novos marcam que são
   modificações; o `Runner.rc` e o `Cargo.toml` do empacotador mantêm "Copyright © Purslane Tech Pte. Ltd.".
   Recomenda-se manter um registro das alterações com data (este README + o patch cumprem esse papel).
4. **Seção 13 (uso pela rede):** se você modificar e oferecer o software para interação remota, também
   precisa oferecer o código-fonte a esses usuários — o link no rodapé cobre isso.
5. **Marca:** a licença de software **não** concede uso da marca/logo "RustDesk". Por isso o produto se chama
   "SuporteRemotoSistema", deve usar ícone próprio e só menciona "baseado no RustDesk" de forma descritiva.
   Não apresente o produto como sendo do RustDesk ou endossado por ele.
6. **Sem garantia:** a AGPL vem "sem garantia"; mantenha esse aviso na documentação aos clientes.

> Isto é uma orientação técnica, não parecer jurídico. Para uso comercial relevante, consulte um advogado.

---

## 11. Limitações conhecidas da V1

- **Não compilado nem testado aqui** — os comandos foram montados a partir do CI oficial da tag 1.5.1.
- O nome interno é `SuporteRemotoSistema` (sem espaço), que aparece no título da janela e nos textos traduzidos;
  "SUPORTE REMOTO SISTEMA" aparece na tela inicial. Restrição do próprio RustDesk.
- A barra de ferramentas da sessão remota é a original (tem opções extras como gravação, chat, qualidade de
  imagem). Não foi simplificada para preservar a estabilidade; pode ser feito numa V2.
- Sem elevação, janelas de administrador/UAC não podem ser controladas (use "Elevar"; seção 7).
- A engine Flutter customizada vem de `rustdesk/engine` release `main` (tag móvel, como no CI oficial).
- Os pacotes opcionais do CI (driver de impressora remota, display virtual `usbmmidd`,
  `RustDeskTempTopMostWindow` do modo de privacidade) **não** são incluídos — não fazem parte da V1.
- Windows 7/8 e ARM64 não são alvo da V1.
