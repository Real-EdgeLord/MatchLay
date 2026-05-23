import enet
import logging
import threading
from typing import Dict, Tuple

logger = logging.getLogger("matchmaker.enet")

class ENetRelay:
    # Add a background thread in __init__ to monitor empty rooms
    def __init__(self):
        # ... existing code ...
        self._empty_room_cleanup_interval = 30  # seconds
        self._start_empty_room_cleaner()

    def _start_empty_room_cleaner(self):
        def cleaner():
            while self._running:
                time.sleep(self._empty_room_cleanup_interval)
                with self._lock:
                    for port, count in list(self._peer_counts.items()):
                        if count == 0 and port in self.rooms:
                            logger.info(f"Room on port {port} has no peers, cleaning up")
                            self.remove_room(port)
        threading.Thread(target=cleaner, daemon=True).start()

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
        self._loop_threads[port] = thread

    def get_peer_count(self, port: int) -> int:
        with self._lock:
            return self._peer_counts.get(port, 0)

    def remove_room(self, port: int):
        if port not in self.rooms:
            return
        logger.info(f"Stopping ENet relay for room on port {port}")
        self.rooms[port][0].flush()
        with self._lock:
            if port in self.rooms:
                del self.rooms[port]
            if port in self._peer_counts:
                del self._peer_counts[port]
        if port in self._loop_threads:
            self._loop_threads[port].join(timeout=1)

    def shutdown(self):
        self._running = False
        for port in list(self.rooms.keys()):
            self.remove_room(port)
