#!/usr/bin/env bash
# Instala o servidor RustDesk OSS (hbbs + hbbr) para o Suporte Remoto em uma VPS Linux.
# Uso (na VPS):  sudo bash instalar-servidor.sh
# Ao final, mostra a CHAVE PÚBLICA, que é usada em: 02-compilar.ps1 -Key "..."
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute com sudo:  sudo bash $0" >&2
  exit 1
fi

DIR=/opt/suporte-remoto

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Instalando Docker (script oficial get.docker.com)"
  curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "O plugin 'docker compose' não está disponível. Instale o Docker Compose v2." >&2
  exit 1
fi

echo "==> Criando $DIR"
mkdir -p "$DIR/data"
cat > "$DIR/compose.yml" <<'EOF'
services:
  hbbs:
    container_name: hbbs
    image: rustdesk/rustdesk-server:latest
    command: hbbs
    volumes:
      - ./data:/root
    network_mode: "host"
    depends_on:
      - hbbr
    restart: unless-stopped

  hbbr:
    container_name: hbbr
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    volumes:
      - ./data:/root
    network_mode: "host"
    restart: unless-stopped
EOF

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  echo "==> Liberando portas no ufw"
  ufw allow 21115:21117/tcp
  ufw allow 21116/udp
else
  echo "==> ufw inativo ou ausente: libere as portas no firewall do provedor (veja abaixo)."
fi

echo "==> Subindo hbbs e hbbr"
cd "$DIR"
docker compose up -d

for _ in $(seq 1 30); do
  [ -s "$DIR/data/id_ed25519.pub" ] && break
  sleep 1
done

echo
docker compose ps
echo
if [ -s "$DIR/data/id_ed25519.pub" ]; then
  echo "CHAVE PÚBLICA (envie esta linha):"
  cat "$DIR/data/id_ed25519.pub"; echo
else
  echo "A chave ainda não foi gerada. Veja: docker logs hbbs" >&2
fi
echo
echo "Portas que precisam estar liberadas no firewall do PROVEDOR da VPS:"
echo "  TCP 21115, 21116, 21117  e  UDP 21116"
echo "Faça BACKUP de $DIR/data/id_ed25519 e id_ed25519.pub (se a chave mudar, os executáveis param de conectar)."
