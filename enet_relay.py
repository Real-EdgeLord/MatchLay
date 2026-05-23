# enet_relay.py
import enet
import logging
import threading
import time
from typing import Dict, Tuple

logger = logging.getLogger("matchmaker.enet")

class ENetRelay:
    def __init__(self):
        self.rooms: Dict[int, Tuple[enet.Host, Dict[int, enet.Peer]]] = {}
        self._peer_counts: Dict[int, int] = {}
        self._running = True
        self._loop_threads: Dict[int, threading.Thread] = {}
        self._lock = threading.Lock()
        # Start the empty‑room cleaner thread
        self._start_empty_room_cleaner()

    def _start_empty_room_cleaner(self):
        def cleaner():
            while self._running:
                time.sleep(30)  # Check every 30 seconds
                with self._lock:
                    for port in list(self.rooms.keys()):
                        if self._peer_counts.get(port, 0) == 0:
                            logger.info(f"Room on port {port} has no peers, cleaning up")
                            self.remove_room(port)
        thread = threading.Thread(target=cleaner, daemon=True)
        thread.start()

    def create_room(self, port: int):
        if port in self.rooms:
            logger.warning(f"ENet host for port {port} already exists.")
            return
        host = enet.Host(enet.Address(b"0.0.0.0", port), 10, 0, 0, 0)
        with self._lock:
            self.rooms[port] = (host, {})
            self._peer_counts[port] = 0
        logger.info(f"ENet relay started for room on port {port}")

        def _service_loop():
            while self._running and port in self.rooms:
                event = host.service(10)  # 10ms timeout
                if event.type == enet.EVENT_TYPE_CONNECT:
                    peer = event.peer
                    with self._lock:
                        self.rooms[port][1][peer.address.port] = peer
                        self._peer_counts[port] = len(self.rooms[port][1])
                    logger.info(f"Peer {peer.address.port} connected to room on port {port} (count={self._peer_counts[port]})")
                elif event.type == enet.EVENT_TYPE_RECEIVE:
                    sender_port = event.peer.address.port
                    with self._lock:
                        for other_port, peer in self.rooms[port][1].items():
                            if other_port != sender_port:
                                peer.send(event.channel_id, event.packet)
                elif event.type == enet.EVENT_TYPE_DISCONNECT:
                    peer = event.peer
                    with self._lock:
                        if peer.address.port in self.rooms[port][1]:
                            del self.rooms[port][1][peer.address.port]
                            self._peer_counts[port] = len(self.rooms[port][1])
                    logger.info(f"Peer {peer.address.port} disconnected from room on port {port} (count={self._peer_counts[port]})")
            if port in self.rooms:
                host.flush()
                with self._lock:
                    del self.rooms[port]
                    del self._peer_counts[port]

        thread = threading.Thread(target=_service_loop, daemon=True)
        thread.start()
        with self._lock:
            self._loop_threads[port] = thread

    def get_peer_count(self, port: int) -> int:
        with self._lock:
            return self._peer_counts.get(port, 0)

    def remove_room(self, port: int):
        if port not in self.rooms:
            return
        logger.info(f"Stopping ENet relay for room on port {port}")
        with self._lock:
            if port in self.rooms:
                self.rooms[port][0].flush()
                del self.rooms[port]
            if port in self._peer_counts:
                del self._peer_counts[port]
            if port in self._loop_threads:
                # Thread will exit because self._running becomes False
                pass

    def shutdown(self):
        self._running = False
        # Wait a bit for threads to finish
        time.sleep(0.5)
        with self._lock:
            for port in list(self.rooms.keys()):
                self.remove_room(port)


    def register_host(self, port: int) -> None:
        with self._lock:
            if port in self._peer_counts:
            # Increment count by 1 (host counts as one player)
                self._peer_counts[port] += 1
            else:
                self._peer_counts[port] = 1
            logger.info(f"Manually registered host for room on port {port}, count={self._peer_counts[port]}")