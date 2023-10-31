# Project

## Overview
This project is a collection of helper scripts to help you setup a Windows Subsystem for Linux (WSL) environment to mount Azure Blob NFS storage containers and export them to Windows via Samba.

> **Note**
> This is work in progress. Please check back for updates.

## Usage

Install WSL on windows:  
```powershell
windowsblobnfs.ps1 -action "installwsl" 
```

Setup WSL environment (Installing Ubuntu-22.04 distro, systemd, NFS client, & samba server):  

```powershell
windowsblobnfs.ps1 -action "setupwslenv"
```

Mount blob nfs storage container to WSL and export it to windows via Samba:  
```powershell
windowsblobnfs.ps1 -action "mountshare" -mountcommand "mount -t nfs -o vers=3,proto=tcp {account-name}.blob.core.windows.net:/{account-name}/{container-name} /mnt/{path}" -mountdrive "{drive}:"
```

Unmount Samba share and blob nfs storage container from WSL:  
```powershell
windowsblobnfs.ps1 -action "unmountshare" -mountdrive "{drive}:"
```

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

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
