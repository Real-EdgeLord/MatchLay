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
        self._start_empty_room_cleaner()
        logger.info("ENetRelay initialized")

    def _start_empty_room_cleaner(self):
        def cleaner():
            while self._running:
                time.sleep(30)
                with self._lock:
                    for port, count in list(self._peer_counts.items()):
                        if count == 0 and port in self.rooms:
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
        logger.info(f"Created ENet host for room on port {port}")

        def _service_loop():
            logger.info(f"Starting service loop for port {port}")
            while self._running and port in self.rooms:
                event = host.service(10)  # 10ms timeout
                if event.type == enet.EVENT_TYPE_NONE:
                    continue
                elif event.type == enet.EVENT_TYPE_CONNECT:
                    peer = event.peer
                    peer_addr = peer.address.host, peer.address.port
                    logger.info(f"ENet CONNECT event: peer {peer_addr} connected to port {port}")
                    with self._lock:
                        self.rooms[port][1][peer.address.port] = peer
                        self._peer_counts[port] = len(self.rooms[port][1])
                    logger.info(f"Room {port} now has {self._peer_counts[port]} peer(s)")
                elif event.type == enet.EVENT_TYPE_RECEIVE:
                    sender = event.peer.address.port
                    packet_data = event.packet.data
                    logger.info(f"ENet RECEIVE event: from peer {sender} on port {port}, data length {len(packet_data)}")
                    with self._lock:
                        for other_port, peer in self.rooms[port][1].items():
                            if other_port != sender:
                                logger.info(f"Forwarding packet from {sender} to peer {other_port}")
                                peer.send(event.channel_id, event.packet)
                elif event.type == enet.EVENT_TYPE_DISCONNECT:
                    peer = event.peer
                    peer_addr = peer.address.host, peer.address.port
                    logger.info(f"ENet DISCONNECT event: peer {peer_addr} disconnected from port {port}")
                    with self._lock:
                        if peer.address.port in self.rooms[port][1]:
                            del self.rooms[port][1][peer.address.port]
                            self._peer_counts[port] = len(self.rooms[port][1])
                    logger.info(f"Room {port} now has {self._peer_counts[port]} peer(s)")
            logger.info(f"Service loop for port {port} exiting")
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
        logger.info(f"Removing room on port {port}")
        with self._lock:
            if port in self.rooms:
                self.rooms[port][0].flush()
                del self.rooms[port]
            if port in self._peer_counts:
                del self._peer_counts[port]
            if port in self._loop_threads:
                # thread will exit on its own because self._running may be False or port gone
                pass

    def shutdown(self):
        logger.info("Shutting down ENetRelay")
        self._running = False
        time.sleep(0.5)
        with self._lock:
            for port in list(self.rooms.keys()):
                self.remove_room(port)
