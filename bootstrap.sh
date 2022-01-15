#!/bin/bash
#
# Copyright (c) 2022 Operating Systems and Middleware Group @ HPI <bs@hpi.de>
#
# this script has been inspired by parabola-vmbootstrap. The relevant copyright
# notices from the original repository are reproduced below.
#
# Copyright (C) 2017 - 2019  Andreas Grapentin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

STARTDIR="$(pwd)"

. messages.sh

_c () {
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" sudo arch-chroot "$workdir" "$@"
}

_deb_arch () {
  case "$1" in
    ppc64le) echo "ppc64el";;
    *) echo "$1";;
  esac
}

usage() {
  print "usage: %s [-h] [-s SIZE] [-A ARCH] [-M MIRROR] [-r RELEASE] [-L LOCALE] [-C SCRIPT]... IMG" "${0##*/}"
  prose "Produce preconfigured debian GNU/Linux virtual machine instances."
  echo
  echo  "Supported options:"
  echo  "  -s SIZE     Set the size of the VM image"
  echo  "                default: 8GiB"
  echo  "  -A ARCH     Choose a different architecture"
  echo  "                default: the local architecture ($(_deb_arch "$(uname -m)"))"
  echo  "  -M MIRROR   Choose a different mirror to debootstrap from"
  echo  "                default: <http://ftp2.de.debian.org/debian/>"
  echo  "  -r RELEASE  Choose a different release name"
  echo  "                default: stable"
  echo  "  -L LOCALE   Choose a different locale"
  echo  "                default: en_US.UTF-8 UTF-8"
  echo  "  -C SCRIPT   A path to an optional configuration script"
  echo  "  -h          Display this help and exit"
}

pvm_bootstrap() {
  print "%s: starting image creation for %s" "$file" "$arch"

  # create the raw image file
  qemu-img create -f raw "$file" "$size" || return

  # prepare for cleanup
  trap 'pvm_cleanup' INT TERM RETURN

  # setup the virtual disk through loopback
  local workdir loopdev
  workdir="$(mktemp -d -t bootstrap-rootfs-XXXXXXXXXX)" || return
  loopdev="$(sudo losetup -fLP --show "$file")" || return

  # zero the first 8MiB
  sudo dd if=/dev/zero of="$loopdev" bs=1M count=8 || return

  # partition
  parted_opts=()
  case "$arch" in
    ppc64*)
      parted_opts+=(
        mklabel gpt
        mkpart primary 1MiB 8MiB
        set 1 prep on
        mkpart primary ext4 8MiB 100%)
      ;;
    *)
      error "%s: unsupported architecture" "$arch"
      return "$EXIT_FAILURE"
      ;;
  esac

  printf "parted -s '%s'\n  %s\n" "$loopdev" "${parted_opts[*]}"
  sudo parted -s "$loopdev" "${parted_opts[@]}" || return

  # refresh partition data
  sudo partprobe "$loopdev"

  # make file systems and mount partitions
  local swapdev
  case "$arch" in
    ppc64*)
      sudo mkfs.ext4 "$loopdev"p2 || return
      sudo mount "$loopdev"p2 "$workdir" || return
      ;;
    *)
      error "%s: unsupported architecture" "$arch"
      return "$EXIT_FAILURE"
      ;;
  esac

  # debootstrap! :)
  debootstrap_cache="$(pwd)/.cache/debootstrap"
  mkdir -p "$debootstrap_cache"

  debootstrap_opts=(
      "--arch=$arch"
      "--cache-dir=$debootstrap_cache")

  case "$arch" in
    ppc64*)
      debootstrap_opts+=("--include=linux-image-powerpc64le,acpid")
      ;;
    *)
      error "%s: unsupported architecture" "$arch"
      return "$EXIT_FAILURE"
      ;;
  esac

  sudo bash "$STARTDIR"/qemu_debootstrap.sh "${debootstrap_opts[@]}" "$release" "$workdir" "$mirror"
  res=$?

  if [ $res -ne 0 ]; then
    #bash
    return $res
  fi

  # create an fstab
  sudo swapoff --all
  [ -z "$swapdev" ] || sudo swapon "$swapdev" || return
  genfstab -U "$workdir" | sudo tee "$workdir"/etc/fstab || return
  [ -z "$swapdev" ] || sudo swapoff "$swapdev" || return
  sudo swapon --all

  # produce a hostname
  echo "debian" | sudo tee "$workdir"/etc/hostname

  # update package mirrors
  _c apt-get update || return

  linux_cmdline=(
      "console=ttyS0"
      "console=tty0")

  linux_cmdline+=(
      "xive=off")

  # install a boot loader
  case "$arch" in
    ppc64*)
      # install required packages
      _c apt-get install -y grub2 || return

      # enable serial console
      local field=GRUB_CMDLINE_LINUX_DEFAULT
      local value="${linux_cmdline[*]}"
      sudo sed -i "s/.*$field=.*/$field=\"$value\"/" \
        "$workdir"/etc/default/grub || return

      # install grub to the VM
      _c grub-install --target=powerpc-ieee1275 "$loopdev"p1 || return
      _c update-grub || return
      ;;
    *)
      error "%s: unsupported architecture" "$arch"
      return "$EXIT_FAILURE"
      ;;
  esac

  # update the locale
  _c apt-get install -y locales || return
  echo "$locale" | sudo tee -a "$workdir"/etc/locale.gen
  _c locale-gen || return
  _c update-locale LC_ALL="${locale% *}" LANG="${locale% *}" || return

  # regenerate the initcpio
  _c apt-get install -y initramfs-tools || return
  _c update-initramfs -u || return

  # disable audit
  _c systemctl mask systemd-journald-audit.socket

  # set a trivial root password
  _c chpasswd <<< "root:pass" || return

  # load customization script
  [ -z "$script" ] || . "$STARTDIR/$script" || return

  # unmount everything
  pvm_cleanup
}

pvm_cleanup() {
  trap - INT TERM RETURN

  [ -n "$pacconf" ] && rm -f "$pacconf"
  unset pacconf
  if [ -n "$workdir" ]; then
    sudo umount -R "$workdir"
    rmdir "$workdir"
  fi
  unset workdir
  [ -n "$loopdev" ] && sudo losetup -d "$loopdev"
  unset loopdev
}

main() {
  if [ "$(id -u)" -eq 0 ]; then
    error "This program must be run as a regular user"
    exit "$EXIT_FAILURE"
  fi

  local size="8G"
  local mirror="http://ftp2.de.debian.org/debian/"
  local release="stable"
  local locale="en_US.UTF-8 UTF-8"
  local script=""
  local arch="$(_deb_arch "$(uname -m)")"

  # parse options
  while getopts 'hs:M:r:L:A:C:' arg; do
    case "$arg" in
      h) usage; return "$EXIT_SUCCESS";;
      s) size="$OPTARG";;
      M) mirror="$OPTARG";;
      r) release="$OPTARG";;
      L) locale="$OPTARG";;
      A) arch="$OPTARG";;
      C) script="$OPTARG";;
      *) usage >&2; exit "$EXIT_FAILURE";;
    esac
  done
  local shiftlen=$(( OPTIND - 1 ))
  shift $shiftlen
  if [ "$#" -ne 1 ]; then usage >&2; exit "$EXIT_FAILURE"; fi

  local file="$1"

  # determine whether the target output file already exists
  if [ -e "$file" ]; then
    warning "%s: file exists. Continue? [y/N]" "$file"
    read -p " " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit "$EXIT_FAILURE"
    fi
    rm -f "$file" || exit
  fi

  # create the virtual machine
  if ! pvm_bootstrap; then
    error "%s: bootstrap failed" "$file"
    exit "$EXIT_FAILURE"
  fi

  print "%s: bootstrap complete" "$file"
}

main "$@"
