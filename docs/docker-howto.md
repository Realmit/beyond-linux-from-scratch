```bash
docker run --rm -it \
-v "$(pwd):/lfs-builder" \
-v "$(pwd)/lfs-output:/output" \
-w /lfs-builder \
lfs-builder-mac:latest \
python3 builder.py \
--profile xfce \
--output /output \
--config config/build.conf \
--init sysvinit
```