#!/usr/bin/env bash
#
# Copyright (c) 2022 Operating Systems and Middleware Group @ HPI <bs@hpi.de>
#
# This file has been taken in parts from both the messages.sh included in
# parabola libretools, as well as in archlinux pacman. The relevant copyright
# notices from the original repositories are reproduced below.
#
# Copyright (c) 2006-2021 Pacman Development Team <pacman-dev@archlinux.org>
# Copyright (c) 2002-2006 by Judd Vinet <jvinet@zeroflux.org>
#
# Copyright (C) 2011 Joshua Ismael Haase Hernández (xihh) <hahj87@gmail.com>
# Copyright (C) 2012 Nicolás Reynolds <fauno@parabola.nu>
# Copyright (C) 2012-2014, 2016-2018 Luke Shumaker <lukeshu@parabola.nu>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

export EXIT_FAILURE=1
export EXIT_SUCCESS=0

panic ()
{
    printf 'panic: malformed call to internal function' 1>&2;
    exit $EXIT_FAILURE
}

whitespace_collapse ()
{
    [[ $# == 0 ]] || panic;
    tr '\n' '\r' | sed -r -e 's/\r/  /g' -e 's/\t/ /g' -e 's/(^|[^.!? ]) +/\1 /g' -e 's/([.!?])  +/\1  /g' -e 's/\s+$//'
}

prose ()
{
    [[ $# -ge 1 ]] || panic;
    local mesg;
    mesg="$(whitespace_collapse <<<"$1")";
    shift;
    printf -- "$mesg" "$@" | fmt -u
}

print ()
{
    [[ $# -ge 1 ]] || panic;
    local mesg=$1;
    shift;
    printf -- "$mesg\n" "$@"
}

warning ()
{
    local mesg=$1;
    shift;
    printf -- "${YELLOW}==> WARNING:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" 1>&2
}

error ()
{
    local mesg=$1;
    shift;
    printf "${RED}==> ERROR:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" 1>&2
}
