# Change Primary User

This script is provided as-is. No guarantee if it works or not. I'm not 100% sure if all of the permissions are nessecary, as i used the permissions from a migration test from the getrubix migration V8 script, but it worked for me.

## Script Details

You need to create an application registration in Entra ID. For the configuration of the script, you need to have the following three key elements:

- Client ID (from the created application)
- Tenant ID (found in Entra ID overview)
- Secret Key (from the created application)

After that, set the Graph permissions accordingly and grant admin consent with a Global Administrator.

![Graph Permissions](https://github.com/H4L-MKIII/Intune/blob/main/Graph/PrimaryUser/GraphPermissions.png)

## Prerequisites

Before running the script, ensure you have the necessary permissions set up in Microsoft Graph.

- AuditLog.Read.All
- Device.ReadWrite.All
- DeviceManagementConfiguration.ReadWrite.All
- DeviceManagementManagedDevices.PrivilegedOperations.All
- DeviceManagementManagedDevices.ReadWrite.All
- DeviceManagementScripts.ReadWrite.All
- DeviceManagementServiceConfig.ReadWrite.All
- User.Read
- User.Read.All

## Usage

Download the script on your machine, execute locally, and ensure the global administrator has granted the necessary Graph permissions.
