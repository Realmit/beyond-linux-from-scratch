## Comment utiliser le générateur de fonds d'écran LFS

## Générer les 15 images en PNG 1920x1080 (comportement original)
```bash
python3  wblfs-wallpaper-generator.py
```

# Générer seulement les 5 premières en JPEG qualité 90, dans un dossier spécifique
```bash
python3  wblfs-wallpaper-generator.py -o ./wallpapers -f jpg -q 90 -n 5
```

# Générer une version plus légère (800x600) pour aperçu
```bash
python3  wblfs-wallpaper-generator.py --width 800 --height 600
```
# Utiliser une configuration externe (fichier JSON)
```bash
python3  wblfs-wallpaper-generator.py --config-file mes_configs.json
```

## Exemple de fichier JSON externe

```json
[
  {
    "gradient": ["vertical", [[26,26,46], [37,37,53]]],
    "circles": [[1440, 324], [384, 756]],
    "circle_radius": 400,
    "circle_color": [144,238,144],
    "triangles": [
      [[[100,200],[300,50],[400,300]], [60,179,113], [46,139,87], 2]
    ],
    "text": ["LFS", [960, 490], [60,179,113]],
    "dots": 200,
    "dot_color": [46,139,87],
    "extra_lines": true
  }
]
```