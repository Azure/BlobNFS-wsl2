#!/bin/bash

# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------

# Note: Always quote the parameters to avoid any word splitting or globbing issues while calling the functions.

# Exit on undefined variable
set -u
export DEBIAN_FRONTEND=noninteractive

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
#
vecho()
{
    color=$YELLOW

    # Unless VERBOSE_MODE flag is set, do not echo to console.
    if [ "$VERBOSE_MODE" != "0" ]; then
        _log $color "${*}"
        return
    fi
}

##################################################################
# 1. Install systemd
##################################################################

# Install systemd
function install_systemd ()
{
    # Note: This works fine in a freshly installed Ubuntu, without prior usage of it with any other boot configuration.
    #       If the user is using any other boot configuration, then this will override it.
    #
    # To-do: Check if the user is using any other boot configuration and warn the user.

    grep -A1 "[boot]" /etc/wsl.conf | grep -q "systemd=true"
    if [[ $? == 0 ]]; then
        vecho "systemd is already installed."
    else
        echo "[boot]" >> /etc/wsl.conf
        echo "systemd=true" >> /etc/wsl.conf
    fi
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
    # To-do: Use AzNFS.
    op=$(apt-get install nfs-common -y 2>&1)

    if [[ $? != 0 ]]; then
        eecho "Failed to install NFS: $op"
        return 1
    fi

    vecho "NFS installation output:"
    vecho $op
}

# Install Samba
function install_samba ()
{
    op=$(apt-get install samba -y 2>&1)

    if [[ $? != 0 ]]; then
        eecho "Failed to install Samba: $op"
        return 1
    fi

    vecho "Samba installation output:"
    vecho $op
    service smbd restart | grep -q fail

    if [[ $? == 0 ]]; then
        eecho "Failed to restart Samba."
        return 1
    fi

    ufw allow samba > /dev/null
}

# One time Samba setup to set up the Samba user name and password
function onetime_samba_setup ()
{
    if [[ $# != 1 ]]; then
        eecho "Usage: onetime_samba_setup [samba username]"
        return 1
    fi

    sambausername=$1

    # Set username as the password
    vecho "Note: Samba password for $sambausername is same as the username. This makes it easier to mount shares."
    echo -ne "$sambausername\n$sambausername\n" | smbpasswd -a -s $sambausername
    vecho "Successfully created Samba user $sambausername with password $sambausername."

    # To-do: Need to handle all the cases where a user may already be using samba configuration inside wsl.

    # Add get quota script to the Samba global config
    scriptpath=$0
    modulepath=${scriptpath%/*}
    if [[ $modulepath == "" ]]; then
        eecho "Failed to get the module path."
        return 1
    fi

    vecho "Disabling quota support for all SMB shares on this distro."
    quotaquerycommand="get quota command = '$modulepath/query_quota.sh'"

    # Check if the exact get quota command is already set, if not, then add it.
    grep -q "^$quotaquerycommand$" /etc/samba/smb.conf

    if [[ $? == 0 ]]; then
        vecho "get quota command is already set: $quotaquerycommand"
    else
        # Remove all the existing get quota commands
        vecho "Removing all the existing get quota commands."
        sed -i '/get quota command/d' /etc/samba/smb.conf

        vecho "Executing: "
        vecho "/\[global\]/a $quotaquerycommand"
        sed -i "/\[global\]/a $quotaquerycommand" /etc/samba/smb.conf

        if [[ $? != 0 ]]; then
            eecho "Failed to add get quota command to smb.conf"
            return 1
        fi
    fi

    wecho "Disabled quota support for all SMB shares on this distro!"
}

##################################################################
# Mount steps
# 1. Mount the NFS share
# 2. Export the NFS share via Samba
##################################################################

# Setup Samba export
# $1: share name
# $2: dir to share
# To-do:
# 1. Take a lock on the file
# 2. Check if the share name already exists
function share_via_samba ()
{
    if [[ $# != 2 ]]; then
        eecho "Usage: share_via_samba [share name] [dir to share]"
        return 1
    fi

    sharename=$1
    dirtoshare=$2

    echo "[$sharename]" >> /etc/samba/smb.conf
    echo "comment = Samba on NFSv3 WSL2 setup by Blob NFS scripts" >> /etc/samba/smb.conf
    echo "path = $dirtoshare" >> /etc/samba/smb.conf
    echo "read only = no" >> /etc/samba/smb.conf
    echo "guest ok = yes" >> /etc/samba/smb.conf
    echo "browseable = yes" >> /etc/samba/smb.conf

    # Restart Samba
    service smbd restart | grep -q fail

    if [[ $? == 0 ]]; then
        eecho "Failed to restart Samba."
        return 1
    fi

    ufw allow samba > /dev/null
    secho "Created Samba share $shareName."
    return 0
}

# Mount NFS
# $1: mount command
# $2: mount path
function mount_nfs ()
{
    if [[ $# != 2 ]]; then
        eecho "Usage: mount_nfs [mount command] [mount path]"
        return 1
    fi

    mountcommand=$1
    mountpath=$2

    # Execute the mount command
    op=$(eval $mountcommand 2>&1)

    if [[ $? != 0 ]]; then
        eecho "Failed to mount NFS share with: $mountcommand:"
        eecho $op
        return 1
    fi

    # Set the read ahead to 16MB
    vecho "Setting read ahead to 16MB"
    echo 16384 > /sys/class/bdi/0:$(stat -c "%d" $mountpath)/read_ahead_kb

    secho "Mounted NFS share using $mountcommand"
    return 0
}

# Mount SMB and NFS share
# $1: mount parameter type
# $2: mount parameter
# $3: temp file path
function mount_share ()
{
    if [[ $# != 3 ]]; then
        eecho "Usage: mount_share [mountparametertype] [mountparameter] [tempfilepath]"
        return 1
    fi

    # Create the mountpath, sharename, and mountCommand
    mountparametertype=$1
    mountparameter=$2
    tempfilepath=$3
    mountPath=""
    shareName=""
    mountCommand=""

    if [[ $mountparametertype == "command" ]]; then
        # MountCommand: mount -t nfs -o nolock,vers=3,proto=tcp <account-name>.blob.core.windows.net:/<account-name>/<container-name> /mnt/<path>
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
                vecho "Created $mountPath"
            else
                eecho "Mount point $mountPath already exists. Use a different mount point."
                return 1
            fi
        else
            eecho "Mount point $mountPath is not a path"
            return 1
        fi

        mpath=${mountPath:1}

        # replace all / with -
        shareName=${mpath//\//-}
    else
        # RemoteHost: <account-name>.blob.core.windows.net:/<account-name>/<container-name>

        # A random non existent mount path to mount the NFS share
        randomnumber=$RANDOM
        mountPath="/mnt/nfsv3share-$randomnumber"

        while [[ -e $mountPath ]]; do
            randomnumber=$RANDOM
            mountPath="/mnt/nfsv3share-$randomnumber"
        done

        mkdir -p $mountPath
        vecho "Created $mountPath"

        mountCommand="mount -t nfs -o nolock,vers=3,proto=tcp $mountparameter $mountPath"
        shareName="nfsv3share-$randomnumber"
    fi

    # Check if the mount path is already mounted
    mountpoint $mountPath > /dev/null 2>&1
    if [[ $? == 0 ]]; then
        eecho "Mount path $mountPath is already mounted. Use a different mount path."
        return 1
    fi

    vecho "Mounting NFS share.."

    # quote the mount command to preserve the spaces
    mount_nfs "$mountCommand" "$mountPath"

    if [[ $? != 0 ]]; then
        return 1
    fi

    vecho "Exporting NFS share via Samba.."
    share_via_samba "$shareName" "$mountPath"

    if [[ $? != 0 ]]; then
        # Unmount the NFS share
        unmount_nfs $mountPath
        return 1
    fi

    echo "$shareName" > $tempfilepath
    vecho "Saved the share name ($sharename) to $tempfilepath"
}

# Unmount NFS
# $1: mount path
function unmount_nfs ()
{
    if [[ $# != 1 ]]; then
        eecho "Usage: unmount_nfs [mount path]"
        return 1
    fi

    mntpath=$1

    mountpoint $mntpath > /dev/null 2>&1

    if [[ $? != 0 ]]; then
        wecho "Mount path $mountPath is not mounted."
        return 0
    fi

    op=$(umount $mntpath 2>&1)

    # If the umount command fails with 32, then the NFS share is already unmounted
    if [[ $? != 0 && $? != 32 ]]; then
        eecho "Failed to unmount NFS share at $mntpath:"
        eecho $op
        return 1
    fi

    vecho "Removing dir $mntpath"
    rm -rf $mntpath
    secho "Unmounted NFS mount: $mntpath"
    return 0
}

# Unmount smb share and NFS share
# $1: share name
# To-do:
# 1. Take a lock on the smb file
function unmount_share ()
{
    if [[ $# != 1 ]]; then
        eecho "Usage: unmount_share [smb share name]"
        return 1
    fi

    smbsharename=$1
    mntpath=""
    foundshare=false
    startline=0
    endline=0
    linenum=0

    # Take a backup of smb.conf to restore it if the script fails
    rm -f /etc/samba/smb.conf.bak
    cp -f -T /etc/samba/smb.conf /etc/samba/smb.conf.bak

    # Take the last matching share name
    while IFS= read -r line; do
        # line number counter
        linenum=$((linenum + 1))

        # exact match of the share name
        if [[ "$line" == "[$smbsharename]" ]]; then
            foundshare=true
            startline=$linenum

        # next share name after the target share
        elif [[ $foundshare == "true" && "$line" =~ \[.*\] ]]; then
            foundshare=false
            # Current line belongs to a new share. So, the previous line is the end of the share
            endline=$((linenum - 1))
        fi

        # If the path is found, get the path of the share and remove the share details from smb.conf
        # Sample line: path = /mnt/nfs/share1
        match="path\s*=.*"
        if [[ $foundshare == "true" && $line =~ $match ]]; then
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
        vecho "Removed SMB share with: $smbsharename."

        # Restart Samba so that we can unmount the NFS share, else we get "device is busy" error
        service smbd restart | grep -q fail

        if [[ $? == 0 ]]; then
            eecho "Failed to restart Samba."
            return 1
        fi

        ufw allow samba > /dev/null

    else
        wecho "No SMB share found for $smbsharename."

        # Even if the SMB share is not found, return 0 to let the client unmount it's mapped drive
        return 0
    fi

    if [[ $mntpath == "" ]]; then
        secho "No backing dir found for $smbsharename."
        return 0
    fi

    unmount_nfs $mntpath

    if [[ $? != 0 ]]; then
        # Restore smb.conf
        mv /etc/samba/smb.conf.bak /etc/samba/smb.conf

        # Restart Samba
        service smbd restart | grep -q fail

        if [[ $? == 0 ]]; then
            eecho "Failed to restart Samba."
            return 1
        fi

        ufw allow samba > /dev/null

        vecho "Restored smb.conf and restarted Samba."
        return 1
    fi
}

# if the first argument is installsystemd, then install systemd
if [[ $1 == "installsystemd" ]]; then
    install_systemd

# else if the first argument is installnfssmb, then run the setup steps
elif [[ $1 == "installnfssmb" ]]; then
    if [[ $# != 2 ]]; then
        eecho "Usage: $0 [installnfssmb] [sambausername]"
        exit 1
    fi

    sambausername=$2

    apt-get update > /dev/null

    install_nfs
    if [[ $? != 0 ]]; then
        exit 1
    fi

    install_samba
    if [[ $? != 0 ]]; then
        exit 1
    fi
    onetime_samba_setup "$sambausername"
    if [[ $? != 0 ]]; then
        exit 1
    fi

# else if the first argument is mountshare, then run the mount in nfs and share via samba
elif [[ $1 == "mountshare" ]]; then
    if [[ $# != 4 ]]; then
        eecho "Usage: $0 [mountshare] [mountparametertype] [mountparameter] [tempfilepath]"
        exit 1
    fi

    mount_share "$2" "$3" "$4"

    if [[ $? != 0 ]]; then
        exit 1
    fi

# if the first argument is unmountshare, then unmount smb and nfs shares
elif [[ $1 == "unmountshare" ]]; then
    if [[ $# != 2 ]]; then
        eecho "Usage: $0 [unmountshare] [smbsharename]"
        exit 1
    fi

    smbsharename=$2

    unmount_share "$smbsharename"

    if [[ $? != 0 ]]; then
        exit 1
    fi

    secho "Removed SMB share and unmounted NFS share."

# if the first argument is resetsamba, then reset samba config and restart samba
elif [[ $1 == "resetsamba" ]]; then
    vecho "Resetting the Samba setup."
    # Reset the samba setup
    rm -f /etc/samba/smb.conf
    # Copy the default smb.conf to /etc/samba/smb.conf to reset the config
    vecho "Saving the old smb.conf to /etc/samba/smb.conf.old"
    cp -T /etc/samba/smb.conf /etc/samba/smb.conf.old
    cp -T /usr/share/samba/smb.conf /etc/samba/smb.conf
    service smbd restart | grep -q fail

    if [[ $? == 0 ]]; then
        eecho "Failed to restart Samba."
        exit 1
    fi

    ufw allow samba > /dev/null
    secho "Successfully reset Samba setup."

# else, print the usage
else
    eecho "Usage: $0 [installsystemd]"
    eecho "Usage: $0 [installnfssmb] [samba username]"
    eecho "Usage: $0 [mountshare] [mount command]"
    eecho "Usage: $0 [unmountshare] [smbsharename]"
    eecho "Usage: $0 [resetsamba]"
fi