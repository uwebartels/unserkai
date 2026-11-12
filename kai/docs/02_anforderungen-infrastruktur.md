# Kai — Anforderungen an die Infrastruktur (für Uwe)

Stand: 2026-11-07 · Status: zur Abstimmung · Bezug: [01 Architektur](01_architektur.md), [Bestandsaufnahme der Instanzen](instance_specs.md), Sprint-Aufgaben S1-05, S1-08, S1-11

Was die beiden Stacks von ihren Maschinen und dem Umfeld brauchen. „Muss“ blockiert die Installation, „Soll“ den sauberen Betrieb, „Kann“ ist Komfort. `kai-entry` ist Uwes Instanz `webui1` (`i-0f6dc684ea90b09cf`), `kai-gpu` ist `kai1` (`i-0f896ee21e1ae8c72`); was davon erfüllt ist, steht in der [Bestandsaufnahme §5](instance_specs.md).

## 1. Instanzen

| | Anforderung | Stufe |
|---|---|---|
| 1.1 | **`kai-entry`** ist `webui1` (`i-0f6dc684ea90b09cf`), wie von Uwe angelegt (Region `eu-central-1`, Zone `eu-central-1b`, x86_64). Gewünschte Größe `t3.medium` (2 vCPU, 4 GB RAM): die heutigen 939 MB reichen nicht für Open WebUI, LiteLLM und Postgres; Uwe hat die Vergrößerung angeboten | Muss |
| 1.2 | **System, beide Maschinen:** Debian 13 (trixie), amd64, das offizielle Image des Debian-Projekts in AWS (Konto `136693071363`, Name `debian-13-amd64-<Build>`), Kernel-Flavour `cloud-amd64`, cloud-init (Uwe und Axel, 06.11.); die Rollen sprechen `apt` wie im Heimnetz (Entscheidung E10 in [01 §6](01_architektur.md)). Beide Instanzen laufen auf Build 20261103-2651 (`ami-04e9b382a9b6299a6`, [Bestandsaufnahme §2](instance_specs.md)); bei einem Wechsel bitte Bescheid geben, damit `kai-entry-pre` und `kai-gpu-pre` das Cloud-Image desselben Builds bekommen | gesetzt |
| 1.3 | **`kai-gpu`** ist `kai1` (`i-0f896ee21e1ae8c72`): `g4dn.xlarge` (1× T4 16 GB, 4 vCPU, 16 GB RAM), dieselbe Zone wie das Volume `kai-models` | Muss |
| 1.4 | **Treiber `kai-gpu`:** keiner im Image; die Rolle `kai_gpu` installiert ihn wie auf Axels GPU-Rechner aus NVIDIAs CUDA-Repo für Debian 13 (`cuda-keyring`, Header `linux-headers-cloud-amd64` zum laufenden Kernel, `nvidia-driver-cuda` mit dem Open-Kernel-Modul `nvidia-kernel-open-dkms`, `nvidia-container-toolkit` aus demselben Repo) im Zweig 620, dem Long Term Support Branch bis 09/2029, festgehalten mit `nvidia-driver-pinning-620`; Debians eigener Treiber (550) ist für das `cuda13`-Image von llama-swap zu alt (braucht ≥ 580). Für Uwe nichts zu tun | gesetzt |
| 1.5 | Standard-Benutzer `admin` mit sudo ohne Passwort auf beiden Maschinen (Standard des Debian-Images), erreichbar für Ansible (siehe §6) | Muss |
| 1.6 | Tags `Name=kai-entry` bzw. `Name=kai-gpu` und `kai:role=entry` bzw. `kai:role=gpu` (für ein späteres dynamisches Inventar) | Soll |
| 1.7 | Root-Volume `kai-entry` von 20 auf 30 GB (Images ~6 GB; Debian vergrößert das Root-Dateisystem beim Start selbst), `kai-gpu` 50 GB (Treiber mit Kernel-Headern, Docker, CUDA-Image `unified-cuda`, im Betrieb 17 von 30 GB belegt; beim Image-Wechsel liegen altes und neues Image samt Entpack-Puffer gleichzeitig auf der Platte, und 30 GB liefen dabei am 07.11.2026 voll); Root enthält nur OS, Treiber und Images. Bleibt Root bei 20 GB, legt die Rolle Dockers `data-root` auf das Volume `kai-data` | Soll |

## 2. Platten

| | Anforderung | Stufe |
|---|---|---|
| 2.1 | **`kai-entry`:** zusätzliches EBS-Volume **gp3, 20 GB**, an die Instanz angehängt; Ansible legt bei Bedarf ein Dateisystem mit Label `kai-data` an und mountet es per Label als `/opt/kai` (Open-WebUI-Daten, Postgres, `.env`) | Muss |
| 2.2 | **`kai-gpu`:** zusätzliches EBS-Volume **gp3, 150 GB**, Label `kai-models`, gemountet als `/opt/kai/models` (2–3 Modelle à 10–15 GB, Luft für Modelltests). 100 GB wäre die Untergrenze | Muss |
| 2.3 | Beide Volumes überleben Stop/Start und werden beim Terminieren **nicht** gelöscht (`DeleteOnTermination=false`); sie sind das, was einen Maschinenwechsel überlebt ([01 §3](01_architektur.md)) | Muss |
| 2.4 | Terraform hängt nur an; der Gerätename ist egal, weil Ansible per Label mountet | Hinweis |
| 2.5 | Root-Volumes unverändert (OS, Treiber); kein Nutzdaten-Mix | Soll |
| 2.6 | Die lokale NVMe der g4dn (125 GB, flüchtig) wird **nicht** genutzt; sie ist nach jedem Stop leer | Hinweis |
| 2.7 | gp3-Durchsatz des Modell-Volumes: Standard 125 MB/s reicht (12 GB laden ≈ 100 s); 250–500 MB/s, falls der Modellwechsel stört ([03](03_modellvorschlag.md)) | Kann |

## 3. Netz, ausgehend

**Befund vom 07.11.:** Beide Maschinen erreichen das Internet ohne öffentliche IPv4 und ohne erkennbare Allowlist ([Bestandsaufnahme §4](instance_specs.md)); offen ist nur noch die Einschränkung auf die Ziele unten.

| | Anforderung | Stufe |
|---|---|---|
| 3.1 | Egress ins Internet für beide Maschinen, eingeschränkt auf die Ziele unten. Wege: NAT-Gateway (≈ 38 $/Monat plus Verkehr) oder je Instanz eine öffentliche IPv4 mit Security Group ohne eingehende Regel (≈ 4 $/Monat je Adresse). Uwe entscheidet | Muss |

| Ziel | Zweck | Maschine |
|---|---|---|
| `ghcr.io`, `pkg-containers.githubusercontent.com`, `registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com` | Container-Images | beide |
| Debian-Spiegel `cdn-aws.deb.debian.org` (im Image eingestellt), dazu `deb.debian.org`, `security.debian.org` | Updates, Pakete, Kernel-Header | beide |
| `download.docker.com` | Docker CE und Compose-Plugin (Dockers apt-Repo) | beide |
| S3-Bucket `amazon-ssm-eu-central-1` (ohne NAT über einen S3-Gateway-Endpunkt erreichbar) | SSM-Agent-Paket, einmalig per user-data (§6.1) | beide |
| `github.com` | Repo-Checkout für die Administration | kai-entry |
| `api.search.brave.com` | Websuche (MCP) | kai-entry |
| `api.openai.com`, `api.anthropic.com` | externe Modelle über LiteLLM, erst nach Beschluss des Teams | kai-entry, später |
| `huggingface.co`, `*.hf.co` (CDN) | Modell-Download (einmalig pro Modell, 10–15 GB) | kai-gpu |
| `developer.download.nvidia.com` | NVIDIA-Treiber und Container Toolkit (CUDA-Repo für Debian 13) | kai-gpu |

Alles andere kann ausgehend geblockt werden.

## 4. Netz im VPC

| | Anforderung | Stufe |
|---|---|---|
| 4.1 | Private Route-53-Zone `unserkai.de` mit dem Eintrag `kai1.unserkai.de` auf die private Adresse von `kai-gpu`; Terraform pflegt ihn beim Ersetzen der Maschine nach. `kai-entry` kennt `kai-gpu` nur unter diesem Namen (`kai_gpu_endpoint`) | Muss |
| 4.2 | Security Group `kai-gpu`: eingehend nur TCP 8080 aus der Security Group `kai-entry` (per Gruppen-ID, nicht per IP). llama-swap hat keine Authentifizierung | Muss |
| 4.3 | Security Group `kai-entry`: eingehend TCP 3000 (Open WebUI) und TCP 4000 (LiteLLM für Harnesses) nur aus dem VPN-Bereich; sonst nichts | Muss |
| 4.4 | Eintrag `webui1.unserkai.de` für `kai-entry`, damit Nutzer-Links und Harness-Konfigurationen einen Namen statt einer IP tragen | Soll |

## 5. Netz, eingehend — Zugang für Nutzer

| | Anforderung | Stufe |
|---|---|---|
| 5.1 | Open WebUI lauscht auf `kai_webui_bind:3000`, LiteLLM auf `kai_litellm_bind:4000`. Der Weg vom Nutzer dorthin ist **Infrastruktur**: VPN (bevorzugt), oder Reverse-Proxy/Load Balancer mit TLS | Muss (eine der beiden) |
| 5.2 | Falls VPN: Nutzer erreichen `http://webui1.unserkai.de:3000`, Harnesses `http://webui1.unserkai.de:4000/v1`. Die beiden `bind`-Variablen zeigen dann auf die VPN-seitige Adresse statt auf `127.0.0.1` | — |
| 5.3 | Falls öffentlich: HTTPS zwingend (Passwörter, Chat-Inhalte, API-Keys). Zertifikat per ALB/ACM oder Caddy auf `kai-entry`; dann kommt ein Proxy-Container in den Entry-Stack (Erweiterung, kein Umbau) | — |
| 5.4 | **Kein** öffentlich erreichbares SSH (Beschluss Meeting 02.11.) | Muss |
| 5.5 | Vier Nutzer, PC und Telefon (S1-09): Browser reicht, keine App | Hinweis |

Offen (Uwe legt fest): VPN-Technik, Domain `unserkai.de` ja/nein, interner DNS-Name.

## 6. Admin-Zugang (Axel, Ansible)

**Befund vom 07.11.:** Die Rolle `ssm-session-access-axel` erlaubt `ec2:DescribeInstances`, `Start`/`StopInstances` für beide Instanzen, `ssm:DescribeInstanceInformation` und `ssm:StartSession` mit dem Standard-Shell-Dokument; das reicht für eine Shell, aber nicht für Ansible, denn `AWS-StartSSHSession` ist verwehrt. Die user-data beider Maschinen installiert den SSM-Agent und enthält kein Passwort; bei `admin` liegt nur das EC2-Schlüsselpaar, nicht Axels Schlüssel ([Bestandsaufnahme §4](instance_specs.md)).

| | Anforderung | Stufe |
|---|---|---|
| 6.1 | **SSM Session Manager** auf beiden Instanzen. Debians Image bringt den SSM-Agent nicht mit (AWS-Doku „Manually installing SSM Agent on Debian Server instances“); die user-data installiert ihn beim ersten Start aus dem regionalen Paket (`https://s3.eu-central-1.amazonaws.com/amazon-ssm-eu-central-1/latest/debian_amd64/amazon-ssm-agent.deb`, `dpkg -i`). Instanzrolle mit `AmazonSSMManagedInstanceCore` | Muss |
| 6.2 | Session-Rolle für Axel zusätzlich: `ssm:StartSession` auf das Dokument `AWS-StartSSHSession` (für beide Instanzen), `ssm:TerminateSession`, `ssm:DescribeSessions`. Damit funktioniert Ansible (SSH über SSM-ProxyCommand) von `kai-dev` aus | Muss |
| 6.3 | Axels SSH-Public-Key (`ansible/files/ssh_keys/axel.pub`, schon im Repo) in `authorized_keys` des Benutzers `admin`, per user-data als `#cloud-config` mit `ssh_authorized_keys` beim ersten Start (cloud-init ist im Image); dieselbe user-data installiert den SSM-Agent (§6.1). Danach pflegt die Rolle `users` die Schlüssel | Muss (einmalig) |
| 6.4 | AWS-CLI-Profil für Axel mit den Rechten aus 6.2 (MFA-geschützt; eingerichtet und geprüft am 05.11.) | Muss |
| 6.5 | Start/Stop beider Instanzen durch Axel (vorhanden, geprüft am 07.11.): spart Abstimmungsrunden bei Installation, Tests und im Betrieb von `kai-gpu` | Muss |
| 6.6 | Snapshot-Recht für Axel: `ec2:CreateSnapshot`, `ec2:DescribeSnapshots`, `ec2:DescribeVolumes` auf die beiden Volumes (S1-11), oder Uwe macht Snapshots auf Zuruf | Kann |
| 6.7 | Lese-Rechte zum Prüfen der Umgebung: `ec2:DescribeImages`, `ec2:DescribeSecurityGroups`, `ec2:DescribeSubnets` | Kann |


## 7. Betrieb und Kosten

| | Anforderung | Stufe |
|---|---|---|
| 7.1 | `kai-entry` läuft durch: `t3.medium` ≈ 35 $/Monat in Frankfurt, dazu EBS (Root 30 GB + 20 GB gp3 ≈ 5 $/Monat). Alternative `t3a.medium` (AMD) etwa 10 % günstiger | Hinweis |
| 7.2 | `kai-gpu` nur bei Bedarf: On-Demand ≈ 0,66 $/h, 100 Betriebsstunden ≈ 66 $; im Stop-Zustand nur EBS (150 GB gp3 ≈ 14 $/Monat + Root). Start/Stop zunächst von Hand (Axel oder Uwe), Automatik später ([01 §5](01_architektur.md)) | Hinweis |
| 7.3 | Egress nach §3.1: NAT-Gateway ≈ 38 $/Monat oder zwei öffentliche IPv4 ≈ 8 $/Monat | Hinweis |
| 7.4 | Stabile Namen (`webui1.unserkai.de`, `kai1.unserkai.de`), damit Nutzer-Links und Harness-Konfigurationen nach Stop/Start oder Maschinenwechsel gleich bleiben | Soll |
| 7.5 | EBS-Snapshot von `kai-data` vor der Erstinstallation und an Meilensteinen; Restore-Test einmal durchspielen (S1-11) | Soll |
| 7.6 | Budget-Alarm in AWS (Billing Alert) auf den im Team vereinbarten Betrag | Soll |

## 8. Was Axel von Uwe braucht, bevor es losgeht

Erfüllt ist, was die [Bestandsaufnahme §5](instance_specs.md) so ausweist; offen bleibt:

1. `kai-entry` (`webui1`): `t3.medium`, Root 30 GB, Volume `kai-data` angehängt, Axels Key bei `admin` (§1.1, §1.7, §2.1, §6.3)
2. `kai-gpu` (`kai1`): Root 50 GB, Axels Key bei `admin` (§1.7, §6.3)
3. Private DNS-Namen (§4.1, §4.4)
4. Session-Rolle mit `AWS-StartSSHSession` (§6.2); Prüfung: `ssh` über den SSM-ProxyCommand liefert eine Shell als `admin`
5. Entscheidung zu §5 (VPN/öffentlich), damit `kai_webui_bind` und `kai_litellm_bind` gesetzt werden können; kann auch nach der Installation geändert werden
