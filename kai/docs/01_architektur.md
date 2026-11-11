# Kai — Architektur und Design (zwei Maschinen)

Stand: 2026-11-07 · Status: Entwurf zur Abstimmung · Autor: Axel (mit Claude Code)

Dieses Dokument beschreibt, **was** auf den Kai-Maschinen läuft, **warum** es so gebaut wird und **wie** die Teile zusammenhängen. Es ist die Grundlage für die Skripte (Phase 2) und die Umsetzung (Phase 3). Für Nicht-Techniker gibt es die Bilder in [bilder/](bilder/) und die Kurzfassung in der [README](../README.md).

Verwandt: [02 Anforderungen an die Infrastruktur](02_anforderungen-infrastruktur.md) · [03 Modellvorschlag](03_modellvorschlag.md) · [04 Plan](04_plan.md) · [Bestandsaufnahme der Instanzen](instance_specs.md)

---

## 1. Ziel und Rahmen

- **Ziel des ersten Durchstichs:** Ein Chat für vier Personen (Uwe, Axel, Nic, Martin) mit einem lokal laufenden Sprachmodell auf einer gemieteten GPU-Maschine in AWS, nutzbar vom PC und Telefon. Dazu Websuche als erstes Werkzeug (Brave) und ein Endpunkt, an dem später Harnesses wie OpenCode, OpenClaw oder OpenWork andocken.
- **Nicht-Ziele des Durchstichs:** Messenger-Anbindung, automatisches Hoch- und Runterfahren der GPU-Maschine, Hochverfügbarkeit, Einbindung privater Hardware (lezki), externe KI-Dienste mit Pseudonymisierung. Für all das ist der Platz vorgesehen (§5), gebaut wird es später.
- **Vorbild:** Axels Heim-Setup (`lezki` = GPU-Rechenknoten mit llama.cpp hinter llama-swap, `mcps` = Open WebUI als Frontend). Übertragen auf AWS: zwei Maschinen mit genau dieser Rollenteilung, alles in **Docker-Containern**, Verteilung über **Ansible** (Konvention dieses Repos).
- **Ausgangslage:** Uwe hat am 06.11. beide Instanzen bereitgestellt, `webui1` als `kai-entry` und `kai1` als `kai-gpu`, beide aus dem Debian-Image 20261103-2651 (Befund in [instance_specs.md](instance_specs.md): SSM-Zugang, privates Subnetz, Egress). Alle Kai-Maschinen tragen Debian 13 wie die Maschinen in Axels Heimnetz (Uwe und Axel, 06.11.): `kai-entry` und `kai-gpu` dasselbe offizielle Debian-Image, die Test-VMs im Heimnetz das Debian-Cloud-Image desselben Builds. Rollen und Stacks entstehen nach dem Muster des Heim-Setups; was Uwe in AWS bereitstellt, ist der Maßstab. Kai trennt von Anfang an Oberfläche und Rechenknoten.

## 2. Zielbild: `kai-entry` und `kai-gpu`

```
Nutzer (PC, Telefon) ────VPN / Zugangsregel (Uwe)────┐
Harnesses (OpenCode, OpenClaw, …) ───────────────────┤
                                                     ▼
┌────────────────── kai-entry · t3.medium · läuft durch ─────────────────────────────────┐
│                                                                                        │
│  [open-webui] :3000 ──── OpenAI-API ────▶ [litellm] :4000 ◀──── OpenAI-API ── Harnesses │
│       │                                       │   └── [litellm-db] (Postgres: Keys,    │
│       │ MCP (Streamable HTTP)                 │                     Budgets, Verbrauch) │
│       └──────────▶ [brave-mcp] :8000 ── HTTPS ─│──▶ api.search.brave.com (extern)      │
│                                               │                                        │
│  Volume /opt/kai (EBS): data/open-webui · data/litellm-db · .env                            │
└───────────────────────────────────────────────┼────────────────────────────────────────┘
                                                │ OpenAI-API an kai1.unserkai.de:8080
                                                │ (nur im VPC, Security Group)
┌───────────────────────────────────────────────▼──── kai-gpu · g4dn.xlarge · bei Bedarf an ──┐
│                                                                                             │
│  [llama-swap] :8080 ── startet / stoppt ──▶ [llama-server] (GPU, Modell X)                  │
│                                                                                             │
│  Volume /opt/kai/models (EBS): GGUF-Dateien                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

später daneben, alle als weitere Einträge in LiteLLM: GPU-VM B (größer) · lezki über Tunnel · OpenAI / Anthropic
```

### Rollen der beiden Maschinen

| | `kai-entry` | `kai-gpu` |
|---|---|---|
| AWS-Name | `webui1` (`i-0f6dc684ea90b09cf`), von Uwe angelegt; `kai-entry` ist der Name im Konzept und im Inventory | `kai1` (`i-0f896ee21e1ae8c72`), von Uwe angelegt; `kai-gpu` ist der Name im Konzept und im Inventory |
| System | Debian 13, offizielles Debian-Image | dasselbe Image; NVIDIA-Treiber, Docker und Container Toolkit installiert Ansible |
| Betrieb | läuft durch, günstig | nur an, wenn gebraucht; später automatisch |
| Hält | Konten, Chat-Verlauf, Dokumente, Werkzeuge, Keys, Modellliste | Modelldateien, Grafikkarte |
| Ersetzbar durch | größere Instanz derselben Art | GPU-VM mit mehr VRAM, zweite GPU-VM daneben |
| Zugang für Nutzer | ja (VPN) | nein, nur aus dem VPC |

### Komponenten

| Maschine | Container | Image (Vorschlag, in Phase 2 gepinnt) | Aufgabe | Port |
|---|---|---|---|---|
| kai-entry | `open-webui` | `ghcr.io/open-webui/open-webui:<version ≥ 0.6.31>` | Chat-Oberfläche, Benutzerkonten, Chat-Verlauf, Dokumente, Werkzeug-Anbindung | 3000 auf `kai_webui_bind` |
| kai-entry | `litellm` | `ghcr.io/berriai/litellm:<version>-stable` | OpenAI-kompatibler Endpunkt für Open WebUI und Harnesses; Modellliste aus allen Backends; Routing, Fallback; virtuelle Keys, Budgets, Verbrauch pro Key | 4000 auf `kai_litellm_bind` |
| kai-entry | `litellm-db` | `docker.io/library/postgres:17` | Datenbank für Keys, Budgets und Verbrauch von LiteLLM | nur intern |
| kai-entry | `brave-mcp` | `docker.io/mcp/brave-search` (oder `brave/brave-search-mcp-server`), Transport `http` | Websuche als MCP-Werkzeug für Open WebUI | 8000, nur intern |
| kai-gpu | `llama-swap` | `ghcr.io/mostlygeek/llama-swap:unified-cuda` (CUDA 12; das CUDA-13-Image hat keinen Kernel für die T4) (enthält `llama-server`) | lädt das angefragte Modell auf die GPU, entlädt bei Wechsel | 8080 auf der VPC-Adresse |

Begründungen:

- **Zwei Maschinen von Anfang an:** die kleine Maschine kostet im Dauerbetrieb wenig und hält alles, was die Nutzer sehen. Die GPU-Maschine ist der teure Teil und läuft nur, wenn jemand rechnet. Sie lässt sich durch eine größere ersetzen oder um eine zweite ergänzen, ohne dass Konten, Verlauf oder Links sich ändern.
- **LiteLLM auf `kai-entry` ist der Verteiler:** ein OpenAI-kompatibler Endpunkt, hinter dem alle Backends hängen (heute `kai-gpu`, später GPU-VM B, lezki, OpenAI, Anthropic). Open WebUI kennt genau eine Verbindung, Harnesses bekommen je einen eigenen Key mit Budget, Modelle werden an einer Stelle gepflegt (`litellm.yaml`). LiteLLM ist Open Source (MIT), das Gateway läuft ohne Lizenzschlüssel; Keys, Budgets, Verbrauchszählung und Admin-UI sind im freien Teil. Enterprise-Funktionen (SSO ab sechs Nutzern, Audit-Logs, Budget pro Modell und Key) braucht Kai nicht. Folge: eine Postgres-Datenbank als weiterer Docker Container.
- **Open WebUI mit nativem MCP:** seit 0.6.31 spricht Open WebUI MCP über Streamable HTTP direkt. Der Brave-Server unterstützt `http`-Transport, also entfällt der Umweg über `mcpo`. Werkzeuge werden vom Admin registriert (Admin → Settings → External Tools → Typ „MCP (Streamable HTTP)“) und für alle Benutzer freigegeben.
- **Kein eigener Reverse-Proxy im Stack:** Zugang und TLS legt Uwe fest (VPN oder Load Balancer). Der Stack lauscht nur auf der konfigurierten Adresse; was von außen erreichbar ist, entscheidet die Infrastruktur, nicht der Stack. Siehe [02 §5](02_anforderungen-infrastruktur.md).

### Netz und Ports

- **kai-entry:** alle Container hängen in einem Compose-Netz `kai`. Host-Ports: `open-webui` auf `kai_webui_bind:3000` für die Nutzer, `litellm` auf `kai_litellm_bind:4000` für Harnesses. Beide Adressen sind die VPN-seitige Adresse der Maschine oder `127.0.0.1`, je nach Zugangsweg. `brave-mcp` und `litellm-db` sind nur aus dem Docker-Netz erreichbar.
- **kai-gpu:** `llama-swap` veröffentlicht 8080 auf der VPC-Adresse, weil `kai-entry` es erreichen muss. llama-swap hat keine Authentifizierung, deshalb lässt die Security Group 8080 nur aus der Security Group von `kai-entry` zu, nie aus dem VPN und nie öffentlich. Die Verwaltungsendpunkte von llama-swap (`/running`, `/unload`, `/logs`, Web-UI) bleiben damit intern; für Admin-Blicke: SSM-Portweiterleitung.
- **Adressierung:** `kai-entry` erreicht `kai-gpu` ausschließlich über den DNS-Namen in der Ansible-Variable `kai_gpu_endpoint` (Vorschlag `http://kai1.unserkai.de:8080`, private Route-53-Zone von Uwe). Keine IP-Adresse im Repo, in `litellm.yaml` oder in einer Compose-Datei. Siehe §3.
- **Ausgehend:** Image-Registries, Hugging Face (nur `kai-gpu`), api.search.brave.com (nur `kai-entry`), Debian-Spiegel, Dockers apt-Repo, NVIDIAs CUDA-Repo (Treiber und Toolkit, nur `kai-gpu`). Liste in [02 §3](02_anforderungen-infrastruktur.md). Beide Instanzen haben heute Egress ohne Allowlist ([Bestandsaufnahme §4](instance_specs.md)).

### Daten und Persistenz

| Maschine | Daten | Ort | Wächst? | Sicherung |
|---|---|---|---|---|
| kai-entry | Benutzerkonten, Chat-Verlauf, hochgeladene Dokumente, Einstellungen | `/opt/kai/data/open-webui` (`/app/backend/data`, SQLite + Dateien) | ja, langsam | EBS-Snapshot des Volumes `kai-data` (S1-11) |
| kai-entry | LiteLLM-Keys, Budgets, Verbrauch | `/opt/kai/data/litellm-db` (Postgres) | langsam | gleicher Snapshot |
| kai-entry | `.env` (Geheimnisse) | `/opt/kai/.env` | nein | gleicher Snapshot + Team-KeePass |
| kai-entry | Compose, `litellm.yaml` | `/opt/kai/` (von Ansible verwaltet) | nein | im Git |
| kai-gpu | Modelldateien (GGUF) | `/opt/kai/models` (Volume `kai-models`) | pro Modell 5–15 GB | **nicht** nötig: wiederbeschaffbar; Snapshot optional, um einen Maschinenwechsel zu beschleunigen |
| kai-gpu | Compose, `llama-swap.yaml` | `/opt/kai/` (von Ansible verwaltet) | nein | im Git |

Die Root-Platten beider Maschinen enthalten nichts, was fehlen dürfte: Betriebssystem, Treiber, Docker-Images. Alles davon kommt aus dem Image oder wird von Ansible installiert.

Ein Sprachmodell **speichert nichts**. Was gespeichert wird (Chats, Uploads), liegt auf dem Volume von `kai-entry` auf einer EBS-Platte in Frankfurt; Zugriff darauf hat, wer Admin in Open WebUI ist oder Root auf der Maschine. Das ist die Antwort auf die Datenschutz-Frage aus dem Meeting vom 02.11.; sie ist bei S1-04 festzuhalten. Fragen an externe Dienste (OpenAI, Anthropic) gibt es erst, wenn das Team Regeln dafür beschlossen hat (§5).

### Secrets

- Alle Geheimnisse liegen auf `kai-entry` in `/opt/kai/.env`, Rechte `0600 root`, **nicht** im Git: `BRAVE_API_KEY`, `WEBUI_SECRET_KEY` (signiert Sitzungen), `LITELLM_MASTER_KEY` (Admin-Key von LiteLLM), `LITELLM_SALT_KEY` (verschlüsselt gespeicherte Anbieter-Keys, darf nach dem ersten Start nie wechseln), `LITELLM_DB_PASSWORD`; später `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`. Im Repo liegt nur [`compose/entry/.env.example`](../compose/entry/.env.example) mit Platzhaltern.
- Virtuelle Keys für Nutzer und Harnesses entstehen in LiteLLM (UI oder API) und liegen in der Postgres-Datenbank, nicht in `.env`.
- `kai-gpu` hat genau ein Geheimnis in `/opt/kai/.env` (`0600 root`): `LLAMA_SWAP_KEY`, den llama-swap (`apiKeys`) von jeder Anfrage verlangt, auch von seiner Web-UI. Derselbe Wert steht auf `kai-entry` in `.env` (LiteLLM sendet ihn, der Pförtner reicht ihn durch und liest ihn für eigene Abfragen) und in der KeePass. Erste Schutzschicht bleibt die Security Group ([08 Härtung](08_haertung.md) M1, M7).
- Compose liest `.env` automatisch; Container bekommen Keys per `env_file`, nicht auf der Kommandozeile (sonst stehen sie in `docker inspect` und der Shell-History).
- Ansible kopiert `.env` **nicht**; die Rolle prüft nur, dass die Datei existiert, und bricht sonst mit Hinweis ab. Master-Key, Brave-Key und `WEBUI_SECRET_KEY` zusätzlich in der Team-KeePass (`unserkai.kdbx`), das Admin-Passwort von Open WebUI nur dort.

### Ressourcen

| Maschine | Ressource | Vorhanden | Verbraucher |
|---|---|---|---|
| kai-entry (t3.medium) | RAM | 4 GB | Open WebUI ~1–1,5 GB (mit Embedding-Modell), LiteLLM ~0,5–1 GB, Postgres ~0,2 GB, brave-mcp ~0,1 GB, OS. `webui1` hat heute 939 MB; Uwe hat angeboten, die Instanz zu vergrößern |
| kai-entry | vCPU | 2 | unkritisch; Last entsteht nur beim Hochladen und Einbetten von Dokumenten |
| kai-entry | Platte | Root 30 GB + Volume `kai-data` 20 GB | Images ~6 GB auf Root; Daten auf dem Volume |
| kai-gpu (g4dn.xlarge) | GPU-Speicher | 16 GB (T4) | Modell ~11 GB + KV-Cache für Kontext; siehe [03](03_modellvorschlag.md) |
| kai-gpu | RAM | 16 GB | llama-swap/llama-server ~1–2 GB (mmap des Modells zählt als Page-Cache), Docker, OS |
| kai-gpu | vCPU | 4 | Prompt-Vorverarbeitung läuft auf der GPU; CPU ist unkritisch |
| kai-gpu | Platte | Root 30 GB + Volume `kai-models` 150 GB | Treiber mit Kernel-Headern und DKMS-Bau ~1 GB, CUDA-Image ~5 GB auf Root; 2–3 Modelle ~30 GB plus Luft für Tests auf dem Volume |

## 3. Austauschbarkeit: die Maschine ist Wegwerfware

Beide Maschinen sollen sich jederzeit ersetzen lassen, `kai-gpu` durch eine mit mehr VRAM, `kai-entry` durch eine größere. Die Regel dafür: **Zustand liegt auf eigenen Volumes, alles andere kommt aus Git.** Ein Wechsel ist dann kein Umzug, sondern ein Neuaufbau, der ohnehin bei jedem Test auf `kai-entry-pre` und `kai-gpu-pre` geprobt wird.

| Regel | Umsetzung |
|---|---|
| Zustand nur auf eigenen EBS-Volumes | `kai-entry`: Volume `kai-data` als `/opt/kai`. `kai-gpu`: Volume `kai-models` als `/opt/kai/models`. Ansible mountet per Dateisystem-Label (`LABEL=kai-data`, `LABEL=kai-models`), nie per Gerätenamen, weil NVMe-Namen mit dem Instanztyp wechseln. Volume und Instanz liegen in derselben Availability Zone. EBS-Snapshot als Rückfall, falls auch das Volume ersetzt wird |
| Keine Adressen im Stack | `kai-gpu` wird über den privaten DNS-Namen aus `kai_gpu_endpoint` erreicht. Security Groups verweisen aufeinander per Gruppen-ID, nicht per IP. Eine neue GPU-VM bekommt denselben Namen und dieselbe Gruppe, `kai-entry` merkt den Wechsel nicht |
| Inventar nach Rolle, nicht nach Maschine | Gruppen `kai_entry` und `kai_gpu`; alle Variablen in `group_vars`. In `host_vars` steht nur, was die konkrete Maschine ausmacht: Instanz-ID für den SSM-ProxyCommand, VRAM, Modellliste, Kontextgröße. Später kann das Plugin `amazon.aws.aws_ec2` die Maschine am Tag `kai:role` finden, dann ändert ein Wechsel null Zeilen |
| Rollen laufen von Null auf frischem Image | ohne Handarbeit, zweimal hintereinander, der zweite Lauf meldet `changed=0`. Genau das prüft die Abnahmeregel für `kai-entry-pre` und `kai-gpu-pre` |
| Docker macht den Stack maschinenunabhängig | Images per Digest gepinnt; GPU per `deploy.resources.reservations.devices` mit `count: all`, also gleich für eine T4 oder zwei A10G. Das Betriebssystem ist für die Container egal; beide Maschinen tragen dasselbe Debian-13-Image, also haben die Ansible-Rollen einen einzigen Paketweg (`apt`), wie im Heimnetz. Die einzige Bindung an die Maschine ist der NVIDIA-Treiber, den die Rolle `kai_gpu` aus NVIDIAs CUDA-Repo für Debian 13 installiert: die CUDA-Version des llama-swap-Images muss zum Treiberzweig passen (`cuda13` braucht Treiber ≥ 580), deshalb ist der Zweig gepinnt ([02 §1.4](02_anforderungen-infrastruktur.md)) |

Aufwand für einen Wechsel von `kai-gpu`, sobald die Rollen aus Phase 2 stehen:

| Schritt | Wer | Dauer |
|---|---|---|
| Terraform: Instanztyp oder Image ändern, Volume `kai-models` anhängen, DNS-Eintrag | Uwe | 10 bis 15 min |
| Instanz-ID in `host_vars` eintragen, `make deploy LIMIT=kai1` | Axel | 10 bis 15 min Laufzeit, davon der Großteil Treiberbau (DKMS), ein Neustart und Image-Pull |
| Erster Chat, Modell lädt, Antwortzeit prüfen | Axel | 5 min |
| Nur wenn das Volume neu ist: Modelle laden | Axel | 3 bis 5 min pro Modell |

Rund 30 Minuten, überwiegend Wartezeit. Das Risiko sitzt im Treiber: ein neuer Kernel oder Treiberzweig kann den DKMS-Bau oder das CUDA-Image brechen; deshalb ist der Zweig gepinnt, der Kernel folgt dem Image, und `kai-gpu-pre` baut den Treiber vorab gegen denselben Kernel (Flavour `cloud-amd64`). Für `kai-entry` gilt dasselbe Muster, dazu kommt `.env` aus der KeePass, falls das Volume neu ist, und der Zugangsweg der Nutzer (VPN-Adresse oder DNS).

## 4. Betrieb

- **kai-entry läuft durch.** Beim Neustart kommen die Container mit `restart: unless-stopped` von selbst hoch.
- **kai-gpu wird von Hand gestartet und gestoppt** (`aws ec2 start-instances`, Axel oder Uwe). Beim Start kommt llama-swap von selbst hoch; llama-swap lädt das erste Modell gleich beim Start vor (≈ 100 s von der EBS-Platte bei 125 MB/s, gemessen 08.11.); bis zum ersten Token vergehen ab `start-instances` ≈ 2,5–3 min. Ist `kai-gpu` aus, meldet LiteLLM das Modell als nicht erreichbar und Open WebUI zeigt ehrlich „Modell antwortet nicht“; Konten und Verlauf bleiben nutzbar. Automatisches Wecken bei Anfrage und Stoppen nach Leerlauf: Vorschlag in [05](05_vorschlag-auto-stop.md).
- **Updates:** Images sind auf Versionen gepinnt; ein Update ist eine Änderung im Git + `make deploy`. Keine `latest`-Tags.
- **Snapshots:** `kai-data` vor der Erstinstallation und an Meilensteinen (S1-11). Eine Wiederherstellung ist „Volume aus Snapshot + `make deploy`“.
- **Logs:** `docker compose logs` je Maschine; llama-swap zeigt Modellwechsel und Lade-Dauer, LiteLLM den Verbrauch pro Key. Keine zentrale Log-Sammlung im Durchstich.

## 5. Ausblick: was der Endpunkt später aufnimmt

Jede Erweiterung ist ein weiterer Eintrag in `litellm.yaml` oder ein weiterer Host in einer Inventargruppe; die Oberfläche und die Konten bleiben gleich.

- **GPU-VM B mit mehr VRAM:** zweiter Host in der Gruppe `kai_gpu`, eigener DNS-Name, eigene Modelle (etwa Qwen3.6-35B-A3B in MXFP4, siehe [03](03_modellvorschlag.md)). Nutzer wählen das Modell im Dropdown, LiteLLM leitet an die richtige Maschine.
- **lezki und weitere Heim-Maschinen:** brauchen einen Tunnel zwischen Heimnetz und VPC (WireGuard oder SSM), das ist Uwes Zugangsfrage. Für Heim-Harnesses ist der Weg Heim → AWS → Heim ein Umweg, für das Team aber der einzige gemeinsame Punkt.
- **OpenAI und Anthropic:** technisch ein Key in `.env` und ein Eintrag in LiteLLM; LiteLLM zählt den Verbrauch pro Person und deckelt ihn. Die Pseudonymisierungsfrage aus dem Meeting bleibt offen und entscheidet, ob und wofür das Team das freigibt.
- **Harnesses (OpenCode, OpenClaw, OpenWork):** bekommen je einen virtuellen Key mit Budget und als Basis-URL den LiteLLM-Endpunkt. Modellwahl geschieht beim Harness, die Liste kommt von LiteLLM.
- **Automatik für kai-gpu:** Wecken beim ersten Aufruf, Stoppen nach Leerlauf. Kandidaten: ein kleiner Dienst auf `kai-entry` mit einer Instanzrolle, die nur `kai-gpu` starten und stoppen darf.

## 6. Entscheidungen (Kurzliste)

| # | Entscheidung | Alternative, verworfen weil |
|---|---|---|
| E1 | Docker Compose für alle Dienste | native Installation wie auf lezki: schwerer reproduzierbar, Maschinenwechsel aufwändiger |
| E2 | llama-swap + llama.cpp (ein Image) auf `kai-gpu` | Ollama (im Repo-Verlauf): weniger Kontrolle über Quantisierung/Kontext, kein Harmony/Jinja-Feintuning; vLLM: braucht mehr VRAM für gleiche Modelle |
| E3 | Natives MCP in Open WebUI | mcpo-Proxy: ein Container mehr, nur nötig für stdio-Server |
| E4 | Zustand je Maschine auf einem eigenen EBS-Volume, Mount per Label | alles auf Root-EBS: die Root-Platte ist klein, Snapshot vermischt OS und Daten, Wechsel der Maschine wird zum Umzug |
| E5 | Stack lauscht nur lokal bzw. im VPC, Zugang regelt Infrastruktur | Caddy/Traefik im Stack: doppelt, solange VPN/Zugangsweg nicht feststeht |
| E6 | `.env` nur auf `kai-entry`, `.env.example` im Git | sops-verschlüsselt im Git: möglich, aber zweiter Geheimnis-Pfad neben KeePass; später bei Bedarf |
| E7 | Zwei Ansible-Rollen `kai_entry` und `kai_gpu`, zwei Compose-Stacks | eine Rolle mit Schalter: vermischt zwei Maschinen mit verschiedenen Abhängigkeiten (GPU-Runtime, Postgres) |
| E8 | Zwei Maschinen von Anfang an | eine GPU-Maschine für alles: kurzfristig billiger, aber zweiter Umzug, und die Einstiegs-Instanz existiert bereits |
| E9 | LiteLLM auf `kai-entry` als Endpunkt und Verteiler | llama-swap dort: ist ein Prozess-Manager ohne GPU-Aufgabe; nur Open WebUI mit mehreren Verbindungen: reicht für den Durchstich, aber keine Keys für Harnesses und Modelle an zwei Stellen |
| E10 | Alle Maschinen auf Debian 13 (offizielles Debian-Image, Uwe und Axel 06.11.): die Rollen sprechen `apt` wie im Heim-Setup, Docker CE aus Dockers Repo, auf `kai-gpu` Treiber (Open-Kernel-Modul per DKMS, Zweig gepinnt) und Container Toolkit aus NVIDIAs CUDA-Repo für Debian 13 | Image mit vorinstalliertem GPU-Treiber: zweiter Kernel- und Treiberstand neben dem der Rollen, Test-VMs ohne Vorbild im Heimnetz |