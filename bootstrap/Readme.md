# `bootstrap` Verzeichnis

## Allgemein

Der Code im `bootstrap` Verzeichnis wird benutzt, damit die Voraussetzungen für das Arbeiten mit Terraform im Team gegeben sind.
Dazu gehören:

- die Erstellung eines PGP Keys zur Verschlüsselung von sensitiven Daten
- die Erstellung eines AWS S3 Buckets zur Speicherung des `terraform state`
- die Erstellung einer AWS Dynamo Tabelle für das Terraform Locking
- die Erstellung des AWS Benutzers für `terraform`

Die Erstellung des S3 Buckets, der Dynamo Tabelle und des `terraform` Benutzer sind nach Terraform-Dokumentation konfiguriert.

## PGP

IAM User werden mit einem Passwort versehen.
Dieses wird im terraform state base64-encoded und pgp-verschlüsselt abgelegt.
Um das Passwort zu entschlüsseln, muss in der Arbeitsumgebung PGP installiert und konfiguriert werden.

### Installation PGP on MacOS

```sh
brew install gpg2
```

### Erstellung des PGP-Keys on Mac OS

Zu einfachen Erstellung des PGP-Keys wurde ein Skript erstellt: `generate_pgp_key.sh`.
Den Anweisungen nach Abschluss des Scriptsaufrufs sollte man folgen:

- Der PGP-Key muss gepackt werden und in keepass gespeichert werden.
- Weiterhin muss der pgp-public-key base64-encoded im terraform code konfiguriert werden.
  Die angezeigte Zeichenkette ist bereits base64-encoded.

### Konfiguration PGP on Mac OS

Die benötigten PGP-Keys sind in einer keepass-Datenbank in dem Eintrag `pgp keyring` enthalten.
Das attachment `terraform.gnupg.tgz` muss exportiert und im aktuellen Verzeichnis in `.gnupg` entpackt werden:

```sh
mkdir -p .gnupg && tar xf terraform.gnupg.tgz -C .gnupg && chmod 700 .gnupg
```

Die genutzte Umgebungsvariable `GNUPGHOME` wird über direnv, Datei `.envrc` konfiguriert.

### Extrahieren von Benutzerpasswörtern

Für das Erstellen von Benutzer wird das terraform module `iam-user` benutzt.
Um das Passwort zu extrahieren, wird hierfür der private key des PGP-Schlüssels benötigt.
Weiterhin wird der Name der Terraform Module `iam-user` Instanz benötigt, z.B. `iam_user-user1`.

Um die Arbeitsumgebung für PGP vorzubereiten, siehe [PGP Abschnitt](#pgp) oben.
Anschließend kann das unten stehende Kommando ausgeführt werden. Der
Beispielbenutzer `iam_user-user1` wird hierbei durch den realen Benutzer ersetzt:

```sh
terraform init
terraform state show 'module.iam_user-user1.aws_iam_user_login_profile.this[0]' \
    | awk '/encrypted_password/ {print $3}' \
    | sed -e 's/"//g' \
    | base64 -d \
    | gpg -d 2>/dev/null; \
    echo
```

Für `terraform` IAM user das Kommando ist:

```sh
terraform init
terraform state show 'module.iam_user-terraform.aws_iam_user_login_profile.this[0]' \
    | awk '/encrypted_password/ {print $3}' \
    | sed -e 's/"//g' \
    | base64 -d \
    | gpg -d 2>/dev/null; \
    echo
```

Zur Erklärung des Kommandos:

- Das erste Kommando extrahiert die Daten des Terraform Objektes.
- mit `awk` wird der Passwortstring inkl. `"` herausgefiltert. d
- mit `sed` werden die `"` entfernt.
- dann wird die Zeichenkette `base64`-dekodiert.
- mit `gpg2` wird das Passwort entschlüsselt.
- mit `echo` wird noch ein Zeilenumbruch zur besseren Lesbarkeit ausgegeben.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.68.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.20.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_group"></a> [group](#module\_group) | terraform-aws-modules/iam/aws//modules/iam-group-with-policies | 4.7.0 |
| <a name="module_iam_assumable_role_terraform"></a> [iam\_assumable\_role\_terraform](#module\_iam\_assumable\_role\_terraform) | terraform-aws-modules/iam/aws//modules/iam-assumable-role | ~> 3.0 |
| <a name="module_iam_user-terraform"></a> [iam\_user-terraform](#module\_iam\_user-terraform) | terraform-aws-modules/iam/aws//modules/iam-user | ~> 3.0 |

## Resources

| Name | Type |
|------|------|
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_pgp_key"></a> [pgp\_key](#input\_pgp\_key) | base64 encoded string of pgp public key | `string` | n/a | yes |
| <a name="input_profile"></a> [profile](#input\_profile) | aws profile with personal account | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | aws region | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
