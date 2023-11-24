#!/bin/bash

# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------

# To-do:
# - Add enums for all the parameters

# Exit on undefined variable
set -u

VERBOSE_MODE=0

RED="\e[2;31m"
GREEN="\e[2;32m"
YELLOW="\e[2;33m"
NORMAL="\e[0m"

#
# Core logging function.
#
_log()
{
    color=$1
    msg=$2
    echo -e "${color}${msg}${NORMAL}"
}

#
# Plain echo.
#
pecho()
{
    color=$NORMAL
    _log $color "${*}"
}

#
# Success echo.
#
secho()
{
    color=$GREEN
    _log $color "${*}"
}

#
# Warning echo.
#
wecho()
{
    color=$YELLOW
    _log $color "${*}"
}

#
# Error echo.
#
eecho()
{
    color=$RED
    _log $color "${*}"
}

#
# Verbose echo, no-op unless VERBOSE_MODE variable is set.
# To-do: Why is this not working?
#
vecho()
{
    color=$NORMAL

    # echo "VERBOSE_MODE is $VERBOSE_MODE"

    # # Unless VERBOSE_MODE flag is set, do not echo to console.
    # if [ "$VERBOSE_MODE" != "0" ]; then
    #     _log $color "${*}"
    #     return
    # fi

    _log $color "${*}"

}

##################################################################
# 1. Install systemd
##################################################################

# Install systemd
function install_systemd ()
{
    # To-do: Check if systemd is already installed
    echo "[boot]" >> /etc/wsl.conf
    echo "systemd=true" >> /etc/wsl.conf
}

##################################################################
# One time setup steps
# 1. Install NFS
# 2. Install Samba
# 3. Setup the Samba user name and password
##################################################################

# Install NFS
function install_nfs ()
{
    # To-do: Check if there are any existing NFS mounts and upgrade only if there are no existing ones.
    # dpkg -s nfs-common > /dev/null
    apt-get install nfs-common -y > /dev/null
}

# Install Samba
function install_samba ()
{
    # To-do: Check if there are any existing SMB shares and upgrade only if there are no existing shares
    apt-get install samba -y > /dev/null
    service smbd restart > /dev/null
    ufw allow samba > /dev/null
}

# One time Samba setup to set up the Samba user name and password
function onetime_samba_setup ()
{
    # Set username as the password
    vecho "Note: Samba password for $1 is same as the username. This makes it easier to mount shares."
    # remove "Added user $1" message
    echo -ne "$1\n$1" | tee - | smbpasswd -a -s $1

    # Add get quota script to the Samba global config
    # To-do: Add a warning that quota is not supported for all the SMB shares.
    sed -i "/\[global\]/ a get quota command = $(dirname -- $0)/query_quota.sh" /etc/samba/smb.conf
}

##################################################################
# Mount steps
# 1. Mount the NFS share
# 2. Export the NFS share via Samba
##################################################################

# Mount NFS
# $1: mount command
# To-do: Return the result of the mount command
function mount_nfs ()
{
    # vecho "Got $# number of args: $*"
    # execute the mount command passed as the first argument
    $1

    if [[ $? != 0 ]]; then
        eecho "Failed to mount NFS share with: $1"
        exit 1
    fi

    # Set the read ahead to 16MB
    vecho "Setting read ahead to 16MB"
    cd $2
    vecho 16384 > /sys/class/bdi/0:$(stat -c "%d" .)/read_ahead_kb
    cd -

    secho "Mounted NFS share."
}

# Unmount smb share and NFS share
# $1: export name
# To-do:
# 1. Take a lock on the smb file
function unmount_share ()
{
    mntpath=""
    foundshare=false
    startline=0
    endline=0
    linenum=0

    # Take a backup of smb.conf to restore it if the script fails
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

    # Take the last matching share name
    while IFS= read -r line; do
        # line number counter
        linenum=$((linenum + 1))

        # exact match of the share name
        if [[ "$line" == "[$1]" ]]; then
            foundshare=true
            startline=$linenum

        # next share name after the target share
        elif [[ $foundshare == "true" && "$line" == "["*"]" ]]; then
            foundshare=false
            # Current line belongs to a new share. So, the previous line is the end of the share
            endline=$((linenum - 1))
        fi

        # If the path is found, get the path of the share and remove the share details from smb.conf
        # Sample line: path = /mnt/nfs/share1
        if [[ $foundshare == "true" && "$line" == "path"* ]]; then
            # Split the line into tokens
            read -r pathstr eq mntpath <<< "$line"
        fi
    done < /etc/samba/smb.conf

    # Sometimes the share is the last share in the file, so endline is not set
    if [[ $foundshare == "true" && $endline == 0 ]]; then
        # Last line in the file is the endline
        endline=$linenum
    fi

    if [[ $startline < $endline ]]; then
        # Remove the share details from smb.conf
        sed -i "$startline,$endline d" /etc/samba/smb.conf
        secho "Removed SMB share with: $1."

        # Restart Samba so that we can unmount the NFS share, else we get "device is busy" error
        service smbd restart > /dev/null
    else
        wecho "No SMB share found for $1."

        # Even if the SMB share is not found, exit with 0 to let the client unmount it's mapped drive
        exit 0
    fi

    # check if mntpath is a path
    if [[ ${mntpath:0:1} == "/" ]]; then
        # check if the path exists
        if [[ -d $mntpath ]]; then
            # To-do:
            # - Add retries and add a background queue to unmount the NFS share
            # - Remove the dir after unmounting the NFS share
            umount $mntpath

            # If the umount command fails with 32, then the NFS share is already unmounted
            if [[ $? != 0 && $? != 32 ]]; then
                eecho "Failed to unmount NFS share at: $mntpath"

                # Restore smb.conf
                mv /etc/samba/smb.conf.bak /etc/samba/smb.conf
                exit 1
            fi
            secho "Unmounted NFS mount at: $mntpath"
        else
            wecho "Mount point $mntpath does not exist"
        fi
    else
        wecho "Mount point $mntpath is not a path"
    fi
}


# Setup Samba export
# $1: export name
# $2: mount point
# To-do:
# 1. Take a lock on the file
# 2. Check if the export name already exists
function export_via_samba ()
{
    # vecho "Got $# number of args: $*"
    sharename=$1
    mountpoint=$2

    echo "[$sharename]" >> /etc/samba/smb.conf
    echo "comment = Samba on NFSv3 WSL2 setup by Blob NFS scripts" >> /etc/samba/smb.conf
    echo "path = $mountpoint" >> /etc/samba/smb.conf
    echo "read only = no" >> /etc/samba/smb.conf
    echo "guest ok = yes" >> /etc/samba/smb.conf
    echo "browseable = yes" >> /etc/samba/smb.conf

    # use testparm to check if the smb.conf is valid
    # testparm

    # Restart Samba
    service smbd restart
    ufw allow samba
}


# echo "Got $# number of args: $*"
while getopts ":d" option; do

    echo "Got option $option"
    case $option in
        d) # set VERBOSE_MODE on
            VERBOSE_MODE=1
            echo "Verbose mode is on"
            exit;;
        \?) # Invalid option
            eecho "Error: Invalid option"
            exit;;
    esac
done

# if the first argument is installsystemd, then install systemd
if [[ $1 == "installsystemd" ]]; then
    install_systemd

# else if the first argument is installnfssmb, then run the setup steps
elif [[ $1 == "installnfssmb" ]]; then

    apt-get update > /dev/null
    install_nfs
    install_samba
    onetime_samba_setup $2

# else if the first argument is mountshare, then run the mount steps
elif [[ $1 == "mountshare" ]]; then

    if [[ $# != 4 ]]; then
        eecho "Usage: $0 <mountshare> <mountParameterType> <mountParameter> <tempFilePath>"
        exit 1
    fi

    mountparametertype=$2
    mountparameter=$3
    tempFilePath=$4

    # Create the mountpath, sharename, and mountCommand
    mountPath=""
    shareName=""
    mountCommand=""
    if [[ $mountparametertype == "command" ]]; then
        # MountCommand: mount -t nfs -o vers=3,proto=tcp <account-name>.blob.core.windows.net:/<account-name>/<container-name> /mnt/<path>
        mountCommand=$mountparameter
        vecho "Mount command is: $mountCommand"

        # Split the mount command into tokens
        IFS=' ' read -ra nametokens <<< "$mountCommand"

        # last element is the mount point
        mountPath=${nametokens[-1]}

        # check if the last element is a path
        if [[ ${mountPath:0:1} == "/" ]]; then
            # check if the path exists
            if [[ ! -d $mountPath ]]; then
                mkdir -p $mountPath
                secho "Created $mountPath"
            else
                vecho "Mount point $mountPath already exists"
            fi
        else
            eecho "Mount point $mountPath is not a path"
            exit 1
        fi

        mpath=${mountPath:1}

        # replace all / with -
        shareName=${mpath//\//-}
    else
        # RemoteHost: <account-name>.blob.core.windows.net:/<account-name>/<container-name>

        # A random mount path to mount the NFS share
        randomnumber=$RANDOM
        mountPath="/mnt/nfsv3share-$randomnumber"
        while [[ -e $mountPath ]]; do
            randomnumber=$RANDOM
            mountPath="/mnt/nfsv3share-$randomnumber"
        done

        mkdir -p $mountPath
        secho "Created $mountPath"

        mountCommand="mount -t nfs -o vers=3,proto=tcp $mountparameter $mountPath"
        shareName="nfsv3share-$randomnumber"
    fi

    vecho "Mounting NFS share.."

    # quote the mount command to preserve the spaces
    mount_nfs "$mountCommand" "$mountPath"
    secho "Done NFS mounting."
    # To-do: Don't proceed if the mount command failed

    vecho "Exporting NFS share via Samba.."
    export_via_samba "$shareName" "$mountPath"

    echo "$shareName" > $tempFilePath
    secho "Done Samba exporting and saved the share name ($sharename) to $tempFilePath."

# if the first argument is unmountshare, then unmount smb and nfs shares
elif [[ $1 == "unmountshare" ]]; then
    # vecho "Got $# number of args: $*"
    unmount_share $2
    secho "Removed SMB share and unmounted NFS share."

# else, print the usage
else
    eecho "Usage: $0 <installsystemd>"
    eecho "Usage: $0 <installnfssmb> <samba username>"
    eecho "Usage: $0 <mountshare> <mount command>"
    eecho "Usage: $0 <unmountshare> <smbsharename>"
fi