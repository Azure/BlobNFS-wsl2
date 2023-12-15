# Project

## Overview

This project is a collection of PS commands to help you mount Azure Blob NFS storage containers via a Windows Subsystem for Linux (WSL). It provides commands to seemlessly install all the required components and mount and unmount your containers within Windows. With this setup, you can access your containers from Windows Explorer and any other Windows applications.  

Here a list of components that is installed by this module:

- WSL2,
- Ubuntu distro,
- Systemd,
- NFS,
- Samba.  

Samba is used to export the WSL mounted container to Windows since accessing the mounted container directly from Windows using the native filesystem is seen to provide lower performance.

Architectural diagram of the WSLBlobNFS setup:
![Architectural diagram of the WSLBlobNFS setup](/resources/architecture.png)  

This PS module majorly has two components:

- WSLBlobNFS.psm1 - Windows PS script as an interface between User and WSL.
- wsl2_linux_script.sh - Linux script to setup the WSL environment, mount and unmount containers.  

> **Note**  
> This is work in progress. Please check back for updates.

## Prerequisites

1. This module requires WSL2.  

1. WSL2 is available only on 64 bit machines. Further, only use 64 bit version of the Powershell to use the module.  

1. WSL2 features needed by this module are available only on Windows 10, version 2004 or higher, and Windows Server 2022, version 2009 or higher. Check [here](https://learn.microsoft.com/en-us/windows/wsl/install#prerequisites) for more details.  

1. WSL2 requires virtualization. Please select a machine that supports virtualization.  

    i. If you are installing this module on an Azure VM, then select a VM size that supports nested virtualization. You can check the list of VM SKU that supports nested virtualization [here](https://docs.microsoft.com/en-us/azure/virtual-machines/acu).  
    For example, Dv5 SKU supports nested virtualization:
    ![Nested Virtualization support on Azure VMs](/resources/nested-virt.png)

    ii. If you are installing this module on any other  machine, then make sure that the virtualization is enabled in the BIOS. Check [here](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting#error-0x80370102-the-virtual-machine-could-not-be-started-because-a-required-feature-is-not-installed) for more details.  

1. Follow the steps here to create an Azure Blob NFS storage container: [Create an NFS 3.0 storage container](https://docs.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to?tabs=azure-portal#create-an-nfs-30-storage-container).

<!-- To-do: Provide one click option to create vm and storage account with all the necessary setup to just launch and try the module. -->

## Usage

1. Install the module from PSGallery:  

```powershell
Install-Module -Name WSLBlobNFS -Scope CurrentUser
```

> **Note**  
> The mounted drive will be visible only to the user who mounts it, so please make sure that you are running the cmdlets as the same user.


2. Import the module:  

```powershell
Import-Module -Name WSLBlobNFS -Force
```

To check the list of commands available in the module:  

```powershell
Get-Command -Module WSLBlobNFS
```

To get help on a specific command:  

```powershell
Get-Help -Full -Name <command-name>
```

3. Install WSL (Restart the machine if WSL is installed for the first time.):  

```powershell
Install-WSLBlobNFS
```

4. Setup WSL environment (Installing Ubuntu-22.04 distro, systemd, NFS client, & samba server):  

> **Note**  
> If Ubuntu-22.04 is being installed for the first time, you will be prompted to create a new user account.  

```powershell
Initialize-WSLBlobNFS
```

5. Mount blob nfs storage container to WSL and map it via Samba on a drive that you can access from windows:  

> **Note**  
> - The module uses default mount options to mount the blob nfs storage container. If you want to use custom mount options, you can provide the complete mount command as a parameter to the Mount-WSLBlobNFS cmdlet. Check ```Get-Help -Full -Name Mount-WSLBlobNFS``` for more examples.

```powershell
Mount-WSLBlobNFS -RemoteMount "<account-name>.blob.core.windows.net:/<account-name>/<container-name>"
```

6. To auto mount the blob nfs storage containers on startup (Run as Admin as creating Scheduled Task requires admin privileges):  

```powershell
Register-AutoMountWSLBlobNFS
```

You can check the status of the mount by running the following command:  

```powershell
Get-SmbMapping -LocalPath "<drive>:"
```

To remove the drive from windows and blob nfs storage container from WSL:  

```powershell
Dismount-WSLBlobNFS -MountDrive "<drive>:"
```

To Uninstall the module:  

```powershell
Uninstall-Module -Name WSLBlobNFS
```

To Update the module (Reimporting the module is required after updating):  

```powershell
Update-Module -Name WSLBlobNFS
Import-Module -Name WSLBlobNFS -Force
```

## Help

> **Tip**  
> Use -Verbose switch to get verbose output for the cmdlets.

- Currently only Dv5 series VMs support nested virtualization with **Trusted Launch** enabled. If you are using a different VM SKU with **Trusted Launch** enabled, then you may see the following error while installing the module. :  

    > ```powershell
    > Ubuntu 22.04 LTS is already installed.
    > Launching Ubuntu 22.04 LTS...
    > Installing, this may take a few minutes...
    > WslRegisterDistribution failed with error: 0x80370102
    > Please enable the Virtual Machine Platform Windows feature and ensure virtualization is enabled in the BIOS.
    > For information please visit https://aka.ms/enablevirtualization
    > Press any key to continue...
    > ```
    >
    > Create a VM without **Trusted Launch** and try installing the module again.
    > Check if your VM has **Trusted Launch** enabled under the Security section of the VM blade in the Azure portal.
    ![Trusted Launch for Azure VMs](/resources/dmaonvms.png)
    > Check [here](https://learn.microsoft.com/en-us/azure/virtual-machines/trusted-launch#unsupported-features) for more details on **Trusted Launch**.  

- For any other WSL2 installation issues, check issues on [WSL troubleshooting guide](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting) or [WSL GitHub repo](https://github.com/Microsoft/wsl/issues).  

- If you get the following error while running the Mount-WSLBlobNFS cmdlet, do the below steps and try mount again:  

    ```powershell
    Mounting SMB share \\<wsl-ip>\<samba-share-name> onto drive Z:
    System error 1272 has occurred.

    You can't access this shared folder because your organization's security policies block unauthenticated guest access. These policies help protect your PC from unsafe or malicious devices on the network.
    ```

    Commands to resolve the above issue:

    ```powershell
    Update-Module WSLBlobNFS
    Import-Module WSLBlobNFS -Force
    Initialize-WSLBlobNFS -Force
    ```

- If auto mounting is not working on startup, run the following command to manually setup the pipeline again:  

    ```powershell
    Assert-PipelineWSLBlobNFS
    ```

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [https://cla.opensource.microsoft.com](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
