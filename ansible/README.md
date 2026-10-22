# Ansible-Konfiguration für Linux-Maschinen

Diese Struktur konfiguriert mehrere Debian-/Ubuntu-Maschinen zentral. Die
Beispielmaschine `ws-01` erhält vier Benutzerkonten (`uwe`, `axel`, `nic`,
`martin`), Docker inklusive Compose-Plugin und CMake mit grundlegenden
Build-Werkzeugen.

## Struktur

```text
ansible/
├── ansible.cfg                  # Inventory, Rollenpfad, become-/SSH-Defaults
├── requirements.yml             # benoetigte Collections (ansible.posix)
├── Makefile                     # Kurzbefehle fuer Syntaxcheck, Lint, Deploy
├── .ansible-lint                # Lint-Profil
├── inventory/
│   ├── hosts.yml                # Hosts und Gruppenzuordnung
│   ├── group_vars/all.yml       # Variablen fuer alle Hosts
│   └── host_vars/ws-01.yml      # Benutzer, Docker-Benutzer, Verbindungsdaten
├── files/ssh_keys/              # oeffentliche SSH-Keys (uwe.pub, axel.pub, ...)
├── playbooks/site.yml           # Einstiegspunkt
└── roles/
    ├── common/                  # Basispakete, Zeitzone, apt
    ├── users/                   # Benutzerkonten, sudoers, SSH-Keys
    ├── docker/                  # Docker Engine + Compose aus dem offiziellen Repo
    └── cmake/                   # CMake und optionale Build-Werkzeuge
```

## Voraussetzungen

- Zielsysteme: Debian oder Ubuntu (die Rollen prüfen das und brechen sonst mit
  einer klaren Meldung ab).
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

Vor dem ersten Lauf `inventory/host_vars/ws-01.yml` anpassen:

```yaml
ansible_host: 203.0.113.10   # echte IP oder DNS-Name
ansible_user: ansible        # Bootstrap-Benutzer mit sudo
# ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

Danach:

```bash
make syntax                  # Syntaxcheck ohne Verbindung
make ping                    # SSH- und Python-Verbindung testen
make check                   # Dry-Run mit --check --diff
make deploy                  # Konfiguration anwenden
```

Wenn der Bootstrap-Benutzer ein sudo-Passwort benötigt: `-K` ergänzen, z. B.
`ansible-playbook -i inventory/hosts.yml playbooks/site.yml -K`.
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
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit ws-01

# nur bestimmte Rollen
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags users,docker
# oder ueber make
make deploy TAGS=users,docker

# alle verfügbaren Tags anzeigen
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --list-tags
```

Die Rollen `docker` und `cmake` laufen nur auf Hosts, die in den Gruppen
`docker_hosts` bzw. `build_hosts` eingetragen sind. `users` läuft auf jedem Host,
für den `users_managed` definiert ist.

## Neue Maschine hinzufügen

1. Host in `inventory/hosts.yml` unter `linux` eintragen. Für Docker/CMake
   zusätzlich unter `docker_hosts`/`build_hosts` aufnehmen.
2. `inventory/host_vars/<hostname>.yml` mit Verbindungsdaten und optional
   `users_managed`, `docker_users` anlegen.
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
- Die Rollen unterstützen aktuell Debian/Ubuntu. Für RHEL-Derivate wären
  zusätzliche Task-Dateien (dnf, Docker-Repo für RHEL) nötig.

## Troubleshooting

- `make ping` schlägt fehl: SSH-Benutzer, Key-Pfad und Hostkey prüfen;
  ggf. `-u <user> --ask-pass` verwenden.
- sudo fragt nach Passwort: `-K` mitgeben oder `users_passwordless_sudo`
  gezielt setzen.
- Docker-Installation bricht ab: Distribution prüfen; die Rolle unterstützt nur
  Debian und Ubuntu mit dem offiziellen Docker-Repository.
- Benutzer ohne SSH-Key: Datei `files/ssh_keys/<name>.pub` anlegen und
  `make deploy TAGS=users` erneut ausführen.
