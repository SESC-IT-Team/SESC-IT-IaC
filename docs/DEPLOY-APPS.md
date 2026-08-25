# Деплой приложений через ArgoCD: Spravki, Technical Support, SESC Portal, Document Renderer

Манифесты всех приложений живут в этом репозитории (GitOps). DNS-зона кластера — `global.baseDomain` в [charts/cluster/values.yaml](../charts/cluster/values.yaml). Образы — в приватном registry `reg.<baseDomain>` (внутри кластера containerd тянет их через mirror `http://127.0.0.1:5000`).

---

## Что где лежит

| Приложение | Chart | Namespace | URL | Порт |
|---|---|---|---|---|
| Spravki Frontend | `apps/spravki-frontend/` | `spravki` | `spravki.<baseDomain>` | 80 |
| Spravki Backend | `apps/spravki-backend/` | `spravki` | `api.spravki.<baseDomain>` | 8000 |
| Technical Support Backend | `apps/technical-support-backend/` | `technical-support` | `api.support.<baseDomain>` | 8123 |
| SESC Portal | `apps/sesc-portal/` | `sesc-portal` | `portal.<baseDomain>` | 8000 |
| Document Renderer | `apps/document-renderer/` | `document-renderer` | — (taskiq worker) | — |
| RabbitMQ | `apps/rabbitmq/` | `rabbitmq` | — (ClusterIP) | 5672 |
| Redis | `apps/redis/` | `redis` | — (ClusterIP) | 6379 |
| MinIO | `apps/minio/` | `minio` | `s3.<baseDomain>` / `minio.<baseDomain>` | 9000/9001 |
| Vault UI | `apps/vault/` | `vault` | `vault.<baseDomain>` | 8200 |
| Registry | `apps/registry/` | `registry` | `reg.<baseDomain>` | 5000 |
| Authentik | `apps/authentik/` | `authentik` | `auth.<baseDomain>` | 9000 |
| Lyceum Auth | `apps/lyceum-auth/` | `lyceum-auth` | `users.<baseDomain>` | 8000 |

ArgoCD Applications: `argocd/apps/*.yaml`, sync-wave `1` — инфраструктура, `2` — приложения.

Смена зоны — одно значение `global.baseDomain` в `charts/cluster/values.yaml`. Префиксы хостов задаются в values каждого чарта (`hostPrefix`).

## Доверие к внутреннему CA из Pod

Внутренний CA создаётся cert-manager в `cert-manager/sesc-internal-ca-secret`. ArgoCD устанавливает
trust-manager (`argocd/apps/trust-manager.yaml`), а `argocd/apps/internal-ca-bundle.yaml` создаёт Bundle,
который публикует объединённый bundle (публичные CA + `sesc-internal-ca`) как ConfigMap
`sesc-internal-ca` во всех namespace.

Основные backend/frontend/worker Deployment и migration Job монтируют этот ConfigMap в
`/etc/ssl/certs/sesc-internal-ca.crt`. Для Python-клиентов также выставлены `SSL_CERT_FILE` и
`REQUESTS_CA_BUNDLE`, поэтому обращения к внутренним HTTPS-адресам с сертификатами от
`sesc-internal-issuer` проходят обычную проверку TLS.

После первого применения дождитесь появления ConfigMap в нужном namespace:

```bash
kubectl -n spravki get configmap sesc-internal-ca
kubectl -n spravki rollout restart deployment/spravki-backend
```

Не отключайте проверку сертификатов через `verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED=0` или
аналогичные параметры. Новое приложение должно подключить хелперы `cluster.internalCAMount` и
`cluster.internalCAVolume`; для Python также используйте `cluster.internalCAEnv`.

---

## 1. Секреты в Vault (kv v2)

Добавить в Vault (UI: `https://vault.<baseDomain>`, движок `kv`, секреты в `apps/*`):

Для массового импорта используйте токен с политикой из [vault-importer-policy.hcl](vault-importer-policy.hcl). Политику нужно применить администраторским токеном один раз:

```bash
export VAULT_SKIP_VERIFY=true
vault policy write vault-importer docs/vault-importer-policy.hcl
vault policy read vault-importer
vault token create -policy=vault-importer
VAULT_TOKEN=<полученный-токен> ./docs/import-vault-secrets.sh
```

If the token was already created before `vault policy write` succeeded, create a new token after verifying the policy. Revoke the old token because it was exposed in terminal output or chat.

`vault kv put` проверяет доступ к `kv/metadata/apps/*` перед записью. Поэтому токен только с доступом к `kv/data/apps/*` завершится ошибкой `preflight capability check returned 403`.

| Path | Ключ | Значение |
|---|---|---|
| `apps/spravki-backend` | `POSTGRES_PASSWORD` | пароль postgres для spravki |
| `apps/technical-support-backend` | `POSTGRES_PASSWORD` | пароль postgres для TS |
| `apps/sesc-portal` | `POSTGRES_PASSWORD` | пароль postgres для SESC Portal |
| `apps/sesc-portal` | `DATABASE_URL` | `postgresql+psycopg://sesc:<password>@sesc-portal-postgres:5432/sesc` |
| `apps/sesc-portal` | `SECRET_KEY` | случайный секрет для сессий приложения |
| `apps/rabbitmq` | `RABBITMQ_USER` | имя пользователя (не `guest`) |
| `apps/rabbitmq` | `RABBITMQ_PASSWORD` | пароль RabbitMQ |
| `apps/rabbitmq` | `RABBITMQ_ERLANG_COOKIE` | случайная строка (например, `openssl rand -hex 16`) |
| `apps/redis` | `REDIS_PASSWORD` | пароль Redis |
| `apps/minio` | `MINIO_ROOT_USER` | access key MinIO |
| `apps/minio` | `MINIO_ROOT_PASSWORD` | secret key MinIO (мин. 8 символов) |
| `apps/document-renderer` | `BUCKET_NAME` | имя бакета, например `spravki` |
| `apps/registry` | `HTPASSWD` | строка `user:bcrypt-hash` — `htpasswd -Bbn <user> <pass>` |
| `apps/registry` | `REGISTRY_USERNAME` | тот же user, для pull-секрета |
| `apps/registry` | `REGISTRY_PASSWORD` | тот же пароль |
| `apps/authentik` | `SPRAVKI_REDIRECT_URI` | `https://api.spravki.<baseDomain>/auth/callback` |
| `apps/authentik` | `TECHNICAL_SUPPORT_REDIRECT_URI` | `https://api.support.<baseDomain>/auth/callback` |
| `apps/lyceum-auth` | `POSTGRES_PASSWORD` | пароль встроенной PostgreSQL для Lyceum Auth |
| `apps/lyceum-auth` | `ADMIN_PASSWORD` | пароль пользователя `ADMIN_LOGIN` |
| `apps/lyceum-auth` | `SA_AUTH_ADMIN_APP_API_TOKEN` | API-токен service account `auth-admin-app` из Authentik |

Lyceum Auth должен получить Secret `lyceum-auth-secrets` из Vault-пути `apps/lyceum-auth` до запуска Deployment и migration Job. После заполнения значений импортируйте их через:

```bash
VAULT_TOKEN=<токен> ./docs/import-vault-secrets.sh <подготовленный-json-манифест>
```

## 2. DNS

A-записи → `212.113.98.188`:

```
spravki.<baseDomain>
api.spravki.<baseDomain>
api.support.<baseDomain>
portal.<baseDomain>
s3.<baseDomain>
minio.<baseDomain>
vault.<baseDomain>
reg.<baseDomain>
auth.<baseDomain>
users.<baseDomain>
argocd.<baseDomain>
```

(`api.spravki.<baseDomain>` — два уровня, одинокий wildcard `*.<baseDomain>` его не покрывает.)

## 3. Registry (secure)

Registry доступен по `https://reg.<baseDomain>` (внутренний CA через cert-manager). Установите `sesc-internal-ca.crt` на Docker-клиент, прежде чем выполнять HTTPS push/pull. Basic-auth (htpasswd) **выключен** (`auth.enabled: false` в `apps/registry/values.yaml`); чтобы включить — внести `HTPASSWD` в Vault `apps/registry` и переключить флаг в `true`.

Containerd K3s тянет образы **без TLS и без auth** через mirror `http://127.0.0.1:5000` — за это отвечает `/etc/rancher/k3s/registries.yaml` (генерируется ansible, см. `ansible/roles/k3s_setup/tasks/main.yml`). После первого прогона плейбука containerd умеет резолвить `reg.<baseDomain>/<image>` в локальный mirror.

Локальная сборка и push:

```bash
docker login reg.<baseDomain>   # только после включения auth.enabled: true
docker build --platform linux/amd64 -t reg.<baseDomain>/<app>:<sha> .
docker push reg.<baseDomain>/<app>:<sha>
```

Если registry использует self-signed сертификат, добавьте его домен в Docker Desktop:
`Settings` -> `Docker Engine` -> `insecure-registries`, например:

```json
{
	"insecure-registries": ["reg.<baseDomain>"]
}
```

После перезапуска Docker Desktop запустите сборщик с флагом `--insecure`:

```bash
./docs/build-and-push-images.sh --insecure reg.<baseDomain>
```

В values.yaml репозиторий образа — короткое имя (`spravki-frontend`); шаблон подставляет `reg.<baseDomain>/` через `cluster.privateImage`.

## 4. Сборка образов (с ноута)

Текущие образы (уже запушены):

| Image | Tag (git sha) |
|---|---|
| `reg.<baseDomain>/spravki-frontend` | `a67cf1b` |
| `reg.<baseDomain>/spravki-backend` | `4c8bcca` |
| `reg.<baseDomain>/technical-support-backend` | `d91b55e` |
| `reg.<baseDomain>/sesc-portal` | `<git sha>` |
| `reg.<baseDomain>/document-renderer` | `4e155d2` |

Обновление:

```bash
cd <repo>
docker build --platform linux/amd64 -t reg.<baseDomain>/<app>:$(git rev-parse --short HEAD) .
docker push reg.<baseDomain>/<app>:$(git rev-parse --short HEAD)
# затем поменять tag в apps/<app>/values.yaml и закоммитить — ArgoCD подхватит
```

## 5. Порядок деплоя (первый раз)

1. Собрать и отправить `sesc-portal` в registry, затем указать его git SHA в `apps/sesc-portal/values.yaml`.
2. Внести секреты в Vault (таблица выше).
3. Настроить DNS.
4. Запустить ansible-playbook на сервере (обновит registries.yaml, рестарт k3s).
5. Commit + push этого репозитория — root-app подхватит `argocd/apps/sesc-portal.yaml`.

## 6. Известные нюансы

- **Spravki-Backend**: в репо `pyproject.toml` ссылается на несуществующий workspace `packages/other-package` и `requires-python = ">=3.12"` конфликтует с `sesc-auth-sdk` (требует >=3.13). Для сборки образа локально применены правки: убран workspace-блок, `requires-python = ">=3.13"`, базовый образ `python:3.13-alpine`. Правки не закоммичены — нужно fixes в репозитории приложения.
- **Technical-Support-Backend**: образ не запускает миграции — в Deployment command переопределён на `alembic upgrade head && uv run python -m src.main`.
- **Bucket**: renderer не создаёт бакет автоматически — после подъёма MinIO создать бакет через UI `minio.<baseDomain>` (имя = `BUCKET_NAME` из Vault).
- **Внутрикластерный MinIO** — по HTTP (`minio.minio.svc.cluster.local:9000`), TLS только на Ingress.
