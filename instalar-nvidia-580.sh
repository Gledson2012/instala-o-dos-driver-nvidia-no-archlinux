#!/bin/bash
#
# Driver NVIDIA 580xx (legacy) para GeForce MX110 [GP108 / Pascal]
# Arch Linux + KDE Plasma -- Samsung 340XAA/350XAA/550XAA (i7-8550U + MX110)
#
#   USO:  sudo bash ~/instalar-nvidia-580.sh
#
#por que a serie 580: o driver NVIDIA 590+ removeu suporte a Pascal.
#580.xx e o ultimo branch que suporta a MX110 (10de:174e).
#
# NOTA: o AUR nao pode ser instalado diretamente como root (o paru recusa por
# design). Por isso a fase 3 faz o build com makepkg como usuario normal e so
# a instalacao final (.pkg.tar.zst) roda como root.
#
set -uo pipefail

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[aviso] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[ERRO] %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "execute com sudo: sudo bash $0"

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
[ -n "$USER_HOME" ] || USER_HOME="/home/$REAL_USER"
BUILD="$USER_HOME/.cache/nvidia-580-build"
AUR="https://aur.archlinux.org"

# ---------------------------------------------------------------- 1. dependencias
say "1/8  Dependencias de compilacao (dkms, headers, pahole, vulkan-headers)"
pacman -S --needed --noconfirm dkms linux-headers bc vulkan-headers || die "falha ao instalar dependencias"

# ---------------------------------------------------------------- 2. remover 590+
say "2/8  Removendo pacotes nvidia-open / nvidia-utils da serie 615 (incompativel com Pascal)"
pacman -Rns --noconfirm nvidia-open nvidia-utils 2>/dev/null \
  || warn "nada a remover (ja ausentes)"

# ---------------------------------------------------------------- 3. deps de runtime
say "3/8  Restaurando as bibliotecas EGL e as lib32 removidas como orfas"
# egl-* foram removidos em 2/8 por serem orfas do nvidia-utils, mas sao
# dependencias obrigatorias do nvidia-580xx-utils. As lib32 servem ao
# suporte a jogos de 32 bits.
pacman -S --needed --noconfirm \
  libglvnd egl-wayland egl-gbm egl-x11 \
  lib32-zlib lib32-gcc-libs lib32-libglvnd \
  || die "falha ao instalar dependencias de runtime"

# ---------------------------------------------------------------- 4. build (sem root)
say "4/8  Compilando os pacotes do AUR como usuario '$REAL_USER' (sem root)"
echo "    Isso baixa ~1.4 GB e gera os .pkg.tar.zst. Pode levar varios minutos."

install -d -o "$REAL_USER" -g "$REAL_USER" "$BUILD"

# O script de build e escrito com heredoc QUOTED ('EOF'), ou seja, nenhuma
# variavel e expandida aqui: ele recebe os valores por ambiente. Isso evita
# o emaranhado de aspas de um 'bash -c "..."' aninhado.
BUILD_SCRIPT="$BUILD/build-aur.sh"
cat > "$BUILD_SCRIPT" <<'BUILD_EOF'
set -euo pipefail
cd "$BUILD_DIR"

# nvidia-580xx-utils        -> nvidia-580xx-utils, opencl-nvidia-580xx, nvidia-580xx-dkms
# nvidia-580xx-settings     -> nvidia-580xx-settings, libxnvctrl-580xx
# lib32-nvidia-580xx-utils  -> lib32-nvidia-580xx-utils, lib32-opencl-nvidia-580xx
REPOS="nvidia-580xx-utils nvidia-580xx-settings lib32-nvidia-580xx-utils"

for repo in $REPOS; do
    if [ -f "$repo/PKGBUILD" ]; then
        echo "  -- $repo: PKGBUILD em cache, tentando atualizar"
        git -C "$repo" pull --ff-only >/dev/null 2>&1 \
          || echo "     (sem acesso ao historico; usando a copia em cache)"
    else
        rm -rf "$repo"
        echo "  -- $repo: clonando"
        git clone --depth 1 "$AUR_URL/$repo.git" "$repo"
    fi
done

echo
echo "  === compilando com makepkg ==="
for repo in $REPOS; do
    echo
    echo "  ###### $repo ######"
    cd "$BUILD_DIR/$repo"
    rm -f ./*.pkg.tar.zst
    # -d (--nodeps): dependencias de sistema ja instaladas nas etapas 1 e 3;
    # evita erro no nvidia-580xx-settings que lista nvidia-580xx-utils antes deste estar instalado no sistema
    makepkg -d -f --noconfirm --cleanbuild
    cd "$BUILD_DIR"
done

echo
echo "  === pacotes gerados ==="
find "$BUILD_DIR" -maxdepth 2 -name '*.pkg.tar.zst' ! -name '*-debug-*' -exec ls -lh {} \;
BUILD_EOF

chown "$REAL_USER:$REAL_USER" "$BUILD_SCRIPT"
chmod +x "$BUILD_SCRIPT"

sudo -u "$REAL_USER" -H env BUILD_DIR="$BUILD" AUR_URL="$AUR" \
  bash "$BUILD_SCRIPT" \
  || die "falha no build dos pacotes do AUR (veja o log acima)"

# ---------------------------------------------------------------- 5. instalar
say "5/8  Instalando os pacotes compilados (aqui o DKMS compila o modulo)"
PKGS=$(find "$BUILD" -maxdepth 2 -name "*.pkg.tar.zst" ! -name "*-debug-*" | sort)
[ -n "$PKGS" ] || die "nenhum .pkg.tar.zst foi gerado -- build falhou?"
echo "$PKGS" | sed 's/^/     /'

pacman -U --noconfirm $PKGS || die "falha ao instalar os pacotes compilados"

# ---------------------------------------------------------------- 6. dkms status
say "6/8  Verificando o registro do DKMS"
dkms status || warn "dkms status retornou erro"
dkms status | grep -q "installed" \
  || die "modulo DKMS nao instalado -- NAO reinicie.
     Diagnostico: dkms status  /  /var/lib/dkms/nvidia/*/build/make.log"

# ---------------------------------------------------------------- 7. nouveau + modprobe + initramfs
say "7/8  Configurando nouveau, modprobe e initramfs"

cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
# criado por instalar-nvidia-580.sh
blacklist nouveau
options nouveau modeset=0
EOF

cat > /etc/modprobe.d/nvidia.conf <<'EOF'
# criado por instalar-nvidia-580.sh
# modeset=1 e obrigatorio para o Wayland do KDE Plasma usar a NVIDIA
options nvidia_drm modeset=1 fbdev=1
EOF

# MODULES do mkinitcpio: garante que os modulos nvidia entrem no initramfs
if grep -qE '^MODULES=.*nvidia' /etc/mkinitcpio.conf 2>/dev/null; then
  say "Modulos nvidia ja presentes em /etc/mkinitcpio.conf"
elif grep -qE '^MODULES=\(\)' /etc/mkinitcpio.conf 2>/dev/null; then
  sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
elif grep -q '^MODULES=' /etc/mkinitcpio.conf 2>/dev/null; then
  sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
else
  warn "MODULES nao encontrado em /etc/mkinitcpio.conf -- pulando"
fi
grep -E '^MODULES=' /etc/mkinitcpio.conf

mkinitcpio -P || warn "mkinitcpio retornou erro (veja acima)"

# ---------------------------------------------------------------- 8. resumo
say "8/8  Verificacao final"
echo "--- dkms status ---";  dkms status
echo
echo "--- modulos compilados ---"; find /usr/lib/modules/ -name "nvidia*.ko*" 2>/dev/null || true
echo
echo "--- pacotes nvidia instalados ---"; pacman -Q | grep -iE 'nvidia|xnvctrl' || true

KVER_RUN=$(uname -r)
KVER_MOD=$(basename "$(ls -d /usr/lib/modules/*/ 2>/dev/null | tail -1)")
cat <<EOF

=====================================================================
 INSTALACAO CONCLUIDA
=====================================================================

Falta REINICIAR:

    sudo reboot

Verifique depois:

    nvidia-smi                     # deve listar a GeForce MX110
    dkms status
    cat /proc/driver/nvidia/version

ATENCAO -- kernel:
    rodando agora : $KVER_RUN
    modulo DKMS   : $KVER_MOD
    Se nvidia-smi falhar com "couldn't communicate with the NVIDIA
    driver", reinicie novamente: o modulo so entra no boot para o kernel
    em que foi compilado. Como este sistema usa UKI (unified kernel
    image) no Limine, existe uma unica entrada e ela ja foi regenerada
    com o modulo incluido.

Sua maquina e hibrida (Intel UHD 620 + NVIDIA MX110): o Intel continua
como GPU principal, o que economiza bateria. Para rodar um app na
NVIDIA, use o "Executar com GPU NVIDIA" do menu do Plasma, ou:

    prime-run <programa>

Ajuste fino de energia/desempenho:

    nvidia-settings

=====================================================================
EOF