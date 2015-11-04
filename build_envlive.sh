#!/bin/sh

# Load the config
source ./config.sh

# Preventively unmount filesystems
echo -n "Unmounting previously mounted filesystems, if any..."
umount -R ${PROLOLIVE_DIR}/boot  2>/dev/null
umount -R ${PROLOLIVE_DIR}       2>/dev/null
umount -R overlay-intermediate   2>/dev/null
umount -R ${PROLOLIVE_DIR}.light 2>/dev/null
umount -R ${PROLOLIVE_DIR}.big   2>/dev/null
umount -R ${PROLOLIVE_DIR}.full  2>/dev/null
umount -R *                      2>/dev/null
kpartx -r ${PROLOLIVE_IMG}       2>/dev/null
echo " Done."


# Allocate space for filesystems and the root
echo "Allocating filesystems files (will not overwrite existing files)..."
(test -f ${PROLOLIVE_IMG}.light && dd if=/dev/zero of=${PROLOLIVE_IMG}.light bs=1M count=1 conv=notrunc) || dd if=/dev/zero of=${PROLOLIVE_IMG}.light bs=1M count=1 seek=1000
(test -f ${PROLOLIVE_IMG}.big   && dd if=/dev/zero of=${PROLOLIVE_IMG}.big   bs=1M count=1 conv=notrunc) || dd if=/dev/zero of=${PROLOLIVE_IMG}.big   bs=1M count=1 seek=2500
(test -f ${PROLOLIVE_IMG}.full  && dd if=/dev/zero of=${PROLOLIVE_IMG}.full  bs=1M count=1 conv=notrunc) || dd if=/dev/zero of=${PROLOLIVE_IMG}.full  bs=1M count=1 seek=5000
test -f ${PROLOLIVE_IMG}                                                                                 || dd if=/dev/zero of=${PROLOLIVE_IMG}       bs=1M count=1 seek=3823
echo "Done."

# Partition the image disk file
echo "Partition the disk image"
sfdisk ${PROLOLIVE_IMG} < prololive.dos

# Create loop devices for the disk image file
echo "Generate device mappings for the disk image..."
LOOP=$(kpartx -av ${PROLOLIVE_IMG} | grep -o "loop[0-9]" | tail -n1)
# To avoid annoying messages about already existing filesystems.
dd if=/dev/zero of=/dev/mapper/${LOOP}p1 bs=1M count=1
dd if=/dev/zero of=/dev/mapper/${LOOP}p2 bs=1M count=1
echo "Done."

# Format all filesystems
echo "Format all filesystems..."
for f in ${PROLOLIVE_IMG}.full ${PROLOLIVE_IMG}.big ${PROLOLIVE_IMG}.light ; do
    mkfs.ext4 $f
done

mkfs.ext4 /dev/mapper/${LOOP}p1 -L proloboot
mkfs.ext4 /dev/mapper/${LOOP}p2 -L persistent

# Mount filesystems
echo -n "Mounting filesystems and adding working/ and system/ directories in each one..."
mkdir -p ${PROLOLIVE_DIR}/      # Where all FS will be union-mounted
mkdir -p ${PROLOLIVE_DIR}.light # Where the core OS filesystem will be mounted alone
mkdir -p ${PROLOLIVE_DIR}.big   # Where many light tools will be provided as well as DE/WP
mkdir -p ${PROLOLIVE_DIR}.full  # Where the biggest packages will go. Hi ghc!
mkdir -p overlay-intermediate   # Where .big will be mounted over .light
mkdir -p first-bind             # Where the first system/ directory is mounted

mount ${PROLOLIVE_IMG}.light ${PROLOLIVE_DIR}.light
mount ${PROLOLIVE_IMG}.big   ${PROLOLIVE_DIR}.big
mount ${PROLOLIVE_IMG}.full  ${PROLOLIVE_DIR}.full

for mountpoint in ${PROLOLIVE_DIR}.light ${PROLOLIVE_DIR}.big ${PROLOLIVE_DIR}.full ; do
    mkdir ${mountpoint}/{work,system} # Create all of them for harmonization when making squashfs
done
echo " Done."


echo "Install packages available in repositories..."
echo "Install core system packages on the lower layer"
# Binding directory to a mountpoint is a good way to ensure a good pacstrap behaviour
mount -o bind ${PROLOLIVE_DIR}.light/system first-bind/
mkdir -p first-bind/boot
mount /dev/mapper/${LOOP}p1 first-bind/boot
pacstrap -C pacman.conf -c first-bind base base-devel syslinux


# Copy the hook needed to mount squash filesystems on boot
echo -n "Copying hook files..."
cp prolomount.build first-bind/usr/lib/initcpio/install/prolomount
cp prolomount.runtime first-bind/usr/lib/initcpio/hooks/prolomount
echo " Done."


# Copy config and generating initcpio
echo "Generate the initcpio ramdisk..."
cp mkinitcpio.conf first-bind/etc/mkinitcpio.conf
systemd-nspawn -q -D first-bind mkinitcpio -p linux


echo "Install interpreters (GHC apart) and graphical packages on the intermediate layer"
umount /dev/mapper/${LOOP}p1
umount first-bind
mount -t overlay overlay -o lowerdir=${PROLOLIVE_DIR}.light/system,upperdir=${PROLOLIVE_DIR}.big/system,workdir=${PROLOLIVE_DIR}.big/work overlay-intermediate/
mount /dev/mapper/${LOOP}p1 overlay-intermediate/boot
pacstrap -C pacman.conf -c overlay-intermediate/ boost ed firefox firefox-i18n-fr \
	 fpc gambit-c gcc-ada gdb git grml-zsh-config htop jdk7-openjdk lxqt \
	 luajit mono mono-basic mono-debugger networkmanager nodejs ntp ntfs-3g \
	 ocaml openssh php python python2 rlwrap rxvt-unicode screen sddm tmux \
	 valgrind wget xorg xorg-apps zsh

umount /dev/mapper/${LOOP}p1
umount overlay-intermediate

echo "Install remaining and big packages on the top layer (${PROLOLIVE_DIR})"
mount -t overlay overlay -o lowerdir=${PROLOLIVE_DIR}.big/system:${PROLOLIVE_DIR}.light/system,upperdir=${PROLOLIVE_DIR}.full/system/,workdir=${PROLOLIVE_DIR}.full/work/ ${PROLOLIVE_DIR}
mount /dev/mapper/${LOOP}p1 ${PROLOLIVE_DIR}/boot
pacstrap -C pacman.conf -c ${PROLOLIVE_DIR}/ codeblocks eclipse eric \
	 esotope-bfc-git eric-i18n-fr fsharp geany ghc kate kdevelop \
	 leafpad mercurial monodevelop monodevelop-debugger-gdb netbeans \
	 notepadqq-bin openjdk7-doc pycharm-community reptyr rsync \
	 samba scite

# Configure system environment
echo "System configuration..."
echo "prololive" > ${PROLOLIVE_DIR}/etc/hostname
systemd-nspawn -q -D ${PROLOLIVE_DIR} ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo 'fr_FR.UTF-8 UTF-8' >  ${PROLOLIVE_DIR}/etc/locale.gen
echo 'en_US.UTF-8 UTF-8' >> ${PROLOLIVE_DIR}/etc/locale.gen
echo "LANG=fr_FR.UTF-8"  >  ${PROLOLIVE_DIR}/etc/locale.conf
echo "KEYMAP=fr-pc"      >  ${PROLOLIVE_DIR}/etc/vconsole.conf
systemd-nspawn -q -D ${PROLOLIVE_DIR} locale-gen
cp sddm.conf ${PROLOLIVE_DIR}/etc/
systemd-nspawn -q -D ${PROLOLIVE_DIR} systemctl enable sddm
systemd-nspawn -q -D ${PROLOLIVE_DIR} systemctl enable NetworkManager
cp 00-keyboard.conf ${PROLOLIVE_DIR}/etc/X11/xorg.conf.d/
cp .Xresources ${PROLOLIVE_DIR}/etc/skel/
echo 'alias ocaml="rlwrap ocaml"' >> /etc/skel/.zshrc
echo 'source /etc/profile.d/jre.sh' >> /etc/skel/.zshrc

cat > ${PROLOLIVE_DIR}/etc/systemd/journald.conf <<EOF
[Journal]
Storage=volatile
EOF

# Configure passwords for prologin and root users
echo -n "Configuring users and passwords..."
systemd-nspawn -q -D ${PROLOLIVE_DIR} usermod root -p $(echo ${CANONIQUE} | openssl passwd -1 -stdin) -s /bin/zsh
systemd-nspawn -q -D ${PROLOLIVE_DIR} useradd prologin -G games -m -p $(echo "prologin" | openssl passwd -1 -stdin) -s /bin/zsh
echo " Done."


# Copy the pacman config
cp pacman.conf ${PROLOLIVE_DIR}/etc/pacman.conf


# Configure fstab
cat > ${PROLOLIVE_DIR}/etc/fstab <<EOF
LABEL=proloboot /boot                     ext4  defaults 0 0
tmpfs           /var/cache/pacman         tmpfs defaults 0 0
tmpfs           /home/prologin/.cache     tmpfs defaults 0 0
tmpfs           /home/prologin/ramfs      tmpfs defaults 0 0
EOF


# Create dirs who will be ramfs-mounted
systemd-nspawn -q -D ${PROLOLIVE_DIR} -u prologin mkdir /home/prologin/.cache /home/prologin/ramfs

# Configure boot system
echo -n "Installing syslinux..."
dd if=${PROLOLIVE_DIR}/usr/lib/syslinux/bios/mbr.bin of=/dev/${LOOP} bs=440 count=1
mkdir -p ${PROLOLIVE_DIR}/boot/syslinux
cp -r ${PROLOLIVE_DIR}/usr/lib/syslinux/bios/*.c32 ${PROLOLIVE_DIR}/boot/syslinux/
extlinux --device /dev/mapper/${LOOP}p1 --install ${PROLOLIVE_DIR}/boot/syslinux

cp logo.png ${PROLOLIVE_DIR}/boot/syslinux/ || echo -n " missing logo.png file..."
cp syslinux.cfg ${PROLOLIVE_DIR}/boot/syslinux/
echo " Done."

# Creating squash filesystems
echo "Create squash filesystems..."
for mountpoint in ${PROLOLIVE_DIR}.light ${PROLOLIVE_DIR}.big ${PROLOLIVE_DIR}.full ; do
    mksquashfs ${mountpoint}/system ${PROLOLIVE_DIR}/boot/${mountpoint}.squashfs -comp xz -Xdict-size 100% -b 1048576 -e ${mountpoint}/system/proc ${mountpoint}/system/tmp ${mountpoint}/system/boot ${mountpoint}/system/dev
done

cp documentation.squashfs ${PROLOLIVE_DIR}/boot/

# Unmounting all mounted filesystems
echo -n "Unmounting filesystems..."
umount -R ${PROLOLIVE_DIR}
umount ${PROLOLIVE_DIR}.full
umount ${PROLOLIVE_DIR}.big
umount ${PROLOLIVE_DIR}.light
echo " Done."

echo "The end."
