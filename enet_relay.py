# enet_relay.py
import asyncio
import threading
import enet
import logging
from typing import Dict, Tuple

logger = logging.getLogger("matchmaker.enet")

class ENetRelay:
    """Manages ENet hosts and forwards packets between peers in the same room."""
    def __init__(self):
        # Map each room's UDP port to its ENet host object and a dict of connected peers
        self.rooms: Dict[int, Tuple[enet.Host, Dict[int, enet.Peer]]] = {}
        self._running = True
        self._loop_threads: Dict[int, threading.Thread] = {}

    def create_room(self, port: int):
        """Start an ENet host for a new room."""
        if port in self.rooms:
            logger.warning(f"ENet host for port {port} already exists.")
            return

        host = enet.Host(enet.Address(b"0.0.0.0", port), 10, 0, 0, 0)
        self.rooms[port] = (host, {})
        logger.info(f"ENet relay started for room on port {port}")

        # Start the host's service loop in its own thread
        def _service_loop():
            while self._running and port in self.rooms:
                event = host.service(10)  # 10ms timeout
                if event.type == enet.EVENT_TYPE_CONNECT:
                    peer = event.peer
                    self.rooms[port][1][peer.address.port] = peer
                    logger.info(f"Peer {peer.address.port} connected to room on port {port}")
                elif event.type == enet.EVENT_TYPE_RECEIVE:
                    # Forward the packet to all other peers in the same room
                    sender_port = event.peer.address.port
                    for port, peer in self.rooms[port][1].items():
                        if port != sender_port:
                            peer.send(event.channel_id, event.packet)
                elif event.type == enet.EVENT_TYPE_DISCONNECT:
                    peer = event.peer
                    del self.rooms[port][1][peer.address.port]
                    logger.info(f"Peer {peer.address.port} disconnected from room on port {port}")
            if port in self.rooms:
                host.flush()
                del self.rooms[port]

        thread = threading.Thread(target=_service_loop, daemon=True)
        thread.start()
        self._loop_threads[port] = thread

    def remove_room(self, port: int):
        """Stop and clean up the ENet host for a room."""
        if port not in self.rooms:
            return
        logger.info(f"Stopping ENet relay for room on port {port}")
        self.rooms[port][0].flush()
        del self.rooms[port]
        if port in self._loop_threads:
            self._loop_threads[port].join(timeout=1)

    def shutdown(self):
        """Stop all ENet hosts."""
        self._running = False
        for port in list(self.rooms.keys()):
            self.remove_room(port)
