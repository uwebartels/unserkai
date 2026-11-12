# Kai — Modellvorschlag für `kai-gpu` (g4dn.xlarge, T4 16 GB)

Stand: 2026-11-05 · Status: Vorschlag für den ersten Durchstich (S1-02); Modelltests folgen später · Bezug: [01 Architektur](01_architektur.md), die Modelle laufen auf `kai-gpu` hinter llama-swap, Nutzer und Harnesses sehen sie über LiteLLM auf `kai-entry`

## Randbedingungen der GPU

- **NVIDIA T4:** 16 GB VRAM, Turing (Compute 7.5), 320 GB/s Speicherbandbreite. Kein BF16, kein FP8 — llama.cpp rechnet in FP16/FP32 und dequantisiert die Gewichte selbst; das funktioniert, ist aber ~3–5× langsamer als eine aktuelle Consumer-Karte.
- Faustregel für ein Modell, das **vollständig** in die GPU passt: Modelldatei + KV-Cache für den Kontext + ~1 GB Reserve ≤ 16 GB. Dichte Modelle über ~14 B Parameter in Q4 passen nicht mehr mit nutzbarem Kontext; MoE-Modelle mit 20–35 B Gesamt- und 3–4 B aktiven Parametern sind der Sweet Spot, weil sie schnell sind und trotzdem gut.
- Erwartete Geschwindigkeit auf der T4 für ein MoE mit ~3,5 B aktiv: etwa 25–40 Token/s bei einem Nutzer, bei vier gleichzeitigen Anfragen (S1-10) entsprechend aufgeteilt (llama-server verarbeitet parallel, `--parallel 4`). Für Chat ist das flüssig.

## Vorschlag: `gpt-oss-20b` (MXFP4) als erster Allrounder

| | |
|---|---|
| Datei | `ggml-org/gpt-oss-20b-GGUF` → `gpt-oss-20b-MXFP4.gguf`, ~12 GB (auf lezki als `gpt-oss-20b` im Einsatz) |
| Architektur | MoE, 21 B gesamt / ~3,6 B aktiv; natives MXFP4 (keine Qualitätsverlust-Quantisierung nötig) |
| Kontext | 32k Token eingestellt (KV-Cache ~2–3 GB mit `-fa on`); technisch bis 128k, passt aber nicht in 16 GB |
| Stärken | Reasoning (einstellbar low/medium/high), Werkzeugaufrufe funktionieren zuverlässig (wichtig für Brave-Suche), Deutsch gut, Apache-2.0 |
| Schwächen | Kein Bildverständnis; schreibt sachlich-knapp; MXFP4-Dequantisierung auf Turing ist weniger optimiert als auf neueren Karten |
| Warum als erstes | Es ist die im ClickUp-Dokument „Erstes Setup“ benannte Vorlage, bei Axel im Betrieb erprobt, und das kleinste Modell, das Werkzeuge sauber bedient. Erster Durchstich mit bekanntem Verhalten statt neuem Risiko |

**Risiko, das Phase 3 prüft:** gpt-oss wurde in BF16 trainiert; auf FP16-Karten (T4) sind Überlaufprobleme berichtet worden (Unsloth-Hinweis). llama.cpp hat dafür Gegenmaßnahmen, aber der erste Test auf der Maschine ist: zehn deutsche Alltagsfragen plus zwei Werkzeugaufrufe, Antworten plausibel? Wenn nicht → Alternative A.

### llama-swap-Eintrag (Entwurf, Phase 2 pinnt die Flags; Datei `kai/compose/gpu/llama-swap.yaml`)

```yaml
models:
  gpt-oss-20b:
    cmd: >
      /app/llama-server --port ${PORT}
      -m /models/gpt-oss-20b-MXFP4.gguf
      --ctx-size 32768 --parallel 4 -fa on --jinja
      --chat-template-kwargs '{"reasoning_effort":"medium"}'
      -ngl 999 --host 0.0.0.0
    ttl: 0            # Durchstich: nicht automatisch entladen, es gibt nur ein Modell
```

## Alternativen für die Modelltests (S1-02, später)

| | Modell | Größe (Q4/MXFP4) | Passt mit 32k Kontext? | Wofür |
|---|---|---|---|---|
| A | **Qwen3.6-35B-A3B** (Allrounder auf lezki, Text + Bild) | ~20 GB MXFP4 | **nein** — nur mit Q3-Quantisierung (~15 GB) oder Experten-Offload ins RAM (`--n-cpu-moe`), dann ~10–15 Token/s. Kandidat, wenn Bildverständnis gewünscht ist | Vergleich Qualität vs. Geschwindigkeit |
| B | **Qwen3-Serie dicht, 8–14 B** (z. B. Qwen3-14B Q4_K_M ~9 GB) | 9 GB | ja, 32k problemlos | Gute deutsche Texte, kein MoE-Overhead, langsamer pro Token (~15–20 Token/s auf T4) |
| C | **Gemma-3-12B-it** Q4_K_M | ~8 GB | ja | Natürlichere Alltagssprache, Bildverständnis; Werkzeugaufrufe schwächer |
| D | **Kleines Zweitmodell** (Qwen3-4B / Gemma-3-4B, ~3 GB) | 3 GB | ja, **neben** dem Hauptmodell | Für schnelle Aufgaben und Tests, zeigt den Modellwechsel über llama-swap |

**Testmodell für `kai-gpu-pre` (ohne GPU):** `Qwen3-0.6B` in Q8_0 (~0,6 GB, `unsloth/Qwen3-0.6B-GGUF`) läuft auf der CPU in Sekunden an und prüft die Kette Open WebUI → LiteLLM → llama-swap → llama-server in Phase 2. Es sagt nichts über Qualität oder Geschwindigkeit und steht nur in der Modellliste von `kai-gpu-pre`.

Vorgehen bei den Tests (Vorschlag für S1-01/S1-10): gleiche 10–20 Fragen aus dem Alltag der vier Nutzer, je Modell Antwortqualität (Schulnote), Zeit bis zur ersten Antwort, Zeit bis zur fertigen Antwort, einmal mit vier parallelen Anfragen. Ergebnisse als Tabelle in ClickUp.

## Was das für `kai-gpu` bedeutet

- Ein Modell ≈ 10–15 GB auf der Platte; drei Modelle für Tests ≈ 40 GB → bestätigt die 150 GB des Volumes `kai-models` in [02](02_anforderungen-infrastruktur.md) 2.2.
- Beim Modellwechsel über llama-swap lädt die T4 das neue Modell von EBS: bei gp3-Standarddurchsatz (125 MB/s) dauern 12 GB ~100 s. Wenn das stört: gp3-Durchsatz auf 250–500 MB/s hochsetzen (kleine Mehrkosten) oder `ttl` so setzen, dass das Hauptmodell geladen bleibt.
- Mehr VRAM (g5.xlarge, A10G 24 GB, ≈ 1,2 $/h in Frankfurt) würde Qwen3.6-35B-A3B in MXFP4 **mit** Kontext erlauben. Das ist dann eine zweite GPU-VM neben `kai-gpu` oder ihr Ersatz nach den Regeln in [01 §3](01_architektur.md); Oberfläche, Konten und LiteLLM-Endpunkt bleiben gleich. Nicht für den Durchstich.
