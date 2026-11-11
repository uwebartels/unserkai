# Kai — Härtung: Oberflächen, Schnittstellen, Zugangsdaten

Stand 11.11.2026, aus Repo und Doku abgeleitet, Live-Zustand auf `webui1`/`kai1` nicht geprüft (Spalte „Prüfen“ nennt den Befehl). Ziel: jede erreichbare Oberfläche oder API ist bekannt, hat einen Eigentümer für ihr Zugangsgeheimnis und einen festgelegten Zugangsweg. Ergänzt [01 Architektur](01_architektur.md) (Secrets) und [02 Anforderungen](02_anforderungen-infrastruktur.md) §4–5 (Security Groups, VPN).

## 1. Bestandsaufnahme

| # | Stelle | Lauscht auf | Erreichbar von | Schutz | Geheimnis liegt in | Risiko | Prüfen (auf der Maschine) |
|---|---|---|---|---|---|---|---|
| 1 | LiteLLM Admin UI `/ui` und Admin-API, `webui1:4000` | `127.0.0.1` (`kai_litellm_bind`) | nur mit Shell auf `webui1` (SSH über SSM) | eigene Admin-Konten; Umgebungs-Login (`admin` + Master-Key) per `disable_env_credential_login` gesperrt (M2) | `/opt/kai/.env` (0600 root) und KeePass (seit 11.11.) | niedrig nach M2; vorher mittel, weil der Master-Key zugleich Generalschlüssel der API ist | `sudo grep -c LITELLM_MASTER_KEY /opt/kai/.env` |
| 2 | llama-swap API und Web-UI `/ui`, `kai1:8080` | `0.0.0.0` (`kai_gpu_bind`) | ganzes Server-VPC (`ingress-llama` in [aws/kai1/firewall_rules.csv](../../aws/kai1/firewall_rules.csv)) | **keiner** | — | **hoch, sobald das VPN steht**: Client-VPN-Nutzer kommen per NAT als VPC-Adresse an, umgehen LiteLLM-Keys und Budgets, können Modelle laden/entladen und Logs lesen | `ss -ltnp \| grep 8080` |
| 3 | Open WebUI, `webui1:3000` | `127.0.0.1` (`kai_webui_bind`) | nur mit Shell auf `webui1`; Security Group lässt 3000 aber von überall zu ([aws/webui1/firewall_rules.csv](../../aws/webui1/firewall_rules.csv)) | Konten, Registrierung geschlossen | Admin-Passwort nur in der KeePass; `accounts.txt` seit 10.11. gelöscht (Plan 3.13) | mittel: Admin kann Tools/Functions mit Python anlegen = Codeausführung im Container; SG-Regel wird scharf, sobald `kai_webui_bind` geöffnet wird | `sudo ls -l /opt/kai/accounts.txt` (soll fehlen) |
| 4 | Pförtner `kai-pfoertner`, `webui1:8081` | Docker-Bridge-Adresse | jeder Container, jeder lokale Nutzer | keiner | — | niedrig: kann `kai1` starten (Kosten), sonst nichts | `ss -ltnp \| grep 8081` |
| 5 | brave-mcp, `:8000` | `0.0.0.0` im Container | nur Docker-Netz `kai`, kein veröffentlichter Port | keiner; trägt `BRAVE_API_KEY` | `.env` | niedrig | `docker compose ps` zeigt keinen Port |
| 6 | Postgres `litellm-db` | nur Docker-Netz | nur `litellm` | Passwort | `.env` | in Ordnung | — |
| 7 | SSH 22 auf beiden | alle Adressen | privates Netz laut `ingress-ssh` in den Firewall-Regeln plus SSM | Schlüssel | eigene Schlüssel | in Ordnung | — |

Es gibt kein Standardpasswort, das zu ändern wäre: LiteLLM und Postgres nehmen die Zufallswerte aus `.env`, Open WebUI das von `kai-bootstrap` erzeugte Passwort. Die Lücken sind ungeschützte Oberflächen (#2), geteilte Schlüssel als Login (#1, behoben mit M2) und Firewall-Regeln, die weiter sind als die Architektur verlangt (#2, #3; [02](02_anforderungen-infrastruktur.md) §4.3 fordert 3000 und 4000 nur aus dem VPN-Bereich).

## 2. Maßnahmen

| # | Maßnahme | Betrifft | Wer | Stand |
|---|---|---|---|---|
| M1 | Security Group `kai1`: TCP 8080 nur von der Security Group (oder Adresse) von `webui1` statt dem ganzen Server-VPC | #2 | Uwe (`aws/`) | offen |
| M2 | LiteLLM: eigenes Admin-Konto je Person (`proxy_admin`), dann `disable_env_credential_login: true` in `litellm.yaml`; Master-Key bleibt nur API-Schlüssel für `kai-bootstrap`. Ablauf in §3 | #1 | Axel | Admin-Konto angelegt, Master-Key in KeePass (11.11.); Option im Repo, Ausrollen offen |
| M3 | `/opt/kai/accounts.txt` auf `webui1`: Passwörter in die KeePass, dann `shred -u` | #3 | Axel | erledigt 10.11. (Plan 3.13) |
| M4 | Security Group `webui1`: TCP 3000 und 4000 nur aus dem VPN-Client-Bereich (`vpn_vpc_cidr` in `aws/common.hcl`) beziehungsweise dessen NAT-Adressen, nicht von überall | #3 | Uwe (`aws/`) | offen |
| M5 | `WEBUI_SECRET_KEY` und Brave-Key in die Team-KeePass (`unserkai.kdbx`), wie [04 Plan](04_plan.md) Abschnitt Geheimnisse vorsieht | #3, #5 | Axel | nicht belegt |
| M6 | Pförtner und brave-mcp in [01](01_architektur.md) als „bewusst ohne Authentisierung, nur intern erreichbar“ festhalten | #4, #5 | Axel | offen |
| M7 | llama-swap mit `apiKeys` absichern (§5), zusätzlich zu M1, nicht statt M1 | #2 | Axel | im Repo (11.11.), Ausrollen offen: vorher `LLAMA_SWAP_KEY` in beide `.env` und in die KeePass |
| M8 | Sobald das VPN steht: `kai_litellm_bind` und `kai_webui_bind` auf die VPN-seitige Adresse, HTTP bleibt nur innerhalb des VPN-Tunnels; vorher M1, M2, M4 | #1, #3 | Axel nach Uwes VPN | wartet |

## 3. LiteLLM Admin UI: eigene Konten statt Master-Key

LiteLLM kennt drei Login-Wege an der UI: Umgebungs-Login (`UI_USERNAME`, Standard `admin`, mit `UI_PASSWORD` oder, wenn das fehlt, dem Master-Key), eigene Konten in der Datenbank mit Passwort, und SSO (Google, Microsoft, generisches OIDC). Der Umgebungs-Login ist laut LiteLLM nur zum Einrichten gedacht; die UI zeigt dazu ein Warnbanner. Ein `UI_PASSWORD` in `.env` wäre nur ein weiteres geteiltes Klartext-Passwort für alle, deshalb Konten.

1. Mit `admin` und dem Master-Key anmelden (Zugang [06](06_zugang.md)).
2. **Internal Users → + Invite User**, Rolle `proxy_admin`, eigene E-Mail; der Einladungslink setzt das Passwort. Alternativ per API mit dem Master-Key: `POST /user/new` mit `user_role: proxy_admin`, dann `POST /user/update` mit `password`.
3. Abmelden, mit E-Mail und neuem Passwort anmelden und prüfen.
4. `disable_env_credential_login: true` in `litellm.yaml.j2` unter `general_settings` (im Repo), ausrollen. Ab dann gelten Master-Key, `UI_USERNAME` und `UI_PASSWORD` an der UI nicht mehr; die API nimmt den Master-Key weiter an.
5. Rückweg: Zeile entfernen und Stack neu starten, falls kein Admin-Konto mehr funktioniert.

**MFA:** LiteLLM hat keine Zwei-Faktor-Anmeldung für Datenbank-Konten. MFA gibt es nur über SSO beim Identitätsanbieter (Google, Microsoft, OIDC); das braucht eine feste URL und damit das VPN oder einen TLS-Endpunkt. Bis dahin ist der Zugangsweg der zweite Faktor: SSM mit AWS-MFA heute, VPN-Zertifikat später.

## 4. Zugangswege

- **Heute (ohne VPN):** SSH-Tunnel durch SSM auf `webui1`, Port 3000 für Open WebUI und 4000 für LiteLLM; Browser auf dem Rechner, auf dem der Tunnel endet ([06](06_zugang.md)). llama-swap: Tunnel durch SSM auf `kai1` (laufend), Port 8080, siehe §5.
- **Mit VPN:** beide UIs direkt im Browser, sobald M8 die Bind-Adressen öffnet und M4 die Security Group darauf einschränkt. Bis dahin lauscht LiteLLM nur auf `127.0.0.1`, auch mit VPN kommt man nicht hin.
- **Über kai-dev als Zwischenstation:** möglich (Tunnel teji → kai-dev → SSM), ohne Desktop oder Browser auf kai-dev; Einschränkung: während der Tunnel offen ist, erreicht jeder Prozess auf der Agent-VM die UIs ohne weitere Hürde.

## 5. llama-swap absichern

llama-swap ist ohne Konfiguration unauthentisiert. Es kennt eine Liste `apiKeys` in der `config.yaml`; mit einem Eintrag verlangt jede Anfrage den Key (`Authorization: Bearer`, `x-api-key` oder HTTP Basic), auch die Web-UI und `/api/`. Alle Keys sind gleichwertig, es gibt keine Konten, Rollen oder Limits pro Key, und llama-swap selbst nennt `apiKeys` ausdrücklich keinen Ersatz für eine Firewall. Daher M1 (Security Group) als Hauptmaßnahme und `apiKeys` als zweite Schicht.

So ist M7 umgesetzt:

- `kai-gpu`: `/opt/kai/.env` mit `LLAMA_SWAP_KEY` (Mensch, 0600; Vorlage `kai/compose/gpu/.env.example`, optional `kai_gpu_env_seed`), `llama-swap.yaml` mit `apiKeys: [${env.LLAMA_SWAP_KEY}]`; fehlt die Variable, startet llama-swap nicht. Der Compose-Healthcheck sendet den Key, weil auch `/health` ihn verlangt.
- `kai-entry`: derselbe Key in `/opt/kai/.env`; LiteLLM sendet ihn als `api_key`, der Pförtner reicht den Header durch und liest ihn aus der `.env` für seine eigenen Abfragen (`/health`, `/running`, Modell laden); `kai-smoke` liest ihn für die direkten Abfragen an kai-gpu.
- Ausrollen: Key erzeugen (`echo "sk-$(openssl rand -hex 24)"`), in die KeePass, in beide `.env` eintragen, erst `kai-gpu` dann `kai-entry` deployen; beide Rollen brechen ab, wenn der Key fehlt.

Web-UI heute erreichen (kai1 muss laufen; Browser auf dem Rechner, auf dem der Tunnel endet):

```bash
ssh -N -L 8080:127.0.0.1:8080 \
  -o ProxyCommand="aws ssm start-session --profile PROFILNAME --region eu-central-1 --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p" \
  BENUTZER@i-0f896ee21e1ae8c72
```

Dann `http://localhost:8080/ui`; nach M7 fragt der Browser nach Benutzer und Passwort (HTTP Basic): Benutzer beliebig, Passwort `LLAMA_SWAP_KEY`.
