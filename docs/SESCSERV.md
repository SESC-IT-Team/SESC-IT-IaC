# Кластер sescserv.ru (ветка `env/sescserv`)

Single-node k3s на `129.101.95.254` (Debian 13, за NAT провайдера; 80/443 проброшены).
ArgoCD на сервере следит за веткой `env/sescserv`, а не за `master`.

## Домен — в одном месте

[`charts/cluster/values.yaml`](../charts/cluster/values.yaml):

```yaml
global:
  baseDomain: sescserv.ru        # <globalDomain>
  acmeEmail: it@sescserv.ru      # аккаунт Let's Encrypt
  tlsIssuer: letsencrypt-prod    # issuer для всех Ingress
```

Файл читает ansible (`k3s_setup`) и каждый ArgoCD Application (`valueFiles: ../../charts/cluster/values.yaml`).
Хелпер `cluster.tlsIssuer` подставляет issuer в Ingress.

## Что развёрнуто

Authentik, справки (frontend + backend + document-renderer), техподдержка, lyceum-auth;
зависимости — RabbitMQ, Redis, MinIO; инфраструктура — cert-manager, ArgoCD, Vault, External Secrets,
trust-manager, registry (`reg.sescserv.ru`, htpasswd).

## DNS (reg.ru)

A-записи на `129.101.95.254`: `*`, `*.spravki`, `*.support`, `*.users`
(wildcard покрывает один уровень, поэтому `api.spravki`/`api.support`/`api.users` — отдельно).

## Развёртка с нуля

Скрипты — [`scripts/sescserv/`](../scripts/sescserv); копируются в `/root/` и запускаются от root на сервере.

1. `prep.sh` — пакеты, клон ветки в `/opt/apps/SESC-IT-IaC`, `/root/sescserv-secrets.env` (пароль registry).
2. `bootstrap.sh bootstrap-1` — k3s, cert-manager, ArgoCD, root-app. Останавливается на «Require Vault root token» — это ожидаемо.
3. `vault-init.sh` — `vault operator init` + unseal; ключи в `/root/vault-init.json`, root-токен дописывается в secrets.env.
4. `bootstrap.sh bootstrap-2` — Kubernetes auth, KV `kv`, политика/роль External Secrets.
5. `vault-secrets.sh` — генерирует и кладёт все `kv/apps/*` (существующие пути не трогает).
6. `build-images.sh push` — собирает образы из GitHub на коммитах из `apps/*/values.yaml` и пушит в `reg.sescserv.ru`.
7. `buckets.sh` — бакеты MinIO `geometry-dash` (справки) и `order-photos` (техподдержка).
8. `status.sh` — сводка Applications / подов / сертификатов.

**Ключи unseal (`/root/vault-init.json`) надо сохранить в надёжном месте и удалить с сервера.**
После каждой перезагрузки Vault запечатан: повторить `vault-init.sh` (init пропустится, выполнится unseal).

## Отличия от `master`

- MinIO: `bitnamilegacy/minio` — официальные образы MinIO больше не скачиваются анонимно.
- technical-support-backend: в чарт добавлены `CLIENT_ID/SECRET`, `LOGIN_REDIRECT_URI`, `ROUTER_PATH`,
  `ALLOWED_ISSUERS`, cookie и S3-переменные — без них образ не стартует.
- Образ `technical-support-backend:7463090-cfgfix` собран с патчем `src/config.py`:
  upstream создаёт `Settings(postgres_host='', …)`, и явные аргументы перекрывают переменные окружения
  (БД/S3 всегда пустые). Патч заменяет это на `Settings()`. Правильное исправление — в репозитории
  Technical-Support-Backend; после него тег можно вернуть на обычный SHA.
- Registry с htpasswd; k3s тянет образы с учёткой из `/etc/rancher/k3s/registries.yaml` (пишет ansible).
