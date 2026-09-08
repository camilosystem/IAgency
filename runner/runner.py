#!/usr/bin/env python3
"""
runner.py — Orquestador de la fábrica de agentes IAgency.

Toma una cola de tareas, y para cada una:
  1. crea un git worktree aislado (un archivo, un dueño: los worktrees evitan que
     dos agentes se pisen mientras trabajan)
  2. lanza un contenedor efímero con Claude Code en modo headless
  3. recoge el informe de entrega y el resultado
  4. destruye el contenedor

Está pensado para correr desatendido. Por eso todo tiene tope: tiempo, herramientas
y reintentos. Un agente sin tope es la forma más cara de fallar.

Uso:
    python3 runner.py tareas.yaml
    python3 runner.py tareas.yaml --tarea T-004     # solo una
    python3 runner.py tareas.yaml --simular         # muestra qué haría, no ejecuta
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("Falta PyYAML.  Instálalo con:  pip install pyyaml")


BASE = Path(os.environ.get("IAGENCY_BASE", "/opt/iagency"))
IMAGEN = os.environ.get("IAGENCY_IMAGEN", "iagency/agente:1")
RED = os.environ.get("IAGENCY_RED", "iagency")
MAX_REINTENTOS = 3           # regla de las tres rondas
TIMEOUT_POR_DEFECTO = 3600   # segundos


# --------------------------------------------------------------------------- #

@dataclass
class Tarea:
    id: str
    agente: str
    prompt: str
    repo: str
    rama_base: str = "main"
    modelo: str | None = None
    depende_de: list[str] = field(default_factory=list)
    timeout: int = TIMEOUT_POR_DEFECTO
    max_herramientas: int = 400

    @property
    def rama(self) -> str:
        return f"agente/{self.id.lower()}"

    @property
    def worktree(self) -> Path:
        return BASE / "worktrees" / self.id


def log(msg: str) -> None:
    print(f"[{datetime.now(timezone.utc).isoformat(timespec='seconds')}] {msg}", flush=True)


def correr(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    log("$ " + " ".join(shlex.quote(c) for c in cmd))
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


# --------------------------------------------------------------------------- #

def preparar_worktree(t: Tarea, simular: bool) -> bool:
    """Un worktree por tarea: aislamiento real sin clonar el repositorio entero."""
    repo = BASE / "repos" / t.repo
    if not repo.exists():
        log(f"ERROR  el repositorio {repo} no existe")
        return False

    if t.worktree.exists():
        log(f"  worktree ya existe: {t.worktree}")
        return True

    if simular:
        log(f"  [simular] git worktree add -b {t.rama} {t.worktree} {t.rama_base}")
        return True

    correr(["git", "-C", str(repo), "fetch", "origin", t.rama_base])
    r = correr([
        "git", "-C", str(repo), "worktree", "add",
        "-b", t.rama, str(t.worktree), f"origin/{t.rama_base}",
    ])
    if r.returncode != 0:
        log(f"ERROR  no se pudo crear el worktree:\n{r.stderr}")
        return False
    return True


def construir_prompt(t: Tarea) -> str:
    return (
        f"Eres el agente `{t.agente}` de la fábrica IAgency.\n"
        f"Tarea: {t.id}\n\n"
        f"{t.prompt}\n\n"
        "Al terminar, escribe tu informe de entrega siguiendo la skill `handoff`, "
        f"en `docs/entregas/{t.id}/{t.agente}.md`, y repítelo como último mensaje.\n"
        "Si te bloqueas, repórtalo con estado BLOQUEADO en vez de seguir intentando.\n"
        "Español neutro, sin voseo, en todo lo que escribas."
    )


def ejecutar(t: Tarea, simular: bool) -> dict:
    """Lanza el contenedor efímero con Claude Code en modo headless."""
    salida_dir = BASE / "entregas" / t.id
    salida_dir.mkdir(parents=True, exist_ok=True)

    docker = [
        "docker", "run", "--rm",
        "--name", f"iagency-{t.id.lower()}",
        "--network", RED,
        # Contención de recursos: un agente en bucle no debe tumbar el nodo.
        "--cpus", os.environ.get("IAGENCY_CPUS", "4"),
        "--memory", os.environ.get("IAGENCY_RAM", "8g"),
        "--pids-limit", "2048",
        "--security-opt", "no-new-privileges",
        "--cap-drop", "ALL",
        "--read-only",
        "--tmpfs", "/tmp:rw,exec,size=4g",
        "-v", f"{t.worktree}:/workspace:rw",
        "-v", f"{BASE / 'estado'}:/var/lib/iagency:rw",
        "-v", f"{BASE / 'logs'}:/var/log/iagency:rw",
        "-e", f"ANTHROPIC_API_KEY={os.environ['ANTHROPIC_API_KEY']}",
        "-e", f"IAGENCY_TAREA={t.id}",
        "-e", f"IAGENCY_MAX_HERRAMIENTAS={t.max_herramientas}",
        "-e", "IAGENCY_ENTORNO=pruebas",
        IMAGEN,
        "claude", "-p", construir_prompt(t),
        "--agent", t.agente,
        # 'dontAsk': cero preguntas, pero las reglas allow/deny SIGUEN aplicando.
        # No uses bypassPermissions aquí: desactiva también las reglas deny y deja
        # los hooks como única defensa.
        "--permission-mode", "dontAsk",
        "--output-format", "stream-json",
        "--verbose",
    ]
    if t.modelo:
        docker += ["--model", t.modelo]

    if simular:
        log("  [simular] " + " ".join(shlex.quote(c) for c in docker))
        return {"estado": "simulado"}

    inicio = time.time()
    try:
        proc = subprocess.run(docker, capture_output=True, text=True, timeout=t.timeout)
        rc, out, err = proc.returncode, proc.stdout, proc.stderr
        estado = "ok" if rc == 0 else "fallo"
    except subprocess.TimeoutExpired:
        subprocess.run(["docker", "kill", f"iagency-{t.id.lower()}"], capture_output=True)
        rc, out, err, estado = -1, "", "tiempo agotado", "timeout"

    dur = round(time.time() - inicio, 1)
    (salida_dir / "stream.jsonl").write_text(out, encoding="utf-8")
    if err:
        (salida_dir / "stderr.txt").write_text(err, encoding="utf-8")

    log(f"  {t.id}: {estado}  ({dur}s, rc={rc})")
    return {"estado": estado, "rc": rc, "duracion": dur, "salida": str(salida_dir)}


def leer_informe(t: Tarea) -> str | None:
    p = t.worktree / "docs" / "entregas" / t.id / f"{t.agente}.md"
    return p.read_text(encoding="utf-8") if p.exists() else None


# --------------------------------------------------------------------------- #

def main() -> int:
    ap = argparse.ArgumentParser(description="Orquestador de la fábrica IAgency")
    ap.add_argument("cola", help="archivo YAML con las tareas")
    ap.add_argument("--tarea", help="ejecutar solo esta tarea")
    ap.add_argument("--simular", action="store_true", help="mostrar sin ejecutar")
    args = ap.parse_args()

    if not args.simular and "ANTHROPIC_API_KEY" not in os.environ:
        sys.exit("Falta ANTHROPIC_API_KEY en el entorno.")

    datos = yaml.safe_load(Path(args.cola).read_text(encoding="utf-8"))
    tareas = {d["id"]: Tarea(**d) for d in datos["tareas"]}

    if args.tarea:
        if args.tarea not in tareas:
            sys.exit(f"La tarea {args.tarea} no está en la cola.")
        tareas = {args.tarea: tareas[args.tarea]}

    (BASE / "logs").mkdir(parents=True, exist_ok=True)
    hechas: dict[str, dict] = {}
    pendientes = list(tareas.values())
    vueltas = 0

    while pendientes and vueltas < len(tareas) + 2:
        vueltas += 1
        listas = [t for t in pendientes if all(d in hechas for d in t.depende_de)]
        if not listas:
            log("ERROR  quedan tareas cuyas dependencias nunca se cumplen:")
            for t in pendientes:
                log(f"  {t.id} espera {t.depende_de}")
            break

        for t in listas:
            log(f"=== {t.id}  ({t.agente})")
            if not preparar_worktree(t, args.simular):
                hechas[t.id] = {"estado": "error-worktree"}
            else:
                hechas[t.id] = ejecutar(t, args.simular)
                informe = leer_informe(t)
                if informe:
                    hechas[t.id]["informe"] = informe[:4000]
                elif not args.simular:
                    log(f"  AVISO  {t.id} no dejó informe de entrega")
                    hechas[t.id]["estado"] = "sin-informe"
            pendientes.remove(t)

    resumen = BASE / "entregas" / f"resumen-{datetime.now():%Y%m%d-%H%M%S}.json"
    resumen.parent.mkdir(parents=True, exist_ok=True)
    resumen.write_text(json.dumps(hechas, ensure_ascii=False, indent=2), encoding="utf-8")

    log("")
    log("=== Resumen ===")
    for tid, r in hechas.items():
        log(f"  {tid:12s} {r.get('estado')}")
    log(f"Detalle: {resumen}")

    fallidas = [t for t, r in hechas.items() if r.get("estado") not in ("ok", "simulado")]
    if fallidas:
        log(f"Tareas con problema: {', '.join(fallidas)}  — revísalas antes de seguir.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
