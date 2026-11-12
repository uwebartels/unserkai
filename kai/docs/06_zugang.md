# Kai — Zugang zu Open WebUI, LiteLLM-Admin-UI und llama-swap (bis das VPN steht)

Open WebUI lauscht auf `webui1` nur auf `127.0.0.1:3000`, LiteLLM auf `127.0.0.1:4000`, llama-swap auf `kai1` nur im VPC (Port 8080). Bis Uwe das VPN einrichtet ([02 §5](02_anforderungen-infrastruktur.md)), kommt man über einen SSH-Tunnel durch AWS SSM dran. Der Tunnel ist spürbar zäh; `webui1` selbst antwortet in wenigen Millisekunden.

## Einmalig

1. Werkzeuge auf dem eigenen Rechner: AWS-CLI v2, das Session-Manager-Plugin und `ssh` (macOS: `brew install awscli` und `brew install --cask session-manager-plugin`).
2. Ein eigenes AWS-Profil mit einer Rolle, die `ssm:StartSession` mit dem Dokument `AWS-StartSSHSession` auf `webui1` darf; das Profil richtet Uwe ein.
3. Ein eigener Benutzer auf `webui1` mit dem eigenen öffentlichen SSH-Schlüssel (Rolle `users`, Liste in `ansible/inventory/group_vars/all.yml`).
4. Ein Konto in Open WebUI; das Startpasswort kommt vom Admin und wird nach der ersten Anmeldung unter **Settings → Account** geändert.

## Jedes Mal

```bash
kai/bin/kai-gpu --profile PROFILNAME --instance-id i-0f896ee21e1ae8c72 start   # kai1 starten (kostet im Betrieb)
kai/bin/kai-tunnel --profile PROFILNAME                                         # Tunnel öffnen
```

- `PROFILNAME` ist der Name des eigenen AWS-Profils, nicht wörtlich abschreiben.
- `kai-tunnel` fragt erst die AWS-Sitzung ab (dabei kommt gegebenenfalls die MFA-Abfrage), danach die Passphrase des SSH-Schlüssels; beides gleichzeitig scheitert.
- Es nimmt den ersten freien Port ab 3000 und schreibt die Adresse hin, etwa `http://localhost:3000`; diese Adresse im Browser **auf demselben Rechner** öffnen.
- Das Terminal bleibt offen und zeigt nichts weiter; Strg+C beendet den Tunnel.
- Danach `kai/bin/kai-gpu --profile PROFILNAME --instance-id i-0f896ee21e1ae8c72 stop`.

Die erste Antwort nach dem Start von `kai1` kann noch etwa 1,5 Minuten dauern, solange das Modell von der Platte lädt; llama-swap lädt es inzwischen schon beim Start vor.

## Ohne Skript

```bash
aws sts get-caller-identity --profile PROFILNAME
ssh -N -L 3000:127.0.0.1:3000 \
  -o ProxyCommand="aws ssm start-session --profile PROFILNAME --region eu-central-1 --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p" \
  BENUTZER@i-0f6dc684ea90b09cf
```

Ist Port 3000 auf dem eigenen Rechner belegt, `-L 3001:127.0.0.1:3000` und `http://localhost:3001`. Darf die eigene Rolle zusätzlich `AWS-StartPortForwardingSession`, geht es ohne SSH-Schlüssel mit `aws ssm start-session … --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'`.

## Die drei Oberflächen

| Oberfläche | Maschine | Port dort | Anmeldung |
|---|---|---|---|
| Open WebUI | `webui1` (`i-0f6dc684ea90b09cf`) | 3000 | eigenes Konto |
| LiteLLM Admin-UI `/ui` | `webui1` | 4000 | eigenes `proxy_admin`-Konto; der Master-Key gilt an der UI nicht ([08](08_haertung.md) M2) |
| llama-swap `/ui` | `kai1` (`i-0f896ee21e1ae8c72`), muss laufen | 8080 | Browser-Dialog: Benutzer beliebig, Passwort `LLAMA_SWAP_KEY` aus der KeePass ([08](08_haertung.md) M7) |

Mit `kai-tunnel`, je ein Terminal:

```bash
kai/bin/kai-tunnel --profile PROFILNAME                                                   # Open WebUI: http://localhost:3000
kai/bin/kai-tunnel --profile PROFILNAME --remote-port 4000 --local-port 4001               # LiteLLM:    http://localhost:4001/ui
kai/bin/kai-tunnel --profile PROFILNAME --instance-id i-0f896ee21e1ae8c72 --remote-port 8080 --local-port 8081   # llama-swap: http://localhost:8081/ui
```

Ohne Skript geht alles von `webui1` in einem Tunnel (`-L 3001:127.0.0.1:3000 -L 4001:127.0.0.1:4000`), llama-swap braucht einen zweiten Tunnel auf `kai1` (`-L 8081:127.0.0.1:8080`), Muster wie oben.

**Browser auf einem anderen Rechner als die AWS-CLI** (etwa Arbeitsplatz `A`, CLI und SSH-Schlüssel auf `B`): auf `A` zuerst einen Vortunnel zu `B` öffnen und offen lassen, dann auf `B` die SSM-Tunnel wie oben mit denselben lokalen Ports; der Browser auf `A` nutzt `localhost`.

```bash
ssh -N -L 3001:127.0.0.1:3001 -L 4001:127.0.0.1:4001 -L 8081:127.0.0.1:8081 B
```

## Harness-Zugang

Werkzeuge, die LiteLLM direkt ansprechen (z. B. OpenClaw), bekommen je Person und Werkzeug einen eigenen virtuellen Key, der auf den LiteLLM-Nutzer dieser Person bucht (`user_id` = E-Mail, angelegt von `kai-bootstrap` im Schritt `litellm-users`). Auf `kai-entry` als root:

```bash
kai-bootstrap --harness-key MAIL@BEISPIEL:NAME-openclaw
```

Der Key erscheint genau einmal auf der Konsole und wird nirgends gespeichert; er geht direkt an die Person (bzw. in die Team-KeePass). Ein schon vorhandener Alias wird abgelehnt, nie ersetzt; einen alten Key löscht man bewusst in der LiteLLM-Admin-UI. Open-WebUI-„Direct Connections“ bleiben aus, weil dabei der Key im Browser läge.

LiteLLM hört heute nur auf `127.0.0.1:4000` der Instanz. Wie Harnesses dorthin kommen, ist eine offene Entscheidung für Uwe ([04, Offene Punkte](04_plan.md)): ein zweiter Port in `kai-tunnel` (wie Open WebUI über SSM) oder eine Freigabe für das VPN-CIDR.

## Auswertung

Open WebUI schickt die E-Mail des angemeldeten Nutzers im Header `X-OpenWebUI-User-Email`, LiteLLM bucht die Anfrage damit auf denselben Nutzer wie die Harness-Keys. Preise sind nicht gesetzt, also zählen nur Tokens (Spend bleibt 0). LiteLLM bucht auf die `user_id`, nicht auf das Feld `user_email`: Ein in der LiteLLM-UI angelegter Nutzer bekommt eine zufällige `user_id` und sammelt deshalb nichts; Nutzer legt nur `kai-bootstrap` an, der Admin ist bloß ein UI-Login. `kai-smoke --target entry --user-email MAIL@BEISPIEL` prüft die Zuordnung für einen Nutzer.

- Admin-UI von LiteLLM (über den Tunnel auf Port 4000, Anmeldung mit dem eigenen Konto): Seite „Usage“, Filter nach Nutzer.
- API: `curl -H "Authorization: Bearer $LITELLM_MASTER_KEY" "http://127.0.0.1:4000/spend/logs?user_id=MAIL@BEISPIEL"`.
- SQL, Tokens je Nutzer und Monat (`cd /opt/kai && docker compose exec litellm-db psql -U litellm litellm`):

```sql
SELECT "user", model, date_trunc('month', "startTime") AS monat, sum(prompt_tokens) AS prompt, sum(completion_tokens) AS completion FROM "LiteLLM_SpendLogs" GROUP BY 1, 2, 3 ORDER BY 3, 1, 2;
```
