#!/bin/bash

# also include everything in example.sh
source "$STARTDIR"/scripts/example.sh

# disable advanced interrupts
linux_cmdline+=(
    "xive=off")

local field=GRUB_CMDLINE_LINUX_DEFAULT
local value="${linux_cmdline[*]}"
sudo sed -i "s/.*$field=.*/$field=\"$value\"/" \
  "$workdir"/etc/default/grub || return

# update the grup configuration
_c update-grub || return

sudo cp "$STARTDIR"/scripts/interfaces "$workdir"/etc/network/interfaces
