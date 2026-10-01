# Instalação do Driver NVIDIA 580xx (Legacy) no Arch Linux

Script automatizado de instalação do driver **NVIDIA 580xx** para placas com arquitetura **Pascal** (ex: **GeForce MX110** - `10de:174e`) no **Arch Linux** com **KDE Plasma** (Wayland / X11).

> **Aviso:** A partir da série 590+, a NVIDIA removeu o suporte a arquiteturas Pascal (como a GeForce MX110/MX130/MX150 e GTX 10xx). A série **580.xx** é a última versão com suporte a esses chips.

---

## 💻 Hardware Alvo / Testado

- **Notebooks:** Linha Samsung 340XAA, 350XAA, 550XAA (ou similares com gráficos híbridos).
- **Processador:** Intel Core i7-8550U (Intel UHD 620).
- **GPU Dedicada:** NVIDIA GeForce MX110 [GP108 / Pascal].
- **Sistema Operacional:** Arch Linux + KDE Plasma.

---

## ⚙️ O que o script faz?

1. **Dependências de compilação:** Instala `dkms`, `linux-headers`, `bc` e `vulkan-headers`.
2. **Limpeza de drivers incompatíveis:** Remove `nvidia-open` e `nvidia-utils` das séries 590/615+.
3. **Dependências de runtime:** Restaura bibliotecas EGL (`egl-wayland`, `egl-gbm`, `egl-x11`, `libglvnd`) e bibliotecas 32-bits para jogos (`lib32-nvidia-580xx-utils`, etc.).
4. **Compilação AUR segura:** Compila os pacotes do AUR (`nvidia-580xx-utils`, `nvidia-580xx-settings`, `lib32-nvidia-580xx-utils`) via `makepkg` sem permissão de root (evitando restrições do AUR/makepkg).
5. **Instalação:** Instala os pacotes `.pkg.tar.zst` gerados e aciona o DKMS para o kernel atual.
6. **Configuração de Módulos e DRM:**
   - Blacklist do driver open-source `nouveau`.
   - Ativação de `nvidia_drm modeset=1 fbdev=1` (necessário para Wayland no Plasma).
   - Inclusão dos módulos (`nvidia`, `nvidia_modeset`, `nvidia_uvm`, `nvidia_drm`) no `/etc/mkinitcpio.conf` e regeneração dos initramfs (`mkinitcpio -P`).
7. **Verificação pós-instalação:** Valida o status do DKMS e pacotes instalados.

---

## 🚀 Como Executar

Clone o repositório e execute o script com permissões de superusuário:

```bash
sudo bash instalar-nvidia-580.sh
```

---

## 🔄 Pós-Instalação

Após a conclusão com sucesso, reinicie a máquina:

```bash
sudo reboot
```

Para verificar o status da GPU e do driver:

```bash
nvidia-smi
dkms status
cat /proc/driver/nvidia/version
```

### Gráficos Híbridos (Optimus / PRIME)

A Intel UHD 620 continua como GPU primária para economia de bateria. Para executar qualquer programa ou jogo na NVIDIA dedicada:

- Pelo menu de aplicativos do KDE Plasma: clique com o botão direito e escolha **"Executar com GPU NVIDIA"**.
- Pelo terminal:

```bash
prime-run <comando>
```

Para abrir o painel de configurações da NVIDIA:

```bash
nvidia-settings
```
