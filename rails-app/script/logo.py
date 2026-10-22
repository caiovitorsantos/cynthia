# Gera o logo da Cynth.ia em pixel art estilo 16-bit, como SVG: o selo (login, página inicial,
# README) e o rosto (cabeçalho, favicon). Uso: python3 script/logo.py app/assets/images
import math
import sys

PALETTE = {
    "K": "#1a1424",  # contorno
    "k": "#3a2f45",  # contorno suave (detalhes internos)
    # cabelo loiro
    "Y1": "#fff1a8", "Y2": "#f7d36b", "Y3": "#d9a93c", "Y4": "#a8772a",
    # pele
    "S1": "#ffe0c7", "S2": "#f6c19c", "S3": "#d9946e", "S4": "#a8644a",
    "W": "#ffffff", "E": "#3b2a1e", "Bw": "#a8772a",
    "m": "#a8494a",
    # blusa azul
    "J1": "#5b8fcf", "J2": "#3f6fae", "J3": "#2c5288", "J4": "#1e3a63",
    # madeira
    "D1": "#d6a063", "D2": "#b07a3f", "D3": "#82542a", "D4": "#5a3a1c",
    # bege retrô
    "B1": "#fbf3dc", "B2": "#e6d6b0", "B3": "#bfa97c", "B4": "#8c7650",
    # tela
    "M1": "#123b22", "M2": "#0a2615", "N1": "#7dffa6", "N2": "#3dd96e", "N3": "#1f8a45",
    # garrafa
    "L1": "#cfe6ff", "L2": "#7fb6f0", "L3": "#3b82d6", "L4": "#2456a0",
    # cinza (mouse, caneca)
    "G1": "#ffffff", "G2": "#d9d9e0", "G3": "#a3a3b0",
    # aro
    "O1": "#ffe08a", "O2": "#f0b33a", "O3": "#c4831c", "O4": "#8a5512",
    "R1": "#8a6440", "R2": "#6b4a2b", "R3": "#4a321c",
    "Q1": "#d8c4a8", "Q2": "#9c8466",
    # verdes
    "V1": "#7ff0a8", "V2": "#3fd47c", "V3": "#25a85c", "V4": "#17793f", "V5": "#0f5530",
    "Z1": "#ffffff", "Z2": "#cfe9d8",
}


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]

    def put(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h and c:
            self.px[y][x] = c

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def rect(self, x, y, w, h, c):
        for j in range(h):
            for i in range(w):
                self.put(x + i, y + j, c)

    def shaded_rect(self, x, y, w, h, ramp):
        """ramp = (luz, base, sombra): borda de cima/esquerda clara, de baixo/direita escura."""
        light, base, shadow = ramp
        self.rect(x, y, w, h, base)
        self.rect(x, y, w, 1, light)
        self.rect(x, y, 1, h, light)
        self.rect(x, y + h - 1, w, 1, shadow)
        self.rect(x + w - 1, y, 1, h, shadow)

    def ellipse(self, cx, cy, rx, ry, color_at, clip=None):
        """Preenche a elipse; color_at(nx, ny) recebe a posição normalizada (-1..1)."""
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                if nx * nx + ny * ny <= 1 and (clip is None or clip(x, y)):
                    self.put(x, y, color_at(nx, ny))

    def lit(self, ramp, bias=0.0):
        """Cor por iluminação vinda de cima/esquerda, para usar em ellipse()."""
        def color(nx, ny):
            d = nx * nx + ny * ny
            light = -0.6 * nx - 0.8 * ny + bias
            if d > 0.82 and light < 0.2:
                return ramp[-1]
            if light > 0.75:
                return ramp[0]
            if light > 0.0:
                return ramp[1]
            if light > -0.55:
                return ramp[2] if len(ramp) > 3 else ramp[1]
            return ramp[-1] if len(ramp) > 3 else ramp[2]
        return color

    def paste(self, other, clip=None):
        for y in range(self.h):
            for x in range(self.w):
                c = other.px[y][x]
                if c and (clip is None or clip(x, y)):
                    self.px[y][x] = c

    def outline(self, c="K"):
        filled = {(x, y) for y in range(self.h) for x in range(self.w) if self.px[y][x]}
        for x, y in filled:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if (x + dx, y + dy) not in filled:
                    self.put(x + dx, y + dy, c)

    def crop(self, x, y, w, h):
        out = Canvas(w, h)
        for j in range(h):
            for i in range(w):
                out.px[j][i] = self.get(x + i, y + j)
        return out

    def svg(self, title="Cynth.ia"):
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
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" height="{self.h}" '
                f'shape-rendering="crispEdges" role="img" aria-label="{title}"><title>{title}</title>' + "".join(rects) + "</svg>")


# Fonte 5x7 para as faixas e o monitor.
FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    ".": ["0", "0", "0", "0", "0", "0", "1"],
    " ": ["000"] * 7,
}


def text_width(word):
    return sum(len(FONT[ch][0]) + 1 for ch in word) - 1


def text(cv, x, y, word, color, shadow=None):
    for ch in word:
        glyph = FONT[ch]
        for j, row in enumerate(glyph):
            for i, bit in enumerate(row):
                if bit == "1":
                    if shadow:
                        cv.put(x + i + 1, y + j + 1, shadow)
                    cv.put(x + i, y + j, color)
        x += len(glyph[0]) + 1


def inside(cx, cy, r):
    return lambda x, y: (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r


def ring(cv, cx, cy):
    def by_radius(x, y):
        d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
        ang = math.atan2(y + 0.5 - cy, x + 0.5 - cx)
        light = -math.cos(ang + math.pi / 4)  # claro em cima/esquerda
        if d <= 41:
            return None
        if d <= 43:
            return "O3" if light < 0 else "O2"
        if d <= 51:
            return "R3" if light < -0.4 else ("R1" if light > 0.5 else "R2")
        if d <= 54:
            return "O1" if light > 0.4 else ("O3" if light < -0.3 else "O2")
        if d <= 55:
            return "O4"
        return None
    for y in range(cv.h):
        for x in range(cv.w):
            c = by_radius(x, y)
            if c:
                cv.put(x, y, c)
    for ang in (0.35, 1.2, 1.95, 2.8, 3.5, 5.9, 4.2, 5.25):  # rebites
        rx, ry = cx + 47 * math.cos(ang), cy + 47 * math.sin(ang)
        cv.ellipse(rx, ry, 2.2, 2.2, cv.lit(("Q1", "Q1", "Q2", "R3")))


def inner_disc(cv, cx, cy):
    def green(x, y):
        d = math.hypot(x + 0.5 - cx, y + 0.5 - (cy - 8))
        if d < 16:
            return "V1"
        if d < 27:
            return "V2"
        if d < 36:
            return "V3"
        return "V4"
    for y in range(cv.h):
        for x in range(cv.w):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= 41 * 41:
                cv.put(x, y, green(x, y))


def character(cv):
    hair = ("Y1", "Y2", "Y3", "Y4")
    skin = ("S1", "S2", "S3", "S4")
    blouse = ("J1", "J2", "J3", "J4")
    # cabelo de trás, na altura dos ombros
    cv.ellipse(80, 50, 21, 27, cv.lit(hair, 0.1), clip=lambda x, y: y < 74)
    for x in range(61, 100, 3):  # pontas
        cv.put(x, 74, "Y3")
        cv.put(x + 1, 75, "Y4")
    # tronco e ombros
    cv.ellipse(80, 92, 24, 22, cv.lit(blouse, 0.2))
    cv.rect(75, 63, 10, 9, "S2")  # pescoço
    cv.rect(75, 63, 10, 2, "S3")
    for i in range(7):  # gola em V
        cv.put(74 + i, 71 + i, "W")
        cv.put(73 + i, 71 + i, "J4")
        cv.put(85 - i, 71 + i, "W")
        cv.put(86 - i, 71 + i, "J4")
    cv.ellipse(80, 73, 4, 4, lambda nx, ny: "S2" if ny < 0.2 else None)
    for y in range(78, 104, 3):  # botões
        cv.put(80, y, "J4")
    # rosto
    cv.ellipse(80, 47, 14, 17, cv.lit(("S1", "S2", "S2", "S3"), 0.5))
    cv.ellipse(66, 49, 2.5, 4, cv.lit(skin, 0.2))  # orelhas
    cv.ellipse(94, 49, 2.5, 4, cv.lit(skin, -0.2))
    # franja com risca de lado
    cv.ellipse(80, 36, 16, 12, cv.lit(hair, 0.2), clip=lambda x, y: y < 40 - max(0, (x - 72) // 3))
    for x, y in ((70, 38), (71, 40), (89, 36), (91, 38), (92, 41)):
        cv.put(x, y, "Y2")
    for x in (74, 79, 85, 90):  # mechas
        for y in range(28, 36):
            if cv.get(x, y) in ("Y2", "Y1"):
                cv.put(x, y, "Y3")
    # mechas laterais na frente do rosto
    cv.ellipse(65, 54, 3, 15, cv.lit(hair, -0.1), clip=lambda x, y: y > 40)
    cv.ellipse(95, 54, 3, 15, cv.lit(hair, -0.3), clip=lambda x, y: y > 40)
    # sobrancelhas franzidas (descendo para o centro)
    for i in range(6):
        cv.put(70 + i, 40 + (i // 3), "Bw")
        cv.put(90 - i, 40 + (i // 3), "Bw")
    # óculos
    for lx in (69, 82):
        cv.rect(lx, 43, 10, 8, "K")
        cv.rect(lx + 1, 44, 8, 6, "S1")
        cv.rect(lx + 1, 44, 8, 2, "S3")  # pálpebra pesada (tédio)
        cv.rect(lx + 2, 46, 6, 3, "W")
        cv.rect(lx + 5, 46, 2, 3, "E")  # olhando de lado
        cv.put(lx + 2, 46, "S2")
        cv.put(lx + 7, 44, "W")  # reflexo na lente
    cv.rect(79, 45, 3, 1, "K")  # ponte
    cv.rect(67, 45, 2, 1, "K")  # hastes
    cv.rect(92, 45, 2, 1, "K")
    # nariz e boca emburrada
    cv.put(81, 52, "S3")
    cv.put(81, 53, "S3")
    cv.put(80, 54, "S3")
    cv.rect(77, 58, 7, 1, "m")
    cv.put(76, 59, "m")
    cv.put(84, 59, "m")
    cv.rect(78, 59, 5, 1, "S3")
    cv.put(72, 55, "S3")  # bochechas
    cv.put(88, 55, "S3")


def desk_scene(cv):
    wood = ("D1", "D2", "D3", "D4")
    beige = ("B1", "B2", "B4")
    # mesa (tampo oval) na frente
    cv.ellipse(80, 104, 46, 9, cv.lit(wood, 0.4))
    cv.rect(34, 104, 92, 12, "D3")
    cv.rect(34, 104, 92, 2, "D2")
    # CRT à direita, em perspectiva
    cv.shaded_rect(92, 62, 28, 30, ("B1", "B2", "B3"))
    cv.rect(116, 64, 6, 27, "B3")  # lateral
    cv.rect(116, 64, 6, 1, "B2")
    cv.rect(95, 65, 22, 20, "K")
    cv.rect(96, 66, 20, 18, "M1")
    for y in range(67, 84, 2):  # linhas de varredura
        cv.rect(96, y, 20, 1, "M2")
    for y, w in ((68, 14), (71, 10), (74, 12)):  # texto miúdo das mensagens
        for i in range(0, w, 2):
            cv.put(98 + i, y, "N3")
    text(cv, 98, 76, "UGH", "N1", "N3")
    for i in range(3):
        cv.put(116 - 7 + i * 2, 82, "N2")
    cv.rect(99, 92, 14, 4, "B3")  # base
    cv.rect(96, 96, 20, 3, "B2")
    cv.rect(96, 98, 20, 1, "B4")
    # teclado retrô
    cv.shaded_rect(62, 97, 36, 7, ("B1", "B2", "B4"))
    for y in (98, 100):
        for x in range(64, 96, 3):
            cv.rect(x, y, 2, 1, "B3")
    # mãos sobre o teclado
    cv.ellipse(66, 97, 5, 3, cv.lit(("S1", "S2", "S3", "S4")))
    cv.ellipse(93, 97, 5, 3, cv.lit(("S1", "S2", "S3", "S4")))
    # garrafa azul à esquerda
    cv.shaded_rect(42, 72, 10, 28, ("L2", "L3", "L4"))
    cv.rect(44, 74, 2, 22, "L1")
    cv.rect(44, 66, 6, 6, "L4")
    cv.rect(45, 64, 4, 2, "G3")
    cv.rect(42, 84, 10, 5, "G2")  # rótulo
    # mouse e caneca
    cv.ellipse(56, 103, 4, 2.5, cv.lit(("G1", "G2", "G3")))
    cv.shaded_rect(122, 92, 8, 9, ("G1", "G2", "G3"))
    cv.rect(130, 94, 2, 5, "G3")


def banner(cv, cx, y, word, w):
    green = ("V1", "V2", "V4")
    x = cx - w // 2
    for side, sx in ((-1, x - 9), (1, x + w + 1)):  # pontas dobradas
        cv.rect(sx, y + 4, 8, 13, "V5")
        cv.rect(sx + (0 if side < 0 else 6), y + 6, 2, 9, "K")
    cv.rect(x, y, w, 17, "V3")
    cv.rect(x, y + 1, w, 2, "V2")
    cv.rect(x, y + 14, w, 2, "V4")
    cv.rect(x, y, w, 1, "K")
    cv.rect(x, y + 16, w, 1, "K")
    cv.rect(x, y, 1, 17, "K")
    cv.rect(x + w - 1, y, 1, 17, "K")
    text(cv, cx - text_width(word) // 2, y + 5, word, "Z1", "V5")


def money_bag(cv, cx, cy, flip):
    gold = ("O1", "O2", "O3", "O4")
    cv.ellipse(cx, cy + 3, 7, 7, cv.lit(gold, 0.2))
    cv.rect(cx - 2, cy - 6, 4, 3, "O3")
    cv.rect(cx - 3, cy - 4, 6, 1, "O4")
    for j, row in enumerate(("0110", "1000", "0110", "0001", "0110")):  # cifrão
        for i, bit in enumerate(row):
            if bit == "1":
                cv.put(cx - 2 + i, cy + j, "O4")
    cv.put(cx, cy - 1, "O4")
    cv.put(cx, cy + 5, "O4")
    # asa com penas
    d = 1 if flip else -1
    base_x = cx + d * 7
    for k, (length, dy) in enumerate(((10, -6), (9, -3), (7, 0), (5, 3))):
        for i in range(length):
            cv.put(base_x + d * i, cy + dy - i // 3, "G1" if k % 2 == 0 else "G2")
            cv.put(base_x + d * i, cy + dy + 1 - i // 3, "G2")


def badge():
    cv = Canvas(176, 132)
    cx, cy = 88, 66
    cv.ellipse(cx, cy, 56, 56, lambda nx, ny: "K")
    ring(cv, cx, cy)
    inner_disc(cv, cx, cy)

    person, desk = Canvas(176, 132), Canvas(176, 132)
    character(person)
    desk_scene(desk)
    shifted = Canvas(176, 132)
    for y in range(132):  # personagem 8px para a direita; mesa e objetos também 6px para cima
        for x in range(176):
            shifted.px[y][x] = desk.get(x - 8, y + 6) or person.get(x - 8, y)
    shifted.outline()
    cv.paste(shifted, clip=inside(cx, cy, 41))

    extras = Canvas(176, 132)
    money_bag(extras, 18, 64, flip=False)
    money_bag(extras, 158, 64, flip=True)
    extras.outline()
    cv.paste(extras, clip=lambda x, y: (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 > 56 * 56)

    banners = Canvas(176, 132)
    banner(banners, cx, 2, "ADMIN", 56)
    banner(banners, cx, 112, "CYNTH.IA", 76)
    cv.paste(banners)
    return cv


def face():
    """Rosto recortado do selo, para ícones."""
    scene = Canvas(176, 132)
    character(scene)
    scene.outline()
    return scene.crop(60, 22, 40, 40)


if __name__ == "__main__":
    out = sys.argv[1]
    open(f"{out}/cynthia-badge.svg", "w").write(badge().svg())
    open(f"{out}/cynthia-face.svg", "w").write(face().svg())
    print("ok")
