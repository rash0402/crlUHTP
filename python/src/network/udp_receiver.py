"""
UDP Receiver for UHTP

Receives state updates from Julia Core.
"""

import socket
import threading
from typing import Optional, Callable
from collections import deque

from .protocol import UDPMessage, MESSAGE_SIZE


class UDPReceiver:
    """
    Non-blocking UDP receiver with message queue.
    """

    def __init__(
        self,
        port: int = 12345,
        host: str = "127.0.0.1",
        queue_size: int = 100
    ):
        """Initialize UDP receiver."""
        self.port = port
        self.host = host
        self.queue_size = queue_size

        # Socket
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind((host, port))
        self.socket.setblocking(False)

        # Message queue (thread-safe)
        self._queue: deque[UDPMessage] = deque(maxlen=queue_size)
        self._lock = threading.Lock()

        # Statistics
        self.receive_count = 0
        self.error_count = 0
        self.last_message: Optional[UDPMessage] = None

        # Receiver thread
        self._running = False
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        """Start receiver thread."""
        if self._running:
            return

        self._running = True
        self._thread = threading.Thread(target=self._receive_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        """Stop receiver thread."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=1.0)
            self._thread = None

    def _receive_loop(self) -> None:
        """Background receive loop."""
        while self._running:
            try:
                data, addr = self.socket.recvfrom(MESSAGE_SIZE + 64)
                msg = UDPMessage.from_bytes(data)
                if msg:
                    with self._lock:
                        self._queue.append(msg)
                        self.last_message = msg
                    self.receive_count += 1
            except BlockingIOError:
                # No data available
                pass
            except Exception:
                self.error_count += 1

    def get_latest(self) -> Optional[UDPMessage]:
        """Get the most recent message (non-blocking)."""
        with self._lock:
            return self.last_message

    def get_all(self) -> list[UDPMessage]:
        """Get all queued messages and clear queue."""
        with self._lock:
            messages = list(self._queue)
            self._queue.clear()
            return messages

    def close(self) -> None:
        """Close receiver and socket."""
        self.stop()
        self.socket.close()

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False
