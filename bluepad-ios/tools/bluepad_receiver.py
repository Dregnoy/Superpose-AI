#!/usr/bin/env python3
"""
BluePad Local Wi-Fi Receiver (Zero-Cloud, Zero External Dependencies).
Listens on local TCP port 8765 (and broadcasts UDP discovery beacons on port 8766)
so BluePad iOS can control a Windows PC over the same Wi-Fi/LAN with a PIN.
"""

from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import json
import platform
import secrets
import socket
import threading
import time

DEFAULT_TCP_PORT = 8765
DISCOVERY_UDP_PORT = 8766

# ---------------------------------------------------------------------------
# Windows user32.dll SendInput Bindings
# ---------------------------------------------------------------------------

INPUT_MOUSE = 0
INPUT_KEYBOARD = 1

MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_XDOWN = 0x0080
MOUSEEVENTF_XUP = 0x0100
MOUSEEVENTF_WHEEL = 0x0800
MOUSEEVENTF_HWHEEL = 0x1000

XBUTTON1 = 0x0001
XBUTTON2 = 0x0002

KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004

ULONG_PTR = ctypes.c_uint64 if ctypes.sizeof(ctypes.c_void_p) == 8 else ctypes.c_uint32


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [
        ("uMsg", wintypes.DWORD),
        ("wParamL", wintypes.WORD),
        ("wParamH", wintypes.WORD),
    ]


class _INPUT_UNION(ctypes.Union):
    _fields_ = [
        ("mi", MOUSEINPUT),
        ("ki", KEYBDINPUT),
        ("hi", HARDWAREINPUT),
    ]


class INPUT(ctypes.Structure):
    _anonymous_ = ("_u",)
    _fields_ = [
        ("type", wintypes.DWORD),
        ("_u", _INPUT_UNION),
    ]


IS_WINDOWS = platform.system().lower() == "windows"
if IS_WINDOWS:
    _user32 = ctypes.WinDLL("user32", use_last_error=True)
    _SendInput = _user32.SendInput
    _SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int)
    _SendInput.restype = wintypes.UINT
else:
    _SendInput = None


def send_inputs(items: list[INPUT]) -> None:
    if not items or _SendInput is None:
        return
    arr = (INPUT * len(items))(*items)
    _SendInput(len(items), arr, ctypes.sizeof(INPUT))


def make_mouse_input(dx: int = 0, dy: int = 0, data: int = 0, flags: int = 0) -> INPUT:
    return INPUT(
        type=INPUT_MOUSE,
        mi=MOUSEINPUT(dx=dx, dy=dy, mouseData=data, dwFlags=flags, time=0, dwExtraInfo=0),
    )


def make_key_input(vk: int = 0, scan: int = 0, flags: int = 0) -> INPUT:
    return INPUT(
        type=INPUT_KEYBOARD,
        ki=KEYBDINPUT(wVk=vk, wScan=scan, dwFlags=flags, time=0, dwExtraInfo=0),
    )


# USB HID Usage Page 0x07 -> Windows Virtual Key (VK_*)
HID_TO_VK: dict[int, int] = {
    **{0x04 + i: ord("A") + i for i in range(26)},
    0x1E: 0x31, 0x1F: 0x32, 0x20: 0x33, 0x21: 0x34, 0x22: 0x35,
    0x23: 0x36, 0x24: 0x37, 0x25: 0x38, 0x26: 0x39, 0x27: 0x30,
    0x28: 0x0D,  # Enter
    0x29: 0x1B,  # Escape
    0x2A: 0x08,  # Backspace
    0x2B: 0x09,  # Tab
    0x2C: 0x20,  # Space
    0x2D: 0xBD,  # OEM_MINUS
    0x2E: 0xBB,  # OEM_PLUS
    0x2F: 0xDB,  # OEM_4
    0x30: 0xDD,  # OEM_6
    0x31: 0xDC,  # OEM_5
    0x33: 0xBA,  # OEM_1
    0x34: 0xDE,  # OEM_7
    0x35: 0xC0,  # OEM_3
    0x36: 0xBC,  # OEM_COMMA
    0x37: 0xBE,  # OEM_PERIOD
    0x38: 0xBF,  # OEM_2
    0x39: 0x14,  # Caps Lock
    **{0x3A + i: 0x70 + i for i in range(12)},  # F1..F12
    0x46: 0x2C,  # Print Screen
    0x47: 0x91,  # Scroll Lock
    0x48: 0x13,  # Pause
    0x49: 0x2D,  # Insert
    0x4A: 0x24,  # Home
    0x4B: 0x21,  # Page Up
    0x4C: 0x2E,  # Delete
    0x4D: 0x23,  # End
    0x4E: 0x22,  # Page Down
    0x4F: 0x27,  # Right
    0x50: 0x25,  # Left
    0x51: 0x28,  # Down
    0x52: 0x26,  # Up
    0x53: 0x90,  # Num Lock
    0x54: 0x6F,  # Numpad /
    0x55: 0x6A,  # Numpad *
    0x56: 0x6D,  # Numpad -
    0x57: 0x6B,  # Numpad +
    0x58: 0x0D,  # Numpad Enter
    0x59: 0x61, 0x5A: 0x62, 0x5B: 0x63, 0x5C: 0x64, 0x5D: 0x65,
    0x5E: 0x66, 0x5F: 0x67, 0x60: 0x68, 0x61: 0x69, 0x62: 0x60,
    0x63: 0x6E,  # Numpad .
    0x64: 0xE2,  # Non-US Backslash
    0x65: 0x5D,  # Apps / Menu
}

EXTENDED_HIDS = {0x46, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x54, 0x58, 0x65}

MODIFIER_VKS: list[tuple[int, int, bool]] = [
    (1 << 0, 0xA2, False),  # LControl
    (1 << 1, 0xA0, False),  # LShift
    (1 << 2, 0xA4, False),  # LAlt
    (1 << 3, 0x5B, True),   # LWin
    (1 << 4, 0xA3, True),   # RControl
    (1 << 5, 0xA1, True),   # RShift
    (1 << 6, 0xA5, True),   # RAlt / AltGr
    (1 << 7, 0x5C, True),   # RWin
]

CONSUMER_TO_VK: dict[int, int] = {
    0x00B3: 0xB0,  # FastForward -> Next Track fallback
    0x00B4: 0xB1,  # Rewind -> Prev Track fallback
    0x00B5: 0xB0,  # VK_MEDIA_NEXT_TRACK
    0x00B6: 0xB1,  # VK_MEDIA_PREV_TRACK
    0x00B7: 0xB2,  # VK_MEDIA_STOP
    0x00CD: 0xB3,  # VK_MEDIA_PLAY_PAUSE
    0x00E2: 0xAD,  # VK_VOLUME_MUTE
    0x00E9: 0xAF,  # VK_VOLUME_UP
    0x00EA: 0xAE,  # VK_VOLUME_DOWN
    0x0221: 0xAA,  # VK_BROWSER_SEARCH
    0x0223: 0xAC,  # VK_BROWSER_HOME
    0x0224: 0xA6,  # VK_BROWSER_BACK
    0x0225: 0xA7,  # VK_BROWSER_FORWARD
    0x0227: 0xA8,  # VK_BROWSER_REFRESH
}


class InputInjector:
    def __init__(self) -> None:
        self.pressed_mouse_mask = 0
        self.prev_gamepad_buttons = 0
        self.prev_gamepad_hat = 8

    def handle_event(self, evt: dict) -> None:
        kind = evt.get("t")
        if kind == "m":
            self._handle_mouse_move(evt)
        elif kind == "mb":
            self._handle_mouse_button(int(evt.get("b", 0)), bool(evt.get("p", False)))
        elif kind == "mc":
            btn = int(evt.get("b", 0))
            self._handle_mouse_button(btn, True)
            self._handle_mouse_button(btn, False)
        elif kind == "k":
            self._tap_key(int(evt.get("c", 0)), int(evt.get("m", 0)))
        elif kind == "txt":
            self._type_unicode(str(evt.get("s", "")), bool(evt.get("e", False)))
        elif kind == "c":
            self._tap_consumer(int(evt.get("u", 0)))
        elif kind == "s":
            self._tap_system(int(evt.get("u", 0)))
        elif kind == "g":
            self._handle_gamepad(evt)
        elif kind == "rel":
            self.release_all()

    def release_all(self) -> None:
        if self.pressed_mouse_mask:
            for bit in range(5):
                mask = 1 << bit
                if self.pressed_mouse_mask & mask:
                    self._handle_mouse_button(mask, False)
            self.pressed_mouse_mask = 0
        events = [
            make_key_input(vk=vk, flags=(KEYEVENTF_KEYUP | (KEYEVENTF_EXTENDEDKEY if ext else 0)))
            for _, vk, ext in MODIFIER_VKS
        ]
        send_inputs(events)

    def _handle_mouse_move(self, evt: dict) -> None:
        dx = int(evt.get("dx", 0))
        dy = int(evt.get("dy", 0))
        wheel = int(evt.get("w", 0))
        hwheel = int(evt.get("hw", 0))
        events: list[INPUT] = []
        if dx != 0 or dy != 0:
            events.append(make_mouse_input(dx=dx, dy=dy, flags=MOUSEEVENTF_MOVE))
        if wheel != 0:
            events.append(make_mouse_input(data=(wheel * 120) & 0xFFFFFFFF, flags=MOUSEEVENTF_WHEEL))
        if hwheel != 0:
            events.append(make_mouse_input(data=(hwheel * 120) & 0xFFFFFFFF, flags=MOUSEEVENTF_HWHEEL))
        send_inputs(events)

    def _handle_mouse_button(self, mask: int, pressed: bool) -> None:
        events: list[INPUT] = []
        if mask & (1 << 0):
            events.append(make_mouse_input(flags=MOUSEEVENTF_LEFTDOWN if pressed else MOUSEEVENTF_LEFTUP))
        if mask & (1 << 1):
            events.append(make_mouse_input(flags=MOUSEEVENTF_RIGHTDOWN if pressed else MOUSEEVENTF_RIGHTUP))
        if mask & (1 << 2):
            events.append(make_mouse_input(flags=MOUSEEVENTF_MIDDLEDOWN if pressed else MOUSEEVENTF_MIDDLEUP))
        if mask & (1 << 3):
            events.append(make_mouse_input(data=XBUTTON1, flags=MOUSEEVENTF_XDOWN if pressed else MOUSEEVENTF_XUP))
        if mask & (1 << 4):
            events.append(make_mouse_input(data=XBUTTON2, flags=MOUSEEVENTF_XDOWN if pressed else MOUSEEVENTF_XUP))
        if pressed:
            self.pressed_mouse_mask |= mask
        else:
            self.pressed_mouse_mask &= ~mask
        send_inputs(events)

    def _tap_key(self, hid_code: int, modifiers: int) -> None:
        events: list[INPUT] = []
        active_mods: list[tuple[int, bool]] = []
        for bit, vk, ext in MODIFIER_VKS:
            if modifiers & bit:
                active_mods.append((vk, ext))
                events.append(make_key_input(vk=vk, flags=KEYEVENTF_EXTENDEDKEY if ext else 0))

        # Handle AltGr (Right Alt) -> Win32 typically expects AltGr key or LCtrl+RAlt depending on layout
        vk = HID_TO_VK.get(hid_code, 0)
        if vk:
            kflag = KEYEVENTF_EXTENDEDKEY if hid_code in EXTENDED_HIDS else 0
            events.append(make_key_input(vk=vk, flags=kflag))
            events.append(make_key_input(vk=vk, flags=kflag | KEYEVENTF_KEYUP))

        for vk_mod, ext in reversed(active_mods):
            events.append(make_key_input(vk=vk_mod, flags=KEYEVENTF_KEYUP | (KEYEVENTF_EXTENDEDKEY if ext else 0)))
        send_inputs(events)

    def _type_unicode(self, text: str, append_enter: bool) -> None:
        events: list[INPUT] = []
        normalized = text.replace("\r\n", "\n").replace("\r", "\n")
        for ch in normalized:
            if ch == "\n":
                events.append(make_key_input(vk=0x0D))
                events.append(make_key_input(vk=0x0D, flags=KEYEVENTF_KEYUP))
            elif ch == "\t":
                events.append(make_key_input(vk=0x09))
                events.append(make_key_input(vk=0x09, flags=KEYEVENTF_KEYUP))
            else:
                raw = ch.encode("utf-16-le")
                for i in range(0, len(raw), 2):
                    code_unit = int.from_bytes(raw[i:i + 2], "little")
                    events.append(make_key_input(scan=code_unit, flags=KEYEVENTF_UNICODE))
                    events.append(make_key_input(scan=code_unit, flags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP))
        if append_enter:
            events.append(make_key_input(vk=0x0D))
            events.append(make_key_input(vk=0x0D, flags=KEYEVENTF_KEYUP))
        send_inputs(events)

    def _tap_consumer(self, usage: int) -> None:
        vk = CONSUMER_TO_VK.get(usage)
        if vk:
            send_inputs([
                make_key_input(vk=vk, flags=KEYEVENTF_EXTENDEDKEY),
                make_key_input(vk=vk, flags=KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP),
            ])

    def _tap_system(self, bits: int) -> None:
        if bits & 0x01:
            send_inputs([make_key_input(vk=0x5F), make_key_input(vk=0x5F, flags=KEYEVENTF_KEYUP)])

    def _handle_gamepad(self, evt: dict) -> None:
        # Keyboard/mouse fallback so the Gamepad tab works on PC immediately without extra drivers.
        lx = int(evt.get("lx", 0))
        ly = int(evt.get("ly", 0))
        rx = int(evt.get("rx", 0))
        ry = int(evt.get("ry", 0))
        hat = int(evt.get("h", 8))
        buttons = int(evt.get("b", 0))

        # Camera look via Right Analog -> Mouse delta
        if abs(rx) > 12 or abs(ry) > 12:
            self._handle_mouse_move({"dx": int(rx / 10), "dy": int(ry / 10)})
        elif abs(lx) > 35 or abs(ly) > 35:
            # Left Analog also nudges arrow keys / scroll lightly when pushed hard
            pass

        if hat != self.prev_gamepad_hat:
            hat_to_vk = {
                0: [0x26],              # Up
                1: [0x26, 0x27],        # UpRight
                2: [0x27],              # Right
                3: [0x28, 0x27],        # DownRight
                4: [0x28],              # Down
                5: [0x28, 0x25],        # DownLeft
                6: [0x25],              # Left
                7: [0x26, 0x25],        # UpLeft
            }
            old_vks = set(hat_to_vk.get(self.prev_gamepad_hat, []))
            new_vks = set(hat_to_vk.get(hat, []))
            evts: list[INPUT] = []
            for vk in old_vks - new_vks:
                evts.append(make_key_input(vk=vk, flags=KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP))
            for vk in new_vks - old_vks:
                evts.append(make_key_input(vk=vk, flags=KEYEVENTF_EXTENDEDKEY))
            send_inputs(evts)
            self.prev_gamepad_hat = hat

        btn_map = {
            1 << 0: 0x20,  # A -> Space
            1 << 1: 0x1B,  # B -> Esc
            1 << 2: 0x45,  # X -> E
            1 << 3: 0x52,  # Y -> R
            1 << 9: 0x0D,  # Start -> Enter
        }
        changed = buttons ^ self.prev_gamepad_buttons
        if changed:
            evts = []
            for mask, vk in btn_map.items():
                if changed & mask:
                    if buttons & mask:
                        evts.append(make_key_input(vk=vk))
                    else:
                        evts.append(make_key_input(vk=vk, flags=KEYEVENTF_KEYUP))
            send_inputs(evts)
        self.prev_gamepad_buttons = buttons


def get_primary_local_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 80))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def beacon_loop(stop_event: threading.Event, host_name: str, local_ip: str, tcp_port: int) -> None:
    payload = json.dumps({
        "type": "bluepad_host",
        "name": host_name,
        "ip": local_ip,
        "port": tcp_port,
        "os": platform.system(),
    }).encode("utf-8")

    targets = ["255.255.255.255"]
    parts = local_ip.split(".")
    if len(parts) == 4 and local_ip != "127.0.0.1":
        directed = f"{parts[0]}.{parts[1]}.{parts[2]}.255"
        if directed not in targets:
            targets.append(directed)

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        while not stop_event.is_set():
            for dst in targets:
                try:
                    sock.sendto(payload, (dst, DISCOVERY_UDP_PORT))
                except OSError:
                    pass
            stop_event.wait(2.0)


def handle_client(conn: socket.socket, addr: tuple[str, int], expected_pin: str, host_name: str) -> None:
    injector = InputInjector()
    authenticated = False
    buf = b""
    print(f"[+] iPhone baglandi: {addr[0]}:{addr[1]}", flush=True)
    try:
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                raw_line, buf = buf.split(b"\n", 1)
                if not raw_line.strip():
                    continue
                try:
                    msg = json.loads(raw_line.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue

                if not authenticated:
                    if msg.get("t") == "auth" and str(msg.get("pin", "")).strip() == expected_pin:
                        authenticated = True
                        client_name = msg.get("name", "BluePad")
                        resp = json.dumps({"t": "ok", "host": host_name, "os": platform.system()}) + "\n"
                        conn.sendall(resp.encode("utf-8"))
                        print(f"[OK] Oturum dogrulandi: {client_name} ({addr[0]})", flush=True)
                    else:
                        resp = json.dumps({"t": "err", "msg": "PIN hatali"}) + "\n"
                        conn.sendall(resp.encode("utf-8"))
                        print(f"[!] Hatali PIN denemesi: {addr[0]}", flush=True)
                        return
                else:
                    injector.handle_event(msg)
    except OSError:
        pass
    finally:
        injector.release_all()
        conn.close()
        print(f"[-] Baglanti kapandi: {addr[0]}:{addr[1]}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="BluePad Local Wi-Fi HID Receiver (Zero-Cloud)")
    parser.add_argument("--port", type=int, default=DEFAULT_TCP_PORT, help="TCP dinleme portu (varsayilan: 8765)")
    parser.add_argument("--pin", type=str, default=None, help="Ozel 4 haneli PIN (bos birakilirsa rastgele)")
    args = parser.parse_args()

    pin = args.pin.strip() if args.pin else f"{secrets.randbelow(9000) + 1000}"
    host_name = socket.gethostname() or "Windows PC"
    local_ip = get_primary_local_ip()
    qr_uri = f"bluepad://{local_ip}:{args.port}/{pin}"

    print("=" * 58, flush=True)
    print("  BluePad Yerel Wi-Fi Alicisi (Sifir Bulut / Sifir Telemetri)", flush=True)
    print("=" * 58, flush=True)
    print(f"  Bilgisayar : {host_name} ({platform.system()})", flush=True)
    print(f"  IP Adresi  : {local_ip}", flush=True)
    print(f"  TCP Port   : {args.port}", flush=True)
    print(f"  PIN Kodu   : {pin}", flush=True)
    print(f"  QR / URI   : {qr_uri}", flush=True)
    if not IS_WINDOWS:
        print("  [!] Uyari: SendInput yalnizca Windows uzerinde giris enjekte eder.", flush=True)
    print("-" * 58, flush=True)
    print("  iPhone BluePad -> Baglanti -> Wi-Fi Yerel Ag kartindan baglanin.", flush=True)
    print("  Cikmak icin Ctrl+C basin.", flush=True)
    print("=" * 58, flush=True)

    stop_event = threading.Event()
    beacon_thread = threading.Thread(
        target=beacon_loop,
        args=(stop_event, host_name, local_ip, args.port),
        daemon=True,
    )
    beacon_thread.start()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", args.port))
    server.listen(4)
    server.settimeout(1.0)

    try:
        while True:
            try:
                conn, addr = server.accept()
            except socket.timeout:
                continue
            threading.Thread(
                target=handle_client,
                args=(conn, addr, pin, host_name),
                daemon=True,
            ).start()
    except KeyboardInterrupt:
        print("\nKapatiliyor...")
    finally:
        stop_event.set()
        server.close()


if __name__ == "__main__":
    main()
