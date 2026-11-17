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
3. `vault-transit.sh` — политика и токен на `vault-unsealer`, Secret `vault-transit-token` (без него `vault-0` не стартует).
4. `vault-init.sh` — `vault operator init` (на transit seal — recovery-ключи); ключи в `/root/vault-init.json`,
   root-токен дописывается в secrets.env.
5. `bootstrap.sh bootstrap-2` — Kubernetes auth, KV `kv`, политика/роль External Secrets.
6. `vault-secrets.sh` — генерирует и кладёт все `kv/apps/*` (существующие пути не трогает).
7. `build-images.sh push` — собирает образы из GitHub на коммитах из `apps/*/values.yaml` и пушит в `reg.sescserv.ru`.
8. `buckets.sh` — бакеты MinIO `geometry-dash` (справки) и `order-photos` (техподдержка).
9. `status.sh` / `smoke.sh [public]` — сводка и проверка эндпоинтов.

10. `create-user.sh` — создать пользователей через lyceum-auth (Authentik + доменные данные/роли). Вход один раз
    в браузере под `admin`; пользователей, созданных только в UI Authentik, справки и техподдержка не видят.
    Массово — `import-users.py users.csv` (см. [ADMIN-GUIDE.md](ADMIN-GUIDE.md)).

**`/root/vault-init.json` (root-токен и recovery-ключи) надо сохранить в надёжном месте и удалить с сервера.**

## Auto-unseal (transit, как в GitOps-IaC)

`vault-unsealer` ([argocd/apps/vault-unsealer.yaml](../argocd/apps/vault-unsealer.yaml), sync-wave `-3`) — отдельный
Vault с file storage на PVC, сам себя инициализирует и распечатывает при старте и хранит transit-ключ `autounseal`.
Основной Vault (`seal "transit"` в [apps/vault/values.yaml](../apps/vault/values.yaml)) при старте расшифровывает
master key через unsealer — ручной unseal после перезагрузки не нужен.

- Токен основного Vault к unsealer — orphan, periodic 720h, обновляется самим Vault, пока тот работает.
  Если сервер выключен дольше 30 дней — перевыпустить: удалить Secret `vault-transit-token`, запустить `vault-transit.sh`.
- Transit-ключ и ключи самого unsealer лежат только на его PVC (`/vault/data`). **Потеря этого PVC = потеря данных
  основного Vault**: recovery-ключи распечатать его не могут, они нужны только для операций вроде `generate-root`.
  Бэкапить каталог PVC unsealer (local-path на узле) вместе с бэкапами основного Vault.
- Миграция существующего Vault с Shamir выполнена `vault-transit.sh` (`vault operator unseal -migrate`).

## Отличия от `master`

- MinIO: `bitnamilegacy/minio` — официальные образы MinIO больше не скачиваются анонимно.
- technical-support-backend: в чарт добавлены `CLIENT_ID/SECRET`, `LOGIN_REDIRECT_URI`, `ROUTER_PATH`,
  `ALLOWED_ISSUERS`, cookie и S3-переменные — без них образ не стартует.
- Registry с htpasswd; k3s тянет образы с учёткой из `/etc/rancher/k3s/registries.yaml` (пишет ansible).
