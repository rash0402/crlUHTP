"""
PyGame Renderer for UHTP

60Hz visualization of cursor and target with task-specific features.
"""

import pygame
import numpy as np
from typing import Optional, List
from dataclasses import dataclass, field
from collections import deque

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
    trace_color: tuple = (0, 100, 150)
    cursor_radius: int = 10
    target_radius: int = 15
    # World to screen scaling (meters to pixels)
    scale: float = 1000.0  # 1m = 1000 pixels (fits ±300mm on screen)
    # Origin offset (center of screen)
    origin_x: int = 640
    origin_y: int = 360
    # Trace settings
    trace_length: int = 500  # Number of points to keep
    show_trace: bool = True
    # Plot panel
    plot_width: int = 300
    plot_height: int = 150
    show_plot: bool = True


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
        self.small_font: Optional[pygame.font.Font] = None
        self.running = False

        # Current state for rendering
        self.last_message: Optional[UDPMessage] = None

        # Trajectory trace
        self.trace: deque = deque(maxlen=self.config.trace_length)

        # Error history for plot
        self.error_history: deque = deque(maxlen=300)  # 5 seconds at 60Hz
        self.time_history: deque = deque(maxlen=300)

        # Fitts targets (for visualization)
        self.fitts_targets: List[tuple] = []
        self._init_fitts_targets()

    def _init_fitts_targets(self, num_targets=13, radius=0.08):
        """Pre-compute Fitts target positions."""
        self.fitts_targets = []
        for i in range(num_targets):
            angle = 2 * np.pi * i / num_targets - np.pi / 2
            x = radius * np.cos(angle)
            y = radius * np.sin(angle)
            self.fitts_targets.append((x, y))

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
            self.small_font = pygame.font.SysFont('monospace', 12)

            self.running = True
            return True
        except Exception as e:
            print(f"Failed to initialize renderer: {e}")
            return False

    def world_to_screen(self, x: float, y: float) -> tuple:
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
                elif event.key == pygame.K_t:
                    # Toggle trace
                    self.config.show_trace = not self.config.show_trace
                elif event.key == pygame.K_p:
                    # Toggle plot
                    self.config.show_plot = not self.config.show_plot
                elif event.key == pygame.K_c:
                    # Clear trace
                    self.trace.clear()

        # Store message and update history
        if message:
            self.last_message = message

            # Update trace
            if self.config.show_trace:
                self.trace.append((message.cursor_x, message.cursor_y))

            # Update error history
            error = np.sqrt(
                (message.cursor_x - message.target_x)**2 +
                (message.cursor_y - message.target_y)**2
            )
            self.error_history.append(error * 1000)  # Convert to mm
            self.time_history.append(message.timestamp_us / 1e6)

        # Clear screen
        self.screen.fill(self.config.background_color)

        # Draw grid
        self._draw_grid()

        # Draw task-specific elements
        if self.last_message:
            self._draw_task_elements(self.last_message)

        # Draw trace
        if self.config.show_trace and len(self.trace) > 1:
            self._draw_trace()

        # Draw target and cursor
        if self.last_message:
            self._draw_target(self.last_message)
            self._draw_cursor(self.last_message)

        # Draw error plot
        if self.config.show_plot:
            self._draw_error_plot()

        # Draw info overlay
        if self.last_message:
            self._draw_info(self.last_message)

        # Draw help
        self._draw_help()

        # Update display
        pygame.display.flip()

        # Limit frame rate
        self.clock.tick(self.config.fps)

        return True

    def _draw_grid(self) -> None:
        """Draw coordinate grid."""
        grid_color = (50, 50, 60)

        # Vertical lines (every 10cm)
        for i in range(-10, 11):
            x = self.config.origin_x + int(i * 0.1 * self.config.scale)
            if 0 <= x <= self.config.width:
                pygame.draw.line(
                    self.screen, grid_color,
                    (x, 0), (x, self.config.height), 1
                )

        # Horizontal lines (every 10cm)
        for i in range(-5, 6):
            y = self.config.origin_y - int(i * 0.1 * self.config.scale)
            if 0 <= y <= self.config.height:
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

    def _draw_task_elements(self, msg: UDPMessage) -> None:
        """Draw task-specific elements."""
        # Draw all Fitts targets as faint circles
        for tx, ty in self.fitts_targets:
            pos = self.world_to_screen(tx, ty)
            pygame.draw.circle(
                self.screen,
                (60, 60, 70),  # Faint color
                pos,
                8,
                1
            )

    def _draw_trace(self) -> None:
        """Draw cursor trajectory trace."""
        if len(self.trace) < 2:
            return

        points = [self.world_to_screen(x, y) for x, y in self.trace]

        # Draw with fading color
        for i in range(len(points) - 1):
            alpha = int(255 * (i + 1) / len(points))
            color = (
                min(255, self.config.trace_color[0] + alpha // 4),
                min(255, self.config.trace_color[1] + alpha // 4),
                min(255, self.config.trace_color[2] + alpha // 4)
            )
            pygame.draw.line(self.screen, color, points[i], points[i + 1], 2)

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

    def _draw_error_plot(self) -> None:
        """Draw real-time error plot."""
        if len(self.error_history) < 2:
            return

        # Plot area (bottom right)
        plot_x = self.config.width - self.config.plot_width - 10
        plot_y = self.config.height - self.config.plot_height - 10
        plot_w = self.config.plot_width
        plot_h = self.config.plot_height

        # Draw background
        pygame.draw.rect(
            self.screen,
            (30, 30, 40),
            (plot_x, plot_y, plot_w, plot_h)
        )
        pygame.draw.rect(
            self.screen,
            (60, 60, 80),
            (plot_x, plot_y, plot_w, plot_h),
            1
        )

        # Title
        title = self.small_font.render("Error (mm)", True, (200, 200, 200))
        self.screen.blit(title, (plot_x + 5, plot_y + 2))

        # Scale error to plot height
        errors = list(self.error_history)
        max_error = max(max(errors), 10)  # At least 10mm scale

        # Draw Y axis labels
        for val in [0, max_error / 2, max_error]:
            y = plot_y + plot_h - 15 - int((val / max_error) * (plot_h - 20))
            label = self.small_font.render(f"{val:.0f}", True, (150, 150, 150))
            self.screen.blit(label, (plot_x + 5, y - 6))

        # Draw error line
        points = []
        for i, err in enumerate(errors):
            x = plot_x + 30 + int(i * (plot_w - 35) / len(errors))
            y = plot_y + plot_h - 5 - int((err / max_error) * (plot_h - 20))
            points.append((x, y))

        if len(points) > 1:
            pygame.draw.lines(self.screen, (255, 150, 50), False, points, 2)

    def _draw_info(self, msg: UDPMessage) -> None:
        """Draw information overlay."""
        info_color = (200, 200, 200)

        # Compute error
        error = np.sqrt(
            (msg.cursor_x - msg.target_x)**2 +
            (msg.cursor_y - msg.target_y)**2
        ) * 1000  # mm

        lines = [
            f"Time: {msg.timestamp_us / 1e6:.2f} s",
            f"Pos: ({msg.cursor_x * 1000:.1f}, {msg.cursor_y * 1000:.1f}) mm",
            f"Target: ({msg.target_x * 1000:.1f}, {msg.target_y * 1000:.1f}) mm",
            f"Error: {error:.1f} mm",
            f"State: {msg.task_state.name}",
            f"Trial: {msg.trial_number}",
        ]

        y = 10
        for line in lines:
            text = self.font.render(line, True, info_color)
            self.screen.blit(text, (10, y))
            y += 20

    def _draw_help(self) -> None:
        """Draw keyboard shortcuts."""
        help_color = (100, 100, 100)
        help_text = "T:trace  P:plot  C:clear  ESC:quit"
        text = self.small_font.render(help_text, True, help_color)
        self.screen.blit(text, (10, self.config.height - 20))

    def clear_history(self):
        """Clear trace and error history."""
        self.trace.clear()
        self.error_history.clear()
        self.time_history.clear()

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
