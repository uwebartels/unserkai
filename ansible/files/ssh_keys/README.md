# SSH-Keys der verwalteten Benutzer

Hier die oeffentlichen SSH-Keys ablegen, benannt nach dem Benutzer:

```text
uwe.pub
axel.pub
nic.pub
martin.pub
```

Die Dateien werden in `inventory/host_vars/ws-01.yml` eingelesen. Fehlt eine
Datei, wird der Benutzer trotzdem angelegt, erhaelt aber keinen Key. In dem
Fall muss der Zugang anders erfolgen (z. B. Passwort setzen).

Oeffentliche Keys duerfen eingecheckt werden. Private Keys gehoeren niemals
ins Repository.
