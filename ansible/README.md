# Ansible-Konfiguration für Linux-Maschinen

Diese Struktur konfiguriert mehrere Debian-13-Maschinen zentral. Die
Kai-Maschinen `kai-entry` und `kai-gpu` (je mit Test-VM `-pre`) erhalten die
Benutzerkonten aus `group_vars/all.yml` und Docker inklusive Compose-Plugin.
Die Rolle `cmake` liegt noch im Repo, läuft aber in `site.yml` auf keiner Gruppe.

## Struktur

```text
ansible/
├── ansible.cfg                  # Inventory, Rollenpfad, become-/SSH-Defaults
├── requirements.yml             # benoetigte Collections (ansible.posix)
├── Makefile                     # Kurzbefehle fuer Syntaxcheck, Lint, Deploy
├── .ansible-lint                # Lint-Profil
├── inventory/
│   ├── hosts.yml                # Gruppen kai_entry und kai_gpu mit ihren Hosts
│   ├── group_vars/              # all.yml (Benutzer), kai_entry.yml, kai_gpu.yml (Stack)
│   ├── host_vars/               # je Host: Zugang, Maschinendaten
│   └── local/                   # gitignoriertes Overlay (Proxy, Adressen der Test-VMs)
├── files/ssh_keys/              # oeffentliche SSH-Keys (uwe.pub, axel.pub, ...)
├── playbooks/site.yml           # Einstiegspunkt
└── roles/
    ├── common/                  # Basispakete, Zeitzone, apt
    ├── users/                   # Benutzerkonten, sudoers, SSH-Keys
    ├── docker/                  # Docker Engine + Compose aus dem offiziellen Repo
    └── cmake/                   # CMake und optionale Build-Werkzeuge
```

## Voraussetzungen

- Zielsysteme: Debian 13 auf x86_64 oder aarch64 (die Rollen prüfen das und
  brechen sonst mit einer klaren Meldung ab).
- Controller: Python 3.10+, `ansible-core >= 2.16`.
- SSH-Zugang zum Zielhost mit einem Benutzer, der `sudo` ausführen darf
  (im Beispiel `ansible`).
- Die öffentlichen SSH-Keys der vier Benutzer unter `files/ssh_keys/` ablegen
  (siehe `files/ssh_keys/README.md`). Fehlt ein Key, wird der Benutzer trotzdem
  angelegt, hat aber keinen SSH-Zugang.

## Schnellstart

```bash
cd ansible
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip ansible-core ansible-lint
make deps
```

Die Test-VMs brauchen vor dem ersten Lauf ein Overlay `inventory/local/`
(gitignoriert, das Makefile hängt es als zweites `-i` an): `hosts.yml` mit den
Hosts und `host_vars/<host>.yml` mit `ansible_host`, `kai_http_proxy` und
`kai_extra_hosts`. Die AWS-Hosts erreichen wir erst in Phase 3 über SSM.

Danach:

```bash
make syntax                  # Syntaxcheck ohne Verbindung
make ping                    # SSH- und Python-Verbindung testen
make check                   # Dry-Run mit --check --diff
make deploy                  # Konfiguration anwenden
```

Wenn der Bootstrap-Benutzer ein sudo-Passwort benötigt: `-K` ergänzen, z. B.
`make deploy ANSIBLE_PLAYBOOK='ansible-playbook -K'`.
Falls noch kein SSH-Key für den Bootstrap-Benutzer hinterlegt ist, hilft
`--ask-pass`.

## Benutzer und SSH-Keys

Die Benutzer werden pro Host in `inventory/host_vars/<host>.yml` definiert:

```yaml
users_managed:
  - name: uwe
    comment: "Uwe Bartels"
    sudo: true
    groups: [developers]              # optional, zusaetzliche Gruppen
    password: "$6$..."                # optional, Passwort-Hash
    ssh_authorized_keys:              # Liste oeffentlicher Keys
      - "ssh-ed25519 AAAA... uwe@laptop"
```

Die Beispielkonfiguration liest die Keys automatisch aus
`files/ssh_keys/<name>.pub`. Ein Passwort-Hash lässt sich z. B. so erzeugen:

```bash
mkpasswd -m sha-512
# oder mit OpenSSL:
openssl passwd -6
```

Passwort-Hashes gehören nicht im Klartext ins Repository. Besser mit
`ansible-vault` verschlüsseln und per `--ask-vault-pass` bzw.
`--vault-password-file` einlesen.

`users_passwordless_sudo: true` ist in der Beispielmaschine gesetzt, damit die
Konten ohne Passwort direkt `sudo` nutzen können. Für produktive Maschinen
Passwort-Hashes hinterlegen und den Wert auf `false` setzen.

## Rollen

| Rolle | Zweck | Wichtige Variablen |
| --- | --- | --- |
| `common` | apt-Update, Basispakete, Zeitzone | `common_packages`, `common_timezone`, `common_upgrade_packages` |
| `kai_updates` | Nur Sicherheitsupdates automatisch (Kernel eingeschlossen), alle 6 h und 8 min nach dem Boot, Dienst-Neustarts per needrestart nur in diesem Lauf, Kontrolle mit `kai-smoke` | `kai_updates_boot_delay`, `kai_updates_automatic_reboot` (nur `kai_entry`), `kai_updates_restart_skip` |
| `users` | Konten, sudoers, SSH-Keys | `users_managed`, `users_passwordless_sudo` |
| `docker` | Docker CE, Buildx, Compose, Daemon-Konfiguration | `docker_packages`, `docker_daemon_config`, `docker_users` |
| `cmake` | CMake und Build-Werkzeuge | `cmake_packages`, `cmake_install_build_tools` |

`docker_daemon_config` wird als `/etc/docker/daemon.json` geschrieben. Die
Standardwerte begrenzen die Log-Größe und aktivieren `live-restore`.

Die `cmake`-Rolle installiert die CMake-Version der Distribution (bei Debian 12
ist das 3.25) sowie optional `build-essential`, `gdb`, `make`, `ninja-build` und
`pkg-config`. Für eine neuere CMake-Version wäre ein zusätzliches Repository
(z. B. Kitware) oder eine Source-Installation nötig.

## Gezielt konfigurieren

```bash
# nur einen Host
ansible-playbook -i inventory/hosts.yml -i inventory/local playbooks/site.yml --limit kai-entry-pre

# nur bestimmte Rollen
ansible-playbook -i inventory/hosts.yml -i inventory/local playbooks/site.yml --tags users,docker
# oder ueber make
make deploy TAGS=users,docker

# alle verfügbaren Tags anzeigen
ansible-playbook -i inventory/hosts.yml -i inventory/local playbooks/site.yml --list-tags
```

Jede Gruppe hat in `playbooks/site.yml` ihren Play; `common`, `users` und
`docker` laufen auf allen Kai-Maschinen.

## Neue Maschine hinzufügen

1. Host in `inventory/hosts.yml` unter `kai_entry` oder `kai_gpu` eintragen.
2. `inventory/host_vars/<hostname>.yml` mit Zugang und Maschinendaten anlegen.
3. `make syntax && make ping && make deploy-limit LIMIT=<hostname>` ausführen.

## Sicherheitshinweise

- Mitgliedschaft in der Gruppe `docker` entspricht praktisch `root`-Rechten.
  `docker_users` deshalb bewusst pflegen.
- `users_passwordless_sudo: true` nur für Bootstrap-/Entwicklungsmaschinen
  verwenden.
- Private SSH-Keys niemals einchecken; nur `.pub`-Dateien.
- `StrictHostKeyChecking=accept-new` akzeptiert den Hostkey beim ersten
  Kontakt. In Umgebungen mit festen Hostkeys besser `known_hosts` vorab pflegen
  und die Option entfernen.
- Die Rollen unterstützen nur Debian; ein anderes Betriebssystem bräuchte eigene
  Task-Dateien.
- `kai_http_proxy` (Standard leer) setzt den Egress-Proxy der Test-VMs: apt
  (`/etc/apt/apt.conf.d/90kai-proxy`), ein Drop-in für `docker.service` und
  `/opt/kai/proxy.env` für Container; `kai_no_proxy` nimmt das Testnetz aus.

## Troubleshooting

- `make ping` schlägt fehl: SSH-Benutzer, Key-Pfad und Hostkey prüfen;
  ggf. `-u <user> --ask-pass` verwenden.
- sudo fragt nach Passwort: `-K` mitgeben oder `users_passwordless_sudo`
  gezielt setzen.
- Docker-Installation bricht ab: Distribution prüfen; die Rolle unterstützt nur
  Debian mit dem offiziellen Docker-Repository.
- Benutzer ohne SSH-Key: Datei `files/ssh_keys/<name>.pub` anlegen und
  `make deploy TAGS=users` erneut ausführen.

## Kai-Rollen

- `kai_volume` bindet das Datenvolume per Dateisystem-Label ein (`kai-data` unter `/opt/kai`, `kai-models` unter `/opt/kai/models`); mit `kai_volume_required: true` (AWS) legt sie auf der Platte, die `kai_volume_device` in den `host_vars` als Pfad unter `/dev/disk/by-id` benennt, ein XFS-Dateisystem an (nur wenn die Platte leer ist; ein vorhandenes Label mit anderem Typ bricht ab, es wird nie umformatiert, und fstab-Zeilen desselben Geräts unter anderem Einhängepunkt werden entfernt), ohne Volume (Test-VMs) bleibt der Einhängepunkt ein Verzeichnis.
- `kai_entry` rollt `kai/compose/entry` nach `/opt/kai` aus und startet den Stack; die `.env` mit den Geheimnissen legt ein Mensch an (aus `kai/compose/entry/.env.example`, Modus 0600), die Rolle prüft sie nur und bricht sonst ab.
- `kai_gpu` installiert auf Maschinen mit `kai_gpu_enabled: true` den NVIDIA-Treiber (Zweig `kai_gpu_driver_branch`) und das Container Toolkit, holt die Modelle mit `kai-models-pull` und startet `kai/compose/gpu`; ohne GPU läuft llama-swap über `compose.cpu.yaml` auf der CPU.

## Kai: Arbeitsablauf

Reihenfolge auf einer frischen Maschine (Test-VM oder AWS), jeweils mit `LIMIT=<host>`:

1. `make deploy TAGS=common,users,kai_volume,docker`
2. Auf `kai-entry`: `.env` aus `kai/compose/entry/.env.example` nach `/opt/kai/.env` kopieren, Werte eintragen, Modus 0600; `OPENWEBUI_LITELLM_KEY` bleibt leer.
3. `make deploy` (ganz): rollt die Stacks aus und startet sie; der zweite Lauf muss `changed=0` melden.
4. Auf `kai-entry`: `kai/bin/kai-bootstrap` richtet Open WebUI und LiteLLM ein (Konten, Verbindung, Brave-Werkzeug), danach prüft `kai/bin/kai-smoke` die ganze Kette.

Weitere Regeln:

- `make check` (Dry-Run) sagt nur im bereits ausgerollten Zustand etwas Sinnvolles: auf einer frischen Maschine bricht er an der ersten Abhängigkeit ab (Repo-Schlüssel, Pakete); nach dem ersten Deployment meldet er jede Abweichung als `changed`.
- `make deploy` stellt nach Abweichungen (geänderte Datei, falsche Rechte, gestoppter Container) den Sollzustand wieder her; die Verzeichnisse der Container-Daten (`/opt/kai/data/*`) fasst die Rolle nicht an, denn Besitzer und Rechte setzen die Container selbst.
- Die Test-VMs beginnen nach jedem Stopp wieder frisch; `make ping|check|deploy` beachten `LIMIT=kai-entry-pre,kai-gpu-pre`, damit die AWS-Hosts (noch ohne Instanz-ID) nicht angesprochen werden.
- Private Werte der Test-VMs (Proxy, Adressen) stehen nur im gitignorierten Overlay `inventory/local/`.
- Rollen, die Geheimnisse berühren, gibt es nicht: `.env` auf `kai-entry` (0600) gehört den Menschen und `kai-bootstrap`; Startpasswörter zeigt `kai-bootstrap` einmalig an und schreibt sie nirgends hin, sie gehören in die Team-KeePass.
