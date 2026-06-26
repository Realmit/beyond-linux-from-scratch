#!/usr/bin/env python3
"""
Générateur de fond d'écran LFS
Utilise les couleurs du thème GTK personnalisé
Couleurs :
  - Primaire : #2E8B57 (vert LFS)
  - Secondaire : #1a1a2e (bleu nuit)
  - Accent : #90EE90 (vert clair)
  - Texte : #f0f0f0
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import random

# === Couleurs ===
PRIMARY = (46, 139, 87)       # #2E8B57
PRIMARY_DARK = (35, 107, 67)  # #236B43
PRIMARY_LIGHT = (60, 179, 113) # #3CB371
SECONDARY = (26, 26, 46)      # #1a1a2e
SECONDARY_LIGHT = (37, 37, 53) # #252535
ACCENT = (144, 238, 144)      # #90EE90
TEXT_COLOR = (240, 240, 240)  # #f0f0f0

WIDTH, HEIGHT = 1920, 1080

# === Création de l'image ===
img = Image.new('RGB', (WIDTH, HEIGHT), SECONDARY)
draw = ImageDraw.Draw(img)

# === Dégradé vertical (du secondaire vers une version plus claire) ===
for y in range(HEIGHT):
    ratio = y / HEIGHT
    r = int(SECONDARY[0] + (SECONDARY_LIGHT[0] - SECONDARY[0]) * ratio)
    g = int(SECONDARY[1] + (SECONDARY_LIGHT[1] - SECONDARY[1]) * ratio)
    b = int(SECONDARY[2] + (SECONDARY_LIGHT[2] - SECONDARY[2]) * ratio)
    draw.line([(0, y), (WIDTH, y)], fill=(r, g, b))

# === Cercle lumineux (accent) ===
# Cercle 1 (grand, translucide)
circle_center = (WIDTH * 0.75, HEIGHT * 0.3)
radius = 400
for r in range(radius, 0, -1):
    alpha = int(255 * (1 - r / radius) * 0.15)
    color = (*ACCENT, alpha)
    draw.ellipse([circle_center[0]-r, circle_center[1]-r,
                  circle_center[0]+r, circle_center[1]+r],
                 outline=None, fill=color)

# Cercle 2 (plus petit, vert primaire)
circle_center2 = (WIDTH * 0.2, HEIGHT * 0.7)
radius2 = 300
for r in range(radius2, 0, -1):
    alpha = int(255 * (1 - r / radius2) * 0.1)
    color = (*PRIMARY, alpha)
    draw.ellipse([circle_center2[0]-r, circle_center2[1]-r,
                  circle_center2[0]+r, circle_center2[1]+r],
                 outline=None, fill=color)

# === Lignes décoratives ===
# Ligne horizontale avec dégradé
for x in range(0, WIDTH, 2):
    ratio = x / WIDTH
    r = int(PRIMARY[0] + (ACCENT[0] - PRIMARY[0]) * ratio)
    g = int(PRIMARY[1] + (ACCENT[1] - PRIMARY[1]) * ratio)
    b = int(PRIMARY[2] + (ACCENT[2] - PRIMARY[2]) * ratio)
    draw.line([(x, HEIGHT * 0.85), (x + 2, HEIGHT * 0.85 + 10)], fill=(r, g, b), width=2)

# Une autre ligne plus bas
for x in range(WIDTH, 0, -2):
    ratio = x / WIDTH
    r = int(ACCENT[0] + (PRIMARY[0] - ACCENT[0]) * ratio)
    g = int(ACCENT[1] + (PRIMARY[1] - ACCENT[1]) * ratio)
    b = int(ACCENT[2] + (PRIMARY[2] - ACCENT[2]) * ratio)
    draw.line([(x, HEIGHT * 0.9), (x - 2, HEIGHT * 0.9 + 8)], fill=(r, g, b), width=2)

# === Triangles géométriques (style) ===
def draw_triangle(draw, points, fill, outline=None, width=0):
    draw.polygon(points, fill=fill, outline=outline, width=width)

# Triangle 1
points1 = [(100, 200), (300, 50), (400, 300)]
draw_triangle(draw, points1, fill=PRIMARY_LIGHT, outline=PRIMARY, width=2)

# Triangle 2 (plus grand, translucide)
points2 = [(WIDTH-200, HEIGHT-300), (WIDTH-100, HEIGHT-100), (WIDTH-400, HEIGHT-200)]
draw_triangle(draw, points2, fill=(*PRIMARY, 80), outline=PRIMARY, width=2)

# Triangle 3 (petit)
points3 = [(WIDTH//2 - 100, 100), (WIDTH//2 + 50, 200), (WIDTH//2 - 150, 250)]
draw_triangle(draw, points3, fill=ACCENT, outline=None)

# === Texte "LFS" ===
try:
    # Essayer de charger une police (si disponible)
    font_path = "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"
    font = ImageFont.truetype(font_path, 180)
except:
    # Fallback: police par défaut
    font = ImageFont.load_default()

text = "LFS"
# Position
text_width = draw.textlength(text, font=font)  # pour PIL >= 8.0
if 'textlength' not in dir(draw):
    # Fallback: approximatif
    text_width = len(text) * 100
text_x = (WIDTH - text_width) // 2
text_y = (HEIGHT - 200) // 2

# Ombre portée
shadow_offset = 10
draw.text((text_x + shadow_offset, text_y + shadow_offset), text, font=font, fill=(0,0,0,128))

# Texte principal (avec dégradé)
# On ne peut pas faire de dégradé direct, on dessine lettre par lettre ou on utilise un filtre
# On va simplement appliquer un dégradé via un rectangle en mode "blend" ?
# Plus simple: dessiner le texte en blanc, puis appliquer un filtre ?
# Pour un effet "dégradé", on peut dessiner un rectangle avec un dégradé sur le texte, mais compliqué.
# Solution: dessiner en blanc, puis créer un masque avec le texte et colorier.
# On va plutôt utiliser un contour en couleur.

draw.text((text_x, text_y), text, font=font, fill=PRIMARY_LIGHT)
draw.text((text_x - 3, text_y - 3), text, font=font, fill=PRIMARY)
draw.text((text_x + 3, text_y + 3), text, font=font, fill=ACCENT)

# Effet de lueur autour du texte (simple)
for i in range(5):
    offset = i * 2
    alpha = 255 - i * 40
    draw.text((text_x - offset, text_y - offset), text, font=font, fill=(*PRIMARY, alpha))
    draw.text((text_x + offset, text_y + offset), text, font=font, fill=(*PRIMARY, alpha))

# === Ajout d'un motif subtil (cercles) ===
for _ in range(200):
    x = random.randint(0, WIDTH)
    y = random.randint(0, HEIGHT)
    radius = random.randint(1, 4)
    color = PRIMARY if random.random() > 0.7 else SECONDARY_LIGHT
    draw.ellipse([x-radius, y-radius, x+radius, y+radius], fill=color, outline=None)

# === Flou sur certains éléments ? ===
# On pourrait appliquer un flou gaussien sur une copie pour un effet de profondeur, mais on garde simple.

# === Sauvegarde ===
img.save("lfs-wallpaper.png")
print("Fond d'écran généré : lfs-wallpaper.png")