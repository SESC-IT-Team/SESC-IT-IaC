#!/bin/bash
# Create users through lyceum-auth (POST /v1/users), which creates the account
# in Authentik AND the domain record (roles, class...) that spravki and
# technical-support look up by the token's `sub`. A user created only in the
# Authentik UI is unknown to those services.
#
# lyceum-auth requires an access token of a user with role `admin` and scope
# auth:users:create, issued to the auth-admin-app client. That client only has
# the authorization-code grant, so you log in once in a browser:
#   1. open the printed link, log in as `admin`
#      (password: see the command printed below);
#   2. the browser lands on https://admin.<domain>/auth/callback?code=...
#      (a certificate warning or 404 is expected - nothing runs there);
#      copy the FULL address from the address bar;
#   3. paste it here. The token is then reused for every user in this session.
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

D=$(awk '/baseDomain:/ {print $2; exit}' /opt/apps/SESC-IT-IaC/charts/cluster/values.yaml)
AUTH="https://auth.$D"
API="https://api.users.$D/v1"
REDIRECT="https://admin.$D/auth/callback"
env_of() { kubectl -n authentik get deploy authentik-server -o json \
  | jq -r --arg n "$1" '.spec.template.spec.containers[0].env[] | select(.name==$n) | .value'; }
CID=$(env_of AUTH_ADMIN_APP_CLIENT_ID)
CSECRET=$(kubectl -n authentik get secret authentik-secrets -o jsonpath='{.data.AUTH_ADMIN_APP_CLIENT_SECRET}' | base64 -d)
urlenc() { jq -rn --arg v "$1" '$v|@uri'; }

STATE=$(openssl rand -hex 16)
SCOPE="openid profile auth:users:create auth:users:read auth:users:update"
cat <<EOF

1) Откройте в браузере и войдите под пользователем admin:

$AUTH/application/o/authorize/?response_type=code&client_id=$(urlenc "$CID")&redirect_uri=$(urlenc "$REDIRECT")&scope=$(urlenc "$SCOPE")&state=$STATE

   Пароль admin:  kubectl -n lyceum-auth get secret lyceum-auth-secrets -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d; echo

2) Браузер откроет $REDIRECT?code=... (предупреждение о сертификате или 404 - это нормально, нужен только адрес).
EOF
read -rp "3) Вставьте полный адрес из адресной строки: " CB
CODE=$(sed -nE 's/.*[?&]code=([^&]+).*/\1/p' <<<"$CB")
GOT_STATE=$(sed -nE 's/.*[?&]state=([^&]+).*/\1/p' <<<"$CB")
[ -n "$CODE" ] || { echo "В адресе нет code="; exit 1; }
[ "$GOT_STATE" = "$STATE" ] || { echo "state не совпадает - откройте ссылку из этого запуска"; exit 1; }

RESP=$(curl -s -u "$(urlenc "$CID"):$(urlenc "$CSECRET")" \
  --data-urlencode grant_type=authorization_code --data-urlencode code="$CODE" \
  --data-urlencode redirect_uri="$REDIRECT" "$AUTH/application/o/token/")
TOKEN=$(jq -r '.access_token // empty' <<<"$RESP")
[ -n "$TOKEN" ] || { echo "Не удалось получить токен: $(jq -c '{error,error_description}' <<<"$RESP")"; exit 1; }
ME=$(curl -s -H "Authorization: Bearer $TOKEN" "$API/users/me")
echo "Токен получен для: $(jq -r '"\(.login) roles=\(.roles|join(","))"' <<<"$ME" 2>/dev/null || echo "$ME")"

ask() { local v; read -rp "$1" v; printf '%s' "$v"; }
while :; do
  echo; echo "--- Новый пользователь (Enter - пропустить необязательное поле) ---"
  LAST=$(ask "Фамилия: "); FIRST=$(ask "Имя: "); MIDDLE=$(ask "Отчество (необяз.): ")
  LOGIN=$(ask "Логин: ")
  ROLES=$(ask "Роли через запятую [student]: (admin,teacher,student,parent,staff,guest,graduate) ")
  GENDER=$(ask "Пол (male/female) [male]: ")
  GRADE=$(ask "Класс 8-11 (необяз.): "); LETTER=""; [ -n "$GRADE" ] && LETTER=$(ask "Буква класса (А-Я): ")
  read -rsp "Пароль: " PASS; echo
  BODY=$(jq -n --arg l "$LAST" --arg f "$FIRST" --arg m "$MIDDLE" --arg login "$LOGIN" \
    --arg roles "${ROLES:-student}" --arg g "${GENDER:-male}" --arg grade "$GRADE" --arg letter "$LETTER" '
    {last_name:$l, first_name:$f, login:$login, gender:$g,
     roles:($roles|split(",")|map(gsub("^ +| +$";""))), lives_in_dormitory:false}
    + (if $m != "" then {middle_name:$m} else {} end)
    + (if $grade != "" then {grade:($grade|tonumber), letter:$letter} else {} end)')
  R=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d "$BODY" "$API/users")
  CODE_HTTP=$(tail -1 <<<"$R"); R=$(sed '$d' <<<"$R")
  if [ "$CODE_HTTP" != 201 ]; then echo "Ошибка создания ($CODE_HTTP): $R"
  else
    ID=$(jq -r .id <<<"$R")
    P=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN" \
        -H 'Content-Type: application/json' -d "$(jq -n --arg p "$PASS" '{password:$p}')" "$API/users/$ID/password")
    [ "$P" = 204 ] && echo "Создан: $LOGIN (id=$ID), пароль установлен" \
                   || echo "Создан $LOGIN (id=$ID), но пароль не установлен (HTTP $P)"
  fi
  [ "$(ask 'Создать ещё одного? [y/N]: ')" = y ] || break
done
