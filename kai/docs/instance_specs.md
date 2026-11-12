# Bestandsaufnahme der Instanzen `kai-entry` und `kai-gpu`

Erhoben am 2026-11-07 über SSM-Sitzung (Standard-Shell-Dokument) und EC2-API mit der Rolle `ssm-session-access-axel`; beide Instanzen dafür gestartet und danach wieder gestoppt. Zweck: Maßstab für die Rollen und für die Test-VMs `kai-entry-pre` und `kai-gpu-pre` ([04 Plan, Phase 2.0](04_plan.md)). Uwe hat beide Maschinen am 06.11. bereitgestellt.

## 1. Instanzen (EC2-API und IMDS)

| | `kai-entry` | `kai-gpu` |
|---|---|---|
| Instanz-ID | `i-0f6dc684ea90b09cf` | `i-0f896ee21e1ae8c72` |
| Tags | `Name=webui1`, `SSMAccess=true` | `Name=kai1`, `SSMAccess=true` |
| Typ | `t3.micro`: 2 vCPU (1 Kern mit Hyperthreading, Xeon Platinum 8175M), 939 MB RAM | `g4dn.xlarge`: 4 vCPU (2 Kerne mit Hyperthreading, Xeon Platinum 8259CL), 15,3 GiB RAM, 1× Tesla T4 |
| Image | `ami-04e9b382a9b6299a6` | dasselbe |
| Zone | `eu-central-1b`, x86_64 | dieselbe |
| Boot | Legacy-BIOS (`CurrentInstanceBootMode=legacy-bios`), GRUB `i386-pc`; kein UEFI, kein Secure Boot | dasselbe |
| Root-Volume | EBS 20 GB `vol-0d61b13d20663e349`, `DeleteOnTermination=true` | EBS 20 GB `vol-0141318f49efc45b7`, `DeleteOnTermination=true` |
| Weitere Platten | keine | EBS 150 GB `vol-0b351d3718d5b2104` als `/dev/sdf`, `DeleteOnTermination=false`, ohne Dateisystem; lokale NVMe (Instance Storage) 116,4 GiB |
| Instanzprofil | `terraform/webui1` | `terraform/kai1` |
| Security Group | `webui1` | `kai1` |
| Netz | privates Subnetz `/20`, keine öffentliche IPv4, kein IPv6, Hostname nach Muster `ip-…` | dasselbe |
| IMDS | nur IMDSv2 (`HttpTokens=required`, ohne Token 401), Hop-Limit 1, keine Tags im IMDS | dasselbe |
| Start | SSM-Agent rund 1 min nach `start-instances` online; Boot bis `graphical.target` 15 s | dasselbe, 12 s |

Nicht einsehbar, weil der Rolle `ec2:DescribeImages`, `ec2:DescribeVolumes` und `ec2:DescribeSecurityGroups` fehlen: Besitzer und Name des Images, Typ und Durchsatz der Volumes, Regeln der Security Groups.

## 2. System (beide Maschinen gleich)

| | |
|---|---|
| Build | `/etc/cloud-release`: `ID=ec2`, `VERSION="20261103-2651"`, also das Debian-Image `debian-13-amd64-20261103-2651` |
| Release | Debian 13.7 (trixie), `VERSION_ID="13"` |
| Kernel | `6.12.115+deb13.1-cloud-amd64` (Paket `6.12.115-2`); Kommandozeile `console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0`, Root per `PARTUUID` |
| Pakete | 338, genau das [Manifest des ec2-Builds 20261103-2651](https://cloud.debian.org/images/cloud/trixie/20261103-2651/debian-13-ec2-amd64-20261103-2651.json) mit denselben Versionen plus `amazon-ssm-agent` 3.3.5708.0-1 aus der user-data; kein `apt upgrade` gelaufen (am 07.11. ausstehend: `apt`, `apt-utils`, `libapt-pkg7.0` 3.0.3 → 3.0.4) |
| Gegenüber `genericcloud` | das ec2-Image hat 15 Pakete mehr: `amazon-ec2-utils`, `awscli`, `docutils-common`, `python3-awscrt`, `-colorama`, `-dateutil`, `-docutils`, `-jmespath`, `-prompt-toolkit`, `-pyasn1`, `-roman`, `-ruamel.yaml`, `-ruamel.yaml.clib`, `-wcwidth`, `-zipp`; sonst gleiche Pakete, gleiche Versionen |
| Vorhanden | `python3` 3.13.5 mit `python3-apt`, `sudo`, `curl`, `wget`, `vim`, `nano`, `lsb-release`, `sqv` (apt prüft Signaturen damit) |
| Nicht vorhanden | `docker`, `git`, `gpg`/`gnupg`, `jq`, `unzip`, `rsync`, `acl`, `dkms`, `gcc`, Kernel-Header |
| cloud-init | 25.1.4-1+deb13u1, Datenquelle `DataSourceEc2Local`; `/etc/cloud/cloud.cfg.d/01_debian_cloud.cfg` setzt den Standard-Benutzer `admin` (Gruppen `adm, audio, cdrom, dialout, dip, floppy, plugdev, sudo, video`, sudo ohne Passwort, `lock_passwd`) und `apt: generate_mirrorlists: true`; `disable_root: true`, `preserve_hostname: false`, `manage_etc_hosts` nicht gesetzt (`/etc/hosts` nur mit den localhost-Zeilen) |
| apt | `/etc/apt/sources.list.d/debian.sources` (deb822, `deb` und `deb-src`): `trixie trixie-updates trixie-backports` über `mirror+file:///etc/apt/mirrors/debian.list` → `https://cdn-aws.deb.debian.org/debian`, `trixie-security` über `debian-security.list` → `https://cdn-aws.deb.debian.org/debian-security`; Komponente nur `main`; dazu `/etc/apt/apt.conf.d/99force-ipv4` (`Acquire::ForceIPv4 "true";`) aus der user-data |
| Updates | `unattended-upgrades` 2.12 aktiv, `20auto-upgrades` mit `Update-Package-Lists "1"` und `Unattended-Upgrade "1"`, Timer `apt-daily` und `apt-daily-upgrade` |
| Partitionen | GPT: `p1` ext4 19,9 GB `/` (ohne Label, `fstab` per `PARTUUID` mit `discard,errors=remount-ro,x-systemd.growfs`), `p14` BIOS-Boot 3 MB, `p15` vfat 124 MB `/boot/efi`; kein Swap |
| Netz | `ens5` (ENA), MTU 9001; netplan `50-cloud-init.yaml` (DHCPv4, `match: macaddress`) für systemd-networkd; systemd-resolved mit Stub-`resolv.conf`, Nameserver ist der VPC-Resolver; kein NetworkManager |
| Zeit, Sprache | systemd-timesyncd mit Amazon Time Sync (`fd00:ec2::123`, Fallback `169.254.169.123`), Zeitzone `Etc/UTC`, `LANG=C.UTF-8` |
| AppArmor | aktiv, 106 Profile |
| sshd | `ssh.service` auf Port 22, nur Schlüssel (`PasswordAuthentication no`, `KbdInteractiveAuthentication no`), `PermitRootLogin without-password` mit der cloud-init-Sperre in `/root/.ssh/authorized_keys` („Please login as the user admin“), `AllowTcpForwarding yes`, keine Drop-ins |
| Benutzer | `admin` (uid 1000) mit sudo ohne Passwort aus `/etc/sudoers.d/90-cloud-init-users`; `ssm-user` (uid 1001, `/bin/sh`, sudo ohne Passwort aus `ssm-agent-users`), vom SSM-Agent bei der ersten Sitzung angelegt |
| Dienste | aktiviert: `amazon-ssm-agent`, `apparmor`, cloud-init (5 Units), `e2scrub_reap`, `getty@`, `grub-common`, `ssh`, `sshd-keygen`, `systemd-network-generator`, `systemd-networkd`, `systemd-networkd-wait-online`, `systemd-pstore`, `systemd-resolved`, `systemd-timesyncd`, `unattended-upgrades`; Konsole auf `ttyS0`; Journal persistent |

## 3. Nur `kai-gpu`

- Tesla T4 auf PCI `00:1e.0` (`10de:1eb8`); kein NVIDIA-Treiber, kein `/dev/nvidia*`, und der Cloud-Kernel hat kein Modul `nouveau`, also gibt es nichts zu sperren.
- NVMe-Reihenfolge beim Start: `nvme0n1` Root, `nvme1n1` Instance Storage, `nvme2n1` das 150-GB-Volume an `/dev/sdf`; der Gerätename folgt nicht der Zuordnung (Architektur E4).

## 4. Zugang und Umfeld

| | |
|---|---|
| user-data | Shell-Skript, kein `#cloud-config`: schreibt `99force-ipv4`, `apt-get update`, lädt den SSM-Agent von `https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb`, `dpkg -i`, aktiviert und startet ihn; auf `kai-gpu` sind `set -euxo pipefail` und das Log nach `/var/log/ssm-agent-install.log` auskommentiert; kein Passwort |
| SSH-Schlüssel | nur das EC2-Schlüsselpaar (RSA 2048, `SHA256:QytINnp0aNWwuwPi8QjIByg7KXhiZYEPOGq+s7l2I+g`, auf beiden dasselbe) bei `admin`; Axels Schlüssel fehlt |
| SSM | Agent 3.3.5708.0 auf beiden `Online`; Shell-Sitzung, `start-instances` und `stop-instances` gehen für beide; `AWS-StartSSHSession` ist verwehrt (`AccessDeniedException`) |
| Egress | offen ohne erkennbare Allowlist: Debian-Spiegel, `download.docker.com`, `ghcr.io`, `registry-1.docker.io`, `huggingface.co`, `developer.download.nvidia.com`, `api.search.brave.com`, `github.com`, `api.anthropic.com`, das SSM-Paket im S3-Bucket und ebenso `example.com` und `pypi.org` antworten |
| Private DNS | `gpu.kai.internal` und `entry.kai.internal` lösen nicht auf |

## 5. Abgleich mit [02 Anforderungen](02_anforderungen-infrastruktur.md)

| Punkt | Stand am 07.11. |
|---|---|
| §1.1 `kai-entry` als `t3.medium` | offen: `t3.micro` mit 939 MB RAM |
| §1.2 Debian 13, Build | erfüllt: Build 20261103-2651 |
| §1.3 `kai-gpu` als `g4dn.xlarge` in der Zone des Volumes | erfüllt |
| §1.5 Benutzer `admin` mit sudo ohne Passwort | erfüllt |
| §1.6 Tags `Name=kai-entry`/`kai-gpu`, `kai:role` | offen: `Name=webui1`/`kai1`, kein `kai:role` |
| §1.7 Root 30 GB | offen: 20 GB auf beiden |
| §2.1 Volume `kai-data` | offen: kein zweites Volume an `kai-entry` |
| §2.2, §2.3 Volume `kai-models` 150 GB, bleibt beim Terminieren | erfüllt (Typ gp3 nicht prüfbar) |
| §3.1 Egress | erfüllt, ohne Allowlist |
| §4.1, §4.4 Zone `kai.internal` | offen |
| §6.1 SSM-Agent per user-data | erfüllt (globales statt regionales Paket) |
| §6.2 `AWS-StartSSHSession` | offen |
| §6.3 Axels Schlüssel bei `admin` | offen |
| §6.5 Start/Stop beider Instanzen durch Axel | erfüllt |
| §6.6, §6.7 Lese- und Snapshot-Rechte | offen |

## 6. Folgerungen für die Test-VMs

1. Das `genericcloud`-Image 20261103-2651 bleibt die richtige Basis: gleiche Pakete und Versionen wie die Instanzen bis auf die 15 Pakete aus §2 und `amazon-ssm-agent`, die keine Rolle braucht.
2. Die Instanzen booten per Legacy-BIOS über die BIOS-Boot-Partition, nicht per UEFI; mit SeaBIOS statt OVMF nimmt die Test-VM denselben Bootpfad aus demselben Image, und Secure Boot spielt auf keiner Seite eine Rolle.
3. Root ist auf den Instanzen 20 GB, nicht 30 GB; solange Uwe nicht vergrößert (02 §1.7), zeigt eine Test-VM mit 20 GB, ob Images und Treiber auf Root passen.
4. `kai-entry` hat heute 939 MB RAM; die Test-VM `kai-entry-pre` bildet mit 4 GiB das Ziel `t3.medium` ab, nicht den Ist-Stand.
5. Die Test-VMs übernehmen aus der user-data nur `/etc/apt/apt.conf.d/99force-ipv4`; den Rest (SSM-Agent, `ssm-user`) gibt es nur in AWS.
6. Der Standard-Benutzer `admin` entsteht in der Test-VM mit denselben Gruppen und `sudo` wie in `01_debian_cloud.cfg` (§2), nicht mit dem `default`-Benutzer `debian` des genericcloud-Images.
7. Die Instanzen holen Pakete von `cdn-aws.deb.debian.org`, die Test-VMs von `deb.debian.org`; beides liegt unter `.debian.org`, die Paketstände sind dieselben.
8. Kein `gpg` im Image: Repo-Schlüssel legen die Rollen als `.asc` mit `signed-by` ab (so schon die Rolle `docker`), nie per `gpg --dearmor`.
