Pour utiliser `make-release.sh` avec la nouvelle stratégie de release (cache + ISO), voici comment orchestrer le tout.

---

## 1. Le rôle de `make-release.sh`

Ce script **versionne le code source** :
- Extrait la version depuis `builder.py`
- Crée un tag Git (ex: `v4.3.0`)
- Génère un tarball du code (sans les artefacts lourds)

**Il ne crée pas** le cache ni l’ISO.  
Ce sont les workflows GitHub Actions qui les produisent et les publient.

---

## 2. Nouvelle stratégie de release (cache + ISO)

Vous avez deux workflows :

| Workflow | Déclenchement | Produit |
|----------|---------------|---------|
| `XFCE SYSVINIT x86_64 Build Live ISO` (ou similaire) | Manuel ou schedule | Construit tout depuis zéro → cache `.tar.xz` + ISO, publiés dans une **release** |
| `Build ISO from Cache` | Manuel | Télécharge le cache de la **dernière release**, exécute les étapes finales → ISO, publié dans une **release** séparée |

---

## 3. Comment utiliser `make-release.sh` dans ce contexte

### Cas A – Vous voulez publier une nouvelle version majeure du code source (et ensuite déclencher les builds)

1. **Mettez à jour la version** dans `builder.py` (par exemple `__version__ = "4.4.0"`).
2. **Exécutez** `./make-release.sh --no-tar` (ou avec `--no-tar` si vous ne voulez pas le tarball local, ou l'inclure selon vos besoins).
   ```bash
   ./make-release.sh --no-tar   # crée le tag sans tarball
   ```
   Ou bien avec tarball si vous voulez l'uploader manuellement.
3. **Poussez le tag** :
   ```bash
   git push origin v4.4.0
   ```
4. **Déclenchez manuellement** le workflow de build complet (ou attendez le schedule).  
   Dans GitHub Actions, allez sur le workflow `XFCE SYSVINIT x86_64 Build Live ISO` et cliquez sur **Run workflow**.  
   Il utilisera le code du tag que vous venez de pousser (car vous êtes sur la branche par défaut).  
   → Une release sera créée avec le cache et l’ISO (tag par défaut `v4.3.0-live` ou similaire – vous pouvez adapter le tag dans le workflow).

### Cas B – Vous voulez simplement reconstruire un ISO à partir d’un cache existant (sans recompiler)

1. Assurez-vous qu’une release précédente contient `rootfs.tar.xz`.
2. Lancez le workflow `Build ISO from Cache` manuellement (via GitHub Actions).
    - Il va télécharger le cache de la dernière release, exécuter les scripts finaux, et publier une nouvelle release avec l’ISO (tag `v4.3.0-live-from-cache-<numéro>`).

---

## 4. Adapter `make-release.sh` pour le nouveau flux (optionnel)

Si vous voulez que `make-release.sh` crée également un tag qui sera utilisé par les workflows, vous pouvez modifier les workflows pour qu’ils utilisent **le même tag** que celui créé par le script.

Par exemple, dans le workflow `Build ISO from Cache`, au lieu de créer un tag fixe, vous pourriez :

- Récupérer le dernier tag Git (via `git describe --tags`) et l’utiliser comme base.
- Ou utiliser le tag créé par `make-release.sh` pour nommer la release.

Mais actuellement, les workflows utilisent des tags dédiés (`v4.3.0-live`, `v4.3.0-live-from-cache-...`). C’est plus simple pour distinguer les artefacts.

---

## 5. Recommandation finale

- Utilisez `make-release.sh` uniquement pour **versionner le code source** (tag + tarball).
- Pour les builds (cache et ISO), **utilisez les workflows GitHub Actions**.
- Si vous voulez lier les deux, vous pouvez automatiser le déclenchement du workflow de build après la création du tag (via un trigger `on: push tags`). Mais ce n’est pas nécessaire.

**En résumé** :

```bash
# 1. Mettre à jour la version dans builder.py
vim builder.py

# 2. Créer le tag et le tarball
./make-release.sh

# 3. Pousser le tag
git push origin vX.Y.Z

# 4. Aller sur GitHub Actions et lancer manuellement le workflow de build complet ou le workflow "Build ISO from Cache"
```

---

## 6. Si vous voulez que le workflow de build utilise le tag créé par `make-release.sh`

Modifiez le workflow `XFCE SYSVINIT x86_64 Build Live ISO` pour qu’il utilise le tag comme nom de release :

```yaml
- name: Create Release and Upload Artifacts
  uses: softprops/action-gh-release@v2
  with:
    tag_name: ${{ github.ref_name }}   # utilise le tag déclencheur
    name: "LFS Builder ${{ github.ref_name }}"
    # ...
```

Mais alors, il faut que le workflow soit déclenché par `on: push tags` pour récupérer le tag. Vous pouvez ajouter :

```yaml
on:
  push:
    tags:
      - 'v*'
```

Et ainsi, dès que vous poussez un tag, le workflow construira tout et publiera la release avec ce tag.

---

**Avec ces explications, vous pouvez utiliser `make-release.sh` en toute connaissance de cause, et orchestrer vos releases comme vous le souhaitez.**