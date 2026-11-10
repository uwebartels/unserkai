"""
title: Kai-Status
author: unserkai
description: Starts the GPU machine for the selected model via kai-pfoertner and shows boot progress as a status line.
version: 0.1.0
required_open_webui_version: 0.6.0
"""

import asyncio
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request

import pydantic


class Filter:
    class Valves(pydantic.BaseModel):
        pfoertner_url: str = "http://kai-pfoertner:8081"
        poll_seconds: float = 2.0
        max_wait_seconds: int = 420
        priority: int = 0

    def __init__(self):
        self.valves = self.Valves()

    def _http_json(self, url: str, method: str = "GET"):
        data = b"" if method == "POST" else None
        req = urllib.request.Request(url, data=data, method=method)
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode("utf-8"))

    async def inlet(self, body: dict, __event_emitter__=None, __user__=None) -> dict:
        try:
            model = body.get("model")
            if not model:
                return body

            base = self.valves.pfoertner_url.rstrip("/")
            q_model = urllib.parse.quote(str(model), safe="")
            status_url = f"{base}/status?model={q_model}"

            async def emit(description: str, done: bool = False):
                if not __event_emitter__:
                    return
                try:
                    await __event_emitter__({
                        "type": "status",
                        "data": {"description": description, "done": done}
                    })
                except Exception:
                    pass

            def status_line(snap: dict) -> str:
                machine = str(snap.get("machine") or "GPU")
                label = str(snap.get("label") or "Modell wird geladen")
                try:
                    percent = max(0, min(100, int(snap.get("percent") or 0)))
                except Exception:
                    percent = 0

                filled = percent // 10
                bar = "▰" * filled + "▱" * (10 - filled)
                parts = [f"⟳ {machine} startet", label, f"{bar} {percent} %"]

                try:
                    eta_seconds = float(snap.get("eta_seconds") or 0)
                except Exception:
                    eta_seconds = 0.0

                if eta_seconds > 0:
                    try:
                        eta = int(math.ceil(eta_seconds / 5.0) * 5)
                    except Exception:
                        eta = 0
                    if eta:
                        parts.append(f"noch etwa {eta} s")

                if snap.get("phase") == "start" and snap.get("error"):
                    parts.append(str(snap["error"]))

                return " · ".join(parts)

            try:
                snap = await asyncio.to_thread(self._http_json, status_url)
            except urllib.error.HTTPError as exc:
                if exc.code == 404:
                    return body
                return body
            except Exception:
                return body

            if not isinstance(snap, dict):
                return body

            loaded = snap.get("loaded") if isinstance(snap.get("loaded"), list) else []
            if snap.get("ready") and model in loaded:
                return body

            machine = str(snap.get("machine") or "GPU")
            wake_url = f"{base}/wake/{urllib.parse.quote(machine, safe='')}?model={q_model}&reason=filter"

            try:
                await asyncio.to_thread(self._http_json, wake_url, "POST")
            except Exception:
                return body

            deadline = time.monotonic() + self.valves.max_wait_seconds
            success = False
            failed = False
            last = snap

            while time.monotonic() < deadline:
                await asyncio.sleep(max(0.1, self.valves.poll_seconds))

                try:
                    last = await asyncio.to_thread(self._http_json, status_url)
                except Exception:
                    break

                if not isinstance(last, dict):
                    break

                loaded = last.get("loaded") if isinstance(last.get("loaded"), list) else []
                if last.get("ready") and model in loaded:
                    success = True
                    break

                if last.get("phase") == "error":
                    failed = True
                    break

                await emit(status_line(last))

            machine = str(last.get("machine") or machine)

            if success:
                await emit(f"✔ {machine} bereit", done=True)
            elif failed:
                error = str(last.get("error") or "unbekannter Fehler")
                await emit(f"✖ {machine} konnte nicht gestartet werden: {error}", done=True)
            else:
                await emit(f"✖ {machine} antwortet nicht (Zeitlimit)", done=True)

            return body
        except Exception:
            return body
