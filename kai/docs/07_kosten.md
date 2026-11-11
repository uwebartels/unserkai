# Kai — AWS-Kostenübersicht

Stand 10.11.2026, Region Frankfurt (`eu-central-1`), Listenpreise On-Demand in USD **ohne 19 % USt** (AWS EMEA stellt sie in Rechnung). Monat = 730 h. Grundlage ist der Terraform-Stand in `aws/` ([kai1/ec2.tf](../../aws/kai1/ec2.tf), [webui1/ec2.tf](../../aws/webui1/ec2.tf), [vpn/](../../aws/vpn/), [route53/](../../aws/route53/), [bootstrap/](../../bootstrap/)); Preise von den AWS-Preisseiten (EC2, EBS, VPC, VPN, Route 53, CloudWatch). Rundung auf 10 Cent.

## 1. Was Geld kostet

| Ressource | Terraform | Preis |
|---|---|---|
| `webui1` (`kai-entry`) | `t3.medium`, läuft durch | 0,048 $/h |
| `kai1` (`kai-gpu`) | `g4dn.xlarge`, nur bei Bedarf an | 0,658 $/h |
| EBS gp3 | Root 30 GB + Daten 20 GB (`webui1`); Root 30 GB + `kai-models` 150 GB (`kai1`); alle `delete_on_termination = false` | 0,0952 $/GB·Monat; 3 000 IOPS und 125 MB/s inklusive; darüber 0,0476 $ je MB/s·Monat, 0,006 $ je IOPS·Monat |
| EBS-Snapshots | Tag `dlm_snapshot = "true"` auf allen Volumes; Richtlinie nicht im Repo | 0,054 $/GB·Monat (nur geänderte Blöcke) |
| Egress aus den privaten Subnetzen | VPC-Modul nicht im Repo (`aws/modules/vpc/` leer); beide Instanzen ohne öffentliche IP, Egress funktioniert ([Bestandsaufnahme §4](instance_specs.md)) → **Annahme: ein NAT-Gateway in einer AZ** | 0,052 $/h + 0,052 $/GB verarbeitet; dazu dessen öffentliche IPv4 0,005 $/h |
| Client VPN | `aws/vpn/`: ein Endpunkt, **eine** Subnetz-Zuordnung, SAML über IAM Identity Center; laut [06](06_zugang.md) noch nicht in Betrieb | 0,10 $/h je Subnetz-Zuordnung (läuft immer) + 0,05 $/h je verbundenem Client |
| Route 53 | öffentliche Zone `unserkai.de`; Domain `.de`, `auto_renew` | 0,50 $/Zone·Monat; 9 $/Jahr Domain; Abfragen 0,40 $/Mio |
| CloudWatch | `monitoring = true` auf beiden Instanzen (Detailed Monitoring, 7 Metriken) | 0,30 $/Metrik·Monat → 2,10 $ je laufender Instanz; gestoppt 0 |
| KMS | Schlüssel für den Terraform-State-Bucket (`bootstrap/`) | 1,00 $/Monat |
| Kostenlos | SSM Session Manager, IAM Identity Center, ACM-Zertifikat, Security Groups, VPC, Instance Storage der g4dn, S3-State (Cent-Beträge), Datenverkehr in den VPC hinein | — |

## 2. Ruhekosten (kai1 gestoppt, webui1 läuft)

| Posten | $/Monat |
|---|---:|
| `webui1` `t3.medium` 730 h | 35,00 |
| EBS `webui1` 50 GB | 4,80 |
| EBS `kai1` 180 GB (Root + `kai-models`, auch im Stop-Zustand) | 17,10 |
| NAT-Gateway 730 h + IPv4 (Annahme, §1) | 41,60 |
| Snapshots (Schätzung: ≈ 50 GB belegt) | 2,70 |
| Detailed Monitoring `webui1` | 2,10 |
| Route 53 Zone + Domain (9 $/Jahr umgelegt) | 1,30 |
| KMS | 1,00 |
| **Summe Ruhe** | **≈ 106** |

Das sind ≈ 1 270 $ im Jahr, bevor `kai1` eine Stunde läuft. Ohne NAT-Gateway (zwei öffentliche IPv4 statt dessen, [02 §3.1](02_anforderungen-infrastruktur.md)) wären es ≈ 72 $/Monat; das NAT-Gateway ist nach `webui1` selbst der größte Fixposten.

Hinweis `t3.medium`: im Modus `unlimited` kostet CPU über dem Basiswert (20 %) 0,05 $ je vCPU-Stunde; bei Chat-Last vernachlässigbar, bei Dauerlast auf beiden Kernen bis ≈ 58 $/Monat zusätzlich.

## 3. Betriebskosten (kai1 an)

Je Betriebsstunde von `kai1`: **0,66 $** (`g4dn.xlarge` 0,658 $ + Detailed Monitoring 0,003 $). Dazu 0,052 $ je GB, das durch das NAT-Gateway geht (Modell-Download 10 GB ≈ 0,50 $, einmalig je Modell).

| Betrieb `kai1` je Monat | Betrieb $ | Ruhe + Betrieb $ |
|---|---:|---:|
| 20 h (gelegentlich) | 13 | ≈ 119 |
| 50 h | 33 | ≈ 139 |
| 100 h (Annahme aus [02 §7.2](02_anforderungen-infrastruktur.md)) | 66 | ≈ 172 |
| 200 h | 132 | ≈ 238 |
| 730 h (durchlaufend) | 482 | ≈ 588 |

Eine vergessene Nacht (12 h) kostet 7,90 $, ein vergessenes Wochenende (60 h) 39,50 $; deshalb [05 Pförtner](05_vorschlag-auto-stop.md). Spot (0,23–0,33 $/h) halbiert die Betriebsstunde, nicht die Ruhekosten.

**Client VPN, sobald es läuft:** + 73,00 $/Monat Fixkosten für die Subnetz-Zuordnung, dazu 0,05 $ je Client-Stunde (4 Nutzer × 40 h = 8 $). Das VPN wäre damit teurer als `webui1` selbst; die Zuordnung lässt sich per Terraform lösen, solange niemand es braucht, dann fallen nur Verbindungsstunden an.

## 4. Einmalkosten

| Posten | $ |
|---|---:|
| Domain `unserkai.de` erstes Jahr (danach Verlängerung, in §2 umgelegt) | 9,00 |
| Erstbefüllung `kai-models` (NAT-Verarbeitung, ≈ 100 GB Modelle) | 5,20 |
| Images, Treiber, CUDA-Repo für beide Maschinen (≈ 10 GB) | 0,50 |
| Snapshot `kai-data` vor der Erstinstallation (S1-11; 20 GB) | 1,10/Monat solange er liegt |
| AMI Debian 13, SSM-Agent, Terraform-Bootstrap | 0 |

AWS erhebt keine Einrichtungsgebühren; „einmalig“ ist hier fast nur Datenverkehr. Ein Instanztyp- oder Volume-Wechsel kostet nichts außer der Zeit.

## 5. Optionen

| Option | Änderung | $/Monat | Bemerkung |
|---|---|---:|---|
| `kai1` Root 30 → 50 GB | `volume_size = 50` in [kai1/ec2.tf](../../aws/kai1/ec2.tf) | + 1,90 | online ohne Neustart; `x-systemd.growfs` in der fstab wächst das Dateisystem beim nächsten Boot, sonst `growpart` + `resize2fs`. Falls Root heute noch 20 GB hat ([Bestandsaufnahme §1.7](instance_specs.md)), sind es + 2,90 |
| `kai-models` 125 → 250 MB/s | `throughput = 250` am `aws_ebs_volume.data` | + 5,95 | 125 MB/s über dem Freibetrag × 0,0476 $; Modell 10 GB lädt in ≈ 50 s statt ≈ 100 s ([05 §Flankierend](05_vorschlag-auto-stop.md)) |
| `kai-models` 125 → 400 MB/s | `throughput = 400` | + 13,10 | 275 MB/s × 0,0476 $; ≈ 30 s je Modell. Die `g4dn.xlarge` liefert EBS-Bandbreite 950 Mbit/s (≈ 119 MB/s) im Grundwert und 3 500 Mbit/s (≈ 437 MB/s) als Burst für ≤ 30 min je 24 h; ein Modell-Load liegt weit darunter, Dauerlast über 119 MB/s nicht. gp3 verlangt 1 IOPS je 0,25 MB/s, also 1 600 IOPS, innerhalb der freien 3 000 |
| beides zusammen (50 GB + 400 MB/s) | | + 15,00 | Ruhe ≈ 121 $/Monat |

Durchsatz wird sekundengenau berechnet, solange er provisioniert ist, und lässt sich ohne Ausfall wieder senken (eine Änderung je Volume alle 6 h). Wer sparen will, provisioniert 400 MB/s nur, solange `kai1` tatsächlich häufig geweckt wird; im Stop-Zustand kostet der Durchsatz genauso weiter wie der Speicher.

## 6. Unsicherheiten

- **NAT-Gateway** ist angenommen, nicht belegt: das VPC-Modul liegt nicht im Repo. Uwe prüft in der Konsole (VPC → NAT-Gateways); mit zwei Gateways (eines je AZ) verdoppelt sich der Posten auf ≈ 83 $.
- **Snapshots:** die DLM-Richtlinie ist nicht im Repo; Kosten hängen von Häufigkeit, Aufbewahrung und Änderungsrate ab. Ein voller Satz aller 230 GB läge bei ≈ 12 $/Monat, inkrementelle Folgesnapshots weit darunter.
- **Private Route-53-Zone** ([01 §3](01_architektur.md)): falls vorhanden, + 0,50 $/Monat.
- **Datenverkehr aus AWS heraus** (Antworten an Nutzer über VPN/SSM): 0,09 $/GB nach 100 GB frei; bei Chat vernachlässigbar.
- Preise ändern sich; Kontrolle ist die Rechnung bzw. Cost Explorer unter dem Terraform-Profil.
