#!/usr/bin/env python3
"""
Générateur de fonds d'écran LFS – multiples variantes
Conserve le style original tout en créant des variations.
"""

from PIL import Image, ImageDraw, ImageFont
import random
import os

# === Couleurs de base (thème GTK LFS) ===
PRIMARY = (46, 139, 87)       # #2E8B57
PRIMARY_DARK = (35, 107, 67)  # #236B43
PRIMARY_LIGHT = (60, 179, 113) # #3CB371
SECONDARY = (26, 26, 46)      # #1a1a2e
SECONDARY_LIGHT = (37, 37, 53)
ACCENT = (144, 238, 144)      # #90EE90
TEXT_COLOR = (240, 240, 240)  # #f0f0f0

WIDTH, HEIGHT = 1920, 1080

# === Fonctions de dessin ===
def draw_gradient(draw, colors, orientation="vertical"):
    """Dessine un dégradé sur toute l'image."""
    if orientation == "vertical":
        for y in range(HEIGHT):
            ratio = y / HEIGHT
            r = int(colors[0][0] + (colors[1][0] - colors[0][0]) * ratio)
            g = int(colors[0][1] + (colors[1][1] - colors[0][1]) * ratio)
            b = int(colors[0][2] + (colors[1][2] - colors[0][2]) * ratio)
            draw.line([(0, y), (WIDTH, y)], fill=(r, g, b))
    elif orientation == "horizontal":
        for x in range(WIDTH):
            ratio = x / WIDTH
            r = int(colors[0][0] + (colors[1][0] - colors[0][0]) * ratio)
            g = int(colors[0][1] + (colors[1][1] - colors[0][1]) * ratio)
            b = int(colors[0][2] + (colors[1][2] - colors[0][2]) * ratio)
            draw.line([(x, 0), (x, HEIGHT)], fill=(r, g, b))
    elif orientation == "diagonal":
        for x in range(WIDTH):
            for y in range(HEIGHT):
                ratio = (x + y) / (WIDTH + HEIGHT)
                r = int(colors[0][0] + (colors[1][0] - colors[0][0]) * ratio)
                g = int(colors[0][1] + (colors[1][1] - colors[0][1]) * ratio)
                b = int(colors[0][2] + (colors[1][2] - colors[0][2]) * ratio)
                draw.point((x, y), fill=(r, g, b))

def draw_circles(draw, centers, radius, color, alpha_min=0.05, alpha_max=0.15):
    """Dessine des cercles translucides avec un dégradé radial."""
    for cx, cy in centers:
        for r in range(radius, 0, -1):
            alpha = int(255 * (1 - r / radius) * (alpha_min + random.random() * (alpha_max - alpha_min)))
            draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(*color, alpha))

def draw_triangles(draw, triangles):
    """Dessine des triangles avec remplissage et contour."""
    for points, fill, outline, width in triangles:
        draw.polygon(points, fill=fill, outline=outline, width=width)

def draw_text(draw, text, font_path, font_size, pos, color, shadow=True):
    """Dessine du texte avec ombre portée et effets."""
    try:
        font = ImageFont.truetype(font_path, font_size)
    except:
        font = ImageFont.load_default()
    if shadow:
        draw.text((pos[0]+10, pos[1]+10), text, font=font, fill=(0,0,0,128))
    draw.text(pos, text, font=font, fill=color)

def random_points(n, width, height, margin=100):
    """Génère n points aléatoires dans l'image."""
    pts = []
    for _ in range(n):
        pts.append((random.randint(margin, width-margin), random.randint(margin, height-margin)))
    return pts

# === Styles variés ===
configs = [
    {   # Style original (gardé intact)
        "gradient": ("vertical", (SECONDARY, SECONDARY_LIGHT)),
        "circles": [(WIDTH*0.75, HEIGHT*0.3), (WIDTH*0.2, HEIGHT*0.7)],
        "circle_radius": 400,
        "circle_color": ACCENT,
        "triangles": [
            ([(100, 200), (300, 50), (400, 300)], PRIMARY_LIGHT, PRIMARY, 2),
            ([(WIDTH-200, HEIGHT-300), (WIDTH-100, HEIGHT-100), (WIDTH-400, HEIGHT-200)], (*PRIMARY, 80), PRIMARY, 2),
            ([(WIDTH//2 - 100, 100), (WIDTH//2 + 50, 200), (WIDTH//2 - 150, 250)], ACCENT, None, 0)
        ],
        "text": ("LFS", (WIDTH//2, HEIGHT//2 - 50), PRIMARY_LIGHT),
        "dots": 200,
        "dot_color": PRIMARY,
        "extra_lines": True
    },
    {   # Variation : dégradé horizontal, cercles primaires, triangles plus grands
        "gradient": ("horizontal", (SECONDARY, PRIMARY_DARK)),
        "circles": [(WIDTH*0.3, HEIGHT*0.3), (WIDTH*0.7, HEIGHT*0.7)],
        "circle_radius": 300,
        "circle_color": PRIMARY_LIGHT,
        "triangles": [
            ([(50, 50), (200, 50), (125, 300)], PRIMARY, ACCENT, 3),
            ([(WIDTH-50, HEIGHT-50), (WIDTH-200, HEIGHT-50), (WIDTH-125, HEIGHT-300)], (*ACCENT, 100), PRIMARY, 2),
            ([(WIDTH//2, 50), (WIDTH//2+100, 200), (WIDTH//2-100, 200)], PRIMARY_LIGHT, None, 0)
        ],
        "text": ("LFS", (WIDTH//2, HEIGHT//2 + 50), PRIMARY_LIGHT),
        "dots": 150,
        "dot_color": ACCENT,
        "extra_lines": False
    },
    {   # Variation : dégradé diagonal, cercles verts, formes hexagonales (approximées)
        "gradient": ("diagonal", (SECONDARY, PRIMARY)),
        "circles": [(WIDTH*0.5, HEIGHT*0.5)],
        "circle_radius": 250,
        "circle_color": PRIMARY_LIGHT,
        "triangles": [
            ([(100, 400), (300, 200), (500, 400)], PRIMARY_LIGHT, ACCENT, 2),
            ([(WIDTH-100, HEIGHT-400), (WIDTH-300, HEIGHT-200), (WIDTH-500, HEIGHT-400)], (*ACCENT, 80), PRIMARY, 2),
            # Hexagone approximatif
            ([(WIDTH//2, 100), (WIDTH//2+150, 200), (WIDTH//2+150, 350), (WIDTH//2, 450), (WIDTH//2-150, 350), (WIDTH//2-150, 200)], (*PRIMARY, 60), ACCENT, 2)
        ],
        "text": ("LFS", (WIDTH//2, HEIGHT//2 - 80), PRIMARY_LIGHT),
        "dots": 100,
        "dot_color": PRIMARY,
        "extra_lines": True
    },
    {   # Variation : minimaliste, fond sombre, texte en accent
        "gradient": ("vertical", (SECONDARY, (10,10,20))),
        "circles": [(WIDTH*0.8, HEIGHT*0.2)],
        "circle_radius": 200,
        "circle_color": PRIMARY,
        "triangles": [
            ([(200, 200), (400, 100), (500, 300)], PRIMARY_LIGHT, ACCENT, 3)
        ],
        "text": ("LFS", (WIDTH//2, HEIGHT//2 - 20), ACCENT),
        "dots": 250,
        "dot_color": ACCENT,
        "extra_lines": False
    },
    {   # Variation : chaud, cercles dorés, lignes ondulées
        "gradient": ("vertical", (SECONDARY, (60, 40, 20))),
        "circles": [(WIDTH*0.2, HEIGHT*0.8), (WIDTH*0.6, HEIGHT*0.2)],
        "circle_radius": 350,
        "circle_color": (200, 180, 100),  # doré
        "triangles": [
            ([(50, 50), (150, 20), (200, 100)], (200, 180, 100), PRIMARY, 1),
            ([(WIDTH-50, HEIGHT-50), (WIDTH-150, HEIGHT-20), (WIDTH-200, HEIGHT-100)], (*PRIMARY, 80), ACCENT, 2)
        ],
        "text": ("LFS", (WIDTH//2, HEIGHT//2 + 30), (200, 180, 100)),
        "dots": 120,
        "dot_color": (200, 180, 100),
        "extra_lines": True
    }
]

# === Génération ===
for idx, cfg in enumerate(configs):
    # Créer l'image
    img = Image.new('RGBA', (WIDTH, HEIGHT), SECONDARY)
    draw = ImageDraw.Draw(img)

    # Dégradé
    grad_orient, grad_colors = cfg["gradient"]
    draw_gradient(draw, grad_colors, grad_orient)

    # Cercles
    if cfg["circles"]:
        draw_circles(draw, cfg["circles"], cfg["circle_radius"], cfg["circle_color"])

    # Triangles
    if cfg["triangles"]:
        draw_triangles(draw, cfg["triangles"])

    # Texte
    text, pos, color = cfg["text"]
    font_path = "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"
    try:
        font = ImageFont.truetype(font_path, 180)
    except:
        font = ImageFont.load_default()
    # Ombre
    draw.text((pos[0]+10, pos[1]+10), text, font=font, fill=(0,0,0,128))
    draw.text(pos, text, font=font, fill=color)
    # Effet de lueur (simple)
    for i in range(5):
        offset = i * 2
        alpha = 255 - i * 40
        draw.text((pos[0]-offset, pos[1]-offset), text, font=font, fill=(*PRIMARY, alpha))
        draw.text((pos[0]+offset, pos[1]+offset), text, font=font, fill=(*PRIMARY, alpha))

    # Points décoratifs
    if cfg["dots"] > 0:
        for _ in range(cfg["dots"]):
            x = random.randint(0, WIDTH)
            y = random.randint(0, HEIGHT)
            radius = random.randint(1, 4)
            color = cfg["dot_color"] if random.random() > 0.7 else SECONDARY_LIGHT
            draw.ellipse([x-radius, y-radius, x+radius, y+radius], fill=color, outline=None)

    # Lignes supplémentaires (optionnelles)
    if cfg.get("extra_lines", False):
        for x in range(0, WIDTH, 3):
            ratio = x / WIDTH
            r = int(PRIMARY[0] + (ACCENT[0] - PRIMARY[0]) * ratio)
            g = int(PRIMARY[1] + (ACCENT[1] - PRIMARY[1]) * ratio)
            b = int(PRIMARY[2] + (ACCENT[2] - PRIMARY[2]) * ratio)
            draw.line([(x, HEIGHT*0.85), (x+2, HEIGHT*0.85+10)], fill=(r, g, b), width=2)
        for x in range(WIDTH, 0, -2):
            ratio = x / WIDTH
            r = int(ACCENT[0] + (PRIMARY[0] - ACCENT[0]) * ratio)
            g = int(ACCENT[1] + (PRIMARY[1] - ACCENT[1]) * ratio)
            b = int(ACCENT[2] + (PRIMARY[2] - ACCENT[2]) * ratio)
            draw.line([(x, HEIGHT*0.9), (x-2, HEIGHT*0.9+8)], fill=(r, g, b), width=2)

    # Sauvegarde
    if idx == 0:
        # Le premier est le style original -> sauvegarde en tant que lfs-wallpaper.png
        img.save("lfs-wallpaper.png")
        print(f"✅ Style original sauvegardé : lfs-wallpaper.png")
    # Tous les styles sont sauvegardés avec un numéro
    img.save(f"lfs-wallpaper-{idx+1}.png")
    print(f"✅ Fond d'écran {idx+1} généré : lfs-wallpaper-{idx+1}.png")

print("\n🎨 Tous les fonds d'écran ont été générés !")