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
        self._lock = threading.Lock()
        self._start_empty_room_cleaner()
        logger.info("ENetRelay initialized")

    def _start_empty_room_cleaner(self):
        def cleaner():
            while self._running:
                time.sleep(30)
                with self._lock:
                    for port in list(self.rooms.keys()):
                        if self._peer_counts.get(port, 0) == 0:
                            logger.info(f"Cleaning up empty room on port {port}")
                            self.remove_room(port)
        threading.Thread(target=cleaner, daemon=True).start()

    def create_room(self, port: int):
        if port in self.rooms:
            logger.warning(f"Room on port {port} already exists")
            return
        host = enet.Host(enet.Address(b"0.0.0.0", port), 10, 0, 0, 0)
        with self._lock:
            self.rooms[port] = (host, {})
            self._peer_counts[port] = 0

        def _service_loop():
            logger.info(f"Service loop for port {port} started")
            while self._running and port in self.rooms:
                event = host.service(10)
                if event.type == enet.EVENT_TYPE_NONE:
                    continue
                elif event.type == enet.EVENT_TYPE_CONNECT:
                    peer = event.peer
                    with self._lock:
                        self.rooms[port][1][peer.address.port] = peer
                        self._peer_counts[port] = len(self.rooms[port][1])
                    logger.info(f"Peer {peer.address.port} connected to {port} (count={self._peer_counts[port]})")
                elif event.type == enet.EVENT_TYPE_RECEIVE:
                    sender = event.peer.address.port
                    with self._lock:
                        for other_port, peer in self.rooms[port][1].items():
                            if other_port != sender:
                                peer.send(event.channel_id, event.packet)
                elif event.type == enet.EVENT_TYPE_DISCONNECT:
                    peer = event.peer
                    with self._lock:
                        if peer.address.port in self.rooms[port][1]:
                            del self.rooms[port][1][peer.address.port]
                            self._peer_counts[port] = len(self.rooms[port][1])
                    logger.info(f"Peer {peer.address.port} disconnected from {port} (count={self._peer_counts[port]})")
            logger.info(f"Service loop for port {port} exiting")
            with self._lock:
                if port in self.rooms:
                    host.flush()
                    del self.rooms[port]
                    if port in self._peer_counts:
                        del self._peer_counts[port]

        thread = threading.Thread(target=_service_loop, daemon=True)
        thread.start()
        logger.info(f"Created room on port {port}")

    def get_peer_count(self, port: int) -> int:
        with self._lock:
            return self._peer_counts.get(port, 0)

    def remove_room(self, port: int):
        with self._lock:
            if port not in self.rooms:
                return
            logger.info(f"Removing room on port {port}")
            # Mark the room for deletion; the service loop will exit because `port in self.rooms` becomes false.
            # To force the loop to exit quickly, we also set a flag.
            # The host will be cleaned up in the service loop after it exits.
            # No need to close the socket manually; just let the loop exit.
            # However, to avoid waiting for the full 10ms service timeout, we don't do anything special.
            # The room dictionary entry is removed, so the next iteration the loop will exit.
            # But we must ensure the host is not already processing a packet. This is safe.
            # The loop will see that `port not in self.rooms` and break.
            del self.rooms[port]
            if port in self._peer_counts:
                del self._peer_counts[port]

    def shutdown(self):
        logger.info("Shutting down ENetRelay")
        self._running = False
        # Wait a moment for all service loops to exit
        time.sleep(0.5)
        with self._lock:
            for port in list(self.rooms.keys()):
                self.remove_room(port)
