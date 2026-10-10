#!/usr/bin/env python3
import argparse
import socket
import threading
import time

BUF = 65535
UDP_TIMEOUT = 120


def tcp_pipe(a, b):
    try:
        while True:
            data = a.recv(BUF)
            if not data:
                break
            b.sendall(data)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.close()
            except OSError:
                pass


def tcp_forward(port, target):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("127.0.0.1", port))
    except OSError as e:
        print(f"TCP 127.0.0.1:{port}: skip ({e})", flush=True)
        return
    srv.listen(64)
    print(f"TCP 127.0.0.1:{port} -> {target}:{port}", flush=True)
    while True:
        cli, _ = srv.accept()
        try:
            up = socket.create_connection((target, port), timeout=10)
        except OSError:
            cli.close()
            continue
        threading.Thread(target=tcp_pipe, args=(cli, up), daemon=True).start()
        threading.Thread(target=tcp_pipe, args=(up, cli), daemon=True).start()


def udp_forward(port, target):
    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        srv.bind(("127.0.0.1", port))
    except OSError as e:
        print(f"UDP 127.0.0.1:{port}: skip ({e})", flush=True)
        return
    print(f"UDP 127.0.0.1:{port} -> {target}:{port}", flush=True)
    out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    peer = [None, 0.0]
    lock = threading.Lock()

    def from_client():
        while True:
            try:
                data, addr = srv.recvfrom(BUF)
            except OSError:
                return
            with lock:
                peer[0], peer[1] = addr, time.time()
            try:
                out.sendto(data, (target, port))
            except OSError:
                pass

    def from_server():
        while True:
            try:
                resp, _ = out.recvfrom(BUF)
            except OSError:
                return
            with lock:
                dst = peer[0]
            if dst:
                try:
                    srv.sendto(resp, dst)
                except OSError:
                    pass

    threading.Thread(target=from_client, daemon=True).start()
    threading.Thread(target=from_server, daemon=True).start()
    while True:
        time.sleep(UDP_TIMEOUT)
        with lock:
            if peer[0] and time.time() - peer[1] > UDP_TIMEOUT:
                peer[0] = None


def parse_ports(spec):
    ports = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            ports.update(range(int(a), int(b) + 1))
        else:
            ports.add(int(part))
    return sorted(ports)


def main():
    ap = argparse.ArgumentParser(description="StarConflict player-side forwarder")
    ap.add_argument("--target", required=True, help="белый IP сервера (как на экране логина)")
    ap.add_argument("--tcp", default="3815,3850,3800-3830,9000-9010,35000-35099")
    ap.add_argument("--udp", default="3815,3850,3800-3830,9000-9010,35000-35099")
    args = ap.parse_args()
    for p in parse_ports(args.tcp):
        threading.Thread(target=tcp_forward, args=(p, args.target), daemon=True).start()
    for p in parse_ports(args.udp):
        threading.Thread(target=udp_forward, args=(p, args.target), daemon=True).start()
    print("ready, Ctrl+C to stop", flush=True)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
