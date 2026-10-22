# Gera o logo pixel art da Cynth.ia como SVG: o selo (login, página inicial, README) e o rosto
# (cabeçalho, favicon). Uso: python3 script/logo.py app/assets/images
import sys

PALETTE = {
    "K": "#1e1a2e",  # contorno
    "Y": "#f5cf5a", "y": "#c99a2e",  # cabelo loiro
    "S": "#f7c8a5", "s": "#dca07a",  # pele
    "W": "#ffffff", "E": "#3a2a1a",  # olho / pupila
    "m": "#a84a45",  # boca
    "T": "#00a884", "t": "#007a60",  # blusa (verde da marca)
    "D": "#b07740", "d": "#7a4e27",  # madeira
    "B": "#e9dcc0", "b": "#c2b08c",  # bege retrô
    "M": "#0d2914", "N": "#3dff73",  # tela CRT
    "L": "#3b82d6", "l": "#9cc6f5", "c": "#1f4f99",  # garrafa
    "C": "#f4f4f4", "x": "#cfcfcf",  # caneca
    "P": "#f2b705", "p": "#e86a92", "g": "#8a8a8a",  # lápis, borracha, mouse
    "O": "#e3a92b", "o": "#9c6a17",  # dourado do aro / saquinhos
    "R": "#6b4a2b", "r": "#4a321c", "Q": "#a88a6a",  # aro marrom e rebites
    "V": "#25d366", "v": "#128c4a", "F": "#0e5a33",  # verdes do fundo e das faixas
    "Z": "#e9edef",  # texto claro das faixas
    "J": "#2f5d8c", "j": "#22456a",  # blusa azul
    "A": "#ffffff",  # asas
}

FACE = """
....KKKKKKKK....
..KKYYYYYYYYKK..
.KYYYYYYYYYYYYK.
.KYYYYYYYYYYyYK.
KYYYyyyyyyyyYYYK
KYYySSSSSSSSyYYK
KYYKsssKKsssKYYK
KYYKWWEKKWWEKYYK
KYYKKKKSSKKKKYYK
KYYsSSSSSSSSsYYK
KYYsSSSSsSSSsYYK
KYYYsSSSSSSSsYYK
KYYYsSSmmmSSsYYK
KYYYYsmSSSmsYYYK
.KYYKKsssssKKYK.
..KK.KKKKKK.KK..
"""


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h and c != ".":
            self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        for j in range(h):
            for i in range(w):
                self.put(x + i, y + j, c)

    def sprite(self, x, y, art):
        for j, row in enumerate(art.strip("\n").split("\n")):
            for i, c in enumerate(row):
                self.put(x + i, y + j, c)

    def outline(self, c="K"):
        filled = {(x, y) for y in range(self.h) for x in range(self.w) if self.px[y][x]}
        for x, y in list(filled):
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < self.w and 0 <= ny < self.h and (nx, ny) not in filled:
                    self.px[ny][nx] = c

    def svg(self, scale=1, title="Cynth.ia"):
        rects = []
        for y in range(self.h):
            x = 0
            while x < self.w:
                c = self.px[y][x]
                if not c:
                    x += 1
                    continue
                run = 1
                while x + run < self.w and self.px[y][x + run] == c:
                    run += 1
                rects.append(f'<rect x="{x}" y="{y}" width="{run}" height="1" fill="{PALETTE[c]}"/>')
                x += run
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w * scale}" height="{self.h * scale}" '
                f'shape-rendering="crispEdges" role="img" aria-label="{title}"><title>{title}</title>' + "".join(rects) + "</svg>")


# Fonte 3x5 para o "UGH..." do monitor.
GLYPHS = {
    "A": ["###", "#.#", "###", "#.#", "#.#"],
    "C": ["###", "#..", "#..", "#..", "###"],
    "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "G": ["###", "#..", "#.#", "#.#", "###"],
    "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],
    "M": ["#.#", "###", "###", "#.#", "#.#"],
    "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
    "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    ".": [".", ".", ".", ".", "#"],
}


def text(canvas, x, y, word, color="Z"):
    for ch in word:
        glyph = GLYPHS[ch]
        for j, row in enumerate(glyph):
            for i, c in enumerate(row):
                if c == "#":
                    canvas.put(x + i, y + j, color)
        x += len(glyph[0]) + 1


def text_width(word):
    return sum(len(GLYPHS[ch][0]) + 1 for ch in word) - 1


def disc(cv, cx, cy, r, c):
    for y in range(cv.h):
        for x in range(cv.w):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                cv.put(x, y, c)


def banner(cv, cx, y, word, w):
    x = cx - w // 2
    cv.rect(x - 3, y + 2, 3, 7, "F")  # pontas dobradas
    cv.rect(x + w, y + 2, 3, 7, "F")
    cv.rect(x, y, w, 9, "v")
    cv.rect(x, y + 1, w, 7, "V")
    cv.rect(x, y, w, 1, "K")
    cv.rect(x, y + 8, w, 1, "K")
    text(cv, cx - text_width(word) // 2, y + 2, word)


BAG = """
...oo...
..oOOo..
.OOOOOO.
OOOooOOO
OOooOOOO
OOOOooOO
OOooOOOO
.OOOOOO.
"""
WING = """
AA...
AAAA.
AAAAA
.AAAA
..AA.
"""


def badge():
    cv = Canvas(80, 64)
    cx, cy = 40, 32
    disc(cv, cx, cy, 29, "K")
    disc(cv, cx, cy, 28, "O")
    disc(cv, cx, cy, 27, "R")
    disc(cv, cx, cy, 23, "o")
    disc(cv, cx, cy, 22, "v")
    disc(cv, cx, cy - 3, 14, "V")
    for ang in (0.6, 2.55, 3.75, 5.65):  # rebites no aro
        import math
        rx, ry = int(cx + 25 * math.cos(ang)), int(cy + 25 * math.sin(ang))
        cv.rect(rx, ry, 2, 2, "Q")

    # personagem e mesa num canvas próprio, com contorno, recortado no círculo interno
    inner = Canvas(80, 64)
    inner.rect(25, 30, 20, 12, "J")  # blusa
    inner.rect(25, 30, 2, 12, "j")
    inner.rect(43, 30, 2, 12, "j")
    inner.rect(32, 30, 6, 2, "W")  # gola
    inner.put(34, 32, "W")
    inner.put(35, 32, "W")
    inner.sprite(27, 14, FACE)
    inner.rect(18, 44, 46, 3, "D")  # mesa
    inner.rect(18, 46, 46, 2, "d")
    inner.rect(28, 41, 14, 3, "B")  # teclado
    for i in range(29, 41, 2):
        inner.put(i, 41, "b")
    inner.rect(26, 40, 3, 3, "S")  # mãos
    inner.rect(41, 40, 3, 3, "S")
    inner.rect(45, 25, 17, 16, "B")  # CRT
    inner.rect(59, 25, 3, 16, "b")
    inner.rect(46, 27, 13, 10, "M")
    text(inner, 47, 28, "UGH", "N")
    for i in range(3):
        inner.put(47 + i * 2, 34, "N")
    inner.rect(49, 41, 7, 3, "b")
    inner.rect(19, 30, 4, 14, "L")  # garrafa
    inner.rect(20, 32, 1, 10, "l")
    inner.rect(20, 28, 2, 2, "c")
    inner.rect(22, 42, 3, 2, "x")  # mouse
    inner.outline()
    for y in range(inner.h):
        for x in range(inner.w):
            if inner.px[y][x] and (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= 22 * 22:
                cv.px[y][x] = inner.px[y][x]

    banner(cv, cx, 3, "ADMIN", 30)
    banner(cv, cx, 52, "CYNTH.IA", 40)
    bags = Canvas(80, 64)
    for bx, flip in ((2, False), (70, True)):  # saquinhos de dinheiro com asas
        cv_x = bx + (0 if flip else 3)
        bags.sprite(cv_x, 28, BAG)
        bags.put(cv_x + 3, 31, "o")
        wing = WING if flip else "\n".join(row[::-1] for row in WING.strip("\n").split("\n"))
        bags.sprite(bx + (7 if flip else 0), 26, wing)
    bags.outline()
    for y in range(bags.h):
        for x in range(bags.w):
            if bags.px[y][x] and not cv.px[y][x]:
                cv.px[y][x] = bags.px[y][x]
    return cv


def face():
    cv = Canvas(16, 16)
    cv.sprite(0, 0, FACE)
    return cv


if __name__ == "__main__":
    out = sys.argv[1]
    open(f"{out}/cynthia-badge.svg", "w").write(badge().svg(scale=1))
    open(f"{out}/cynthia-face.svg", "w").write(face().svg(scale=1))
    print("ok")
