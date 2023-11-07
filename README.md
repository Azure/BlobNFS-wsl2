# Project

## Overview
This project is a collection of helper scripts to help you setup a Windows Subsystem for Linux (WSL) environment to mount Azure Blob NFS storage containers and export them to Windows via Samba.

> **Note**
> This is work in progress. Please check back for updates.

## Usage
Follow the below steps:

1. Install WSL on windows:  
```powershell
windowsblobnfs.ps1 -action "installwsl" 
```

2. Restart the machine if wsl is installed for the first time. Then, Setup WSL environment (Installing Ubuntu-22.04 distro, systemd, NFS client, & samba server):  

```powershell
windowsblobnfs.ps1 -action "setupwslenv"
```

3. Mount blob nfs storage container to WSL and export it via Samba on the specified drive that you can access from windows:  
```powershell
windowsblobnfs.ps1 -action "mountshare" -mountcommand "mount -t nfs -o vers=3,proto=tcp <account-name>.blob.core.windows.net:/<account-name>/<container-name> /mnt/<path>" -mountdrive "<drive>:"
```

You can check the status of the mount by running the following command:  
```powershell
Get-SmbMapping
```


To remove the drive from windows and blob nfs storage container from WSL:  
```powershell
windowsblobnfs.ps1 -action "unmountshare" -mountdrive "<drive>:"
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
