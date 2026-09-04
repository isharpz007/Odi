"""
motion_movement.py

A Python (pygame) port of a Flutter "AI head" animated widget.
Reproduces three independent motion behaviors from the original Dart code:

  1. Bobbing   - a slow, continuous up/down float (sine easing)
  2. Head turn - periodic random glances left/right with a pseudo-3D
                 perspective squash (simulating a rotateY turn)
  3. Blinking  - randomized, asymmetric eye blinks with occasional
                 quick double-blinks

Run with:  pip install pygame
           python motion_movement.py
"""

import math
import random
import sys

import pygame

# ---------------------------------------------------------------------------
# Config (mirrors constants from the original Dart widget)
# ---------------------------------------------------------------------------
WIDTH, HEIGHT = 500, 500
BG_COLOR = (6, 8, 18)

HEAD_SIZE = 180
BOB_AMPLITUDE = 8.0          # px, vertical float distance
BOB_PERIOD_MS = 2400         # one full up-down cycle

MAX_TURN_ANGLE_SCALE = 0.42  # simulated rotateY "strength"
MAX_TILT = 0.05
FPS = 60


def ease_in_out(t: float) -> float:
    """Cubic-like ease in/out, t in [0,1]."""
    if t < 0.5:
        return 4 * t * t * t
    u = -2 * t + 2
    return 1 - (u ** 3) / 2


def ease_out_cubic(t: float) -> float:
    inv = 1 - t
    return 1 - inv ** 3


class Bob:
    """Continuous slow up/down float, matching _AiHeadWidgetState."""

    def __init__(self):
        self.t = 0.0  # ms elapsed within current half-cycle
        self.direction = 1  # 1 = going down, -1 = going up

    def update(self, dt_ms: float):
        self.t += dt_ms
        if self.t >= BOB_PERIOD_MS:
            self.t -= BOB_PERIOD_MS
            self.direction *= -1

    @property
    def offset_y(self) -> float:
        frac = self.t / BOB_PERIOD_MS  # 0..1 within this half
        eased = ease_in_out(frac)
        # -amplitude -> +amplitude across a period, direction flips each leg
        return self.direction * (eased - 0.5) * 2 * BOB_AMPLITUDE


class HeadTurn:
    """Periodic randomized left/right glances, matching _HeadTurnState."""

    def __init__(self):
        self.value = 0.0       # -1 (left) .. 1 (right)
        self.target = 0.0
        self.start_value = 0.0
        self.anim_elapsed = 0.0
        self.anim_duration = 0.0
        self.animating = False
        self.wait_remaining = self._rand_wait()
        self.state = "idle"    # idle -> turning -> holding -> (maybe glance) -> returning

    @staticmethod
    def _rand_wait():
        return random.uniform(1800, 5000)

    def _begin_turn(self, target, ms):
        self.start_value = self.value
        self.target = target
        self.anim_elapsed = 0.0
        self.anim_duration = ms
        self.animating = True

    def update(self, dt_ms: float):
        if self.state == "idle":
            self.wait_remaining -= dt_ms
            if self.wait_remaining <= 0:
                magnitude = random.uniform(0.45, 1.0)
                target = magnitude * random.choice([1, -1])
                self._begin_turn(target, random.uniform(500, 950))
                self.state = "turning"

        elif self.state == "turning":
            self._advance_anim(dt_ms)
            if not self.animating:
                self.hold_remaining = random.uniform(400, 1300)
                self.state = "holding"

        elif self.state == "holding":
            self.hold_remaining -= dt_ms
            if self.hold_remaining <= 0:
                if random.random() < 0.3:
                    other = -math.copysign(1, self.target) * random.uniform(0.45, 1.0)
                    self._begin_turn(other, random.uniform(450, 850))
                    self.state = "glancing"
                else:
                    self._begin_turn(0.0, random.uniform(500, 1000))
                    self.state = "returning"

        elif self.state == "glancing":
            self._advance_anim(dt_ms)
            if not self.animating:
                self.hold_remaining = random.uniform(300, 1000)
                self.state = "glance_hold"

        elif self.state == "glance_hold":
            self.hold_remaining -= dt_ms
            if self.hold_remaining <= 0:
                self._begin_turn(0.0, random.uniform(500, 1000))
                self.state = "returning"

        elif self.state == "returning":
            self._advance_anim(dt_ms)
            if not self.animating:
                self.wait_remaining = self._rand_wait()
                self.state = "idle"

    def _advance_anim(self, dt_ms):
        self.anim_elapsed += dt_ms
        t = min(self.anim_elapsed / self.anim_duration, 1.0)
        eased = ease_in_out(t)
        self.value = self.start_value + (self.target - self.start_value) * eased
        if t >= 1.0:
            self.animating = False


class BlinkingEyes:
    """Randomized asymmetric blink, matching _BlinkingEyesState."""

    def __init__(self):
        self.phase = "idle"   # idle -> closing -> opening
        self.phase_elapsed = 0.0
        self.phase_duration = 0.0
        self.depth = 1.0
        self.close_fraction = 0.35
        self.open_fraction = 0.65
        self.total_duration = 200.0
        self.idle_remaining = 2500.0

    def update(self, dt_ms: float):
        if self.phase == "idle":
            self.idle_remaining -= dt_ms
            if self.idle_remaining <= 0:
                self._start_blink()
        else:
            self.phase_elapsed += dt_ms
            if self.phase_elapsed >= self.phase_duration:
                self._advance_phase()

    def _start_blink(self):
        self.depth = random.uniform(0.55, 1.0)
        self.total_duration = random.uniform(110, 320)
        self.close_fraction = random.uniform(0.28, 0.42)
        self.open_fraction = 1.0 - self.close_fraction
        self.phase = "closing"
        self.phase_elapsed = 0.0
        self.phase_duration = self.total_duration * self.close_fraction

    def _advance_phase(self):
        if self.phase == "closing":
            self.phase = "opening"
            self.phase_elapsed = 0.0
            self.phase_duration = self.total_duration * self.open_fraction
        else:
            self.phase = "idle"
            double_blink = random.random() < 0.12
            self.idle_remaining = (
                random.uniform(220, 380) if double_blink else random.uniform(2200, 6000)
            )

    def closure(self) -> float:
        """0 = open, 1 = fully closed (scaled by this blink's depth)."""
        if self.phase == "idle" or self.phase_duration <= 0:
            return 0.0
        t = min(self.phase_elapsed / self.phase_duration, 1.0)
        if self.phase == "closing":
            return ease_out_cubic(t) * self.depth
        eased = ease_in_out(t)
        return (1 - eased) * self.depth


def draw_head(surface, cx, cy, size, turn_value, closure):
    # Simulated perspective "turn": squash width + slight horizontal drift,
    # standing in for the Dart rotateY/translate/rotateZ transform.
    squash = 1 - 0.28 * abs(turn_value)
    dx = turn_value * (size * 0.035)
    w = max(1, size * squash)

    # Halo
    halo = pygame.Surface((size + 100, size + 100), pygame.SRCALPHA)
    pygame.draw.circle(halo, (40, 120, 255, 40), halo.get_rect().center, (size + 100) // 2)
    surface.blit(halo, (cx - halo.get_width() / 2 + dx, cy - halo.get_height() / 2))

    # Head body
    head = pygame.Surface((int(w), size), pygame.SRCALPHA)
    pygame.draw.ellipse(head, (10, 20, 50, 235), head.get_rect())
    pygame.draw.ellipse(head, (60, 190, 255, 160), head.get_rect(), width=2)
    surface.blit(head, (cx - w / 2 + dx, cy - size / 2))

    # Eyes (scaleY by 1-closure, matching Transform.scale on _BlinkingEyes)
    eye_r = 4
    gap = size * 0.22 * squash
    ey = cy
    for sign in (-1, 1):
        ex = cx + dx + sign * (gap / 2)
        eh = max(1, eye_r * (1 - closure))
        eye_rect = pygame.Rect(0, 0, eye_r * 2, eh * 2)
        eye_rect.center = (ex, ey)
        eye_surf = pygame.Surface((eye_r * 2, int(eh * 2) + 1), pygame.SRCALPHA)
        pygame.draw.ellipse(eye_surf, (230, 245, 255, 255), eye_surf.get_rect())
        surface.blit(eye_surf, eye_rect.topleft)


def main():
    pygame.init()
    screen = pygame.display.set_mode((WIDTH, HEIGHT))
    pygame.display.set_caption("motion_movement")
    clock = pygame.time.Clock()

    bob = Bob()
    turn = HeadTurn()
    eyes = BlinkingEyes()

    running = True
    while running:
        dt_ms = clock.tick(FPS)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                running = False

        bob.update(dt_ms)
        turn.update(dt_ms)
        eyes.update(dt_ms)

        screen.fill(BG_COLOR)
        cx, cy = WIDTH / 2, HEIGHT / 2 + bob.offset_y
        draw_head(screen, cx, cy, HEAD_SIZE, turn.value, eyes.closure())
        pygame.display.flip()

    pygame.quit()
    sys.exit()


if __name__ == "__main__":
    main()