#!/usr/bin/env python3
"""Bulk-import users into lyceum-auth (Authentik account + roles/class/departments).

Usage (on the server, as root):
    python3 import-users.py users.csv --check   # validate the file, send nothing
    python3 import-users.py users.csv           # import

CSV (UTF-8, comma-separated, header row; see docs/ADMIN-GUIDE.md):
    last_name,first_name,middle_name,login,password,roles,gender,grade,letter,
    graduation_year,birthday,lives_in_dormitory,departments,children
  roles        student;parent            (admin teacher student parent staff guest graduate)
  gender       male | female
  departments  educational_department:admin;dormitory:worker
  children     logins of this parent's children: ivanov;ivanova
Empty password -> a random one is generated. New logins/passwords are written to
/root/import-passwords-<time>.csv (root only) - hand them out, then delete it.
Existing logins are not recreated and their passwords are not changed; their
departments and children are still applied, so the same file can promote
existing users to department admins.

Auth: you log in once in a browser as `admin` (auth-admin-app client only has the
authorization-code grant), then paste the address the browser lands on.
"""
import base64, csv, json, os, re, secrets, subprocess, sys, time
import urllib.error, urllib.parse, urllib.request

ROLES = {"admin", "teacher", "student", "parent", "staff", "guest", "graduate"}
DEPARTMENTS = {"academic_department", "olympiad_support_department", "medical_station",
               "educational_department", "library", "it_department",
               "laboratory_of_tech_teaching_aids", "competitive_selection_department",
               "additional_education_department", "dormitory"}
POSITIONS = {"admin", "worker"}
REQUIRED = ["last_name", "first_name", "login", "roles", "gender"]


def split(v):
    return [x.strip() for x in (v or "").replace(",", ";").split(";") if x.strip()]


def parse(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    errors, users, logins = [], [], set()
    for n, r in enumerate(rows, start=2):
        r = {k.strip(): (v or "").strip() for k, v in r.items() if k}
        e = [f"нет поля {k}" for k in REQUIRED if not r.get(k)]
        roles = split(r.get("roles"))
        e += [f"неизвестная роль {x}" for x in roles if x not in ROLES]
        if r.get("gender") and r["gender"] not in ("male", "female"):
            e.append("gender должен быть male или female")
        if r.get("login") in logins:
            e.append("логин повторяется в файле")
        logins.add(r.get("login"))
        body = {"last_name": r.get("last_name"), "first_name": r.get("first_name"),
                "login": r.get("login"), "roles": roles, "gender": r.get("gender"),
                "lives_in_dormitory": r.get("lives_in_dormitory", "").lower() in ("1", "true", "да", "yes")}
        if r.get("middle_name"): body["middle_name"] = r["middle_name"]
        if r.get("grade"):
            if not r["grade"].isdigit() or not 8 <= int(r["grade"]) <= 11: e.append("grade должен быть 8-11")
            else: body["grade"] = int(r["grade"])
            if not re.fullmatch(r"[А-ЯЁ]", r.get("letter", "")): e.append("letter - одна заглавная русская буква")
            else: body["letter"] = r["letter"]
        if r.get("graduation_year"):
            if r["graduation_year"].isdigit(): body["graduation_year"] = int(r["graduation_year"])
            else: e.append("graduation_year - год числом")
        if r.get("birthday"):
            if re.fullmatch(r"\d{4}-\d{2}-\d{2}", r["birthday"]): body["birthday"] = r["birthday"]
            else: e.append("birthday в формате ГГГГ-ММ-ДД")
        deps = []
        for d in split(r.get("departments")):
            name, _, pos = d.partition(":")
            pos = pos or "worker"
            if name not in DEPARTMENTS or pos not in POSITIONS: e.append(f"отдел '{d}' (отдел:admin|worker)")
            else: deps.append((name, pos))
        if e:
            errors.append(f"строка {n} ({r.get('login') or '?'}): " + "; ".join(e))
        users.append({"body": body, "password": r.get("password", ""), "departments": deps,
                      "children": split(r.get("children"))})
    for u in users:
        for c in u["children"]:
            if c not in logins:
                errors.append(f"{u['body']['login']}: ребёнок {c} не найден в файле (будет искаться среди существующих)")
    return users, errors


class Api:
    def __init__(self):
        cfg = open("/opt/apps/SESC-IT-IaC/charts/cluster/values.yaml", encoding="utf-8").read()
        d = re.search(r"baseDomain:\s*(\S+)", cfg).group(1)
        self.auth, self.api, self.redirect = f"https://auth.{d}", f"https://api.users.{d}/v1", f"https://admin.{d}/auth/callback"
        env = json.loads(kubectl("-n", "authentik", "get", "deploy", "authentik-server", "-o", "json"))
        env = {x["name"]: x.get("value") for x in env["spec"]["template"]["spec"]["containers"][0]["env"]}
        self.cid = env["AUTH_ADMIN_APP_CLIENT_ID"]
        self.secret = base64.b64decode(kubectl("-n", "authentik", "get", "secret", "authentik-secrets",
                                               "-o", "jsonpath={.data.AUTH_ADMIN_APP_CLIENT_SECRET}")).decode()
        self.token = self.refresh = None

    def login(self):
        state = secrets.token_hex(16)
        q = urllib.parse.urlencode({"response_type": "code", "client_id": self.cid, "redirect_uri": self.redirect,
                                    "scope": "openid profile offline_access auth:users:create auth:users:read auth:users:update",
                                    "state": state}, quote_via=urllib.parse.quote)
        print(f"\n1) Откройте в браузере и войдите под admin:\n\n{self.auth}/application/o/authorize/?{q}\n")
        print("   Пароль admin: kubectl -n lyceum-auth get secret lyceum-auth-secrets "
              "-o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d; echo")
        print("2) Браузер откроет admin.../auth/callback?code=... (ошибка/предупреждение - это нормально).")
        cb = urllib.parse.urlparse(input("3) Вставьте полный адрес из адресной строки: ").strip())
        p = urllib.parse.parse_qs(cb.query)
        if p.get("state", [""])[0] != state:
            sys.exit("state не совпадает - используйте ссылку из этого запуска")
        self._token({"grant_type": "authorization_code", "code": p["code"][0], "redirect_uri": self.redirect})
        me = self.call("GET", "/users/me")[1]
        print(f"Вошли как {me.get('login')} (роли: {', '.join(me.get('roles', []))})")
        if "admin" not in me.get("roles", []):
            sys.exit("Нужна роль admin")

    def _token(self, data):
        req = urllib.request.Request(f"{self.auth}/application/o/token/", data=urllib.parse.urlencode(data).encode(),
                                     headers={"Authorization": "Basic " + base64.b64encode(
                                         f"{self.cid}:{self.secret}".encode()).decode()})
        try:
            r = json.load(urllib.request.urlopen(req, timeout=30))
        except urllib.error.HTTPError as e:
            sys.exit(f"Не удалось получить токен: {e.read().decode()[:300]}")
        self.token, self.refresh = r["access_token"], r.get("refresh_token", self.refresh)

    def call(self, method, path, body=None, retry=True):
        req = urllib.request.Request(self.api + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return r.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            if e.code == 401 and retry and self.refresh:
                self._token({"grant_type": "refresh_token", "refresh_token": self.refresh})
                return self.call(method, path, body, retry=False)
            raw = e.read().decode()
            try: return e.code, json.loads(raw)
            except ValueError: return e.code, {"detail": raw[:300]}

    def find(self, login):
        st, r = self.call("GET", "/users?" + urllib.parse.urlencode({"search": login, "limit": 50}))
        for u in (r.get("users") or []) if st == 200 else []:
            if u.get("login") == login:
                return u["id"]
        return None


def kubectl(*a):
    return subprocess.run(["kubectl", *a], check=True, capture_output=True, text=True,
                          env={**os.environ, "KUBECONFIG": "/etc/rancher/k3s/k3s.yaml"}).stdout


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    users, problems = parse(sys.argv[1])
    hard = [p for p in problems if "будет искаться" not in p]
    for p in problems: print(("ОШИБКА  " if p in hard else "ВНИМАНИЕ ") + p)
    print(f"Строк: {len(users)}, ошибок: {len(hard)}")
    if hard: sys.exit("Исправьте ошибки и запустите снова.")
    if "--check" in sys.argv:
        return

    api = Api(); api.login()
    ids, created = {}, []
    for u in users:
        login = u["body"]["login"]
        st, r = api.call("POST", "/users", u["body"])
        if st == 201:
            ids[login] = r["id"]
            pw = u["password"] or secrets.token_urlsafe(9)
            ps, pr = api.call("PUT", f"/users/{r['id']}/password", {"password": pw})
            created.append((login, pw if ps == 204 else f"<не установлен: {pr}>"))
            print(f"+ {login}")
        else:
            ids[login] = api.find(login)
            print(f"= {login}: уже есть" if ids[login] else f"! {login}: ошибка {st} {r}")
        for dep, pos in u["departments"]:
            if ids[login]:
                s, r = api.call("PUT", f"/departments/{dep}/members/{ids[login]}", {"position": pos})
                print(f"    {dep}: {pos}" if s in (200, 201, 204) else f"    ! {dep}: {s} {r}")
    for u in users:
        pid = ids.get(u["body"]["login"])
        kids = [ids.get(c) or api.find(c) for c in u["children"]]
        if pid and u["children"]:
            missing = [c for c, k in zip(u["children"], kids) if not k]
            s, r = api.call("PATCH", f"/users/{pid}/children", {"ids_to_add": [k for k in kids if k]})
            print(f"  {u['body']['login']} -> дети: {', '.join(u['children'])}"
                  + (f" (не найдены: {', '.join(missing)})" if missing else "") + ("" if s in (200, 204) else f" ! {s} {r}"))
    if created:
        out = f"/root/import-passwords-{time.strftime('%Y%m%d-%H%M%S')}.csv"
        fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            csv.writer(f).writerows([("login", "password"), *created])
        print(f"\nСоздано: {len(created)}. Логины и пароли: {out} - раздайте и удалите файл.")


if __name__ == "__main__":
    main()
