import enet
import logging
import threading
import time
from typing import Dict, Tuple

logger = logging.getLogger("matchmaker.enet")

class ENetRelay:
    def __init__(self):
        self.rooms: Dict[int, Tuple[enet.Host, Dict[int, enet.Peer], threading.Thread]] = {}
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
                            logger.info(f"Empty room on port {port} – removing")
                            self.remove_room(port)
        threading.Thread(target=cleaner, daemon=True).start()

    def create_room(self, port: int):
        if port in self.rooms:
            logger.warning(f"Room on port {port} already exists")
            return
        try:
            host = enet.Host(enet.Address(b"0.0.0.0", port), 10, 0, 0, 0)
        except Exception as e:
            logger.error(f"Failed to create ENet host on port {port}: {e}")
            return
        with self._lock:
            self.rooms[port] = (host, {}, None)
            self._peer_counts[port] = 0

        def _service_loop():
            logger.info(f"Service loop for port {port} started")
            while self._running and port in self.rooms:
                try:
                    event = host.service(10)  # 10ms timeout
                except Exception as e:
                    logger.error(f"ENet service error on port {port}: {e}")
                    break
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
                                try:
                                    peer.send(event.channel_id, event.packet)
                                except Exception as e:
                                    logger.error(f"Failed to send packet from {sender} to {other_port}: {e}")
                elif event.type == enet.EVENT_TYPE_DISCONNECT:
                    peer = event.peer
                    with self._lock:
                        if peer.address.port in self.rooms[port][1]:
                            del self.rooms[port][1][peer.address.port]
                            self._peer_counts[port] = len(self.rooms[port][1])
                    logger.info(f"Peer {peer.address.port} disconnected from {port} (count={self._peer_counts[port]})")
            # Exit loop – clean up
            with self._lock:
                if port in self.rooms:
                    host.flush()
                    del self.rooms[port]
                    if port in self._peer_counts:
                        del self._peer_counts[port]
            logger.info(f"Service loop for port {port} finished")

        thread = threading.Thread(target=_service_loop, daemon=True)
        thread.start()
        with self._lock:
            # store the thread
            host, peers, _ = self.rooms[port]
            self.rooms[port] = (host, peers, thread)
        logger.info(f"Room on port {port} created successfully")

    def get_peer_count(self, port: int) -> int:
        with self._lock:
            return self._peer_counts.get(port, 0)

    def remove_room(self, port: int):
        with self._lock:
            if port not in self.rooms:
                return
            logger.info(f"Removing room on port {port}")
            # mark it as gone; the service loop will exit on its own
            # we don't close the host here to avoid freezing
            # the loop will see that port is no longer in self.rooms and break
            del self.rooms[port]
            if port in self._peer_counts:
                del self._peer_counts[port]

    def shutdown(self):
        logger.info("Shutting down ENetRelay")
        self._running = False
        time.sleep(0.5)
        with self._lock:
            for port in list(self.rooms.keys()):
                self.remove_room(port)
