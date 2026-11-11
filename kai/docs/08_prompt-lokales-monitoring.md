# 08 Prompt: lokales Ressourcen-Monitoring auf webui1 und kai1

Eigenständiger Auftrag für eine Agenten-Sitzung in diesem Repo. Vorbild ist das Heim-Monitoring „fleetmon“, aber ohne Versand: Die Daten bleiben auf der Maschine, abgeholt werden sie allenfalls beim nächsten Deploy oder von `kai-smoke`.

```text
Goal: measure whether webui1 (t3.micro, 939 MB RAM: Open WebUI, LiteLLM, Postgres, Pförtner) and kai1
(g4dn.xlarge, Tesla T4) are sized right. Build a new Ansible role `kai_monitor` for both groups.

What it records, every 10 s, one line per window, space-separated key=value (new keys never break readers):
- header line per file: time, format version, host, ncpu, page size, psi 0/1, kernel
- window: end time, length in ms; CPU busy/iowait/steal jiffies (deltas); PSI cpu/memory/io some+full µs
  (deltas, /proc/pressure); RAM total/available/cached KiB; swap total/free; OOM kills and major faults
  (deltas, /proc/vmstat); per disk ms with I/O in flight (delta); on kai1 GPU util % and VRAM avg/max/total
  MiB from nvidia-smi
- once per hour per mount: type, size, used, inodes total/used
Counters are deltas over the window, gauges are values at its end.

How:
- a system account `kai-monitor` without password, shell or sudo that reads only /proc, /sys and nvidia-smi
- a systemd service with Restart=always (no cron keep-alive), LogLevelMax=notice; buffer in memory, append
  hourly to /var/lib/kai-monitor/<host>_<date>.w, gzip finished days, delete files older than 365 days (about 0.1–0.3 MB per host and day compressed, so under 100 MB a year);
  a crash loses at most the current hour
- size budget: at most a few MB per day; check the free space rule of kai_volume does not suffer
- a tiny evaluator (python3 standard library only) that prints per day: p50/p95/max of CPU busy, RAM
  available, swap used, PSI memory/io, disk busy, GPU util/VRAM, and the number of OOM kills
- collection without a network path: `kai-smoke` prints a one-line summary of the last 24 h, and a make
  target (e.g. `make -C ansible monitor-fetch LIMIT=…`) copies the day files to a gitignored folder on
  the control machine, through the existing SSH/SSM access; no new port, no push, no AWS service

Done when: ./check passes; on kai-entry-pre and kai-gpu-pre two deploys, second changed=0; after 2 min the
day file grows and the evaluator prints plausible values; kai1's pause (stopped instance) leaves a gap,
not an error; AGENTS.md lists the role in the same change.
```
