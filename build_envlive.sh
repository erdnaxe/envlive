#!/bin/sh

# Loading the config
source ./config.sh

# Preventively unmounting filesystems
umount -R ${PROLOLIVE_DIR}/boot
umount -R ${PROLOLIVE_DIR}
umount -R overlay-intermediate
umount -R ${PROLOLIVE_DIR}.light
umount -R ${PROLOLIVE_DIR}.big
umount -R ${PROLOLIVE_DIR}.full


# Deleting previously generated squash files
rm -f *.squashfs


# Allocating space for filesystems
rm -f ${PROLOLIVE_IMG}.light && fallocate -l 1G            ${PROLOLIVE_IMG}.light
rm -f ${PROLOLIVE_IMG}.big   && fallocate -l 1500M         ${PROLOLIVE_IMG}.big
rm -f ${PROLOLIVE_IMG}.full  && fallocate -l 5G            ${PROLOLIVE_IMG}.full
rm -f ${PROLOLIVE_IMG}       && fallocate -l ${IMAGE_SIZE} ${PROLOLIVE_IMG}


# Formatting all filesystems
mkfs.ext4 -F ${PROLOLIVE_IMG}.light
mkfs.ext4 -F ${PROLOLIVE_IMG}.big
mkfs.ext4 -F ${PROLOLIVE_IMG}.full


# Mounting filesystems
mkdir -p ${PROLOLIVE_DIR}/      # Where all FS will be union-mounted
mkdir -p ${PROLOLIVE_DIR}.light # Where the core OS filesystem will be mounted alone
mkdir -p ${PROLOLIVE_DIR}.big   # Where many light toold will be provided as well as DE/WP
mkdir -p ${PROLOLIVE_DIR}.full  # Where the biggest packages will go. Hi ghc!

mkdir -p ${PROLOLIVE_DIR}/{work,system}     # Dirs for mounting with overlayfs
mkdir -p overlay-intermediate/{work,system} # Dirs for mounting with overlayfs

mount ${PROLOLIVE_IMG}.light ${PROLOLIVE_DIR}.light
mount ${PROLOLIVE_IMG}.big   ${PROLOLIVE_DIR}.big
mount ${PROLOLIVE_IMG}.full  ${PROLOLIVE_DIR}.full

mount -t overlay overlay -o lowerdir=${PROLOLIVE_DIR}.light/,upperdir=${PROLOLIVE_DIR}.big/system/,workdir=${PROLOLIVE_DIR}.big/work/ overlay-intermediate/
mount -t overlay overlay -o lowerdir=overlay-intermediate,upperdir=${PROLOLIVE_DIR}.full/system/,workdir=${PROLOLIVE_DIR}.full/work/ ${PROLOLIVE_DIR}

mkdir ${PROLOLIVE_DIR}/boot
mount ${PROLOLIVE_IMG}.boot ${PROLOLIVE_DIR}/boot


# Installing packages
pacstrap -C pacman.conf -c ${PROLOLIVE_DIR}.light base base-devel

pacstrap -C pacman.conf -c ${PROLOLIVE_DIR}.big btrfs-progs clang firefox \
	 firefox-i18n-fr grml-zsh-config htop networkmanager openssh \
	 rxvt-unicode screen tmux zsh ntfs-3g lxqt xorg xorg-apps gdb valgrind \
	 js luajit nodejs ocaml php

pacstrap -C pacman.conf -c ${PROLOLIVE_DIR}.full clang-analyzer \
	 clang-tools-extra git mercurial ntp reptyr rlwrap rsync samba \
	 syslinux wget sublime-text codeblocks eclipse ed eric eric-i18n-fr \
	 geany kate kdevelop leafpad mono-debugger monodevelop \
	 monodevelop-debugger-gdb netbeans openjdk8-doc scite boost ghc


# Copying the hook needed to mount squash filesystems on boot
cp prolomount.build ${PROLOLIVE_DIR}/usr/lib/initcpio/install/prolomount
cp prolomount.runtime ${PROLOLIVE_DIR}/usr/lib/initcpio/hooks/prolomount


# Copying config and generating initcpio
cp mkinitcpio.conf ${PROLOLIVE_DIR}/etc/mkinitcpio.conf
systemd-nspawn -q -D ${PROLOLIVE_DIR} mkinitcpio -p linux


# Configuring passwords for prologin and root users
systemd-nspawn -q -D ${PROLOLIVE_DIR} usermod root -p $(echo ${CANONIQUE} | openssl passwd -1 -stdin) -s /bin/zsh
systemd-nspawn -q -D ${PROLOLIVE_DIR} useradd prologin -G games -m -p $(echo "prologin" | openssl passwd -1 -stdin) -s /bin/zsh

# Copying the pacman config
cp pacman.conf ${PROLOLIVE_DIR}/etc/pacman.conf


# Installing yaourt and some AUR packages
systemd-nspawn -q -D ${PROLOLIVE_DIR} pacman -S yaourt --noconfirm
echo "prologin ALL=(ALL) NOPASSWD: ALL" >> ${PROLOLIVE_DIR}/etc/sudoers
systemd-nspawn -q -D ${PROLOLIVE_DIR} -u prologin yaourt -S notepadqq-git pycharm-community --noconfirm
sed "s:prologin:#prologin:" -i ${PROLOLIVE_DIR}/etc/sudoers

# Configuring fstab
cat > ${PROLOLIVE_DIR}/etc/fstab <<EOF
LABEL=proloboot /boot                     ext4  defaults 0 0
tmpfs           /var/log                  tmpfs defaults 0 0
tmpfs           /var/cache/pacman         tmpfs defaults 0 0
tmpfs           /home/prologin/.cache     tmpfs defaults 0 0
tmpfs           /home/prologin/ramfs      tmpfs defaults 0 0
EOF

# Configuring system environment
echo "prololive" > ${PROLOLIVE_DIR}/etc/hostname
systemd-nspawn -q -D ${PROLOLIVE_DIR} ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo 'fr_FR.UTF-8' >  ${PROLOLIVE_DIR}/etc/locale.gen
echo 'en_US.UTF-8' >> ${PROLOLIVE_DIR}/etc/locale.gen
echo "LANG=fr_FR.UTF-8" > ${PROLOLIVE_DIR}/etc/locale.conf
systemd-nspawn -q -D ${PROLOLIVE_DIR} locale-gen

systemd-nspawn -q -D ${PROLOLIVE_DIR} systemctl enable lxdm
systemd-nspawn -q -D ${PROLOLIVE_DIR} sed -i "s:.*\?#.*\?autologin=.\+\?:autologin=prologin:" /etc/lxdm/lxdm.conf

cat > ${PROLOLIVE_DIR}/etc/systemd/journald.conf <<EOF
[Journal]
Storage=none
EOF

# Creating dirs who will be ramfs-mounted
systemd-nspawn -q -D ${PROLOLIVE_DIR} -u prologin mkdir /home/prologin/.cache /home/prologin/ramfs


# Configuring boot system
mkdir ${PROLOLIVE_DIR}/boot/syslinux
cp -r ${PROLOLIVE_DIR}/usr/lib/syslinux/bios/*.c32 ${PROLOLIVE_DIR}/boot/syslinux/
extlinux --install ${PROLOLIVE_DIR}/boot/syslinux
dd if=${PROLOLIVE_DIR}/usr/lib/syslinux/bios/mbr.bin of=${PROLOLIVE_IMG} bs=440 count=1

cp ${LOGOFILE} ${PROLOLIVE_DIR}/boot/syslinux/${LOGOFILE}
cp syslinux.cfg ${PROLOLIVE_DIR}/boot/syslinux/

umount ${PROLOLIVE_DIR}/boot


# Creating squash filesystems
for mountpoint in ${PROLOLIVE_DIR}.light ${PROLOLIVE_DIR}.big ${PROLOLIVE_DIR}.full ; do
    mksquashfs {mountpoint}/ ${mountpoint}.squashfs -comp lz4 -b 1048576 -e ${mountpoint}/proc ${mountpoint}/tmp ${mountpoint}/home ${mountpoint}/boot ${mountpoint}/dev
done


# Unmounting all mounted filesystems
umount ${PROLOLIVE_DIR}       # All FS merged minus /boot
umount ${PROLOLIVE_DIR}.full  #
umount overlay-intermediate   # Light and big FS merged
umount ${PROLOLIVE_DIR}.big   #
umount ${PROLOLIVE_DIR}.light #
