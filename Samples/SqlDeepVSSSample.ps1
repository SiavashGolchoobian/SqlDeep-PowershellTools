[string]$myShadowCopyVolume='C:'
[string]$myShadowCopyFolder='C:\ShadowCopyContent'
[string[]]$myDatabaseFiles='C:\ShadowCopyContent\Program Files\Microsoft SQL Server\MSSQL16.NODE\MSSQL\DATA\Vss.mdf','C:\ShadowCopyContent\Program Files\Microsoft SQL Server\MSSQL16.NODE\MSSQL\DATA\Vss_log.ldf'
[string]$myNewDatabaseFilesDestination='C:\Databases\'
[string]$myDestConnectionString='Data Source=WinClient2022.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True'
[string]$myQuery=$null

#--Drop existed shadow database because of file lock
$myQuery="
    USE [master];
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name ='VSS0')
    BEGIN
        ALTER DATABASE [Vss0] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
        DROP DATABASE [VSS0]
    END
"
INVOKE-SQLCMD -ConnectionString 'Data Source=WinClient2022.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True' -Query $myQuery

#--Copy inused database files by shadowcopy feature
Import-Module .\SqlDeepVSS.psm1
$myShadowCopy=New-ShadowCopy -ComputerName localhost -Drive $myShadowCopyVolume -Confirm:$false
Mount-ShadowCopy -Id ($myShadowCopy.Id) -Path $myShadowCopyFolder -Confirm:$false
$myDatabaseFiles | Copy-Item -Destination $myNewDatabaseFilesDestination -Force
Unmount-ShadowCopy -Path $myShadowCopyFolder -Confirm:$false
Remove-ShadowCopy -ComputerName localhost -Id ($myShadowCopy.Id) -Confirm:$false

#--Set files permission
$myNewAcl = Get-Acl -Path ($myNewDatabaseFilesDestination + 'Vss.mdf')
# Set properties
$myIdentity = 'SqlDeep\SQL_ServiceGMSA$'
$myFileSystemRights = 'FullControl'
$myType = 'Allow'
# Create new rule
$myFileSystemAccessRuleArgumentList = $myIdentity, $myFileSystemRights, $myType
$myFileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $myFileSystemAccessRuleArgumentList
# Apply new rul
$myNewAcl.SetAccessRule($myFileSystemAccessRule)
Set-Acl -Path ($myNewDatabaseFilesDestination + 'Vss.mdf') -AclObject $myNewAcl
Set-Acl -Path ($myNewDatabaseFilesDestination + 'Vss_log.ldf') -AclObject $myNewAcl

#--Attach Database
$myQuery="
    USE [master];
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name ='VSS0')
    BEGIN
        ALTER DATABASE [Vss0] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
        DROP DATABASE [VSS0]
    END

    CREATE DATABASE [Vss0] ON 
    ( FILENAME = N'"+$myNewDatabaseFilesDestination+"Vss.mdf' ),
    ( FILENAME = N'"+$myNewDatabaseFilesDestination+"Vss_log.ldf' )
     FOR ATTACH
"
INVOKE-SQLCMD -ConnectionString 'Data Source=WinClient2022.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True' -Query $myQuery