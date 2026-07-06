## How to use the LFS wallpaper generator

### Generate all 15 images as PNG at 1920×1080 (default behavior)
```bash
python3 wblfs-wallpaper-generator.py
```

### Generate only the first 5 images as JPEG quality 90, in a custom folder
```bash
python3 wblfs-wallpaper-generator.py -o ./wallpapers -f jpg -q 90 -n 5
```

### Generate a lighter preview version (800×600)
```bash
python3 wblfs-wallpaper-generator.py --width 800 --height 600
```

### Use an external JSON configuration file
```bash
python3 wblfs-wallpaper-generator.py --config-file my_configs.json
```

---

## Example external JSON file

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