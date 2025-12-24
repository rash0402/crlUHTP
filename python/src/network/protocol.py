"""
UDP Message Protocol for UHTP

Binary format (little-endian, 64 bytes total):
- timestamp_us: Float64 (8 bytes)
- cursor_x: Float64 (8 bytes)
- cursor_y: Float64 (8 bytes)
- cursor_vx: Float64 (8 bytes)
- cursor_vy: Float64 (8 bytes)
- target_x: Float64 (8 bytes)
- target_y: Float64 (8 bytes)
- task_state: UInt32 (4 bytes)
- trial_number: UInt32 (4 bytes)
"""

import struct
from dataclasses import dataclass
from enum import IntEnum
from typing import Optional


class TaskState(IntEnum):
    """Task state enumeration."""
    IDLE = 0
    RUNNING = 1
    PAUSED = 2
    COMPLETED = 3
    FAILED = 4


MESSAGE_SIZE = 64
MESSAGE_FORMAT = '<dddddddII'  # little-endian: 7 doubles + 2 uint32


@dataclass
class UDPMessage:
    """UDP message structure."""
    timestamp_us: float
    cursor_x: float
    cursor_y: float
    cursor_vx: float
    cursor_vy: float
    target_x: float
    target_y: float
    task_state: TaskState
    trial_number: int

    @classmethod
    def from_bytes(cls, data: bytes) -> Optional['UDPMessage']:
        """Parse UDP message from bytes."""
        if len(data) < MESSAGE_SIZE:
            return None

        try:
            values = struct.unpack(MESSAGE_FORMAT, data[:MESSAGE_SIZE])
            return cls(
                timestamp_us=values[0],
                cursor_x=values[1],
                cursor_y=values[2],
                cursor_vx=values[3],
                cursor_vy=values[4],
                target_x=values[5],
                target_y=values[6],
                task_state=TaskState(values[7]),
                trial_number=values[8]
            )
        except (struct.error, ValueError):
            return None

    def to_bytes(self) -> bytes:
        """Serialize message to bytes."""
        return struct.pack(
            MESSAGE_FORMAT,
            self.timestamp_us,
            self.cursor_x,
            self.cursor_y,
            self.cursor_vx,
            self.cursor_vy,
            self.target_x,
            self.target_y,
            int(self.task_state),
            self.trial_number
        )
