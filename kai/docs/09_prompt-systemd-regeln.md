# 09 Prompt: Regeln für systemd-Units und wiederkehrende Jobs

Eigenständiger Auftrag für eine Agenten-Sitzung in diesem Repo. Er überträgt die Unit-Regeln des Heim-Setups auf Kai.

```text
Goal: every service, timer and recurring job that the Ansible roles put on webui1 and kai1 follows the
same rules, and the repo gate enforces them.

Rules:
1. A recurring job is a systemd timer, never a cron entry.
2. A daemon runs as a service with Restart= (on-failure or always) and RestartSec=, never via a cron or
   loop keep-alive.
3. A service started more often than hourly gets LogLevelMax=notice, so it cannot flood the journal.
4. Unit files live in the role next to the script they start (templates/ or files/), never inline in a
   task, and every unit passes `systemd-analyze verify`.
5. Own units carry an explicit User= unless they need root, and state why in a comment if they do.

Do:
- inventory every unit and drop-in the roles write (kai_pfoertner, kai_updates, kai_gpu, docker, others)
  and list deviations from the rules with file:line
- fix the deviations in the roles
- add a step to ./check that renders the unit templates and runs `systemd-analyze verify` on them, and a
  check for rules 1 and 3 (no cron module, LogLevelMax= on units whose timer fires more than hourly)
- one sentence per rule in AGENTS.md under Stolperfallen only where a reader of the roles would still get it
  wrong

Done when: ./check passes and fails on a planted bad unit; two deploys on kai-entry-pre and kai-gpu-pre,
second changed=0; `systemctl --failed` empty on both.
```
