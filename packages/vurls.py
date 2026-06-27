#!/usr/bin/env python3
import re
from pathlib import Path

original = Path("sources.list")
validated = Path("sources.list.validated")

# Lire les URL valides
valid_urls = set()
with open(validated) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#'):
            # Extraire l'URL (sans commentaire)
            url = line.split('#')[0].strip()
            if url:
                valid_urls.add(url)

# Annoter l'original
with open(original) as f_in, open("sources.list.annotated", "w") as f_out:
    for line in f_in:
        stripped = line.strip()
        # Si c'est une ligne de commentaire ou vide, on la garde telle quelle
        if not stripped or stripped.startswith('#'):
            f_out.write(line)
            continue
        # Extraire l'URL (peut avoir des commentaires inline)
        parts = stripped.split('#')
        url = parts[0].strip()
        if not url:
            f_out.write(line)
            continue
        # Vérifier si l'URL est dans la liste validée
        if url in valid_urls:
            f_out.write(line)
        else:
            # Ajouter un commentaire en fin de ligne
            if len(parts) > 1:
                # Il y avait déjà un commentaire inline
                f_out.write(f"{parts[0].strip()}  # INVALID (original comment: {parts[1].strip()})\n")
            else:
                f_out.write(f"{line.rstrip()}  # INVALID\n")