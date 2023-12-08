# Project

## Overview

This project is a collection of helper scripts to help you setup a Windows Subsystem for Linux (WSL) environment to mount Azure Blob NFS storage containers and export them to Windows via Samba. Samba is used to export the mounted blob nfs storage container to Windows since accessing the mounted blob nfs storage container directly from Windows is seen to give lower performance.


> **Note**  
> This is work in progress. Please check back for updates.

## Prerequisites
1. Since this module uses WSL to mount the Blob NFS share, Virtualization must be enabled on the machine.  

    i. If you are installing this module on an Azure VM, then select a VM size that supports nested virtualization. You can check the list of VM SKU that supports nested virtualization. Check [here](https://docs.microsoft.com/en-us/azure/virtual-machines/acu).  
    For example, Dv5 SKU supports nested virtualization:
    ![Nested Virtualization support on Azure VMs](/resources/nested-virt.png)

    > **Warning**  
    > Currently only Dv5 series VMs support nested virtualization with **Trusted Launch** enabled. If you are using a different VM SKU with **Trusted Launch** enabled, then you may see the following error while installing the module. :  
    > ```powershell
    > Ubuntu 22.04 LTS is already installed.
    > Launching Ubuntu 22.04 LTS...
    > Installing, this may take a few minutes...
    > WslRegisterDistribution failed with error: 0x80370102
    > Please enable the Virtual Machine Platform Windows feature and ensure virtualization is enabled in the BIOS.
    > For information please visit https://aka.ms/enablevirtualization
    > Press any key to continue...
    > ```
    > Create a VM without **Trusted Launch** and try installing the module again.
    > Check if your VM has **Trusted Launch** enabled under the Security section of the VM blade in the Azure portal.
    ![Trusted Launch for Azure VMs](/resources/dmaonvms.png)
    > Check [here](https://learn.microsoft.com/en-us/azure/virtual-machines/trusted-launch#unsupported-features) for more details on **Trusted Launch**.  

    ii. If you are installing this module on a your own machine, then make sure that the machine virtualization is enabled in the BIOS. Check [here](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting#error-0x80370102-the-virtual-machine-could-not-be-started-because-a-required-feature-is-not-installed) for more details.  

    iii. For any other installation issues, check issues on [WSL troubleshooting guide](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting) or [WSL GitHub repo](https://github.com/Microsoft/wsl/issues).  

2. Follow the steps here to create an Azure Blob NFS storage container: [Create an NFS 3.0 storage container](https://docs.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to?tabs=azure-portal#create-an-nfs-30-storage-container).



## Usage

1. Install the module from PSGallery:  

```powershell
Install-Module -Name WSLBlobNFS
```
    Check the above Prerequisite section if you face any errors while installing the module.  

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
> Only after setting up the user account, proceed to Initialize-WSLBlobNFS step.


```powershell
Initialize-WSLBlobNFS
```

5. Mount blob nfs storage container to WSL and map it via Samba on a drive that you can access from windows:  

> **Note**  
> - The module uses default mount options to mount the blob nfs storage container. If you want to use custom mount options, you can provide the complete mount command as a parameter to the Mount-WSLBlobNFS cmdlet.
> - MountDrive parameter is optional. If not provided, the drive will be automatically assigned.
> - Check ```Get-Help -Full -Name Mount-WSLBlobNFS``` for more examples.

```powershell
Mount-WSLBlobNFS -RemoteMount "<account-name>.blob.core.windows.net:/<account-name>/<container-name>"
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

To Update the module:  

```powershell
Update-Module -Name WSLBlobNFS
```

## Help

1. Use -Verbose switch to get verbose output for the cmdlets.

2. Common issues and their solutions:  

    - If you get the following error while running the Mount-WSLBlobNFS cmdlet, do the following and try mount again: 

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
