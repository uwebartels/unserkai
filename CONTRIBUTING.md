# Mitarbeit: Prüfstufen vor Commit und Push

Dieses Repo ist öffentlich. Alles, was hier landet, ist für immer lesbar, auch nach dem Löschen (Forks, Caches, Klone). Darum laufen vor jedem Commit und jedem Push Prüfungen, und einige Dinge gehören nie hinein.

## Einmalige Einrichtung je Klon

```sh
git config core.hooksPath .githooks
```

Werkzeuge für das Gate: `ansible`, `ansible-lint`, `yamllint`, `shellcheck`, `gitleaks`, `docker` (mit Compose-Plugin), `python3`. Unter Debian 13 sind alle als Paket da, Collections mit `make -C ansible deps`. Fehlt ein Werkzeug, meldet `./check` das als Fehler, nicht als Übersprungen.

## Stufe 1: vor dem Commit

`.githooks/pre-commit` ruft `./check`. Es prüft das ganze Repo: ansible-lint, Apt-Cache-Regel, yamllint, shellcheck, Python-Syntax, `docker compose config`, Rendern der Vorlagen, gitleaks über den Arbeitsbaum und den Scan auf private Adressen (10/8, 172.16/12, 192.168/16). Ausnahmen für den Adress-Scan stehen in `.check-allow-private-addresses`, heute nur das VPC-CIDR und die Firewall-Regeln unter `aws/`.

Ein Commit ist erst erlaubt, wenn alle Schritte `[PASS]` oder `[SKIP]` melden. `git commit --no-verify` umgeht den Hook; die CI fängt das auf, es verschiebt den Fehler also nur.

## Stufe 2: vor dem Push

`.githooks/pre-push` lässt gitleaks über genau die Commits laufen, die der Push überträgt, und weist Pushes nach `main` ab. Nach `main` kommt Code nur über einen Pull Request. `ALLOW_PUSH_MAIN=1 git push` hebt das bewusst auf, etwa für den Repo-Eigentümer.

Arbeitsweise: eigener Branch, Push in den eigenen Fork oder einen Feature-Branch, Pull Request, Review durch eine zweite Person, CI grün, dann Merge.

## Stufe 3: auf GitHub

`.github/workflows/check.yml` führt `./check` und einen gitleaks-Lauf über die gesamte Historie bei jedem Push und Pull Request aus. Damit hängt die Prüfung nicht davon ab, ob der Hook lokal gesetzt war.

Vom Repo-Eigentümer einzuschalten (Settings des Repos auf GitHub):

- Branches, Rule für `main`: nur per Pull Request, mindestens ein Review, Status-Check `check` verpflichtend, kein Force-Push, kein Löschen.
- Code security: Secret scanning und Push protection einschalten.

## Was nie ins Repo gehört

| Nie im Repo | Stattdessen |
|---|---|
| Private Schlüssel, Tokens, Passwörter, API-Keys | `aws/secrets.yaml` (sops/PGP), auf der Maschine `.env` mit Rechten 0600 |
| KeePass-Dateien, PGP-Schlüsselbunde, VPN-Profile | Außerhalb des Repos, `.gitignore` sperrt `*.kdbx`, `*.ovpn*`, `*.gnupg.tgz` |
| Terraform-State, `*.tfvars` | S3-Backend, lokale Dateien (gitignored) |
| Private IPs, Heimnetz-Adressen, Proxy-Einträge, SSH-Zugangswege | `ansible/inventory/local/` (gitignored), `~/.ssh/config` |
| Fertige `.env` der Compose-Stacks | Nur auf der Maschine; im Repo liegt `.env.example` |

Instanz-IDs, DNS-Namen und Volume-IDs der AWS-Maschinen sind erlaubt, IPs nicht.

## Wenn doch etwas durchgerutscht ist

1. Das Geheimnis gilt ab sofort als kompromittiert: Schlüssel, Token oder Passwort rotieren, bevor etwas anderes passiert.
2. Repo-Eigentümer informieren.
3. Erst dann aus der Historie entfernen (`git filter-repo`), Force-Push, alle klonen neu. Das ist Hygiene, kein Schutz: Forks und GitHub-Caches behalten alte Objekte.
