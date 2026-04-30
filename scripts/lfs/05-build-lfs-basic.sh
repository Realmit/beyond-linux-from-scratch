#!/bin/bash
# Build basic LFS system (run as lfs user after chroot)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Building basic LFS system"

if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

# Créer les répertoires
mkdir -pv $LFS/{dev,proc,sys,run,etc,home,root,boot,usr,var,lib64,bin,sbin}
mkdir -pv $LFS/usr/{bin,lib,sbin,include,share}
mkdir -pv $LFS/etc/profile.d

# Copier bash et les outils essentiels
log_info "Copying essential binaries to LFS environment"
mkdir -p $LFS/bin $LFS/usr/bin

for tool in bash sh ls cp mv mkdir rm cat echo; do
    if [ -f "/bin/$tool" ]; then
        cp -v /bin/$tool $LFS/bin/ 2>/dev/null || true
    fi
done

# Copier les bibliothèques nécessaires
mkdir -p $LFS/lib $LFS/lib64
if [ -d "/lib/x86_64-linux-gnu" ]; then
    cp -rv /lib/x86_64-linux-gnu/* $LFS/lib/ 2>/dev/null || true
fi
if [ -d "/lib64" ]; then
    cp -rv /lib64/* $LFS/lib64/ 2>/dev/null || true
fi

# Monter les systèmes de fichiers
log_info "Mounting virtual filesystems"
mount --bind /dev $LFS/dev 2>/dev/null || true
mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
mount -t proc proc $LFS/proc 2>/dev/null || true
mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# Vérifier que bash est présent
if [ ! -x "$LFS/bin/bash" ] && [ ! -x "$LFS/usr/bin/bash" ]; then
    log_error "bash not found in LFS environment"
    exit 1
fi

# Créer le script de build
cat > $LFS/build-basic.sh << 'INNEREOF'
#!/bin/bash
set -e
echo "Inside chroot - building basic system"
cd /sources

# Build gettext
if ls gettext-*.tar.xz 1>/dev/null 2>&1; then
    echo "Building gettext"
    tar -xf gettext-*.tar.xz
    cd gettext-*
    ./configure --prefix=/usr --disable-shared
    make -j$(nproc)
    make install
    cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
    cd ..
fi

echo "Basic system build complete!"
INNEREOF

chmod +x $LFS/build-basic.sh

# Exécuter dans le chroot
log_info "Entering chroot"
chroot $LFS /bin/bash /build-basic.sh

# Nettoyer
umount $LFS/dev/pts 2>/dev/null || true
umount $LFS/dev 2>/dev/null || true
umount $LFS/proc 2>/dev/null || true
umount $LFS/sys 2>/dev/null || true
umount $LFS/run 2>/dev/null || true

log_info "Basic LFS system build complete!"
