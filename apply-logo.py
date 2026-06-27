import cairosvg
from PIL import Image
import io

# Charger le SVG
svg_data = b'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
    <rect width="200" height="200" rx="20" fill="#2E8B57"/>
    <text x="100" y="120" font-family="Arial" font-size="40" fill="white" text-anchor="middle" font-weight="bold">LFS</text>
    <text x="100" y="150" font-family="Arial" font-size="14" fill="#90EE90" text-anchor="middle">Linux From Scratch</text>
</svg>'''

# Convertir SVG en PNG en mémoire
png_data = cairosvg.svg2png(bytestring=svg_data, output_width=400, output_height=400)
logo_img = Image.open(io.BytesIO(png_data))

# Créer le fond d'écran (déjà généré précédemment)
wallpaper = Image.open("images/lfs-wallpaper.png")  # ou générez-en un neuf

# Positionner le logo au centre
logo_size = (400, 400)
x = (wallpaper.width - logo_size[0]) // 2
y = (wallpaper.height - logo_size[1]) // 2
wallpaper.paste(logo_img, (x, y), logo_img)  # le logo a un fond transparent (grâce au rectangle)
wallpaper.save("lfs-wallpaper-with-logo.png")
print("✅ Fond d'écran avec logo généré !")