#!/bin/bash

# disable advanced interrupts
linux_cmdline+=(
    "xive=off")

local field=GRUB_CMDLINE_LINUX_DEFAULT
local value="${linux_cmdline[*]}"
sudo sed -i "s/.*$field=.*/$field=\"$value\"/" \
  "$workdir"/etc/default/grub || return

# update the grup configuration
_c update-grub || return

# deploy a network interface configuration
_c tee /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto enp0s2
iface enp0s2 inet static
    address 172.20.33.11/23
    gateway 172.20.32.1
    dns-nameservers 141.89.225.97 141.89.225.123
EOF

# install and enable an ssh server
_c apt-get install -y openssh-server || return
_c systemctl enable ssh || return

# create and configure a user for ansible
_c apt-get install -y sudo || return
_c useradd -mU ansible -G sudo || return
_c chpasswd <<< "ansible:ansible" || return
_c tee /etc/sudoers.d/00-ansible << EOF
ansible ALL=(ALL:ALL) NOPASSWD: ALL
EOF

# setup ssh key authentication for the ansible user
_c sudo -u ansible mkdir /home/ansible/.ssh || return
_c sudo -u ansible chmod 0700 /home/ansible/.ssh || return
_c sudo -u ansible tee /home/ansible/.ssh/authorized_keys << EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDb2bZmAXhB0qdrLwBMu8UU4yurNZfeHI5Eg11m2Pg/4H/slQlt6pmmGtzaVVmXtHJuCt6l6IQ609MFtZllnt3VRgdviWL0A7gTmi3tdiXi8PVmrM5bJKA2Q2wEw8M1uwW0+wINbQHlJCegPy37up6BoCLZlE2ybwKkBsEiHXQ6eja1cG/YL6V+JIncw/OkE/f1AiVWgojPxThnshnwZertGVqYpwSmBETs6VQLjgNWC2Zu576iJQkgDzaZKRqSZLm90AqC6cuwuI9clI2Z7qHIGT0bQ5ULiVr5k8TNCAsjOYi3nj82u3yO/9XoXf00QbDYvpG2sQEV6w7pIz0Gdo8F feberhardt@vivado-ic922
EOF
_c sudo -u ansible chmod 0600 /home/ansible/.ssh/authorized_keys || return

_c bash
