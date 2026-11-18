#!/bin/bash
# Monta a ISO do Play Musica.  Uso:  bash montar-iso.sh amd64   (PCs de 64 bits)
#                                    bash montar-iso.sh i386    (PCs antigos de 32 bits)
set -e
ARCH="${1:-amd64}"
case "$ARCH" in
  amd64) FLAV="amd64"; BOOT="" ;;
  i386)  FLAV="686";   BOOT="--bootloaders syslinux" ;;
  *) echo "Arquitetura invalida: $ARCH (use amd64 ou i386)"; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$ROOT/build"; mkdir -p "$ROOT/build"; cd "$ROOT/build"
mkdir -p auto config/package-lists config/hooks/normal
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/etc/systemd/system/getty@tty1.service.d
mkdir -p config/includes.chroot/opt/jukebox/musicas config/includes.chroot/opt/jukebox/imagem config/includes.chroot/opt/jukebox/som

# ---------------------------------------------------------------- auto/config
cat > auto/config <<'__FIM__'
#!/bin/sh
set -e
lb config noauto \
  --distribution bookworm \
  --architectures __ARCH__ \
  --binary-images iso-hybrid \
  --linux-flavours __FLAV__ \
  __BOOT__ \
  --archive-areas "main contrib non-free non-free-firmware" \
  --apt-recommends false \
  --debian-installer none \
  --iso-volume "PLAYMUSICA" \
  --iso-application "Play Musica" \
  --iso-publisher "Play Musica" \
  --memtest none \
  --bootappend-live "boot=live components quiet loglevel=0 noeject nomodeset vga=normal nosplash locales=pt_BR.UTF-8 keyboard-layouts=br timezone=America/Maceio" \
  "${@}"
__FIM__
sed -i "s|__ARCH__|$ARCH|; s|__FLAV__|$FLAV|; s|__BOOT__|$BOOT|" auto/config

# ------------------------------------------------------------ lista de pacotes
cat > config/package-lists/jukebox.list.chroot <<'__FIM__'
xserver-xorg
xserver-xorg-video-all
xserver-xorg-input-all
xserver-xorg-legacy
xserver-xorg-video-vesa
xserver-xorg-video-fbdev
libpam-systemd
dbus
dbus-user-session
xinit
x11-xserver-utils
openbox
unclutter-xfixes
chromium
libgl1-mesa-dri
python3
curl
dbus-x11
pulseaudio
pulseaudio-utils
alsa-utils
alsa-ucm-conf
ntfs-3g
exfatprogs
dosfstools
fonts-dejavu
fonts-noto-color-emoji
locales
kbd
console-setup
keyboard-configuration
firmware-linux-free
firmware-misc-nonfree
firmware-realtek
firmware-amd-graphics
__FIM__
if [ "$ARCH" = "amd64" ]; then
  echo "firmware-sof-signed" >> config/package-lists/jukebox.list.chroot
fi

# ------------------------------------------------------------------- servico
cat > config/includes.chroot/etc/systemd/system/jukebox-server.service <<'__FIM__'
[Unit]
Description=Play Musica - servidor local
After=local-fs.target systemd-udevd.service

[Service]
Environment=PYTHONUTF8=1 LANG=C.UTF-8
ExecStart=/usr/bin/python3 /opt/jukebox/server.py
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
__FIM__

cat > config/includes.chroot/etc/systemd/system/getty@tty1.service.d/zz-jukebox.conf <<'__FIM__'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin user --noclear %I $TERM
Type=idle
__FIM__

# Permite o X rodar sem root em qualquer placa de video
mkdir -p config/includes.chroot/etc/X11
cat > config/includes.chroot/etc/X11/Xwrapper.config <<'__FIM__'
allowed_users=anybody
needs_root_rights=yes
__FIM__


# Video: o listrado azul vinha do VESA em 24/32 bits (placa so aceita outro formato).
# Agora o padrao e VESA em 16 bits e 1024x768. O menu de boot (modo texto) deixa
# escolher outro modo: o parametro jbvideo=... e lido pelo .bash_profile.
cat > config/includes.chroot/etc/X11/xorg-vesa16.conf <<'__FIM__'
Section "Device"
    Identifier "Video"
    Driver "vesa"
EndSection
Section "Monitor"
    Identifier "Monitor0"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Video"
    Monitor "Monitor0"
    DefaultDepth 16
    SubSection "Display"
        Depth 16
        Modes "1024x768" "800x600" "640x480"
    EndSubSection
EndSection
__FIM__
cat > config/includes.chroot/etc/X11/xorg-vesa24.conf <<'__FIM__'
Section "Device"
    Identifier "Video"
    Driver "vesa"
EndSection
Section "Monitor"
    Identifier "Monitor0"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Video"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1024x768" "800x600" "640x480"
    EndSubSection
EndSection
__FIM__
cat > config/includes.chroot/etc/X11/xorg-fbdev.conf <<'__FIM__'
Section "Device"
    Identifier "Video"
    Driver "fbdev"
EndSection
__FIM__

# Som: evita estalos/mudez por economia de energia da placa HDA Intel
mkdir -p config/includes.chroot/etc/modprobe.d
cat > config/includes.chroot/etc/modprobe.d/jukebox-audio.conf <<'__FIM__'
options snd_hda_intel power_save=0 power_save_controller=N
__FIM__

cat > config/includes.chroot/etc/skel/.bash_profile <<'__FIM__'
# Abre o jukebox direto na tela cheia (sem desktop) ao logar no tty1.
# O modo de video vem do menu de boot (parametro jbvideo=... no kernel).
JB="$(tr ' ' '\n' < /proc/cmdline | sed -n 's/^jbvideo=//p' | head -n1)"
tentar() {  # tenta abrir o X; "ok" se ele ficou aberto por 20s ou mais
  t0=$(date +%s)
  if [ -n "$1" ]; then startx -- -config "$1"; else startx; fi
  [ $(( $(date +%s) - t0 )) -ge 20 ]
}
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ] && [ "$JB" != "texto" ]; then
  case "$JB" in
    vesa16) tentar xorg-vesa16.conf || tentar xorg-fbdev.conf ;;
    vesa24) tentar xorg-vesa24.conf || tentar xorg-vesa16.conf ;;
    fbdev)  tentar xorg-fbdev.conf  || tentar xorg-vesa16.conf ;;
    auto)   tentar ""               || tentar xorg-vesa16.conf ;;
    *)      tentar ""               || tentar xorg-fbdev.conf || tentar xorg-vesa16.conf ;;
  esac
  sleep 2
  exit
fi
[ "$JB" = "texto" ] && echo "Modo diagnostico (texto). Para abrir o jukebox digite: startx"
__FIM__

cat > config/includes.chroot/etc/skel/.xinitrc <<'__FIM__'
#!/bin/sh
export LANG=C.UTF-8
xset s off; xset s noblank; xset -dpms
unclutter -idle 1 -root &
openbox &

# Som: inicia o PulseAudio e deixa tudo no maximo e sem mudo
pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1
(
  sleep 5
  for c in 0 1 2 3 4 5 6 7; do
    amixer -q -c "$c" sset "Auto-Mute Mode" Disabled 2>/dev/null
    for ctl in Master Speaker Headphone PCM Front Surround Center LFE "Line Out" Line Digital "Master Mono"; do
      amixer -q -c "$c" sset "$ctl" 100% unmute 2>/dev/null
    done
  done
  S="$(pactl list short sinks 2>/dev/null | cut -f2 | grep -i analog | head -n1)"
  [ -n "$S" ] && pactl set-default-sink "$S"
  for s in $(pactl list short sinks 2>/dev/null | cut -f2); do
    pactl set-sink-mute "$s" 0
    pactl set-sink-volume "$s" 100%
  done
) &

# espera o servidor local subir
for i in $(seq 1 40); do
  curl -s -o /dev/null http://127.0.0.1:8765/api/fontes && break
  sleep 0.5
done

# abre em tela cheia e reabre sozinho se fechar/travar
while true; do
  chromium --kiosk --start-fullscreen --no-first-run --noerrdialogs --disable-infobars \
    --disable-session-crashed-bubble --disable-features=Translate --password-store=basic \
    --overscroll-history-navigation=0 --disable-pinch \
    --autoplay-policy=no-user-gesture-required \
    --disable-gpu --disable-dev-shm-usage \
    --user-data-dir=/tmp/chromium-jukebox \
    http://127.0.0.1:8765/index.html
  sleep 1
done
__FIM__

# --------------------------------------------------------------------- hooks
cat > config/hooks/normal/0100-jukebox.hook.chroot <<'__FIM__'
#!/bin/sh
set -e
systemctl enable jukebox-server.service
mkdir -p /mnt/jukebox
chmod +x /opt/jukebox/server.py
__FIM__

cat > config/hooks/normal/0200-boot-rapido.hook.binary <<'__FIM__'
#!/bin/sh
# Menu de boot (BIOS) em MODO TEXTO, sem vesamenu/graficos: entra sozinho no modo 1
# em 8 segundos, ou o usuario digita 1-5 e aperta ENTER para trocar o modo de video.
F=binary/isolinux/live.cfg
KER=""; INI=""; APP=""
if [ -f "$F" ]; then
  KER="$(grep -m1 -E '^[[:space:]]*(linux|kernel)[[:space:]]' "$F" | awk '{print $2}')"
  INI="$(grep -m1 -E '^[[:space:]]*initrd[[:space:]]' "$F" | awk '{print $2}')"
  APP="$(grep -m1 -E '^[[:space:]]*append[[:space:]]' "$F" | sed -E 's/^[[:space:]]*append[[:space:]]+//')"
fi
if [ -n "$KER" ] && [ -n "$INI" ] && [ -d binary/isolinux ]; then
  BASE="$(echo "$APP" | sed -E 's/(^| )nomodeset//g; s/(^| )vga=[^ ]+//g; s/(^| )splash//g')"
  DIAG="$(echo "$BASE" | sed -E 's/(^| )quiet//g; s/(^| )loglevel=[0-9]+//g')"
  cat > binary/isolinux/boot.txt <<'EOF'

   PLAY MUSICA - escolha o modo de video e aperte ENTER
   (sem escolher, entra sozinho no modo 1 em 8 segundos)

   1   Padrao (VESA 16 bits)
   2   Video: framebuffer (fbdev)
   3   Video: com aceleracao (KMS, sem nomodeset)
   4   Video: VESA 24 bits
   5   Diagnostico (so texto, mostra as mensagens)

EOF
  cat > binary/isolinux/isolinux.cfg <<EOF
prompt 1
timeout 80
default 1
display boot.txt

label 1
  linux $KER
  initrd $INI
  append $BASE nomodeset jbvideo=vesa16

label 2
  linux $KER
  initrd $INI
  append $BASE nomodeset vga=791 jbvideo=fbdev

label 3
  linux $KER
  initrd $INI
  append $BASE jbvideo=auto

label 4
  linux $KER
  initrd $INI
  append $BASE nomodeset jbvideo=vesa24

label 5
  linux $KER
  initrd $INI
  append $DIAG nomodeset jbvideo=texto
EOF
elif [ -f binary/isolinux/live.cfg ] && [ -f binary/isolinux/isolinux.cfg ]; then
  # plano B: so entra direto, sem menu
  L="$(grep -m1 "^label " binary/isolinux/live.cfg | awk "{print \$2}")"
  [ -n "$L" ] && sed -i -E "s/^default .*/default $L/" binary/isolinux/isolinux.cfg
  grep -q "^timeout" binary/isolinux/isolinux.cfg || echo "timeout 1" >> binary/isolinux/isolinux.cfg
  sed -i -E "s/^timeout .*/timeout 1/" binary/isolinux/isolinux.cfg
  grep -q "^prompt" binary/isolinux/isolinux.cfg || echo "prompt 0" >> binary/isolinux/isolinux.cfg
fi
# Menu do GRUB (boot UEFI, so amd64) com as mesmas opcoes de video.
# No UEFI o VESA nao funciona (nao ha BIOS de video), por isso o padrao la e o KMS.
G=binary/boot/grub/grub.cfg
GL=""
[ -f "$G" ] && GL="$(grep -m1 -E '^[[:space:]]*linux[[:space:]]' "$G")"
GI="$(grep -m1 -E '^[[:space:]]*initrd[[:space:]]' "$G" 2>/dev/null | awk '{print $2}')"
GK="$(echo "$GL" | awk '{print $2}')"
if [ -n "$GK" ] && [ -n "$GI" ]; then
  GA="$(echo "$GL" | sed -E 's/^[[:space:]]*linux[[:space:]]+[^[:space:]]+[[:space:]]*//')"
  GB="$(echo "$GA" | sed -E 's/(^| )nomodeset//g; s/(^| )vga=[^ ]+//g; s/(^| )splash//g')"
  GD="$(echo "$GB" | sed -E 's/(^| )quiet//g; s/(^| )loglevel=[0-9]+//g')"
  cat > "$G" <<EOF
set default=0
set timeout=8

menuentry "1  Padrao (KMS - aceleracao, melhor para UEFI)" {
  linux $GK $GB jbvideo=auto
  initrd $GI
}
menuentry "2  Video: framebuffer (fbdev)" {
  linux $GK $GB nomodeset jbvideo=fbdev
  initrd $GI
}
menuentry "3  Video: VESA 16 bits (so BIOS antigo)" {
  linux $GK $GB nomodeset jbvideo=vesa16
  initrd $GI
}
menuentry "4  Video: VESA 24 bits (so BIOS antigo)" {
  linux $GK $GB nomodeset jbvideo=vesa24
  initrd $GI
}
menuentry "5  Diagnostico (so texto, mostra as mensagens)" {
  linux $GK $GD nomodeset jbvideo=texto
  initrd $GI
}
EOF
else
  for f in binary/boot/grub/*.cfg; do
    [ -f "$f" ] && sed -i -E "s/^set timeout=.*/set timeout=0/" "$f"
  done
fi
exit 0
__FIM__

chmod +x auto/config config/hooks/normal/* config/includes.chroot/etc/skel/.xinitrc
cp "$ROOT/index.html" "$ROOT/server.py" config/includes.chroot/opt/jukebox/

if [ -n "$SO_GERAR" ]; then echo "Arvore gerada ($ARCH)."; exit 0; fi

lb config
lb build
ls -lh ./*.iso
mv ./*.iso "$ROOT/PlayMusica-$ARCH.iso"
