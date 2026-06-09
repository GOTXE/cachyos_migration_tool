#!/usr/bin/env python3
"""TUI Python + curses para Linux Migration Tool. Solo stdlib — sin paquetes extra."""

import curses, os, subprocess, sys, shutil, re, shlex, pwd, select, time, stat

PROJECT_ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VERSION = sys.argv[2] if len(sys.argv) > 2 else "?"
MIG = os.path.join(PROJECT_ROOT, "migration.sh")

# ── Pares de color ────────────────────────────────────────────────────────────
CP_BORDER, CP_SEL, CP_CHECK, CP_NORMAL = 1, 2, 3, 4
CUSTOM_SEL_BG = 10

def _init_colors():
    curses.start_color()
    curses.use_default_colors()
    sel_bg = curses.COLOR_GREEN
    if curses.can_change_color() and curses.COLORS > CUSTOM_SEL_BG:
        # Verde más oscuro y menos fosforito que el COLOR_GREEN estándar.
        curses.init_color(CUSTOM_SEL_BG, 0, 520, 0)
        sel_bg = CUSTOM_SEL_BG
    curses.init_pair(CP_BORDER, curses.COLOR_CYAN,  -1)
    curses.init_pair(CP_SEL,   curses.COLOR_WHITE, sel_bg)
    curses.init_pair(CP_CHECK,  curses.COLOR_GREEN, -1)
    curses.init_pair(CP_NORMAL, curses.COLOR_WHITE, -1)

# ── Helpers de dibujo ─────────────────────────────────────────────────────────
def _put(win, y, x, text, attr=0):
    h, w = win.getmaxyx()
    if y < 0 or y >= h - 1 or x >= w - 1:
        return
    try:
        win.addstr(y, x, text[:max(0, w - x - 1)], attr)
    except curses.error:
        pass

def _box(win, title=""):
    h, w = win.getmaxyx()
    win.attron(curses.color_pair(CP_BORDER))
    win.box()
    win.attroff(curses.color_pair(CP_BORDER))
    if title:
        t = f" {title} "
        x = max(2, (w - len(t)) // 2)
        _put(win, 0, x, t[:w - x - 1], curses.color_pair(CP_BORDER) | curses.A_BOLD)

def _hint(win, text):
    h, w = win.getmaxyx()
    t = f" {text} "
    x = max(2, (w - len(t)) // 2)
    _put(win, h - 1, x, t[:w - x - 1], curses.color_pair(CP_BORDER))

def _button_bar(win, labels, selected=None):
    h, w = win.getmaxyx()
    total = sum(len(label) + 4 for label in labels) + max(0, len(labels) - 1) * 2
    x = max(2, (w - total) // 2)
    y = h - 3
    for idx, label in enumerate(labels):
        attr = curses.color_pair(CP_SEL) | curses.A_BOLD if selected is not None and idx == selected else curses.color_pair(CP_NORMAL)
        text = f" <{label}> "
        _put(win, y, x, text, attr)
        x += len(text) + 2

def _reset_screen(stdscr):
    stdscr.erase()
    stdscr.refresh()

def _strip_ansi(text):
    return re.sub(r"\x1b\[[0-9;]*m", "", text)

def _postcheck_summary(lines, max_lines=10):
    keys = (
        "Docker group",
        "Docker service",
        "Powerlevel10k",
        "Syncthing user service",
        "Codex CLI",
        "Claude Code CLI",
        "Wi-Fi regulatorio",
        "Cámara FaceTime HD",
        "KDE Connect",
        "Navegador Chromium",
        "Extension YouTube H264",
        "Broadcom Apple",
    )
    summary = []
    for raw in lines:
        line = _strip_ansi(raw).strip()
        if not line:
            continue
        if line.startswith(("OK", "WARN", "ERROR")) or any(token in line for token in keys):
            summary.append(line)
    if not summary:
        summary = [_strip_ansi(line).strip() for line in lines if line.strip()]
    return summary[-max_lines:]

def _backup_summary(lines, max_lines=12):
    summary = []
    for raw in lines:
        line = _strip_ansi(raw).strip()
        if not line:
            continue
        if line.startswith("Bloque ") or line.startswith("->") or "BACKUP COMPLETADO" in line or line == "Destino:":
            summary.append(line)
    if not summary:
        summary = [_strip_ansi(line).strip() for line in lines if line.strip()]
    return summary[-max_lines:]

def _restore_summary(lines, max_lines=12):
    summary = []
    for raw in lines:
        line = _strip_ansi(raw).strip()
        if not line:
            continue
        if line.startswith("Bloque ") or line.strip().startswith("->") or "RESTAURACION COMPLETADA" in line or line.startswith("Backup restaurado desde:"):
            summary.append(line)
    if not summary:
        summary = [_strip_ansi(line).strip() for line in lines if line.strip()]
    return summary[-max_lines:]

def _extract_backup_destination(lines):
    clean_lines = [_strip_ansi(line).strip() for line in lines]
    for idx, line in enumerate(clean_lines):
        if line != "Destino:":
            continue
        for candidate in clean_lines[idx + 1:]:
            if candidate:
                return candidate
    for line in reversed(clean_lines):
        if re.search(r"/linux_backup_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$", line):
            return line
    return None

def _backup_line_attr(line):
    clean = _strip_ansi(line)
    if "[ERROR]" in clean or "Ruta destino invalida" in clean or "Espacio insuficiente" in clean:
        return curses.color_pair(CP_SEL) | curses.A_BOLD
    if "Verificación con incidencias" in clean or clean.startswith("Faltan:") or clean.startswith("Difieren:"):
        return curses.color_pair(CP_SEL) | curses.A_BOLD
    if "Verificación con avisos" in clean or clean.startswith("Extras:"):
        return curses.color_pair(CP_CHECK) | curses.A_BOLD
    if "BACKUP COMPLETADO CON AVISOS" in clean or clean.startswith("Avisos detectados:"):
        return curses.color_pair(CP_CHECK) | curses.A_BOLD
    if "BACKUP COMPLETADO" in clean or clean.startswith("Verificación: OK"):
        return curses.color_pair(CP_CHECK) | curses.A_BOLD
    if clean.startswith("Bloque ") or clean.strip().startswith("->"):
        return curses.color_pair(CP_CHECK)
    return curses.color_pair(CP_NORMAL)

def _restore_line_attr(line):
    clean = _strip_ansi(line)
    if "[ERROR]" in clean or "Backup no encontrado" in clean or "No se encontro metadata/user_ids.conf" in clean:
        return curses.color_pair(CP_SEL) | curses.A_BOLD
    if "AVISO" in clean:
        return curses.color_pair(CP_CHECK) | curses.A_BOLD
    if "RESTAURACION COMPLETADA" in clean or clean.startswith("OK:"):
        return curses.color_pair(CP_CHECK) | curses.A_BOLD
    if clean.startswith("Bloque ") or clean.strip().startswith("->"):
        return curses.color_pair(CP_CHECK)
    return curses.color_pair(CP_NORMAL)

def _backup_live_lines(lines, max_lines):
    useful = []
    for raw in lines:
        line = _strip_ansi(raw).strip()
        if not line:
            continue
        if line.startswith("Bloque ") or line.strip().startswith("->") or line.startswith("[ERROR]") or "BACKUP COMPLETADO" in line or line == "Destino:":
            useful.append(line)
    if not useful:
        useful = [_strip_ansi(line).strip() for line in lines if line.strip()]
    return useful[-max_lines:]

def _humanize_backup_exit(return_code, lines, verification=None):
    clean_lines = [_strip_ansi(line).strip() for line in lines if line.strip()]
    if verification and verification.get("status") == "mismatch":
        return "Backup completado, pero la verificación detectó diferencias."
    if any("BACKUP COMPLETADO CON AVISOS" in line for line in clean_lines):
        return "Backup completado con avisos. Conviene revisar el detalle antes de darlo por bueno."
    if return_code == 0:
        return "Backup completado correctamente."
    if return_code == 23:
        return "Backup completado con avisos. Algunos archivos no se pudieron copiar o cambiaron durante la copia."
    if any("Espacio insuficiente" in line for line in clean_lines):
        return "Backup cancelado por falta de espacio en destino."
    if any("Ruta destino invalida" in line for line in clean_lines):
        return "Backup cancelado porque la ruta destino no es válida."
    return f"Backup finalizado con un error (código {return_code})."

def _humanize_restore_exit(return_code, lines):
    clean_lines = [_strip_ansi(line).strip() for line in lines if line.strip()]
    if any("RESTAURACION COMPLETADA" in line for line in clean_lines):
        return "Restauración completada correctamente."
    if any("Backup no encontrado" in line for line in clean_lines):
        return "Restauración cancelada porque no se encontró la copia indicada."
    if any("No se encontro metadata/user_ids.conf" in line for line in clean_lines):
        return "La ruta indicada no parece una copia válida para restaurar."
    return f"Restauración finalizada con un error (código {return_code})."

def _parse_backup_progress(lines):
    block_idx = None
    block_total = None
    item_idx = None
    item_total = None
    item_label = ""
    for raw in lines:
        line = _strip_ansi(raw).strip()
        block_match = re.match(r"Bloque\s+(\d+)/(\d+):", line)
        if block_match:
            block_idx = int(block_match.group(1))
            block_total = int(block_match.group(2))
            item_idx = None
            item_total = None
            item_label = ""
            continue
        item_match = re.match(r"->\s+\[(\d+)/(\d+)\]\s+(.+)", line)
        if item_match:
            item_idx = int(item_match.group(1))
            item_total = int(item_match.group(2))
            item_label = item_match.group(3)
    return {
        "block_idx": block_idx,
        "block_total": block_total,
        "item_idx": item_idx,
        "item_total": item_total,
        "item_label": item_label,
    }

def _safe_readlink(path):
    try:
        return os.readlink(path)
    except OSError:
        return ""

def _entry_signature(path):
    st = os.lstat(path)
    mode = st.st_mode
    if stat.S_ISDIR(mode):
        return ("D", 0)
    if stat.S_ISREG(mode):
        return ("F", st.st_size)
    if stat.S_ISLNK(mode):
        return ("L", _safe_readlink(path))
    return ("O", st.st_size)

def _manifest_lines(prefix, manifest):
    lines = []
    for rel_path in sorted(manifest):
        kind, meta = manifest[rel_path]
        suffix = "." if rel_path == "." else rel_path
        lines.append(f"{prefix}|{suffix}|{kind}|{meta}")
    return lines

def _is_excluded_path(path, excluded_paths):
    for excluded in excluded_paths:
        if path == excluded or path.startswith(excluded + os.sep):
            return True
    return False

def _backup_fs_type(target_path):
    try:
        proc = subprocess.run(
            ["findmnt", "-n", "-o", "FSTYPE", "-T", target_path],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return ""
    return (proc.stdout or "").strip()

def _backup_rsync_options_for_path(target_path):
    fs_type = _backup_fs_type(target_path)
    if fs_type in {"exfat", "vfat", "msdos", "ntfs", "ntfs3", "fuseblk"}:
        return ["-rltD", "--copy-links", "--no-perms", "--no-owner", "--no-group"]
    return ["-a"]

def _build_broken_symlink_excludes(root_path):
    excludes = []
    root_path = os.path.abspath(root_path)
    if not os.path.isdir(root_path):
        return excludes
    for current, dirnames, filenames in os.walk(root_path, topdown=True, followlinks=False):
        entries = [os.path.join(current, name) for name in list(dirnames) + filenames]
        for path in entries:
            if os.path.islink(path) and not os.path.exists(path):
                rel_path = os.path.relpath(path, root_path)
                excludes.append(f"--exclude={rel_path}")
    return excludes

def _count_entries(root_path):
    root_path = os.path.abspath(root_path)
    if not (os.path.exists(root_path) or os.path.islink(root_path)):
        return 0
    count = 1
    if not os.path.isdir(root_path) or os.path.islink(root_path):
        return count
    for _, dirnames, filenames in os.walk(root_path, topdown=True, followlinks=False):
        count += len(dirnames) + len(filenames)
    return count

def _classify_rsync_itemized(source_root, backup_root, label, line):
    raw = line.strip()
    if not raw or raw.startswith("sending incremental file list") or raw.startswith("sent ") or raw.startswith("total size is "):
        return None
    if raw.startswith("*deleting "):
        rel_path = raw[len("*deleting "):].strip().rstrip("/")
        pretty = label if rel_path in {"", "."} else f"{label}/{rel_path}"
        return ("extra", pretty)
    if len(raw) < 12 or raw[11] != " ":
        return None
    change = raw[:11]
    rel_path = raw[12:].strip().rstrip("/")
    if not rel_path:
        pretty = label
        backup_path = backup_root
    else:
        pretty = f"{label}/{rel_path}"
        backup_path = os.path.join(backup_root, rel_path)
    if not os.path.lexists(backup_path):
        return ("missing", pretty)
    return ("mismatched", f"{pretty} | cambios detectados: {change}")

def _verify_group_with_rsync(source_root, backup_root, label, extra_rsync_opts=None):
    result = {
        "missing": [],
        "extra": [],
        "mismatched": [],
        "source_entries": _count_entries(source_root),
        "backup_entries": _count_entries(backup_root),
    }
    if not (os.path.exists(source_root) or os.path.islink(source_root)):
        return result

    rsync_options = _backup_rsync_options_for_path(backup_root)
    cmd = ["rsync", "-n", "--delete", "--itemize-changes", *rsync_options]
    if extra_rsync_opts:
        cmd.extend(extra_rsync_opts)
    if os.path.isdir(source_root) and not os.path.islink(source_root):
        cmd.extend(_build_broken_symlink_excludes(source_root))
        cmd.extend([source_root.rstrip(os.sep) + os.sep, backup_root.rstrip(os.sep) + os.sep])
    else:
        cmd.extend([source_root, backup_root])

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    except OSError as exc:
        raise RuntimeError(f"No se pudo ejecutar rsync para verificar {label}: {exc}") from exc

    output_lines = []
    if proc.stdout:
        output_lines.extend(proc.stdout.splitlines())
    if proc.stderr:
        output_lines.extend(proc.stderr.splitlines())

    for line in output_lines:
        classified = _classify_rsync_itemized(source_root, backup_root, label, line)
        if not classified:
            continue
        kind, message = classified
        result[kind].append(message)
    return result

def _scan_path_manifest(root_path, excluded_paths=None):
    root_path = os.path.abspath(root_path)
    excluded_paths = [os.path.abspath(path) for path in (excluded_paths or [])]
    manifest = {}

    if not (os.path.exists(root_path) or os.path.islink(root_path)):
        return manifest

    try:
        manifest["."] = _entry_signature(root_path)
    except OSError:
        return manifest

    if not os.path.isdir(root_path) or os.path.islink(root_path):
        return manifest

    for current, dirnames, filenames in os.walk(root_path, topdown=True, followlinks=False):
        current = os.path.abspath(current)
        if _is_excluded_path(current, excluded_paths) and current != root_path:
            dirnames[:] = []
            continue
        dirnames[:] = [
            name for name in dirnames
            if not _is_excluded_path(os.path.join(current, name), excluded_paths)
        ]
        for name in list(dirnames) + filenames:
            path = os.path.join(current, name)
            if _is_excluded_path(path, excluded_paths):
                continue
            rel_path = os.path.relpath(path, root_path)
            try:
                manifest[rel_path] = _entry_signature(path)
            except OSError:
                continue
    return manifest

def _discover_nested_repo_dirs(root_path):
    root_path = os.path.abspath(root_path)
    repo_dirs = []
    if not os.path.isdir(root_path):
        return repo_dirs
    for current, dirnames, filenames in os.walk(root_path, topdown=True, followlinks=False):
        if current != root_path and (".git" in dirnames or ".git" in filenames):
            repo_dirs.append(os.path.abspath(current))
            dirnames[:] = []
            continue
    return sorted(repo_dirs)

def _compare_manifests(source_manifest, backup_manifest, label):
    missing = []
    extra = []
    mismatched = []

    for rel_path, src_meta in source_manifest.items():
        dst_meta = backup_manifest.get(rel_path)
        pretty_path = label if rel_path == "." else f"{label}/{rel_path}"
        if dst_meta is None:
            missing.append(pretty_path)
            continue
        src_kind, src_value = src_meta
        dst_kind, dst_value = dst_meta
        if src_kind == "D" and dst_kind != "D":
            mismatched.append(f"{pretty_path} | origen: carpeta | backup: {dst_kind}")
        elif src_kind == "F":
            if dst_kind != "F":
                mismatched.append(f"{pretty_path} | origen: archivo | backup: {dst_kind}")
            elif src_value != dst_value:
                mismatched.append(f"{pretty_path} | tamaño origen: {src_value} | tamaño backup: {dst_value}")
        elif src_kind == "L" and rel_path not in backup_manifest:
            missing.append(pretty_path)

    for rel_path in backup_manifest:
        if rel_path in source_manifest:
            continue
        pretty_path = label if rel_path == "." else f"{label}/{rel_path}"
        extra.append(pretty_path)

    return missing, extra, mismatched

def _verify_backup_selection(backup_dir, home_dir, config_items, data_dirs):
    verification = {
        "status": "ok",
        "backup_dir": backup_dir,
        "checked_groups": 0,
        "source_entries": 0,
        "backup_entries": 0,
        "missing": [],
        "extra": [],
        "mismatched": [],
        "source_manifest_path": "",
        "backup_manifest_path": "",
        "diff_path": "",
    }
    if not backup_dir or not os.path.isdir(backup_dir):
        verification["status"] = "unavailable"
        return verification

    home_dir = os.path.abspath(home_dir)
    logs_dir = os.path.join(backup_dir, "logs")
    os.makedirs(logs_dir, exist_ok=True)
    for item in config_items:
        source_root = os.path.join(home_dir, item)
        backup_root = os.path.join(backup_dir, "configs", os.path.basename(item.rstrip(os.sep)))
        label = f"configs/{item}"
        group_result = _verify_group_with_rsync(source_root, backup_root, label)
        verification["checked_groups"] += 1
        verification["source_entries"] += group_result["source_entries"]
        verification["backup_entries"] += group_result["backup_entries"]
        verification["missing"].extend(group_result["missing"])
        verification["extra"].extend(group_result["extra"])
        verification["mismatched"].extend(group_result["mismatched"])

    for data_dir in data_dirs:
        data_dir = os.path.abspath(data_dir)
        nested_repo_dirs = [
            repo_dir for repo_dir in _discover_nested_repo_dirs(data_dir)
            if repo_dir.startswith(data_dir + os.sep)
        ]
        backup_root = os.path.join(backup_dir, "data", os.path.basename(data_dir.rstrip(os.sep)))
        label = f"data/{os.path.basename(data_dir.rstrip(os.sep))}"
        rsync_excludes = [f"--exclude={os.path.relpath(repo_dir, data_dir)}" for repo_dir in nested_repo_dirs]
        group_result = _verify_group_with_rsync(data_dir, backup_root, label, extra_rsync_opts=rsync_excludes)
        verification["checked_groups"] += 1
        verification["source_entries"] += group_result["source_entries"]
        verification["backup_entries"] += group_result["backup_entries"]
        verification["missing"].extend(group_result["missing"])
        verification["extra"].extend(group_result["extra"])
        verification["mismatched"].extend(group_result["mismatched"])

        for repo_dir in nested_repo_dirs:
            if not repo_dir.startswith(home_dir + os.sep):
                continue
            repo_rel = os.path.relpath(repo_dir, home_dir)
            repo_backup_root = os.path.join(backup_dir, "repos", repo_rel)
            repo_label = f"repos/{repo_rel}"
            repo_result = _verify_group_with_rsync(
                repo_dir,
                repo_backup_root,
                repo_label,
                extra_rsync_opts=[
                    "--exclude=venv",
                    "--exclude=.venv",
                    "--exclude=__pycache__",
                    "--exclude=.cache",
                ],
            )
            verification["checked_groups"] += 1
            verification["source_entries"] += repo_result["source_entries"]
            verification["backup_entries"] += repo_result["backup_entries"]
            verification["missing"].extend(repo_result["missing"])
            verification["extra"].extend(repo_result["extra"])
            verification["mismatched"].extend(repo_result["mismatched"])

    verification["diff_path"] = os.path.join(logs_dir, "verify_diff.txt")
    diff_lines = [
        f"Grupos verificados: {verification['checked_groups']}",
        f"Entradas origen revisadas: {verification['source_entries']}",
        f"Entradas presentes en backup: {verification['backup_entries']}",
        f"Faltan: {len(verification['missing'])}",
        f"Extras: {len(verification['extra'])}",
        f"Difieren: {len(verification['mismatched'])}",
        "",
        "[FALTAN]",
    ]
    diff_lines.extend(verification["missing"] or ["(ninguno)"])
    diff_lines.extend(["", "[EXTRAS]"])
    diff_lines.extend(verification["extra"] or ["(ninguno)"])
    diff_lines.extend(["", "[DIFIEREN]"])
    diff_lines.extend(verification["mismatched"] or ["(ninguno)"])
    with open(verification["diff_path"], "w", encoding="utf-8") as fh:
        fh.write("\n".join(diff_lines) + "\n")

    if verification["missing"] or verification["mismatched"]:
        verification["status"] = "mismatch"
    elif verification["extra"]:
        verification["status"] = "warning"
    return verification

def _backup_verification_lines(verification):
    if not verification:
        return []
    if verification.get("status") == "unavailable":
        return ["Verificación: no disponible."]
    lines = []
    if verification.get("status") == "mismatch":
        lines.append("Verificación con incidencias")
    elif verification.get("status") == "warning":
        lines.append("Verificación con avisos")
    else:
        lines.append("Verificación: OK")
    lines.append(f"Grupos revisados: {verification['checked_groups']}")
    lines.append(f"Elementos pendientes en backup: {len(verification['missing'])}")
    lines.append(f"Elementos extra solo en backup: {len(verification['extra'])}")
    lines.append(f"Elementos con diferencias: {len(verification['mismatched'])}")
    if verification.get("diff_path"):
        lines.append("Detalle verificación:")
        lines.append(verification["diff_path"])
    return lines

def _draw_progress_bar(win, y, x, width, ratio):
    usable = max(10, width)
    ratio = max(0.0, min(1.0, ratio))
    filled = int((usable - 2) * ratio)
    bar = "[" + ("#" * filled).ljust(usable - 2) + "]"
    _put(win, y, x, bar, curses.color_pair(CP_NORMAL))

def _postcheck_line_attr(line):
    if "ERROR" in line or "pendiente" in line or "no encontrado" in line or "no activo" in line or "falta" in line:
        return curses.color_pair(CP_SEL) | curses.A_BOLD
    if "WARN" in line or "aviso" in line or "desactualizado" in line or "no se pudo" in line or "no disponible" in line:
        return curses.color_pair(CP_CHECK)
    if "OK" in line or "activo" in line or "habilitado" in line or "presente" in line or "instalado" in line:
        return curses.color_pair(CP_CHECK) | curses.A_BOLD
    return curses.color_pair(CP_NORMAL)

def _newwin(stdscr, h, w, title=""):
    sh, sw = stdscr.getmaxyx()
    h, w = min(h, sh - 2), min(w, sw - 2)
    _reset_screen(stdscr)
    win = curses.newwin(h, w, (sh - h) // 2, (sw - w) // 2)
    win.keypad(True)
    _box(win, title)
    return win, h, w

# ── Widgets ───────────────────────────────────────────────────────────────────
def menu(stdscr, title, items, show_buttons=True):
    """Devuelve índice seleccionado o -1 si se cancela."""
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    w = min(sw - 4, max(56, max(len(lb) for _, lb in items) + 8))
    h = min(sh - 2, len(items) + 5)
    win, h, w = _newwin(stdscr, h, w, title)
    if show_buttons:
        _hint(win, "↑↓ Navegar   ENTER Seleccionar   TAB Botones   ESC Atrás")
        _button_bar(win, ["Aceptar", "Cancelar"], None)
    else:
        _hint(win, "↑↓ Navegar   ENTER Seleccionar   ESC Atrás")
    visible = h - 4
    sel = offset = 0
    focus_buttons = False
    button_sel = 0
    while True:
        if len(items) > visible:
            scroll_hint = f"Elementos {offset + 1}-{min(len(items), offset + visible)} de {len(items)}"
            _put(win, 1, 2, scroll_hint[:w - 4], curses.color_pair(CP_NORMAL))
            _put(win, h - 4, w - 4, "v" if offset + visible < len(items) else " ", curses.color_pair(CP_BORDER) | curses.A_BOLD)
            _put(win, 2, w - 4, "^" if offset > 0 else " ", curses.color_pair(CP_BORDER) | curses.A_BOLD)
        for i in range(visible):
            idx = i + offset
            row_text = f"  {items[idx][1]}" if idx < len(items) else ""
            if focus_buttons:
                attr = curses.color_pair(CP_NORMAL)
            else:
                attr = curses.color_pair(CP_SEL) | curses.A_BOLD if idx == sel else curses.color_pair(CP_NORMAL)
            _put(win, i + 2, 2, f"{row_text:<{w-4}}", attr)
        if show_buttons:
            _button_bar(win, ["Aceptar", "Cancelar"], button_sel if focus_buttons else None)
        win.refresh()
        k = win.getch()
        if k in (27,):
            return -1
        if show_buttons and k in (ord('\t'), curses.KEY_BTAB):
            focus_buttons = not focus_buttons
            continue
        if focus_buttons:
            if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('k'), ord('j'), ord('\t')):
                button_sel ^= 1
            elif k in (curses.KEY_ENTER, 10, 13):
                return sel if button_sel == 0 else -1
            continue
        if k in (curses.KEY_UP, ord('k')) and sel > 0:
            sel -= 1
            if sel < offset: offset = sel
        elif k in (curses.KEY_DOWN, ord('j')) and sel < len(items) - 1:
            sel += 1
            if sel >= offset + visible: offset = sel - visible + 1
        elif k == curses.KEY_PPAGE:
            sel = max(0, sel - visible)
            offset = min(offset, sel)
        elif k == curses.KEY_NPAGE:
            sel = min(len(items) - 1, sel + visible)
            if sel >= offset + visible:
                offset = sel - visible + 1
        elif k in (curses.KEY_ENTER, 10, 13):
            return sel

def checklist(stdscr, title, items, defaults=None):
    """Devuelve lista de tags seleccionados o None si se cancela."""
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    checked = set(defaults or [])
    w = min(sw - 4, max(68, max(len(lb) for _, lb in items) + 14))
    visible = min(sh - 8, len(items))
    win, h, w = _newwin(stdscr, visible + 6, w, title)
    _hint(win, "SPACE Marcar   ↑↓ Navegar   PgUp/PgDn   ENTER Confirmar   TAB Botones   ESC Atrás")
    _button_bar(win, ["Aceptar", "Cancelar"], None)
    sel = offset = 0
    focus_buttons = False
    button_sel = 0
    while True:
        if len(items) > visible:
            scroll_hint = f"Elementos {offset + 1}-{min(len(items), offset + visible)} de {len(items)}"
            _put(win, 1, 2, scroll_hint[:w - 4], curses.color_pair(CP_NORMAL))
            _put(win, h - 4, w - 4, "v" if offset + visible < len(items) else " ", curses.color_pair(CP_BORDER) | curses.A_BOLD)
            _put(win, 2, w - 4, "^" if offset > 0 else " ", curses.color_pair(CP_BORDER) | curses.A_BOLD)
        for i in range(visible):
            idx = i + offset
            if idx >= len(items):
                _put(win, i + 2, 2, " " * (w - 4))
                continue
            tag, label = items[idx]
            mark = "x" if tag in checked else " "
            line = f"  [{mark}]  {label}"
            if focus_buttons:
                attr = curses.color_pair(CP_NORMAL)
            elif idx == sel:
                attr = curses.color_pair(CP_SEL) | curses.A_BOLD
            elif tag in checked:
                attr = curses.color_pair(CP_CHECK)
            else:
                attr = curses.color_pair(CP_NORMAL)
            _put(win, i + 2, 2, f"{line:<{w-4}}", attr)
        _button_bar(win, ["Aceptar", "Cancelar"], button_sel if focus_buttons else None)
        win.refresh()
        k = win.getch()
        if k in (27,):
            return None
        if k in (ord('\t'), curses.KEY_BTAB):
            focus_buttons = not focus_buttons
            continue
        if focus_buttons:
            if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('k'), ord('j'), ord('\t')):
                button_sel ^= 1
            elif k in (curses.KEY_ENTER, 10, 13):
                return [t for t, _ in items if t in checked] if button_sel == 0 else None
            continue
        if k in (curses.KEY_UP, ord('k')) and sel > 0:
            sel -= 1
            if sel < offset: offset = sel
        elif k in (curses.KEY_DOWN, ord('j')) and sel < len(items) - 1:
            sel += 1
            if sel >= offset + visible: offset = sel - visible + 1
        elif k == curses.KEY_PPAGE:
            sel = max(0, sel - visible)
            offset = min(offset, sel)
        elif k == curses.KEY_NPAGE:
            sel = min(len(items) - 1, sel + visible)
            if sel >= offset + visible:
                offset = sel - visible + 1
        elif k == ord(' '):
            tag = items[sel][0]
            checked ^= {tag}
        elif k in (curses.KEY_ENTER, 10, 13):
            return [t for t, _ in items if t in checked]

def inputbox(stdscr, title, prompt, default=""):
    """Devuelve texto introducido o None si se cancela."""
    curses.curs_set(1)
    sh, sw = stdscr.getmaxyx()
    w = min(sw - 4, max(60, len(prompt) + 10))
    win, h, w = _newwin(stdscr, 8, w, title)
    _hint(win, "ENTER Confirmar   TAB Botones   ESC Atrás")
    _button_bar(win, ["Aceptar", "Cancelar"], None)
    _put(win, 2, 3, prompt[:w - 6], curses.color_pair(CP_NORMAL))
    field_x, field_w = 3, w - 6
    value = list(default)
    focus_buttons = False
    button_sel = 0
    while True:
        disp = "".join(value)[max(0, len(value) - field_w):]
        _put(win, 4, field_x, " " * field_w, curses.color_pair(CP_NORMAL))
        _put(win, 4, field_x, disp[:field_w], curses.color_pair(CP_NORMAL) | curses.A_UNDERLINE)
        _button_bar(win, ["Aceptar", "Cancelar"], button_sel if focus_buttons else None)
        try:
            win.move(4, min(field_x + len(disp), field_x + field_w - 1))
        except curses.error:
            pass
        win.refresh()
        k = win.getch()
        if k == 27:
            curses.curs_set(0)
            return None
        if k in (ord('\t'), curses.KEY_BTAB):
            focus_buttons = not focus_buttons
            continue
        if focus_buttons:
            if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('k'), ord('j'), ord('\t')):
                button_sel ^= 1
            elif k in (curses.KEY_ENTER, 10, 13):
                curses.curs_set(0)
                return "".join(value) if button_sel == 0 else None
            continue
        if k in (curses.KEY_ENTER, 10, 13):
            curses.curs_set(0)
            return "".join(value)
        elif k in (curses.KEY_BACKSPACE, 127, 8):
            if value: value.pop()
        elif 32 <= k <= 126:
            value.append(chr(k))

def yesno(stdscr, title, message):
    """Devuelve True para Aceptar, False para Cancelar/ESC."""
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    lines = message.strip().splitlines()
    w = min(sw - 4, max(52, max(len(l) for l in lines) + 8))
    win, h, w = _newwin(stdscr, len(lines) + 7, w, title)
    _hint(win, "ENTER Aceptar   TAB Botones   ESC Cancelar")
    for i, line in enumerate(lines):
        _put(win, i + 2, 3, line[:w - 6], curses.color_pair(CP_NORMAL))
    sel = 0
    while True:
        _button_bar(win, ["Aceptar", "Cancelar"], sel)
        win.refresh()
        k = win.getch()
        if k == 27:
            return False
        if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('\t')):
            sel ^= 1
        elif k in (curses.KEY_ENTER, 10, 13):
            return sel == 0
        elif k in (ord('y'), ord('Y'), ord('s'), ord('S')):
            return True
        elif k in (ord('n'), ord('N'), 27):
            return False

def radiolist(stdscr, title, items, default_idx=0):
    """Devuelve tag seleccionado o None si se cancela."""
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    w = min(sw - 4, max(52, max(len(lb) for _, lb in items) + 12))
    win, h, w = _newwin(stdscr, len(items) + 6, w, title)
    _hint(win, "↑↓ Navegar   ENTER Seleccionar   TAB Botones   ESC Atrás")
    _button_bar(win, ["Aceptar", "Cancelar"], None)
    sel = default_idx
    focus_buttons = False
    button_sel = 0
    while True:
        for i, (tag, label) in enumerate(items):
            mark = "●" if i == sel else "○"
            if focus_buttons:
                attr = curses.color_pair(CP_NORMAL)
            else:
                attr = curses.color_pair(CP_SEL) | curses.A_BOLD if i == sel else curses.color_pair(CP_NORMAL)
            _put(win, i + 2, 2, f"  {mark}  {label:<{w-8}}", attr)
        _button_bar(win, ["Aceptar", "Cancelar"], button_sel if focus_buttons else None)
        win.refresh()
        k = win.getch()
        if k == 27:
            return None
        if k in (ord('\t'), curses.KEY_BTAB):
            focus_buttons = not focus_buttons
            continue
        if focus_buttons:
            if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('k'), ord('j'), ord('\t')):
                button_sel ^= 1
            elif k in (curses.KEY_ENTER, 10, 13):
                return items[sel][0] if button_sel == 0 else None
            continue
        if k in (curses.KEY_UP, ord('k')):
            sel = (sel - 1) % len(items)
        elif k in (curses.KEY_DOWN, ord('j')):
            sel = (sel + 1) % len(items)
        elif k in (curses.KEY_ENTER, 10, 13, ord(' ')):
            return items[sel][0]

def msgbox(stdscr, title, message):
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    lines = message.strip().splitlines()
    w = min(sw - 4, max(52, max(len(l) for l in lines) + 8))
    win, h, w = _newwin(stdscr, len(lines) + 7, w, title)
    _hint(win, "ENTER Aceptar   TAB Botones   ESC Cancelar")
    for i, line in enumerate(lines):
        _put(win, i + 2, 3, line[:w - 6], curses.color_pair(CP_NORMAL))
    sel = None
    win.refresh()
    while True:
        _button_bar(win, ["Aceptar", "Cancelar"], sel)
        win.refresh()
        k = win.getch()
        if k == 27:
            return None
        if k in (ord('\t'), curses.KEY_BTAB, curses.KEY_LEFT, curses.KEY_RIGHT):
            sel = 0 if sel is None else 1 - sel
        elif k in (curses.KEY_ENTER, 10, 13):
            return True if sel in (0, None) else None

# ── Ejecutar operación en terminal ────────────────────────────────────────────
def run_op(stdscr, title, mig_args, env_extra=None):
    curses.endwin()
    cols = shutil.get_terminal_size((78, 24)).columns
    sep = "━" * cols
    print(f"\033[1;36m{sep}\033[0m")
    print(f"\033[1;36m  {title}\033[0m")
    print(f"\033[1;36m{sep}\033[0m\n")
    env = {**os.environ, "AUTO_CONFIRM_ENV": "1", **(env_extra or {})}
    try:
        subprocess.run(["bash", MIG] + mig_args, env=env)
    except Exception as e:
        print(f"\033[1;31mError: {e}\033[0m")
    print(f"\n\033[1;36m{sep}\033[0m")
    print("\033[1;32m  Operación completada. Pulsa ENTER para volver al menú.\033[0m")
    print(f"\033[1;36m{sep}\033[0m")
    try:
        input()
    except (EOFError, KeyboardInterrupt):
        pass
    stdscr.touchwin()
    stdscr.refresh()

def run_op_inline(stdscr, title, mig_args, env_extra=None, backup_verify=None):
    """Ejecuta la operación dentro del propio TUI mostrando la salida en vivo."""
    curses.curs_set(0)
    env = {**os.environ, "AUTO_CONFIRM_ENV": "1", **(env_extra or {})}
    proc = subprocess.Popen(
        ["bash", MIG] + mig_args,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    lines = []
    h, w = stdscr.getmaxyx()
    footer = "ESC Cancelar   ENTER Continuar"
    spinner = "|/-\\"
    spinner_idx = 0
    last_tick = time.monotonic()

    while True:
        if proc.stdout is not None:
            ready, _, _ = select.select([proc.stdout], [], [], 0.15)
            if ready:
                line = proc.stdout.readline()
                if line:
                    lines.append(line.rstrip("\n"))
                elif proc.poll() is not None:
                    remaining = proc.stdout.read()
                    if remaining:
                        lines.extend(remaining.splitlines())
                    break
            elif proc.poll() is not None:
                remaining = proc.stdout.read()
                if remaining:
                    lines.extend(remaining.splitlines())
                break
        if len(lines) > h - 6:
            lines = lines[-(h - 6):]
        if time.monotonic() - last_tick >= 0.1:
            spinner_idx = (spinner_idx + 1) % len(spinner)
            last_tick = time.monotonic()

        stdscr.erase()
        stdscr.bkgd(' ', curses.color_pair(CP_BORDER))
        _box(stdscr, title)
        _hint(stdscr, footer)
        start_row = 2
        if mig_args and mig_args[0] == "backup":
            progress = _parse_backup_progress(lines)
            block_ratio = 0.0
            if progress["block_idx"] and progress["block_total"]:
                block_ratio = progress["block_idx"] / progress["block_total"]
            item_ratio = 0.0
            if progress["item_idx"] and progress["item_total"]:
                item_ratio = progress["item_idx"] / progress["item_total"]
            status = f"{spinner[spinner_idx]} Copiando backup..."
            if progress["item_label"]:
                status = f"{spinner[spinner_idx]} Copiando: {progress['item_label']}"
            _put(stdscr, 2, 2, status[:max(0, w - 4)], curses.color_pair(CP_NORMAL) | curses.A_BOLD)
            if progress["block_idx"] and progress["block_total"]:
                _put(stdscr, 3, 2, f"Bloque {progress['block_idx']}/{progress['block_total']}", curses.color_pair(CP_CHECK))
                _draw_progress_bar(stdscr, 4, 2, max(10, w - 4), block_ratio)
            if progress["item_idx"] and progress["item_total"]:
                _put(stdscr, 5, 2, f"Elemento {progress['item_idx']}/{progress['item_total']}", curses.color_pair(CP_CHECK))
                _draw_progress_bar(stdscr, 6, 2, max(10, w - 4), item_ratio)
            start_row = 8
        live_lines = lines[-(h - 6):]
        attr_fn = _postcheck_line_attr
        if mig_args and mig_args[0] == "backup":
            live_lines = _backup_live_lines(lines, max(0, h - start_row - 2))
            attr_fn = _backup_line_attr
        else:
            live_lines = lines[-max(0, h - start_row - 2):]
        for idx, line in enumerate(live_lines):
            _put(stdscr, idx + start_row, 2, line[:max(0, w - 4)], attr_fn(line))
        stdscr.refresh()

    return_code = proc.wait()
    verification = None
    if mig_args and mig_args[0] == "backup" and return_code == 0 and backup_verify:
        backup_dir = _extract_backup_destination(lines)
        try:
            verification = _verify_backup_selection(
                backup_dir,
                backup_verify.get("home_dir", _effective_user_home()),
                backup_verify.get("config_items", []),
                backup_verify.get("data_dirs", []),
            )
        except Exception as exc:
            verification = {
                "status": "unavailable",
                "error": str(exc),
            }
    final_lines = lines
    if mig_args and mig_args[0] == "postcheck":
        final_lines = _postcheck_summary(lines, max_lines=12)
    elif mig_args and mig_args[0] == "backup":
        final_lines = _backup_summary(lines, max_lines=12)
        final_lines.extend([""] + _backup_verification_lines(verification))
    elif mig_args and mig_args[0] == "restore":
        final_lines = _restore_summary(lines, max_lines=12)
    stdscr.erase()
    stdscr.bkgd(' ', curses.color_pair(CP_BORDER))
    _box(stdscr, title)
    _hint(stdscr, footer)
    if mig_args and mig_args[0] == "postcheck":
        _put(stdscr, 2, 2, "Resumen final:", curses.color_pair(CP_NORMAL) | curses.A_BOLD)
        row = 4
        for line in final_lines[:max(0, h - 7)]:
            _put(stdscr, row, 2, line[:max(0, w - 4)], _postcheck_line_attr(line))
            row += 1
        _put(stdscr, min(h - 2, row + 1), 2, "Pulsa ENTER para volver al menú.", curses.color_pair(CP_NORMAL))
    elif mig_args and mig_args[0] == "backup":
        message = _humanize_backup_exit(return_code, lines, verification=verification)
        _put(stdscr, 2, 2, message[:max(0, w - 4)], _backup_line_attr(message))
        row = 4
        for line in final_lines[:max(0, h - 8)]:
            _put(stdscr, row, 2, line[:max(0, w - 4)], _backup_line_attr(line))
            row += 1
        _put(stdscr, min(h - 2, row + 1), 2, "Pulsa ENTER para volver al menú.", curses.color_pair(CP_NORMAL))
    elif mig_args and mig_args[0] == "restore":
        message = _humanize_restore_exit(return_code, lines)
        _put(stdscr, 2, 2, message[:max(0, w - 4)], _restore_line_attr(message))
        row = 4
        for line in final_lines[:max(0, h - 8)]:
            _put(stdscr, row, 2, line[:max(0, w - 4)], _restore_line_attr(line))
            row += 1
        _put(stdscr, min(h - 2, row + 1), 2, "Pulsa ENTER para volver al menú.", curses.color_pair(CP_NORMAL))
    else:
        _put(stdscr, 2, 2, f"Proceso finalizado con código {return_code}.", curses.color_pair(CP_NORMAL))
        _put(stdscr, 4, 2, "Pulsa ENTER para volver al menú.", curses.color_pair(CP_NORMAL))
    stdscr.refresh()
    while True:
        k = stdscr.getch()
        if k in (curses.KEY_ENTER, 10, 13, 27):
            break
    stdscr.touchwin()
    stdscr.refresh()

def bootstrap_catalog():
    out = subprocess.check_output(["bash", MIG, "bootstrap-catalog"], text=True)
    items = []
    defaults = set()
    for raw_line in out.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        tag, label, default = line.split("|", 2)
        items.append((tag, f"{len(items) + 1}. {label}"))
        if default == "ON":
            defaults.add(tag)
    return items, defaults

def bootstrap_context():
    return subprocess.check_output(["bash", MIG, "bootstrap-context"], text=True)

def _effective_user_name():
    return os.environ.get("SUDO_USER") or os.environ.get("USER") or os.environ.get("LOGNAME") or ""

def _effective_user_home():
    user = _effective_user_name()
    if user:
        try:
            return pwd.getpwnam(user).pw_dir
        except KeyError:
            pass
    return os.path.expanduser("~")

def backup_data_catalog():
    out = subprocess.check_output(["bash", MIG, "backup-data-catalog"], text=True)
    items = []
    defaults = set()
    for raw_line in out.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        path, label, default = line.split("|", 2)
        items.append((path, f"{len(items) + 1}. {label}"))
        if default == "ON":
            defaults.add(path)
    return items, defaults

def backup_config_catalog():
    out = subprocess.check_output(["bash", MIG, "backup-config-catalog"], text=True)
    items = []
    defaults = set()
    for raw_line in out.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        path, label, default = line.split("|", 2)
        items.append((path, f"{len(items) + 1}. {label}"))
        if default == "ON":
            defaults.add(path)
    return items, defaults

def _backup_default_data_dirs():
    home = _effective_user_home()
    candidates = [
        os.path.join(home, "Desktop"),
        os.path.join(home, "Escritorio"),
        os.path.join(home, "Documents"),
        os.path.join(home, "Documentos"),
        os.path.join(home, "Downloads"),
        os.path.join(home, "Descargas"),
        os.path.join(home, "Pictures"),
        os.path.join(home, "Imágenes"),
        os.path.join(home, "Music"),
        os.path.join(home, "Música"),
        os.path.join(home, "Videos"),
        os.path.join(home, "Vídeos"),
        os.path.join(home, ".ssh"),
        os.path.join(home, ".gnupg"),
        os.path.join(home, ".claude"),
        os.path.join(home, ".codex"),
        os.path.join(home, ".neocoding"),
        os.path.join(home, ".vscode"),
        os.path.join(home, ".config", "Code"),
    ]
    defaults = []
    seen = set()
    for path in candidates:
        if os.path.isdir(path) and path not in seen:
            seen.add(path)
            defaults.append(path)
    return defaults

def _backup_default_config_entries():
    home = _effective_user_home()
    candidates = [
        os.path.join(home, ".ssh"),
        os.path.join(home, ".gnupg"),
        os.path.join(home, ".gitconfig"),
        os.path.join(home, ".bashrc"),
        os.path.join(home, ".profile"),
        os.path.join(home, ".zshrc"),
        os.path.join(home, ".claude"),
        os.path.join(home, ".claude.json"),
        os.path.join(home, ".codex"),
        os.path.join(home, ".neocoding"),
        os.path.join(home, ".config", "Code"),
        os.path.join(home, ".vscode"),
    ]
    defaults = []
    seen = set()
    for path in candidates:
        if os.path.exists(path) and path not in seen:
            seen.add(path)
            defaults.append(path)
    return defaults

def _backup_default_entries():
    defaults = []
    seen = set()
    for path in _backup_default_config_entries() + _backup_default_data_dirs():
        if path not in seen:
            seen.add(path)
            defaults.append(path)
    return defaults

def _list_directory_entries(path):
    entries = []
    try:
        with os.scandir(path) as it:
            items = [
                entry for entry in it
                if entry.is_dir(follow_symlinks=False) or entry.is_file(follow_symlinks=False)
            ]
        items.sort(key=lambda entry: (entry.name.startswith("."), not entry.is_dir(follow_symlinks=False), entry.name.lower()))
        for entry in items:
            entries.append(entry.path)
    except (PermissionError, FileNotFoundError, NotADirectoryError):
        pass
    return entries

def _browse_backup_tree(stdscr, start_path, selected, title="Seleccionar elementos a salvar"):
    current = os.path.abspath(start_path)
    start = current
    selected_set = set(selected)
    sel = 0
    offset = 0
    focus_buttons = False
    button_sel = 0
    curses.curs_set(0)

    while True:
        sh, sw = stdscr.getmaxyx()
        win, h, w = _newwin(stdscr, min(sh - 2, max(18, sh - 4)), min(sw - 2, max(84, sw - 6)), title)
        _hint(win, "↑↓ Navegar   ENTER Abrir carpeta   SPACE Marcar   TAB Botones   ESC Atrás")

        parent = os.path.dirname(current.rstrip("/")) or "/"
        entries = []
        if current != "/":
            entries.append(("__up__", "../"))
        current_label = os.path.basename(current.rstrip("/")) or current
        current_mark = "[*]" if current in selected_set else "[ ]"
        entries.append(("__toggle_current__", f"{current_mark} Esta carpeta: {current_label}/"))

        for item_path in _list_directory_entries(current):
            name = os.path.basename(item_path) or item_path
            suffix = "/" if os.path.isdir(item_path) else ""
            mark = "[*]" if item_path in selected_set else "[ ]"
            entries.append((item_path, f"{mark} {name}{suffix}"))

        entries.append(("__view__", f"Ver seleccionadas ({len(selected_set)})"))
        entries.append(("__manual__", "Escribir ruta manualmente"))

        visible = max(1, h - 8)
        if sel >= len(entries):
            sel = max(0, len(entries) - 1)
        if sel < offset:
            offset = sel
        if sel >= offset + visible:
            offset = sel - visible + 1

        path_line = f"Ruta actual: {current}"
        status_line = f"Elementos: {len(entries)}   Seleccionadas: {len(selected_set)}   Mostrando: {offset + 1}-{min(len(entries), offset + visible)}"
        _put(win, 1, 2, path_line[:w - 4], curses.color_pair(CP_NORMAL) | curses.A_BOLD)
        _put(win, 2, 2, status_line[:w - 4], curses.color_pair(CP_NORMAL))

        for i in range(visible):
            idx = i + offset
            row_y = i + 4
            if idx >= len(entries):
                _put(win, row_y, 2, " " * (w - 4), curses.color_pair(CP_NORMAL))
                continue
            label = entries[idx][1]
            if focus_buttons:
                attr = curses.color_pair(CP_NORMAL)
            else:
                attr = curses.color_pair(CP_SEL) | curses.A_BOLD if idx == sel else curses.color_pair(CP_NORMAL)
            _put(win, row_y, 2, f"  {label:<{w-6}}", attr)

        _button_bar(win, ["Finalizar", "Cancelar"], button_sel if focus_buttons else None)
        win.refresh()
        k = win.getch()

        if k == 27:
            if focus_buttons:
                focus_buttons = False
                continue
            if current != start:
                current = parent
                sel = 0
                offset = 0
                continue
            return None
        if k in (ord('\t'), curses.KEY_BTAB):
            focus_buttons = not focus_buttons
            continue
        if focus_buttons:
            if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('h'), ord('l'), ord('\t')):
                button_sel ^= 1
            elif k in (curses.KEY_ENTER, 10, 13):
                if button_sel == 1:
                    return None
                if not selected_set:
                    msgbox(stdscr, title, "Selecciona al menos un elemento antes de terminar.")
                    continue
                return sorted(selected_set)
            continue

        if k in (curses.KEY_UP, ord('k')) and sel > 0:
            sel -= 1
            continue
        if k in (curses.KEY_DOWN, ord('j')) and sel < len(entries) - 1:
            sel += 1
            continue
        if k == ord(' '):
            selected_item = entries[sel][0]
            if selected_item == "__toggle_current__":
                if current in selected_set:
                    selected_set.remove(current)
                else:
                    selected_set.add(current)
            elif os.path.exists(selected_item):
                if selected_item in selected_set:
                    selected_set.remove(selected_item)
                else:
                    selected_set.add(selected_item)
            continue
        if k not in (curses.KEY_ENTER, 10, 13):
            continue

        selected_item = entries[sel][0]
        if selected_item == "__up__":
            current = parent
            sel = 0
            offset = 0
            continue
        if selected_item == "__toggle_current__":
            if current in selected_set:
                selected_set.remove(current)
            else:
                selected_set.add(current)
            continue
        if selected_item == "__view__":
            if selected_set:
                msgbox(stdscr, title, "Carpetas seleccionadas:\n\n" + "\n".join(sorted(selected_set)))
            else:
                msgbox(stdscr, title, "Todavía no has seleccionado ningún elemento.")
            continue
        if selected_item == "__manual__":
            manual = inputbox(stdscr, title, "Escribe la ruta del elemento:", current)
            if manual is None:
                continue
            manual = manual.strip()
            if not manual:
                msgbox(stdscr, title, "Debes escribir una ruta válida.")
                continue
            manual = os.path.abspath(manual)
            if not os.path.exists(manual):
                msgbox(stdscr, title, f"La ruta no existe:\n{manual}")
                continue
            if os.path.isdir(manual):
                current = manual
                sel = 0
                offset = 0
            else:
                if manual in selected_set:
                    selected_set.remove(manual)
                else:
                    selected_set.add(manual)
            continue
        if os.path.isdir(selected_item):
            current = os.path.abspath(selected_item)
            sel = 0
            offset = 0
            continue
        if os.path.isfile(selected_item):
            if selected_item in selected_set:
                selected_set.remove(selected_item)
            else:
                selected_set.add(selected_item)
            continue
        msgbox(stdscr, title, f"No es una ruta válida:\n{selected_item}")

def _split_backup_entries(selected_entries):
    home = os.path.abspath(_effective_user_home())
    config_items = []
    data_dirs = []

    for entry in selected_entries:
        abs_entry = os.path.abspath(entry)
        if not abs_entry.startswith(home + os.sep):
            continue
        rel_entry = os.path.relpath(abs_entry, home)
        first_component = rel_entry.split(os.sep, 1)[0]

        if first_component.startswith(".") or os.path.isfile(abs_entry):
            config_items.append(rel_entry)
        elif os.path.isdir(abs_entry):
            data_dirs.append(abs_entry)

    return sorted(dict.fromkeys(config_items)), sorted(dict.fromkeys(data_dirs))

def select_backup_entries(stdscr):
    defaults = _backup_default_entries()
    home = _effective_user_home()
    return _browse_backup_tree(stdscr, home, defaults, "Explorar elementos del usuario")

def _parse_lsblk_line(line):
    data = {}
    for chunk in shlex.split(line):
        if "=" not in chunk:
            continue
        key, value = chunk.split("=", 1)
        data[key] = value.strip('"')
    return data

def _discover_backup_mounts():
    mounts = []
    seen = set()
    try:
        out = subprocess.check_output(
            ["lsblk", "-P", "-o", "MOUNTPOINT,NAME,SIZE,FSTYPE,LABEL,TRAN"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        for raw_line in out.splitlines():
            data = _parse_lsblk_line(raw_line)
            mountpoint = data.get("MOUNTPOINT", "").strip()
            fstype = data.get("FSTYPE", "").strip().lower()
            if not mountpoint or mountpoint in {"/", "/boot", "/boot/efi"}:
                continue
            if fstype == "swap":
                continue
            if not os.path.isdir(mountpoint):
                continue
            if mountpoint in seen:
                continue
            seen.add(mountpoint)
            mounts.append({
                "mountpoint": mountpoint,
                "name": data.get("NAME", ""),
                "size": data.get("SIZE", ""),
                "fstype": data.get("FSTYPE", ""),
                "label": data.get("LABEL", ""),
                "tran": data.get("TRAN", ""),
            })
    except Exception:
        pass

    if mounts:
        return mounts

    try:
        with open("/proc/mounts", "r", encoding="utf-8") as fh:
            for raw_line in fh:
                parts = raw_line.split()
                if len(parts) < 3:
                    continue
                mountpoint = parts[1]
                fstype = parts[2]
                if not mountpoint or mountpoint in {"/", "/boot", "/boot/efi"}:
                    continue
                if fstype == "swap":
                    continue
                if mountpoint.startswith("/proc") or mountpoint.startswith("/sys") or mountpoint.startswith("/dev"):
                    continue
                if fstype.startswith(("proc", "sysfs", "tmpfs", "devtmpfs", "cgroup", "overlay", "squashfs")):
                    continue
                if not os.path.isdir(mountpoint) or mountpoint in seen:
                    continue
                seen.add(mountpoint)
                mounts.append({
                    "mountpoint": mountpoint,
                    "name": os.path.basename(mountpoint) or mountpoint,
                    "size": "",
                    "fstype": fstype,
                    "label": "",
                    "tran": "",
                })
    except Exception:
        pass

    return mounts

def _read_fstab_mounts():
    mounts = []
    seen = set()
    pseudo_fstypes = {
        "proc", "sysfs", "tmpfs", "devtmpfs", "devpts", "cgroup", "cgroup2",
        "overlay", "squashfs", "nfs", "nfs4", "autofs", "fusectl", "securityfs",
        "pstore", "efivarfs", "debugfs", "tracefs", "hugetlbfs", "mqueue",
        "swap",
    }
    try:
        with open("/etc/fstab", "r", encoding="utf-8") as fh:
            for raw_line in fh:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) < 4:
                    continue
                spec, mountpoint, fstype = parts[:3]
                if not mountpoint or mountpoint in {"/", "/boot", "/boot/efi"}:
                    continue
                if not os.path.isdir(mountpoint):
                    continue
                if mountpoint in seen:
                    continue
                if fstype in pseudo_fstypes:
                    continue
                if not (
                    spec.startswith(("/dev/", "UUID=", "LABEL=", "PARTUUID=", "PARTLABEL="))
                    or spec == "none"
                ):
                    continue
                seen.add(mountpoint)
                mounts.append({
                    "mountpoint": mountpoint,
                    "name": os.path.basename(mountpoint) or mountpoint,
                    "size": "",
                    "fstype": fstype,
                    "label": "fstab",
                    "tran": "",
                })
    except Exception:
        pass
    return mounts

def _discover_backup_roots():
    roots = []
    seen = set()
    user = _effective_user_name() or os.path.basename(_effective_user_home())
    candidates = [
        (f"/run/media/{user}", f"/run/media/{user}"),
        (f"/media/{user}", f"/media/{user}"),
        ("/mnt", "/mnt"),
        ("/run/media", "/run/media"),
        ("/media", "/media"),
    ]
    for path, label in candidates:
        if os.path.isdir(path) and path not in seen:
            seen.add(path)
            roots.append({"path": path, "label": label})

    for entry in _discover_backup_mounts() + _read_fstab_mounts():
        path = entry["mountpoint"]
        if path not in seen:
            seen.add(path)
            roots.append({
                "path": path,
                "label": _format_mount_label(entry),
            })
    return roots

def _format_mount_label(entry):
    bits = [entry.get("mountpoint", "/")]
    meta = []
    if entry.get("label"):
        meta.append(f"etiqueta {entry['label']}")
    if entry.get("fstype"):
        meta.append(entry["fstype"])
    if entry.get("size"):
        meta.append(entry["size"])
    if entry.get("tran"):
        meta.append(entry["tran"])
    if meta:
        bits.append(f"({', '.join(meta)})")
    return " ".join(bits)

def _is_backup_dir(path):
    path = os.path.abspath(path)
    return os.path.isdir(path) and os.path.isfile(os.path.join(path, "metadata", "user_ids.conf"))

def _find_backup_dirs_under(root_path, max_depth=4, max_results=24):
    backups = []
    seen = set()
    root_path = os.path.abspath(root_path)
    if not os.path.isdir(root_path):
        return backups

    queue = [(root_path, 0)]
    while queue and len(backups) < max_results:
        current, depth = queue.pop(0)
        if _is_backup_dir(current) and current not in seen:
            seen.add(current)
            backups.append(current)
            continue
        if depth >= max_depth:
            continue
        try:
            with os.scandir(current) as it:
                dirs = sorted(
                    [entry.path for entry in it if entry.is_dir(follow_symlinks=False)],
                    key=lambda value: os.path.basename(value).lower(),
                )
        except (PermissionError, FileNotFoundError, OSError):
            continue
        for entry in dirs:
            if entry not in seen:
                queue.append((entry, depth + 1))
    return backups

def _discover_restore_backups():
    backups = []
    seen = set()
    for root in _discover_backup_roots():
        for backup_dir in _find_backup_dirs_under(root["path"]):
            if backup_dir not in seen:
                seen.add(backup_dir)
                backups.append(backup_dir)
    backups.sort(key=lambda path: os.path.basename(path).lower(), reverse=True)
    return backups

def browse_directory(stdscr, start_path, title="Navegar destino"):
    current = os.path.abspath(start_path or "/")
    start = current
    sel = 1 if current != "/" else 0
    offset = 0
    focus_buttons = False
    button_sel = 0
    curses.curs_set(0)

    while True:
        try:
            parent = os.path.dirname(current.rstrip("/")) or "/"
            entries = []
            if current != "/":
                entries.append(("__up__", "../"))
            try:
                with os.scandir(current) as it:
                    dirs = sorted(
                        [entry for entry in it if entry.is_dir(follow_symlinks=False)],
                        key=lambda entry: entry.name.lower(),
                    )
                for entry in dirs:
                    entries.append((entry.path, entry.name + "/"))
            except PermissionError:
                msgbox(stdscr, title, f"No se puede leer esta ruta:\n{current}\n\nVuelvo atrás.")
                current = parent
                sel = 0
                offset = 0
                continue

            entries.append(("__manual__", "Escribir ruta manualmente"))

            sh, sw = stdscr.getmaxyx()
            win, h, w = _newwin(stdscr, min(sh - 2, max(18, sh - 4)), min(sw - 2, max(84, sw - 6)), title)
            _hint(win, "↑↓ Navegar   ENTER Abrir carpeta   TAB Botones   ESC Atrás")

            visible = max(1, h - 8)
            if sel >= len(entries):
                sel = max(0, len(entries) - 1)
            if current != "/" and sel == 0 and len(entries) > 1 and entries[0][0] == "__up__":
                sel = 1
            if sel < offset:
                offset = sel
            if sel >= offset + visible:
                offset = sel - visible + 1

            path_line = f"Ruta actual: {current}"
            status_line = f"Carpetas: {len(entries) - 1 if entries and entries[-1][0] == '__manual__' else len(entries)}   Mostrando: {offset + 1}-{min(len(entries), offset + visible)}"
            _put(win, 1, 2, path_line[:w - 4], curses.color_pair(CP_NORMAL) | curses.A_BOLD)
            _put(win, 2, 2, status_line[:w - 4], curses.color_pair(CP_NORMAL))

            for i in range(visible):
                idx = i + offset
                row_y = i + 4
                if idx >= len(entries):
                    _put(win, row_y, 2, " " * (w - 4), curses.color_pair(CP_NORMAL))
                    continue
                label = entries[idx][1]
                if focus_buttons:
                    attr = curses.color_pair(CP_NORMAL)
                else:
                    attr = curses.color_pair(CP_SEL) | curses.A_BOLD if idx == sel else curses.color_pair(CP_NORMAL)
                _put(win, row_y, 2, f"  {label:<{w-6}}", attr)

            _button_bar(win, ["Usar esta ruta", "Cancelar"], button_sel if focus_buttons else None)
            win.refresh()
            k = win.getch()

            if k == 27:
                if focus_buttons:
                    focus_buttons = False
                    continue
                if current != start:
                    current = parent
                    sel = 0
                    offset = 0
                    continue
                return None
            if k in (ord('\t'), curses.KEY_BTAB):
                focus_buttons = not focus_buttons
                continue
            if focus_buttons:
                if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('h'), ord('l'), ord('\t')):
                    button_sel ^= 1
                elif k in (curses.KEY_ENTER, 10, 13):
                    return current if button_sel == 0 else None
                continue
            if k in (curses.KEY_UP, ord('k')) and sel > 0:
                sel -= 1
                continue
            if k in (curses.KEY_DOWN, ord('j')) and sel < len(entries) - 1:
                sel += 1
                continue
            if k == curses.KEY_PPAGE:
                sel = max(0, sel - visible)
                offset = min(offset, sel)
                continue
            if k == curses.KEY_NPAGE:
                sel = min(len(entries) - 1, sel + visible)
                if sel >= offset + visible:
                    offset = sel - visible + 1
                continue
            if k not in (curses.KEY_ENTER, 10, 13):
                continue

            selected = entries[sel][0]
            if selected == "__up__":
                current = parent
                sel = 0
                offset = 0
                continue
            if selected == "__manual__":
                manual = inputbox(stdscr, title, "Escribe la ruta destino:", current)
                if manual is None:
                    continue
                manual = manual.strip()
                if not manual:
                    msgbox(stdscr, title, "Debes escribir una ruta válida.")
                    continue
                manual = os.path.abspath(manual)
                if os.path.isdir(manual):
                    current = manual
                    sel = 0
                    offset = 0
                    continue
                msgbox(stdscr, title, f"La ruta no existe o no es un directorio:\n{manual}")
                continue
            if os.path.isdir(selected):
                current = os.path.abspath(selected)
                sel = 1 if current != "/" else 0
                offset = 0
            else:
                msgbox(stdscr, title, f"No es un directorio válido:\n{selected}")
        except FileNotFoundError:
            msgbox(stdscr, title, f"La ruta ya no existe:\n{current}")
            current = "/"
            sel = 0
            offset = 0

def choose_backup_target(stdscr):
    roots = _discover_backup_roots()
    items = [
        ("manual", "Escribir ruta manualmente"),
    ]
    for root in roots:
        items.append((root["path"], f"Explorar {root['label']}"))
    items.append(("root", "Navegar desde /"))
    choice = menu(stdscr, "Selecciona el destino de backup", items)
    if choice == -1:
        return None
    selected = items[choice][0]
    if selected == "manual":
        while True:
            target = inputbox(stdscr, "Selecciona el destino de backup", "Ruta destino del backup:", "")
            if target is None:
                return None
            target = target.strip()
            if not target:
                msgbox(stdscr, "Selecciona el destino de backup", "Debes escribir una ruta válida.")
                continue
            target = os.path.abspath(target)
            if os.path.isdir(target):
                return target
            msgbox(stdscr, "Selecciona el destino de backup", f"La ruta no existe o no es un directorio:\n{target}")
    if selected == "root":
        return browse_directory(stdscr, "/", "Selecciona el destino de backup")
    return browse_directory(stdscr, selected, "Selecciona el destino de backup")

def choose_restore_source(stdscr):
    detected_backups = _discover_restore_backups()
    roots = _discover_backup_roots()
    items = []
    for backup_dir in detected_backups:
        label = f"Backup detectado: {os.path.basename(backup_dir)}  [{backup_dir}]"
        items.append((f"backup:{backup_dir}", label))
    items.append(("manual", "Escribir ruta manualmente"))
    for root in roots:
        items.append((f"root:{root['path']}", f"Explorar {root['label']}"))
    items.append(("browse-root", "Navegar desde /"))

    while True:
        choice = menu(stdscr, "Selecciona el origen del backup", items)
        if choice == -1:
            return None
        selected = items[choice][0]
        if selected.startswith("backup:"):
            source = selected.split(":", 1)[1]
            if _is_backup_dir(source):
                return source
            msgbox(stdscr, "Selecciona el origen del backup", f"La copia ya no está disponible:\n{source}")
            continue
        if selected == "manual":
            while True:
                source = inputbox(stdscr, "Selecciona el origen del backup", "Ruta del backup a restaurar:", "")
                if source is None:
                    break
                source = os.path.abspath(source.strip())
                if not source:
                    msgbox(stdscr, "Selecciona el origen del backup", "Debes escribir una ruta válida.")
                    continue
                if _is_backup_dir(source):
                    return source
                msgbox(
                    stdscr,
                    "Selecciona el origen del backup",
                    "La ruta no parece una copia válida.\n\n"
                    "Debe contener:\nmetadata/user_ids.conf\n\n"
                    f"Ruta indicada:\n{source}",
                )
            continue
        if selected == "browse-root":
            source = browse_directory(stdscr, "/", "Selecciona el origen del backup")
        else:
            source = browse_directory(stdscr, selected.split(":", 1)[1], "Selecciona el origen del backup")
        if source is None:
            continue
        if _is_backup_dir(source):
            return source
        msgbox(
            stdscr,
            "Selecciona el origen del backup",
            "La ruta seleccionada no parece una copia válida.\n\n"
            "Debes elegir la carpeta raíz del backup, la que contiene:\nmetadata/user_ids.conf\n\n"
            f"Ruta seleccionada:\n{source}",
        )

# ── Flujos ────────────────────────────────────────────────────────────────────
def flow_backup(stdscr):
    target = choose_backup_target(stdscr)
    if target is None:
        return
    target = target.strip()
    if not target:
        msgbox(stdscr, "Backup sistema", "Debes indicar un directorio destino.")
        return
    msgbox(
        stdscr,
        "Backup sistema",
        "Ahora vas a explorar los elementos reales de tu usuario.\n\n"
        f"Ruta inicial: {_effective_user_home()}\n\n"
        "Veras carpetas y archivos. SPACE marca o desmarca.",
    )
    selected_entries = select_backup_entries(stdscr)
    if selected_entries is None:
        return
    selected_config_items, selected_data_dirs = _split_backup_entries(selected_entries)
    if not selected_config_items and not selected_data_dirs:
        msgbox(stdscr, "Backup sistema", "Debes seleccionar al menos un elemento del usuario.")
        return
    if not selected_data_dirs:
        msgbox(stdscr, "Backup sistema", "No has marcado carpetas normales. Solo se salvará configuración oculta.")

    summary_lines = [f"Destino: {target}", ""]
    summary_lines.append("Elementos de configuracion:")
    for item in selected_config_items[:8]:
        summary_lines.append(f"- {item}")
    if len(selected_config_items) > 8:
        summary_lines.append(f"- ... y {len(selected_config_items) - 8} más")
    summary_lines.append("")
    summary_lines.append("Carpetas de datos:")
    for item in selected_data_dirs[:8]:
        summary_lines.append(f"- {item}")
    if len(selected_data_dirs) > 8:
        summary_lines.append(f"- ... y {len(selected_data_dirs) - 8} más")

    if not yesno(stdscr, "Backup sistema", "\n".join(summary_lines) + "\n\n¿Iniciar backup?"):
        return
    env_extra = {
        "BACKUP_SELECTION_FROM_TUI": "1",
        "SELECTED_CONFIG_ITEMS_RAW": "\n".join(selected_config_items),
        "SELECTED_DATA_DIRS_RAW": "\n".join(selected_data_dirs),
    }
    run_op_inline(
        stdscr,
        "Backup sistema",
        ["backup", "--target", target],
        env_extra=env_extra,
        backup_verify={
            "home_dir": _effective_user_home(),
            "config_items": selected_config_items,
            "data_dirs": selected_data_dirs,
        },
    )

def flow_restore(stdscr):
    src = choose_restore_source(stdscr)
    if src is None:
        return
    if not yesno(stdscr, "Restaurar backup", f"Fuente: {src}\n\n¿Iniciar restauración?"):
        return
    run_op_inline(stdscr, "Restaurar backup", ["restore", "--source", src])

def flow_bootstrap(stdscr):
    items, defaults = bootstrap_catalog()
    context = bootstrap_context()
    if not yesno(stdscr, "Bootstrap CachyOS", f"{context}\n\n¿Continuar con este perfil?"):
        return
    selected = checklist(stdscr, "Bootstrap CachyOS", items, defaults)
    if selected is None:
        return
    if not selected:
        msgbox(stdscr, "Bootstrap", "No se seleccionó ningún bloque.")
        return

    env_extra = {}
    ai_selected = {"ai_codex", "ai_claude", "ai_gemini", "ai_opencode", "ai_engram"} & set(selected)
    
    if "wifi" in selected:
        stdscr.clear()
        stdscr.refresh()
        country = inputbox(stdscr, "Configurar Wi-Fi",
                           "Código de país para Wi-Fi (ej. ES):", "ES")
        if country is None:
            return
        env_extra["TUI_WIFI_COUNTRY"] = country.strip().upper()

    if "hwaccel" in selected:
        stdscr.clear()
        stdscr.refresh()
        browser = radiolist(stdscr, "Aceleración HW navegador",
                            [("brave", "Brave Browser"), ("chrome", "Google Chrome")])
        if browser is None:
            return
        env_extra["TUI_BROWSER"] = browser

    stdscr.clear()
    stdscr.refresh()
    if not yesno(stdscr, "Bootstrap CachyOS",
                 "Se ejecutarán los bloques seleccionados.\n¿Continuar?"):
        return

    selected_str = " ".join(f'"{t}"' for t in selected)
    run_op(stdscr, "Bootstrap CachyOS",
           ["tui-bootstrap-run", selected_str,
            env_extra.get("TUI_WIFI_COUNTRY", ""),
            env_extra.get("TUI_BROWSER", "")],
           env_extra=env_extra)

def flow_plasmoid_op(stdscr, title, command):
    target = inputbox(stdscr, title, "Pantalla del plasmoid [primary|screen:N]:", "primary")
    if target is None:
        return
    run_op(stdscr, title, [command, "--target", target.strip() or "primary"])

def flow_watch_plasmoid_menu(stdscr):
    items = [
        ("sep-watch",          "──────── MBP Watch ────────"),
        ("install-watch",      "Instalar sistema MBP Watch"),
        ("uninstall-watch",    "Desinstalar sistema MBP Watch"),
        ("sep-plasmoid",       "──────── Plasmoid MBP Watch ────────"),
        ("add-plasmoid",       "Añadir widget al escritorio"),
        ("move-plasmoid",      "Widget en pantalla..."),
        ("reinstall-plasmoid", "Reinstalar widget MBP Watch"),
        ("uninstall-plasmoid", "Quitar widget MBP Watch"),
        ("back",               "Atrás"),
    ]
    while True:
        idx = menu(stdscr, "MBP Watch y plasmoid", items)
        if idx < 0:
            return
        tag, label = items[idx]
        if tag == "back":
            return
        if tag in {"sep-watch", "sep-plasmoid"}:
            continue
        if tag == "install-watch":
            if yesno(stdscr, label, "¿Instalar o actualizar el sistema MBP Watch?"):
                run_op(stdscr, label, ["install-mbp-watch"])
        elif tag == "add-plasmoid":
            flow_plasmoid_op(stdscr, label, "add-mbp-plasmoid")
        elif tag == "move-plasmoid":
            flow_plasmoid_op(stdscr, label, "move-mbp-plasmoid")
        elif tag == "reinstall-plasmoid":
            flow_plasmoid_op(stdscr, label, "reinstall-mbp-plasmoid")
        elif tag == "uninstall-plasmoid":
            if yesno(stdscr, label, "¿Quitar el widget KDE MBP Watch?"):
                run_op(stdscr, label, ["uninstall-mbp-plasmoid"])
        elif tag == "uninstall-watch":
            if yesno(stdscr, label, "¿Desinstalar el sistema MBP Watch?"):
                run_op(stdscr, label, ["uninstall-mbp-watch"])

# ── Menú principal ────────────────────────────────────────────────────────────
def main_loop(stdscr):
    _init_colors()
    curses.curs_set(0)
    stdscr.bkgd(' ', curses.color_pair(CP_BORDER))
    items = [
        ("backup",             "Backup sistema"),
        ("bootstrap",          "Bootstrap CachyOS"),
        ("postcheck",          "Post-check tras reinicio"),
        ("restore",            "Restaurar backup"),
        ("watch-plasmoid",     "MBP Watch y plasmoid"),
        ("exit",               "Salir"),
    ]
    while True:
        stdscr.clear()
        stdscr.refresh()
        idx = menu(stdscr, f"Linux Migration Tool v{VERSION}  [python]", items, show_buttons=False)
        if idx < 0:
            break
        tag, label = items[idx]
        if tag == "exit":
            break
        elif tag == "backup":
            flow_backup(stdscr)
        elif tag == "bootstrap":
            flow_bootstrap(stdscr)
        elif tag == "postcheck":
            run_op_inline(stdscr, label, ["postcheck"])
        elif tag == "restore":
            flow_restore(stdscr)
        elif tag == "watch-plasmoid":
            flow_watch_plasmoid_menu(stdscr)

def main():
    if not os.path.isfile(MIG):
        print(f"Error: migration.sh no encontrado en {MIG}", file=sys.stderr)
        sys.exit(1)
    try:
        curses.wrapper(main_loop)
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
