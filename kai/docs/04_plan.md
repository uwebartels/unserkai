# Kai — Plan: Phasen, Aufgaben, Prüfungen

Stand: 2026-11-10 · Bezug: Sprint 01 in ClickUp (S1-xx), [01 Architektur](01_architektur.md)

## Stand

- Phase 1 und 2 sind abgeschlossen, und Kai 1.0 läuft seit 07.11. auf `webui1` und `kai1` (PR #14 im Fork, Protokoll dort).
- `webui1` und `kai1` tragen seit 10.11. den Stand von `main` samt Pförtner (3.12, 3.13, Phase 4).
- Offen in Phase 3 sind 3.6–3.8 und 3.11, die Ergebnisse von 3.5 sind unvollständig belegt.
- Danach folgt Phase 4, der Pförtner.

## Phase 1 — Design, Architektur, Plan (abgeschlossen)

| Ergebnis | Datei | Zustand |
|---|---|---|
| Architektur mit zwei Maschinen, Austauschbarkeit, Entscheidungen | [01_architektur.md](01_architektur.md) | Entwurf |
| Anforderungen an Instanzen, Platten, Netz, Zugang (für Uwe) | [02_anforderungen-infrastruktur.md](02_anforderungen-infrastruktur.md) | Entwurf |
| Modellvorschlag + Alternativen für Tests | [03_modellvorschlag.md](03_modellvorschlag.md) | Entwurf |
| Bestandsaufnahme der Instanzen `webui1` und `kai1` | [instance_specs.md](instance_specs.md) | erhoben 07.11. |
| Platzhalter für Geheimnisse | [../compose/entry/.env.example](../compose/entry/.env.example) | Phase 2 |
| Bilder für Laien (SVG + PNG für ClickUp) | [bilder/](bilder/) | Entwurf |
| Dieser Plan | 04_plan.md | Entwurf |

Abnahme Phase 1: Uwe und Axel haben 01–03 gelesen; offene Punkte aus 02 (Zugangsweg, Größe, Egress, Session-Rolle, DNS) sind als ClickUp-Aufgaben erfasst; PR gemergt.

## Phase 2.0 — Entwicklungsumgebung `kai-dev` und Test-VMs `kai-entry-pre`, `kai-gpu-pre`

Drei VMs in Axels Heimnetz, alle aus, wenn nicht gebraucht; ihre Einrichtung ist außerhalb dieses Repos dokumentiert, weil sie Interna des Heimnetzes enthält. Je AWS-Maschine eine Test-VM mit dem Image ihres Vorbilds. Keine GPU: alles mit `nvidia-smi`, echten Modellen und Antwortzeiten bleibt Phase 3.

| VM | Zweck | Bauweise |
|---|---|---|
| `kai-dev` | Entwicklungsumgebung: Clone dieses Repos, Claude Code (nur hier, nie auf den AWS-Maschinen), Prüf-Gate, Ansible-Steuerknoten, ab Phase 3 AWS-Zugang über SSM | Debian 13, abgeschottete Agenten-VM mit eigenem Netz und Egress-Allowlist. Werkzeuge aus Debian-Paketen: `ansible`, `ansible-lint`, `yamllint`, `shellcheck`, `shfmt`, `gitleaks`, `gh`, `docker-cli` mit Compose (nur `config`), `awscli`, `session-manager-plugin`; Claude Code mit GitHub-MCP (Token nur für den Fork) und ClickUp-MCP. Code geht als Branch in Axels Fork und von dort als Pull Request an dieses Repo |
| `kai-entry-pre` | Test-Ziel für den Entry-Stack, Abbild von `kai-entry` | Debian-13-Cloud-Image `genericcloud` (qcow2) aus demselben Build wie das Image der AWS-Maschinen ([02 §1.2](02_anforderungen-infrastruktur.md)): dieselben Pakete, derselbe Cloud-Kernel, cloud-init über NoCloud-`seed.iso`; Benutzer `admin` mit sudo ohne Passwort wie in AWS und dem Key von `kai-dev`; ohne Docker, damit die Rolle `docker` den Installationsweg zeigt; eine zusätzliche virtuelle Platte als Ersatz für das EBS-Volume `kai-data`. Versiegeltes Basis-Image, pro Testlauf ein frisches Overlay |
| `kai-gpu-pre` | Test-Ziel für den GPU-Stack, Abbild von `kai-gpu` | Dasselbe Basis-Image wie `kai-entry-pre` (kein Docker, kein Treiber), weil die Rollen Docker, NVIDIA-Treiber und Container Toolkit auch in AWS selbst installieren; ohne GPU baut DKMS das Treibermodul trotzdem gegen den Cloud-Kernel, nur laden lässt es sich nicht; eine zusätzliche virtuelle Platte als Ersatz für `kai-models`; `kai_gpu_enabled: false`, Modellliste mit dem kleinen CPU-Testmodell aus [03](03_modellvorschlag.md). Versiegeltes Basis-Image, pro Testlauf ein frisches Overlay |

Im Inventory steht `kai-entry-pre` in der Gruppe `kai_entry` und `kai-gpu-pre` in `kai_gpu`, beide mit normalem SSH statt SSM und sonst den Variablen ihrer Gruppe; `kai_gpu_endpoint` hat auf `kai-entry-pre` denselben Wert wie in AWS (`http://kai1.unserkai.de:8080`): das Testnetz hat keinen DNS, die Test-VMs lösen `webui1.unserkai.de` und `kai1.unserkai.de` über `/etc/hosts` auf, und für die Container trägt die Rolle die Namen über die Variable `kai_extra_hosts` als `extra_hosts` ein (in AWS leer, dort antwortet Route 53). Damit läuft die ganze Kette Open WebUI → LiteLLM → llama-swap → llama-server über zwei Maschinen ohne GPU durch, wie später in AWS. Die Adressen der Test-VMs stehen nur in `~/.ssh/config` von `kai-dev` und in einem gitignorierten Inventory-Overlay `ansible/inventory/local/` im Clone (Proxy, `kai_extra_hosts`), nicht im Repo.

Steuerung: `kai-dev` und die Test-VMs liegen im selben abgeschotteten Netz; der Agent in `kai-dev` verbindet sich selbst per SSH mit den Test-VMs und arbeitet dort mit sudo. Starten und Stoppen laufen über eine Anfrage-Datei, die der Hypervisor auswertet; `kai-dev` hat kein Konto auf dem Hypervisor.

| # | Aufgabe | Prüfung |
|---|---|---|
| 2.0.1 | `kai-dev` aufsetzen (Briefing außerhalb des Repos); erledigt 2026-11-04 | `gh auth status`, `ansible --version`, `aws --version`; `make -C ansible syntax lint` grün |
| 2.0.2 | System der AWS-Maschinen: alle Kai-Maschinen tragen Debian 13 (Uwe und Axel, 06.11.), beide Instanzen dasselbe offizielle Debian-Image, Build 20261103-2651; erledigt 2026-11-07 ([Bestandsaufnahme](instance_specs.md)) | Wert in [02 §1.2](02_anforderungen-infrastruktur.md); in 3.3 zeigen beide Maschinen dasselbe `/etc/os-release` und denselben Kernel wie die Test-VMs |
| 2.0.3 | `kai-entry-pre`: cloud-init-Definition, Basis-Image, Start/Stopp mit frischem Overlay; erledigt 2026-11-07 (Bootweg BIOS, Root 20 GB und `admin` wie in der [Bestandsaufnahme](instance_specs.md)) | Start → SSH als `admin` in < 30 s; `/etc/os-release` (Debian 13) und `uname -r` (`…-cloud-amd64`) wie in AWS; kein Docker; leere Platte sichtbar; Stopp lässt das Basis-Image unverändert |
| 2.0.4 | `kai-gpu-pre`: dasselbe wie 2.0.3 mit eigener Adresse, einer leeren Platte vor der Datenplatte anstelle des Instance Storage und der größeren Datenplatte; erledigt 2026-11-07 | Start → SSH als `admin` in < 30 s; `/etc/os-release` und `uname -r` wie in AWS; kein Docker, kein Treiber; leere Platte sichtbar; Stopp lässt das Basis-Image unverändert |

Abnahme Phase 2.0: `make ping` aus `kai-dev` gegen beide Test-VMs grün.

## Phase 2 — Skript-Entwicklung (abgeschlossen 07.11.)

Alles wird in `kai-dev` entwickelt und geprüft, Rollen und Stacks laufen gegen `kai-entry-pre` und `kai-gpu-pre`. Reihenfolge nach Abhängigkeit:

| # | Aufgabe | Prüfung |
|---|---|---|
| 2.1 | **Prüf-Gate `check`** im Repo-Wurzelverzeichnis: `ansible-lint` (Profil `basic` wie bisher, später `production`), `yamllint`, `shellcheck` für Hilfsskripte, `docker compose config` für beide Stacks gegen ihre `.env.example`, `gitleaks` (Geheimnis-Scan), `git grep` auf private Adressbereiche nach RFC 1918, damit das Inventory-Overlay nie in einen Commit rutscht; `offline: true` in `ansible/.ansible-lint`, weil `kai-dev` Galaxy nicht erreicht. Ein Befehl, grün oder rot. Nach Vorbild `Software/agentic-ai-coding` (Lifecycle, `.githooks/pre-commit` ruft `check`) | läuft in `kai-dev` |
| 2.2 | **Entry-Stack** `kai/compose/entry/compose.yaml`: Dienste `open-webui`, `litellm`, `litellm-db`, `brave-mcp`; Netz `kai`; Daten unter `/opt/kai`; Open WebUI mit genau einer OpenAI-Verbindung auf `litellm`; Images **gepinnt** (Tag + Digest); Healthchecks; `restart: unless-stopped`; `env_file: .env`; `.env.example` mit allen Platzhaltern aus [01 Secrets](01_architektur.md) | `docker compose config`; auf `kai-entry-pre` `docker compose up` vollständig, alle Dienste `healthy` (keine GPU nötig) |
| 2.3 | **GPU-Stack** `kai/compose/gpu/compose.yaml`: Dienst `llama-swap` mit `deploy.resources.reservations.devices` (`driver: nvidia`, `count: all`), abschaltbar über `kai_gpu_enabled`; Port 8080 auf `kai_gpu_bind`; Bind-Mount `/opt/kai/models`; Image gepinnt; Healthcheck; `restart: unless-stopped` | `docker compose config`; auf `kai-gpu-pre` ohne GPU-Reservierung startet llama-swap, lädt das Testmodell auf der CPU |
| 2.4 | **llama-swap-Konfiguration** `kai/compose/gpu/llama-swap.yaml` als Template: Modelle aus der Liste in `group_vars`/`host_vars` (`gpt-oss-20b` aus [03](03_modellvorschlag.md), Testmodell für `kai-gpu-pre`), `healthCheckTimeout` groß genug für EBS-Ladezeit | YAML-Lint; Flag-Namen gegen llama.cpp-Doku (context7) |
| 2.5 | **LiteLLM-Konfiguration** `kai/compose/entry/litellm.yaml` als Template: `model_list` mit allen Modellen von `kai_gpu_endpoint` (Typ `openai/`), Master-Key und Datenbank aus `.env`, Platz für weitere Backends | `curl :4000/v1/models` listet die Modelle; von `kai-entry-pre` aus antwortet die ganze Kette Open WebUI → LiteLLM → llama-swap auf `kai-gpu-pre` mit dem Testmodell |
| 2.6 | **Modell-Download-Skript** `kai/bin/kai-models-pull` (bash): lädt GGUFs aus einer Liste mit `curl -C -`, prüft sha256, legt sie nach `${KAI_MODELS_DIR}`; idempotent | `shellcheck`, Trockenlauf mit `--dry-run`; echter Lauf auf `kai-gpu-pre` mit dem Testmodell |
| 2.7 | **Ansible-Rolle `kai_entry`**: Volume mit Label `kai-data` finden oder anlegen (Dateisystem + `fstab` per Label), `/opt/kai` einrichten, Compose + `litellm.yaml` ausrollen (Templates mit `kai_webui_bind`, `kai_litellm_bind`, `kai_gpu_endpoint`), `.env` **nur prüfen** (Abbruch mit Hinweis, wenn fehlt), `docker compose up -d`, Healthcheck abwarten. `meta/main.yml` hängt an `docker`. Variablen in `defaults/main.yml` dokumentiert | `ansible-lint`, `make syntax`; `make deploy TAGS=kai_entry` gegen frisches `kai-entry-pre`, zweiter Lauf `changed=0`; Abbruch ohne `.env` geprüft |
| 2.8 | **Ansible-Rolle `kai_gpu`**: zuerst der NVIDIA-Teil wie auf dem GPU-Rechner im Heimnetz ([02 §1.4](02_anforderungen-infrastruktur.md)): Komponente `contrib`, NVIDIAs CUDA-Repo für Debian 13 per `cuda-keyring`, `linux-headers-cloud-amd64`, `nvidia-driver-pinning-<Zweig>` aus `kai_gpu_driver_branch` vor dem Treiber (620, Long Term Support Branch), `nvidia-driver-cuda` und `nvidia-kernel-open-dkms` (Rechnen ohne Desktop), `nvidia-container-toolkit` aus demselben Repo; die Runtime `nvidia` steht in `docker_daemon_config` (`group_vars/kai_gpu.yml`), sodass die Rolle `docker` sie in `daemon.json` schreibt und `nvidia-ctk runtime configure` entfällt; Neustart per Handler nur nach einem neuen Treiber; danach Volume mit Label `kai-models` finden oder anlegen, `/opt/kai/models` einrichten, Compose + `llama-swap.yaml` ausrollen, Modelle über 2.6 holen, `docker compose up -d`, Healthcheck abwarten. `meta/main.yml` hängt an `docker` | `ansible-lint`, `make syntax`; `make deploy TAGS=kai_gpu` gegen frisches `kai-gpu-pre`, zweiter Lauf `changed=0`; `dkms status` zeigt das Modul `installed` für den laufenden Kernel, `docker info` die Runtime `nvidia`; `curl :8080/v1/models` listet das Testmodell |
| 2.9 | **Rollen `common`/`users`/`docker` auf Debian 13 prüfen** (schon `apt`-basiert, Docker CE aus Dockers Repo wie im Heimnetz): nur noch Debian zulassen (Assertions, `meta/main.yml`, `ansible/README.md`), `docker_apt_arch` aus den Fakten statt fest `arm64` (beide Instanzen sind x86_64); `daemon.json` bleibt das Template der Rolle `docker` und damit ihr einziger Schreiber, die Runtime `nvidia` kommt über `docker_daemon_config` (2.8). Variable `kai_http_proxy` (Standard leer, in AWS leer): wenn gesetzt, schreibt die Rolle den Proxy für apt (`/etc/apt/apt.conf.d/`), als Drop-in für `docker.service` (mit `NO_PROXY` für das Testnetz und `.kai.internal`) und in die Compose-`.env` für Container, die ins Internet gehen; so laufen die Test-VMs hinter dem Egress-Proxy des Heimnetzes mit denselben Rollen. Rolle `cmake` für Kai abwählen | `ansible-lint`; auf beiden Test-VMs läuft nach `make deploy TAGS=common,users,docker` `docker compose version`, ein zweiter Lauf meldet `changed=0`; `kai-gpu-pre`: nach 2.8 und einem weiteren Lauf der Rolle `docker` enthält `daemon.json` weiterhin die Runtime `nvidia` |
| 2.10 | **Inventory nach Rolle**: Gruppen `kai_entry` (Hosts `kai-entry`, `kai-entry-pre`) und `kai_gpu` (Hosts `kai-gpu`, `kai-gpu-pre`); Benutzerliste nach `group_vars/all.yml`; Stack-Variablen in `group_vars/kai_entry.yml` und `kai_gpu.yml`; `host_vars/kai-entry.yml` und `kai-gpu.yml` nur mit Instanz-ID, `ansible_ssh_common_args` (`ProxyCommand aws ssm start-session … --document-name AWS-StartSSHSession`), Benutzer `admin` und Maschinendaten (VRAM, Modellliste, Kontext); `host_vars/kai-entry-pre.yml` und `kai-gpu-pre.yml` nur mit `ansible_user` und `kai_gpu_enabled: false` (`kai_gpu_endpoint` bleibt der Gruppenwert); private Werte der Test-VMs (`kai_http_proxy`, `kai_extra_hosts`) in einem zweiten, gitignorierten Inventory `ansible/inventory/local/`, das das Makefile als weiteres `-i` anhängt, wenn es existiert; Host `unserkai` entfällt; `playbooks/site.yml` mit je einem Play pro Gruppe | `make syntax`; `make ping` gegen `kai-entry-pre` und `kai-gpu-pre` (SSH); SSM-Weg erst in Phase 3 |
| 2.11 | **Doku**: `ansible/README.md` um Kai erweitern; `kai/README.md` Kurzanleitung für Nutzer (S1-12) | Review |

Abnahme Phase 2: `./check` grün, beide Stacks auf frischen Test-VMs zweimal durchgelaufen (zweiter Lauf `changed=0`), Kette mit Testmodell antwortet, PR gemergt, Uwe hat die Rollen gelesen. Erfüllt bis auf einen Punkt: Ob Uwe die Rollen gelesen hat, ist nicht festgehalten.

## Phase 3 — Umsetzung auf den Maschinen

Voraussetzung: Punkte aus [02 §8](02_anforderungen-infrastruktur.md) erfüllt, Snapshot „vor Installation“ von `kai-data` existiert (S1-11).

| # | Schritt | Nachweis | Stand |
|---|---|---|---|
| 3.1 | `make ping` über SSM gegen beide Maschinen, `make check` (Dry-Run) | Ausgabe im PR-Kommentar | erledigt 07.11.; `make check` bricht auf frischer Maschine in `users` ab (Check-Modus, Benutzer fehlen noch), kein Deploy-Fehler |
| 3.2 | **kai-entry:** `make deploy LIMIT=webui1 TAGS=common,users,docker`; `.env` anlegen (Brave-Key, `WEBUI_SECRET_KEY`, LiteLLM-Keys, Postgres-Passwort); `make deploy LIMIT=webui1 TAGS=kai_entry` | `docker compose ps` alles `healthy`; `curl localhost:4000/v1/models` antwortet (Modelle gelistet, Backend noch aus) | erledigt 07.11.; `.env` über `kai_entry_env_seed`, zweiter Lauf `changed=0` |
| 3.3 | **kai-gpu:** Instanz starten, `make deploy LIMIT=kai1` | `nvidia-smi` auf dem Host zeigt die T4 und den gepinnten Treiberzweig; `docker run --rm --gpus all debian:trixie-slim nvidia-smi` zeigt die T4; `curl localhost:8080/v1/models` listet `gpt-oss-20b`; von `kai-entry` aus: `curl http://kai1.unserkai.de:8080/v1/models` (DNS und Security Group) | erledigt 07.11.; Treiber 620.70.06, Image `unified-cuda` (CUDA 12.9), weil CUDA 13 keinen Kernel für die T4 hat |
| 3.4 | Erster Chat über LiteLLM: `curl` an `localhost:4000/v1/chat/completions` mit Master-Key, dann Browser über SSH-Tunnel durch SSM auf 3000 ([06](06_zugang.md)) | Antwort in < 60 s nach Kaltstart (S1-06) | Chat erledigt 07.11., ≈ 59 Tokens/s; Ziel verfehlt: erste Antwort nach Kaltstart 98 s, Abhilfe in Phase 4 |
| 3.5 | Vier Konten anlegen, erstes Konto = Admin, Brave-MCP als Werkzeug registrieren, `ENABLE_SIGNUP=false`; in LiteLLM ein Key für Open WebUI, Keys für Harnesses erst bei Bedarf | Screenshot (S1-07) | Admin-Konto, LiteLLM-Key, Brave-Werkzeug und geschlossene Registrierung per `kai-bootstrap` erledigt 07.11.; die drei weiteren Konten und der Screenshot sind nicht belegt |
| 3.6 | Modell-Plausibilitätstest (10 deutsche Fragen + 2 Suchaufrufe), FP16-Risiko aus [03](03_modellvorschlag.md) | Tabelle in ClickUp | offen |
| 3.7 | Snapshot „nach Installation“ von `kai-data`; Stop/Start-Test `kai-gpu`: bei gestoppter GPU-Maschine bleibt Open WebUI nutzbar und meldet das Modell als nicht erreichbar; nach dem Start antwortet der Chat ohne Eingriff auf `kai-entry` | Protokoll (S1-11) | offen |
| 3.8 | Übergabe an Uwe: Zugangsweg für Nutzer freischalten, vier Personen testen PC + Telefon (S1-09), vier parallele Anfragen messen (S1-10) | Messwerte in ClickUp | Zugangsweg erledigt: Client VPN in Betrieb (`aws/vpn/`, TCP, SAML); Tests durch vier Personen und Messung offen |
| 3.10 | Installationsprotokoll + Abweichungen zurück in die Rollen (S1-15), PR | gemergt | erledigt (7720180, PR #14) |
| 3.11 | **Wechsel-Probe (Kann):** `kai-gpu` einmal durch eine neue Instanz aus demselben Image ersetzen, Volume `kai-models` umhängen, DNS nachziehen, `make deploy LIMIT=kai1` | Dauer gemessen gegen die Tabelle in [01 §3](01_architektur.md); Abweichungen in die Rollen | offen |
| 3.12 | **Stand von `main` ausrollen:** `make check`, dann `make deploy LIMIT=webui1` und `make deploy LIMIT=kai1`; neue Stücke: Platzprüfung und Aufräumen der Images, Modell vorladen, `kai_extra_hosts` | zweiter Lauf `changed=0`; `kai-smoke --target entry` und `--target gpu` grün | erledigt 10.11.: `make check` auf `webui1` `changed=0`, auf `kai1` nur die Apt-Caches; `kai-smoke` auf beiden grün; Root von `kai1` steht in Terraform weiter auf 30 GB (offener Punkt 3) |
| 3.13 | **`kai-bootstrap` ohne Passwortdatei:** Startpasswörter einmal anzeigen, beim zweiten Lauf `KAI_ADMIN_PASSWORD` oder eine Abfrage; zuerst auf `kai-entry-pre` testen, dann nach `/usr/local/sbin` auf `webui1` kopieren; erst wenn das Admin-Passwort in der KeePass liegt, `/opt/kai/accounts.txt` mit `shred -u` löschen | auf `kai-entry-pre` zweimal gelaufen, beim zweiten nichts geändert; auf `webui1` gibt es kein `accounts.txt` mehr | erledigt 10.11.: Code aus PR #17, laut PR auf den Pre-VMs geprüft; `kai-bootstrap` und `kai-smoke` aus `main` in `/usr/local/sbin` auf `webui1`, `accounts.txt` gelöscht |
| 3.14 | **Nutzung je Nutzer in LiteLLM:** Open WebUI schickt die E-Mail per Header (`ENABLE_FORWARD_USER_INFO_HEADERS`), LiteLLM bucht sie über `user_header_mappings` auf einen `internal_user` mit `user_id` = E-Mail; `kai-bootstrap` legt diese Nutzer aus der `--users-file` an (Schritt `litellm-users`) und erzeugt Harness-Keys (`--harness-key`); Preise bleiben ungesetzt, gezählt werden Tokens ([06](06_zugang.md)) | auf `kai-entry-pre` zweimal ausgerollt, zweiter Lauf `changed=0`; `kai-bootstrap` mit Test-Nutzern; `kai-smoke --target entry` mit `litellm-user` und `usage-per-user` | erledigt 11.11.: auf den Pre-VMs geprüft, auf `webui1` zweimal ausgerollt (zweiter Lauf `changed=0`), vier LiteLLM-Nutzer angelegt, `kai-smoke --target entry --user-email` grün; der Admin bleibt ein Login der LiteLLM-UI mit eigener `user_id` |

## Phase 4 — Pförtner: `kai1` bei Bedarf starten, nach Leerlauf stoppen

Das Konzept steht in [05](05_vorschlag-auto-stop.md); Rolle `kai_pfoertner` und `kai/bin/kai-pfoertner` sind mit PR #17 in `main` und laufen seit 10.11. auf `webui1`; LiteLLM erreicht `kai1` nur noch über den Pförtner. Uwe hat die Instanzrolle von `webui1` am 10.11. erweitert ([aws/webui1/iam.tf](../../aws/webui1/iam.tf)): `ec2:StartInstances`/`StopInstances` gelten nur für die Instanz-ID von `kai1` statt per Tag, `ec2:DescribeInstances` für alle Instanzen. Der CloudWatch-Alarm als Sicherheitsnetz fehlt.

## Arbeitsweise

- **Branches:** ein Branch je Thema (`kai-<thema>`), kleine PRs.
- **Fork:** Der Agent pusht nur in Axels Fork; Axel prüft dort und öffnet den Pull Request an dieses Repo. Direkte Commits hierher erst nach Absprache mit Uwe.
- **In `kai-dev`:** Clone dieses Repos, VSCode per Remote-SSH. Gate `check` vor jedem Commit; Claude Code, Ansible, yamllint, gitleaks und `gh` liegen in `kai-dev` (Phase 2.0). Das AWS-Profil kommt erst in Phase 3 dazu und liegt nur dort; Brave-Key, `WEBUI_SECRET_KEY` und LiteLLM-Keys nie in `kai-dev`.
- **Test-Ziele `kai-entry-pre` und `kai-gpu-pre`:** jeder Deployment-Test startet auf frischem Overlay; das Stoppen gehört zu jedem Test, auch nach einem Fehlschlag.
- **Maschinenwechsel:** nie auf einer Maschine von Hand reparieren, was die Rolle nicht auch auf einer frischen Maschine herstellt; jede Abweichung geht zurück in die Rolle. Das hält die Regel aus [01 §3](01_architektur.md) ein.
- **Später auf `kai-entry`:** dieselben Checks laufen dort aus denselben Debian-Paketen wie in `kai-dev`; dessen Werkzeugliste ist die Vorlage dafür.
- **Sprache:** Repo-Konvention Deutsch für Kai-Dokumente, Kommentare und Aufgaben-Namen; Variablennamen, Logausgaben und Dateinamen Englisch.
- **Geheimnisse:** nie im Git. `.env` nur auf `kai-entry`; Brave-Key, `WEBUI_SECRET_KEY` und LiteLLM-Master-Key zusätzlich in der Team-KeePass (`unserkai.kdbx`), das Admin-Passwort von Open WebUI nur dort (`kai-bootstrap` zeigt es einmalig und speichert nichts).

## Offene Punkte (Entscheidung Uwe / Team)

1. Egress: heute offen ohne Allowlist; auf die Ziele in [02 §3](02_anforderungen-infrastruktur.md) einschränken oder offen lassen.
2. Private DNS-Zone `unserkai.de` mit `webui1` und `kai1` (heute ersetzt durch `kai_extra_hosts`); Security Groups per Gruppenreferenz ([02 §4](02_anforderungen-infrastruktur.md)).
3. `kai-gpu` (`kai1`): Root von 30 auf 50 GB, beantragt; Terraform steht weiter auf 30 GB, und 30 GB liefen beim Wechsel des CUDA-Images voll ([02 §1.7](02_anforderungen-infrastruktur.md)).
4. Budget-Grenze für die Betriebsstunden von `kai-gpu` und den Dauerbetrieb von `kai-entry` (S1-03).
5. Datenschutz-Regeln für den Prototyp festhalten (S1-04): wer in Open WebUI Admin ist, wie lange Chats aufbewahrt werden, ob und wann externe Modelle über LiteLLM freigegeben werden.
6. Konten-Datenbank verschlüsseln: Postgres von Open WebUI auf `kai-data` (EBS-Verschlüsselung); für den Start so akzeptiert.
7. Pförtner (Phase 4): Entscheidungen aus [05](05_vorschlag-auto-stop.md); ob Uwe den CloudWatch-Alarm noch anlegt, ist offen.
8. Zugangsweg für Harnesses zu LiteLLM (heute nur `127.0.0.1:4000`): zweiter Port in `kai-tunnel` oder Freigabe im VPN-CIDR ([06](06_zugang.md)); dazu, ob `tpm_limit`/`max_parallel_requests` je Nutzer als Kostenschutz für die GPU-Laufzeit gesetzt werden.
