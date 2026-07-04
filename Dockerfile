FROM ubuntu:22.04

# Installer les dépendances
RUN apt update && apt install -y \
    build-essential bison flex gawk texinfo \
    wget curl git python3 python3-pip \
    grub-pc-bin \
    grub-efi-amd64-bin \
    xorriso isolinux mtools dosfstools squashfs-tools \
    parted rsync sudo \
    && rm -rf /var/lib/apt/lists/*

# Créer un utilisateur non-root
RUN useradd -m -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
WORKDIR /home/builder

# Copier les scripts
COPY --chown=builder:builder . /home/builder/lfs-builder

WORKDIR /home/builder/lfs-builder

# Lancer le build
CMD ["python3", "builder.py", "--profile", "xfce", "--output", "/output"]