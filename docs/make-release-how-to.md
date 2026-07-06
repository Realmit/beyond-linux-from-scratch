## Using `make-release.sh` with the new release strategy (cache + ISO)

### 1. The role of `make-release.sh`

This script **versions the source code**:
- Extracts the version from `builder.py`
- Creates a Git tag (e.g. `v4.3.0`)
- Generates a tarball of the code (without heavy build artifacts)

It does **not** build the cache or the ISO.  
Those are produced and published by GitHub Actions workflows.

---

### 2. New release strategy (cache + ISO)

You have two workflows:

| Workflow | Trigger | Produces |
|----------|---------|----------|
| `XFCE SYSVINIT x86_64 Build Live ISO` (or similar) | Manual or scheduled | Builds everything from scratch → cache `.tar.xz` + ISO, published in a **release** |
| `Build ISO from Cache` | Manual | Downloads the cache from the **latest release**, runs the final stages → ISO, published in a separate **release** |

---

### 3. How to use `make-release.sh` in this context

#### Case A – You want to publish a new major source code version (and then trigger builds)

1. **Update the version** in `builder.py` (e.g. `__version__ = "4.4.0"`).
2. **Run** `./make-release.sh --no-tar` (or without `--no-tar` if you want a local tarball).
   ```bash
   ./make-release.sh --no-tar   # creates the tag without a tarball
   ```
   Or with tarball if you plan to upload it manually.
3. **Push the tag**:
   ```bash
   git push origin v4.4.0
   ```
4. **Manually trigger** the full build workflow (or wait for the schedule).  
   In GitHub Actions, go to the `XFCE SYSVINIT x86_64 Build Live ISO` workflow and click **Run workflow**.  
   It will use the code from the tag you just pushed (since you are on the default branch).  
   → A release will be created with the cache and ISO (default tag `v4.3.0-live` or similar – you can adjust the tag in the workflow).

#### Case B – You only want to rebuild an ISO from an existing cache (no recompilation)

1. Ensure a previous release contains `rootfs.tar.xz`.
2. Manually run the `Build ISO from Cache` workflow (via GitHub Actions).
   - It will download the cache from the latest release, run the final scripts, and publish a new release with the ISO (tag `v4.3.0-live-from-cache-<number>`).

---

### 4. Adapting `make-release.sh` for the new flow (optional)

If you want `make-release.sh` to also create a tag that the workflows will use, you can modify the workflows to use **the same tag** created by the script.

For example, in the `Build ISO from Cache` workflow, instead of using a fixed tag, you could:

- Fetch the latest Git tag (via `git describe --tags`) and use it as a base.
- Or use the tag created by `make-release.sh` to name the release.

However, currently the workflows use dedicated tags (`v4.3.0-live`, `v4.3.0-live-from-cache-...`). This is simpler for distinguishing artifacts.

---

### 5. Final recommendation

- Use `make-release.sh` **only for versioning the source code** (tag + tarball).
- For builds (cache and ISO), **use the GitHub Actions workflows**.
- If you want to link them, you can automate triggering the build workflow after tag creation (via `on: push tags`). But it's not required.

**In short**:

```bash
# 1. Update version in builder.py
vim builder.py

# 2. Create tag and tarball
./make-release.sh

# 3. Push the tag
git push origin vX.Y.Z

# 4. Go to GitHub Actions and manually trigger the full build workflow or the "Build ISO from Cache" workflow
```

---

### 6. If you want the build workflow to use the tag created by `make-release.sh`

Modify the `XFCE SYSVINIT x86_64 Build Live ISO` workflow to use the tag as the release name:

```yaml
- name: Create Release and Upload Artifacts
  uses: softprops/action-gh-release@v2
  with:
    tag_name: ${{ github.ref_name }}   # uses the triggering tag
    name: "LFS Builder ${{ github.ref_name }}"
    # ...
```

But then the workflow must be triggered by `on: push tags` to capture the tag. You can add:

```yaml
on:
  push:
    tags:
      - 'v*'
```

Thus, whenever you push a tag, the workflow will build everything and publish the release with that tag.

---

With these explanations, you can use `make-release.sh` with full understanding and orchestrate your releases as you wish.