"""
PyGame Renderer for UHTP

60Hz visualization of cursor and target.
"""

import pygame
from typing import Optional
from dataclasses import dataclass

from ..network.protocol import UDPMessage, TaskState


@dataclass
class RenderConfig:
    """Renderer configuration."""
    width: int = 1280
    height: int = 720
    fps: int = 60
    background_color: tuple = (20, 20, 30)
    cursor_color: tuple = (0, 200, 255)
    target_color: tuple = (255, 100, 100)
    cursor_radius: int = 10
    target_radius: int = 15
    # World to screen scaling (meters to pixels)
    scale: float = 2000.0  # 1m = 2000 pixels
    # Origin offset (center of screen)
    origin_x: int = 640
    origin_y: int = 360


class Renderer:
    """
    PyGame-based renderer for UHTP visualization.
    """

    def __init__(self, config: Optional[RenderConfig] = None):
        """Initialize renderer."""
        self.config = config or RenderConfig()
        self.screen: Optional[pygame.Surface] = None
        self.clock: Optional[pygame.time.Clock] = None
        self.font: Optional[pygame.font.Font] = None
        self.running = False

        # Current state for rendering
        self.last_message: Optional[UDPMessage] = None

    def init(self) -> bool:
        """Initialize PyGame and create window."""
        try:
            pygame.init()
            pygame.display.set_caption("UHTP Viewer")

            self.screen = pygame.display.set_mode(
                (self.config.width, self.config.height)
            )
            self.clock = pygame.time.Clock()
            self.font = pygame.font.SysFont('monospace', 16)

            self.running = True
            return True
        except Exception as e:
            print(f"Failed to initialize renderer: {e}")
            return False

    def world_to_screen(self, x: float, y: float) -> tuple[int, int]:
        """Convert world coordinates (meters) to screen coordinates (pixels)."""
        sx = int(self.config.origin_x + x * self.config.scale)
        sy = int(self.config.origin_y - y * self.config.scale)  # Y is inverted
        return (sx, sy)

    def update(self, message: Optional[UDPMessage]) -> bool:
        """
        Update display with new message.
        Returns False if window should close.
        """
        if not self.running or not self.screen:
            return False

        # Handle events
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.running = False
                return False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    self.running = False
                    return False

        # Store message
        if message:
            self.last_message = message

        # Clear screen
        self.screen.fill(self.config.background_color)

        # Draw grid
        self._draw_grid()

        # Draw target and cursor
        if self.last_message:
            self._draw_target(self.last_message)
            self._draw_cursor(self.last_message)
            self._draw_info(self.last_message)

        # Update display
        pygame.display.flip()

        # Limit frame rate
        self.clock.tick(self.config.fps)

        return True

    def _draw_grid(self) -> None:
        """Draw coordinate grid."""
        grid_color = (50, 50, 60)

        # Vertical lines (every 5cm)
        for i in range(-10, 11):
            x = self.config.origin_x + int(i * 0.05 * self.config.scale)
            pygame.draw.line(
                self.screen, grid_color,
                (x, 0), (x, self.config.height), 1
            )

        # Horizontal lines
        for i in range(-5, 6):
            y = self.config.origin_y - int(i * 0.05 * self.config.scale)
            pygame.draw.line(
                self.screen, grid_color,
                (0, y), (self.config.width, y), 1
            )

        # Origin axes
        axis_color = (80, 80, 100)
        pygame.draw.line(
            self.screen, axis_color,
            (self.config.origin_x, 0), (self.config.origin_x, self.config.height), 2
        )
        pygame.draw.line(
            self.screen, axis_color,
            (0, self.config.origin_y), (self.config.width, self.config.origin_y), 2
        )

    def _draw_cursor(self, msg: UDPMessage) -> None:
        """Draw cursor circle."""
        pos = self.world_to_screen(msg.cursor_x, msg.cursor_y)
        pygame.draw.circle(
            self.screen,
            self.config.cursor_color,
            pos,
            self.config.cursor_radius
        )

    def _draw_target(self, msg: UDPMessage) -> None:
        """Draw target circle."""
        pos = self.world_to_screen(msg.target_x, msg.target_y)
        # Draw target as ring
        pygame.draw.circle(
            self.screen,
            self.config.target_color,
            pos,
            self.config.target_radius,
            2  # Ring width
        )
        # Draw crosshair
        pygame.draw.line(
            self.screen, self.config.target_color,
            (pos[0] - 8, pos[1]), (pos[0] + 8, pos[1]), 1
        )
        pygame.draw.line(
            self.screen, self.config.target_color,
            (pos[0], pos[1] - 8), (pos[0], pos[1] + 8), 1
        )

    def _draw_info(self, msg: UDPMessage) -> None:
        """Draw information overlay."""
        info_color = (200, 200, 200)

        lines = [
            f"Time: {msg.timestamp_us / 1e6:.2f} s",
            f"Pos: ({msg.cursor_x * 1000:.1f}, {msg.cursor_y * 1000:.1f}) mm",
            f"Vel: ({msg.cursor_vx * 1000:.1f}, {msg.cursor_vy * 1000:.1f}) mm/s",
            f"Target: ({msg.target_x * 1000:.1f}, {msg.target_y * 1000:.1f}) mm",
            f"State: {msg.task_state.name}",
            f"Trial: {msg.trial_number}",
        ]

        y = 10
        for line in lines:
            text = self.font.render(line, True, info_color)
            self.screen.blit(text, (10, y))
            y += 20

    def close(self) -> None:
        """Close renderer and cleanup."""
        self.running = False
        pygame.quit()

    def __enter__(self):
        self.init()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False
