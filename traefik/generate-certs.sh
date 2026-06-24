#!/bin/sh
set -e

CERT_DIR="/certs"
DOMAIN="${DOMAIN:-local.dev}"
WILDCARD_DOMAIN="*.${DOMAIN}"

# Создаем директорию если её нет
mkdir -p "$CERT_DIR"

# Проверяем, существуют ли уже сертификаты
if [ -f "$CERT_DIR/server.crt" ] && [ -f "$CERT_DIR/server.key" ]; then
    echo "Сертификаты уже существуют, пропускаем генерацию"
    exit 0
fi

echo "Генерация самоподписанных сертификатов для ${DOMAIN}..."

# Генерируем приватный ключ
openssl genrsa -out "$CERT_DIR/ca.key" 4096

# Создаем самоподписанный CA сертификат
openssl req -new -x509 -days 3650 -key "$CERT_DIR/ca.key" \
    -out "$CERT_DIR/ca.crt" \
    -subj "/C=RU/ST=Local/L=Local/O=Local CA/CN=Local CA"

# Генерируем ключ для сервера
openssl genrsa -out "$CERT_DIR/server.key" 2048

# Создаем CSR (Certificate Signing Request)
openssl req -new -key "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.csr" \
    -subj "/C=RU/ST=Local/L=Local/O=Local/CN=${DOMAIN}"

# Создаем конфигурационный файл для расширений
cat > "$CERT_DIR/openssl.cnf" <<EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = ${WILDCARD_DOMAIN}
DNS.3 = *.${DOMAIN}
EOF

# Подписываем серверный сертификат нашим CA
openssl x509 -req -days 365 \
    -in "$CERT_DIR/server.csr" \
    -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/server.crt" \
    -extfile "$CERT_DIR/openssl.cnf" \
    -extensions v3_req

# Удаляем временные файлы
rm -f "$CERT_DIR/server.csr" "$CERT_DIR/openssl.cnf" "$CERT_DIR/ca.srl"

# Устанавливаем правильные права
chmod 644 "$CERT_DIR/server.crt" "$CERT_DIR/ca.crt"
chmod 600 "$CERT_DIR/server.key" "$CERT_DIR/ca.key"

echo "Сертификаты успешно сгенерированы в $CERT_DIR"
echo "CA сертификат: $CERT_DIR/ca.crt"
echo "Серверный сертификат: $CERT_DIR/server.crt"
echo "Для доверия браузеров импортируйте ca.crt в доверенные корневые сертификаты"