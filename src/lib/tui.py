#!/usr/bin/env python3
"""TUI Python + curses para Linux Migration Tool. Solo stdlib — sin paquetes extra."""

import curses, os, subprocess, sys, shutil

PROJECT_ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VERSION = sys.argv[2] if len(sys.argv) > 2 else "?"
MIG = os.path.join(PROJECT_ROOT, "migration.sh")

# ── Pares de color ────────────────────────────────────────────────────────────
CP_BORDER, CP_SEL, CP_CHECK, CP_NORMAL = 1, 2, 3, 4

def _init_colors():
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(CP_BORDER, curses.COLOR_CYAN,  -1)
    curses.init_pair(CP_SEL,   curses.COLOR_BLACK, curses.COLOR_CYAN)
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

def _newwin(stdscr, h, w, title=""):
    sh, sw = stdscr.getmaxyx()
    h, w = min(h, sh - 2), min(w, sw - 2)
    win = curses.newwin(h, w, (sh - h) // 2, (sw - w) // 2)
    win.keypad(True)
    _box(win, title)
    return win, h, w

# ── Widgets ───────────────────────────────────────────────────────────────────
def menu(stdscr, title, items):
    """Devuelve índice seleccionado o -1 si se cancela."""
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    w = min(sw - 4, max(56, max(len(lb) for _, lb in items) + 8))
    h = min(sh - 2, len(items) + 5)
    win, h, w = _newwin(stdscr, h, w, title)
    _hint(win, "↑↓ Navegar   ENTER Seleccionar   Q Salir")
    visible = h - 4
    sel = offset = 0
    while True:
        for i in range(visible):
            idx = i + offset
            row_text = f"  {items[idx][1]}" if idx < len(items) else ""
            attr = curses.color_pair(CP_SEL) | curses.A_BOLD if idx == sel else curses.color_pair(CP_NORMAL)
            _put(win, i + 2, 2, f"{row_text:<{w-4}}", attr)
        win.refresh()
        k = win.getch()
        if k in (curses.KEY_UP, ord('k')) and sel > 0:
            sel -= 1
            if sel < offset: offset = sel
        elif k in (curses.KEY_DOWN, ord('j')) and sel < len(items) - 1:
            sel += 1
            if sel >= offset + visible: offset = sel - visible + 1
        elif k in (curses.KEY_ENTER, 10, 13):
            return sel
        elif k in (ord('q'), ord('Q'), 27):
            return -1

def checklist(stdscr, title, items, defaults=None):
    """Devuelve lista de tags seleccionados o None si se cancela."""
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    checked = set(defaults or [])
    w = min(sw - 4, max(68, max(len(lb) for _, lb in items) + 14))
    visible = min(sh - 8, len(items))
    win, h, w = _newwin(stdscr, visible + 6, w, title)
    _hint(win, "SPACE Marcar   ↑↓ Navegar   ENTER Confirmar   Q Cancelar")
    sel = offset = 0
    while True:
        for i in range(visible):
            idx = i + offset
            if idx >= len(items):
                _put(win, i + 2, 2, " " * (w - 4))
                continue
            tag, label = items[idx]
            mark = "x" if tag in checked else " "
            line = f"  [{mark}]  {label}"
            if idx == sel:
                attr = curses.color_pair(CP_SEL) | curses.A_BOLD
            elif tag in checked:
                attr = curses.color_pair(CP_CHECK)
            else:
                attr = curses.color_pair(CP_NORMAL)
            _put(win, i + 2, 2, f"{line:<{w-4}}", attr)
        win.refresh()
        k = win.getch()
        if k in (curses.KEY_UP, ord('k')) and sel > 0:
            sel -= 1
            if sel < offset: offset = sel
        elif k in (curses.KEY_DOWN, ord('j')) and sel < len(items) - 1:
            sel += 1
            if sel >= offset + visible: offset = sel - visible + 1
        elif k == ord(' '):
            tag = items[sel][0]
            checked ^= {tag}
        elif k in (curses.KEY_ENTER, 10, 13):
            return [t for t, _ in items if t in checked]
        elif k in (ord('q'), ord('Q'), 27):
            return None

def inputbox(stdscr, title, prompt, default=""):
    """Devuelve texto introducido o None si se cancela."""
    curses.curs_set(1)
    sh, sw = stdscr.getmaxyx()
    w = min(sw - 4, max(60, len(prompt) + 10))
    win, h, w = _newwin(stdscr, 8, w, title)
    _hint(win, "ENTER Confirmar   ESC Cancelar")
    _put(win, 2, 3, prompt[:w - 6], curses.color_pair(CP_NORMAL))
    field_x, field_w = 3, w - 6
    value = list(default)
    while True:
        disp = "".join(value)[max(0, len(value) - field_w):]
        _put(win, 4, field_x, " " * field_w, curses.color_pair(CP_NORMAL))
        _put(win, 4, field_x, disp[:field_w], curses.color_pair(CP_NORMAL) | curses.A_UNDERLINE)
        try:
            win.move(4, min(field_x + len(disp), field_x + field_w - 1))
        except curses.error:
            pass
        win.refresh()
        k = win.getch()
        if k in (curses.KEY_ENTER, 10, 13):
            curses.curs_set(0)
            return "".join(value)
        elif k == 27:
            curses.curs_set(0)
            return None
        elif k in (curses.KEY_BACKSPACE, 127, 8):
            if value: value.pop()
        elif 32 <= k <= 126:
            value.append(chr(k))

def yesno(stdscr, title, message):
    """Devuelve True para Sí, False para No/ESC."""
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    lines = message.strip().splitlines()
    w = min(sw - 4, max(52, max(len(l) for l in lines) + 8))
    win, h, w = _newwin(stdscr, len(lines) + 7, w, title)
    for i, line in enumerate(lines):
        _put(win, i + 2, 3, line[:w - 6], curses.color_pair(CP_NORMAL))
    sel = 0
    btn_y = h - 3
    while True:
        for i, label in enumerate(["  < Sí >  ", "  < No >  "]):
            bx = w // 2 - 13 + i * 14
            attr = curses.color_pair(CP_SEL) | curses.A_BOLD if i == sel else curses.color_pair(CP_NORMAL)
            _put(win, btn_y, bx, label, attr)
        win.refresh()
        k = win.getch()
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
    _hint(win, "↑↓ Navegar   ENTER Seleccionar   Q Cancelar")
    sel = default_idx
    while True:
        for i, (tag, label) in enumerate(items):
            mark = "●" if i == sel else "○"
            attr = curses.color_pair(CP_SEL) | curses.A_BOLD if i == sel else curses.color_pair(CP_NORMAL)
            _put(win, i + 2, 2, f"  {mark}  {label:<{w-8}}", attr)
        win.refresh()
        k = win.getch()
        if k in (curses.KEY_UP, ord('k')):
            sel = (sel - 1) % len(items)
        elif k in (curses.KEY_DOWN, ord('j')):
            sel = (sel + 1) % len(items)
        elif k in (curses.KEY_ENTER, 10, 13, ord(' ')):
            return items[sel][0]
        elif k in (ord('q'), ord('Q'), 27):
            return None

def msgbox(stdscr, title, message):
    curses.curs_set(0)
    sh, sw = stdscr.getmaxyx()
    lines = message.strip().splitlines()
    w = min(sw - 4, max(52, max(len(l) for l in lines) + 8))
    win, h, w = _newwin(stdscr, len(lines) + 6, w, title)
    _hint(win, "ENTER Continuar")
    for i, line in enumerate(lines):
        _put(win, i + 2, 3, line[:w - 6], curses.color_pair(CP_NORMAL))
    win.refresh()
    while win.getch() not in (curses.KEY_ENTER, 10, 13, ord(' ')):
        pass

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

# ── Flujos ────────────────────────────────────────────────────────────────────
def flow_backup(stdscr):
    target = inputbox(stdscr, "Backup sistema", "Directorio destino del backup:", "")
    if target is None:
        return
    target = target.strip()
    if not target:
        msgbox(stdscr, "Backup sistema", "Debes indicar un directorio destino.")
        return
    if not yesno(stdscr, "Backup sistema", f"Destino: {target}\n\n¿Iniciar backup?"):
        return
    run_op(stdscr, "Backup sistema", ["backup", "--target", target])

def flow_restore(stdscr):
    src = ""
    while True:
        src = inputbox(stdscr, "Restaurar backup",
                       "Ruta completa del backup a restaurar:", src or "")
        if src is None:
            return
        src = src.strip()
        if not src:
            msgbox(stdscr, "Restaurar backup", "Debes indicar una ruta.")
            continue
        if not os.path.isdir(src):
            msgbox(stdscr, "Restaurar backup",
                   f"Ruta no encontrada:\n{src}\n\nRevisa e inténtalo de nuevo.")
            continue
        break
    if not yesno(stdscr, "Restaurar backup", f"Fuente: {src}\n\n¿Iniciar restauración?"):
        return
    run_op(stdscr, "Restaurar backup", ["restore", "--source", src])

def flow_bootstrap(stdscr):
    items = [
        ("sync",       "1. Sincronización y actualización sistema"),
        ("base_dev",   "2. Herramientas base desarrollo (git, go)"),
        ("yay",        "3. AUR helper (yay)"),
        ("flatpak",    "4. Soporte Flatpak + Flathub"),
        ("official",   "5. Paquetes oficiales de repositorio"),
        ("kde",        "6. Aplicaciones base KDE Plasma"),
        ("aur",        "7. Paquetes adicionales desde AUR"),
        ("docker_svc", "8. Configuración servicio Docker"),
        ("zsh",        "9. Oh My Zsh + Powerlevel10k"),
        ("node",       "10. Stack Node / pnpm / bun"),
        ("ai_codex",   "11. Codex CLI (@openai/codex)"),
        ("ai_claude",  "12. Claude Code CLI (nativo)"),
        ("ai_gemini",  "13. Gemini CLI (@google/gemini-cli)"),
        ("ai_opencode", "14. OpenCode CLI"),
        ("mbpwatch",   "15. MBP Watch diagnóstico (systemd)"),
        ("plasmoid",   "16. Plasmoid KDE MBP Watch"),
        ("youtube",    "17. YouTube Force H264"),
        ("apple",      "18. Apple laptop extras (MBP 2015)"),
        ("facetime",   "19. FaceTime HD camera (AUR)"),
        ("iwd",        "20. iwd backend para NetworkManager"),
        ("hyprland",   "21. Hyprland"),
        ("wifi",       "22. Configurar país/región Wi-Fi"),
        ("globalmenu", "23. Global Menu KDE (GTK + VS Code)"),
        ("hwaccel",    "24. Aceleración HW Chromium/Brave"),
        ("vaapi",      "25. VA-API Brave/Chromium Intel Broadwell"),
        ("btrfs",      "26. Snapshots BTRFS (Snapper)"),
    ]
    selected = checklist(stdscr, "Bootstrap CachyOS", items,
                         {"sync", "base_dev", "yay", "flatpak", "official", "kde", "aur", "docker_svc", "zsh", "node", "mbpwatch", "plasmoid"})
    if selected is None:
        return
    if not selected:
        msgbox(stdscr, "Bootstrap", "No se seleccionó ningún bloque.")
        return

    env_extra = {}
    ai_selected = {"ai_codex", "ai_claude", "ai_gemini", "ai_opencode"} & set(selected)
    
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
    target = inputbox(stdscr, title, "Destino del plasmoid:", "primary")
    if target is None:
        return
    run_op(stdscr, title, [command, "--target", target.strip() or "primary"])

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
        ("uninstall-watch",    "Desinstalar MBP Watch"),
        ("uninstall-plasmoid", "Desinstalar plasmoid MBP Watch"),
        ("reinstall-plasmoid", "Reinstalar plasmoid MBP Watch"),
        ("move-plasmoid",      "Mover plasmoid MBP Watch"),
        ("youtube",            "Instalar YouTube Force H264"),
        ("vaapi",              "VA-API Brave/Chromium (Intel Broadwell)"),
        ("exit",               "Salir"),
    ]
    while True:
        stdscr.clear()
        stdscr.refresh()
        idx = menu(stdscr, f"Linux Migration Tool v{VERSION}  [python]", items)
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
            run_op(stdscr, label, ["postcheck"])
        elif tag == "restore":
            flow_restore(stdscr)
        elif tag == "uninstall-watch":
            if yesno(stdscr, label, "¿Desinstalar MBP Watch completo?"):
                run_op(stdscr, label, ["uninstall-mbp-watch"])
        elif tag == "uninstall-plasmoid":
            if yesno(stdscr, label, "¿Desinstalar el plasmoid KDE MBP Watch?"):
                run_op(stdscr, label, ["uninstall-mbp-plasmoid"])
        elif tag == "reinstall-plasmoid":
            flow_plasmoid_op(stdscr, label, "reinstall-mbp-plasmoid")
        elif tag == "move-plasmoid":
            flow_plasmoid_op(stdscr, label, "move-mbp-plasmoid")
        elif tag == "youtube":
            if yesno(stdscr, label, "¿Instalar YouTube Force H264?"):
                run_op(stdscr, label, ["install-youtube-force-h264"])
        elif tag == "vaapi":
            if yesno(stdscr, label, "¿Aplicar corrección VA-API para Intel Broadwell?"):
                run_op(stdscr, label, ["configure-vaapi-brave"])

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
