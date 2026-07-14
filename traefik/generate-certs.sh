#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CERT_DIR="${CERT_DIR:-$SCRIPT_DIR/certs}"
DOMAIN="${DOMAIN:-local.dev}"
WILDCARD_DOMAIN="*.${DOMAIN}"

mkdir -p "$CERT_DIR"

if [ -f "$CERT_DIR/server.crt" ] && [ -f "$CERT_DIR/server.key" ]; then
    echo "Сертификаты уже существуют, пропускаем генерацию"
    exit 0
fi

echo "Генерация локальных TLS-сертификатов для ${DOMAIN}..."


echo "Использую mkcert"
mkcert -install >/dev/null 2>&1 || echo "CA mkcert не установился автоматически; при необходимости выполните 'mkcert -install' вручную"
mkcert -cert-file "$CERT_DIR/server.crt" -key-file "$CERT_DIR/server.key" "$DOMAIN" "$WILDCARD_DOMAIN" >/dev/null 2>&1 || {
    echo "Не удалось сгенерировать сертификаты через mkcert" >&2
    exit 1
}

chmod 644 "$CERT_DIR/server.crt"
chmod 600 "$CERT_DIR/server.key"

echo "Сертификаты успешно сгенерированы в $CERT_DIR"
echo "Для доверия браузеров используйте mkcert -install или импортируйте корневой CA, который создал mkcert"