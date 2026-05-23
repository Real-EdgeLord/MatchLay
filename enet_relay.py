import enet
import logging
import threading
from typing import Dict, Tuple

logger = logging.getLogger("matchmaker.enet")

class ENetRelay:
    def __init__(self):
        self.rooms: Dict[int, Tuple[enet.Host, Dict[int, enet.Peer]]] = {}
        self._running = True
        self._loop_threads: Dict[int, threading.Thread] = {}

    def create_room(self, port: int):
        if port in self.rooms:
            logger.warning(f"ENet host for port {port} already exists.")
            return
        host = enet.Host(enet.Address(b"0.0.0.0", port), 10, 0, 0, 0)
        self.rooms[port] = (host, {})
        logger.info(f"ENet relay started for room on port {port}")

        def _service_loop():
            while self._running and port in self.rooms:
                event = host.service(10)  # 10ms timeout
                if event.type == enet.EVENT_TYPE_CONNECT:
                    peer = event.peer
                    self.rooms[port][1][peer.address.port] = peer
                    logger.info(f"Peer {peer.address.port} connected to room on port {port}")
                elif event.type == enet.EVENT_TYPE_RECEIVE:
                    sender_port = event.peer.address.port
                    for other_port, peer in self.rooms[port][1].items():
                        if other_port != sender_port:
                            peer.send(event.channel_id, event.packet)
                elif event.type == enet.EVENT_TYPE_DISCONNECT:
                    peer = event.peer
                    if peer.address.port in self.rooms[port][1]:
                        del self.rooms[port][1][peer.address.port]
                        logger.info(f"Peer {peer.address.port} disconnected from room on port {port}")
            if port in self.rooms:
                host.flush()
                del self.rooms[port]

        thread = threading.Thread(target=_service_loop, daemon=True)
        thread.start()
        self._loop_threads[port] = thread

    def remove_room(self, port: int):
        if port not in self.rooms:
            return
        logger.info(f"Stopping ENet relay for room on port {port}")
        self.rooms[port][0].flush()
        del self.rooms[port]
        if port in self._loop_threads:
            self._loop_threads[port].join(timeout=1)

    def shutdown(self):
        self._running = False
        for port in list(self.rooms.keys()):
            self.remove_room(port)
