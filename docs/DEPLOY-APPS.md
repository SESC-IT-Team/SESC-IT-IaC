# Деплой приложений через ArgoCD: Spravki, Technical Support, Document Renderer

Манифесты всех приложений живут в этом репозитории (GitOps). DNS-зона кластера — `global.baseDomain` в [charts/cluster/values.yaml](../charts/cluster/values.yaml). Образы — в приватном registry `reg.<baseDomain>` (внутри кластера containerd тянет их через mirror `http://127.0.0.1:5000`).

---

## Что где лежит

| Приложение | Chart | Namespace | URL | Порт |
|---|---|---|---|---|
| Spravki Frontend | `apps/spravki-frontend/` | `spravki` | `spravki.<baseDomain>` | 80 |
| Spravki Backend | `apps/spravki-backend/` | `spravki` | `api.spravki.<baseDomain>` | 8000 |
| Technical Support Backend | `apps/technical-support-backend/` | `technical-support` | `api.support.<baseDomain>` | 8123 |
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

---

## 1. Секреты в Vault (kv v2)

Добавить в Vault (UI: `https://vault.<baseDomain>`, движок `kv`, секреты в `apps/*`):

| Path | Ключ | Значение |
|---|---|---|
| `apps/spravki-backend` | `POSTGRES_PASSWORD` | пароль postgres для spravki |
| `apps/technical-support-backend` | `POSTGRES_PASSWORD` | пароль postgres для TS |
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
| `apps/authentik` | `SPRAVKI_REDIRECT_URI` | `https://spravki.<baseDomain>/auth/callback` |
| `apps/authentik` | `TECHNICAL_SUPPORT_REDIRECT_URI` | `https://api.support.<baseDomain>/auth/callback` |

## 2. DNS

A-записи → `212.113.98.188`:

```
spravki.<baseDomain>
api.spravki.<baseDomain>
api.support.<baseDomain>
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

В values.yaml репозиторий образа — короткое имя (`spravki-frontend`); шаблон подставляет `reg.<baseDomain>/` через `cluster.privateImage`.

## 4. Сборка образов (с ноута)

Текущие образы (уже запушены):

| Image | Tag (git sha) |
|---|---|
| `reg.<baseDomain>/spravki-frontend` | `a67cf1b` |
| `reg.<baseDomain>/spravki-backend` | `4c8bcca` |
| `reg.<baseDomain>/technical-support-backend` | `d91b55e` |
| `reg.<baseDomain>/document-renderer` | `4e155d2` |

Обновление:

```bash
cd <repo>
docker build --platform linux/amd64 -t reg.<baseDomain>/<app>:$(git rev-parse --short HEAD) .
docker push reg.<baseDomain>/<app>:$(git rev-parse --short HEAD)
# затем поменять tag в apps/<app>/values.yaml и закоммитить — ArgoCD подхватит
```

## 5. Порядок деплоя (первый раз)

1. Внести секреты в Vault (таблица выше).
2. Настроить DNS.
3. Запустить ansible-playbook на сервере (обновит registries.yaml, рестарт k3s).
4. Commit + push этого репозитория — root-app подхватит новые Applications в `argocd/apps/`.

## 6. Известные нюансы

- **Spravki-Backend**: в репо `pyproject.toml` ссылается на несуществующий workspace `packages/other-package` и `requires-python = ">=3.12"` конфликтует с `sesc-auth-sdk` (требует >=3.13). Для сборки образа локально применены правки: убран workspace-блок, `requires-python = ">=3.13"`, базовый образ `python:3.13-alpine`. Правки не закоммичены — нужно fixes в репозитории приложения.
- **Technical-Support-Backend**: образ не запускает миграции — в Deployment command переопределён на `alembic upgrade head && uv run python -m src.main`.
- **Bucket**: renderer не создаёт бакет автоматически — после подъёма MinIO создать бакет через UI `minio.<baseDomain>` (имя = `BUCKET_NAME` из Vault).
- **Внутрикластерный MinIO** — по HTTP (`minio.minio.svc.cluster.local:9000`), TLS только на Ingress.
