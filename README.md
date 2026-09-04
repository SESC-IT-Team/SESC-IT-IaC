# SESC-IT-IaC

Инфраструктура SESC-IT как код: K3s, приватный Docker-registry, ArgoCD (GitOps) и сопутствующие сервисы (Logging, S3, RabbitMQ, PostgreSQL).

## Быстрый старт

```bash
cd ansible
ansible-galaxy install -r requirements.yml
VAULT_ROOT_TOKEN='...' ansible-playbook -i inventories/local.yml playbooks/k3s-server.yml
```

`VAULT_ROOT_TOKEN` is required only during bootstrap and must be supplied from
the controller environment or an encrypted Ansible Vault variable. The
playbook declaratively configures Vault Kubernetes auth, the `kv` KV v2 mount,
the External Secrets policy and role, while ArgoCD manages the corresponding
Kubernetes RBAC and secret-store resources.

Подробная инструкция — в [docs/ARGOCD.md](docs/ARGOCD.md).

## Что входит

| Компонент            | Где                                    | Управляется через                |
|----------------------|----------------------------------------|----------------------------------|
| K3s single-node      | [ansible/roles/k3s_setup](ansible/roles/k3s_setup) | ansible                          |
| Private registry     | [apps/registry](apps/registry)         | ArgoCD (helm chart)              |
| ArgoCD               | [argocd/values.yaml](argocd/values.yaml) | ansible (helm install)           |
| GitOps applications  | [argocd/apps/](argocd/apps)            | ArgoCD (app-of-apps)             |
| SSH users            | [ansible/roles/ssh_users](ansible/roles/ssh_users) | ansible                          |
| Logging (Loki/Grafana) | [Logging/](Logging)                  | docker-compose                   |
| Traefik (внешний)    | [traefik/](traefik)                    | docker-compose (выводится из эксплуатации) |

## Структура

```
ansible/      # provisioning: k3s, helm, ArgoCD bootstrap, ssh users
apps/         # helm charts под управлением ArgoCD
argocd/       # helm values ArgoCD + GitOps-манифесты (Application/AppProject)
docs/         # документация
Logging/      # observability stack (docker-compose)
traefik/      # внешний reverse-proxy (выводится из эксплуатации)
```

## GitOps: добавить приложение

1. Скопировать `apps/registry/` → `apps/<myapp>/`.
2. Скопировать `argocd/apps/registry.yaml` → `argocd/apps/<myapp>.yaml`.
3. `git commit && git push` — ArgoCD подхватит автоматически.

Полное руководство — в [docs/ARGOCD.md](docs/ARGOCD.md).

## Доступы

- ArgoCD UI: `https://argocd.sesc-it-team.ru` (пароль — см. [docs/ARGOCD.md](docs/ARGOCD.md#3-доступ-к-ui-argocd))
- Registry: `212.113.98.188:5000` (insecure, без TLS)

## SSH-пользователи

Добавление новых пользователей — через [ansible/group_vars/all.yml](ansible/group_vars/all.yml) и роль `ssh_users`.
