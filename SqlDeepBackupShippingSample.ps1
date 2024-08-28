Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepBackupShipping.psm1

[string[]]$myDatabases=('SqlDeep')
$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module 'BackupShipping' -LogToConsole -LogToFile -LogFilePath 'U:\Databases\Audit\BackupShipping_{Date}.txt' -LogToTable -LogInstanceConnectionString 'Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True' -LogTableName '[dbo].[Events]'

#--Sample #1:   Use Direct username and password then shipp files to destination
$myBackupShipping=[BackupShipping]::New('Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True',$myDatabases,[DestinationType]::SCP,'172.20.50.20','/bk_sql/test/{CustomRule01}/{CustomRule02(J)}/{ServerName}_{InstanceName}',$myLogWriter)
$myBackupShipping.BackupTypes=([BackupType]::FULL,[BackupType]::DIFF,[BackupType]::LOG)
$myBackupShipping.HoursToScanForUntransferredBackups=72
$myBackupShipping.SshHostKeyFingerprint='ssh-ed25519 256 xEkJwBAimRr3rfS3Hm+dnKc5lSTABvDUntt+itokHPw='
$myBackupShipping.ActionType=[ActionType]::Copy
$myBackupShipping.RetainDaysOnDestination='CustomRule01'
$myBackupShipping.TransferedFileDescriptionSuffix='Transfereds'
$myBackupShipping.BackupShippingCatalogTableName='TransferredFiles'
$myBackupShipping.WinScpPath='C:\WinSCP\WinSCPnet.dll'
$myBackupShipping.Set_DestinationCredential('sqldeepbackup','Str0ngP@$$W0rd')
$myBackupShipping.Transfer_Backup()

#--Sample #2:   Use Direct username and password then shipp files to destination
$myBackupShipping=[BackupShipping]::New()
$myBackupShipping.LogWriter=$myLogWriter
$myBackupShipping.SourceInstanceConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True'
$myBackupShipping.Databases=$myDatabases
$myBackupShipping.BackupTypes=([BackupType]::FULL,[BackupType]::DIFF,[BackupType]::LOG)
$myBackupShipping.HoursToScanForUntransferredBackups=72
$myBackupShipping.DestinationType=[DestinationType]::SCP
$myBackupShipping.Destination='172.20.50.200'
$myBackupShipping.DestinationFolderStructure='/bk_sql/test/{CustomRule01}/{CustomRule02(J)}/{ServerName}_{InstanceName}'
$myBackupShipping.SshHostKeyFingerprint='ssh-ed25519 256 xEkJwBAimRr3rfS3Hm+dnKc5lSTABvDUntt+itokHPw='
$myBackupShipping.ActionType=[ActionType]::Copy
$myBackupShipping.RetainDaysOnDestination='CustomRule01'
$myBackupShipping.TransferedFileDescriptionSuffix='Transfereds'
$myBackupShipping.BackupShippingCatalogTableName='TransferredFiles'
$myBackupShipping.WinScpPath='C:\WinSCP\WinSCPnet.dll'
$myBackupShipping.Set_DestinationCredential('sqldeepbackup','Str0ngP@$$W0rd')
$myBackupShipping.Transfer_Backup()


#--Sample #3:   Use Stored Credential then shipp files to destination
#Run bellow script as runtime user only once on your server to save credential on Windows Store
[string]$myCredentialStoreName='SqlDeepCred'
[System.Net.NetworkCredential]$myCredential=Get-Credential
$myBackupShipping.Save_CredentialToStore($myCredentialStoreName,$myCredential)

$myBackupShipping=[BackupShipping]::New()
$myBackupShipping.LogWriter=$myLogWriter
$myBackupShipping.SourceInstanceConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True'
$myBackupShipping.Databases=$myDatabases
$myBackupShipping.BackupTypes=([BackupType]::FULL,[BackupType]::DIFF,[BackupType]::LOG)
$myBackupShipping.HoursToScanForUntransferredBackups=24
$myBackupShipping.DestinationType=[DestinationType]::SCP
$myBackupShipping.Destination='172.20.5.200'
$myBackupShipping.DestinationFolderStructure='/bk_sql/tst/{CustomRule01}/{CustomRule02(J)}/{ServerName}_{InstanceName}'
$myBackupShipping.SshHostKeyFingerprint='ssh-ed25519 256 bvhJwBAktcr3rfS3Hm+dnKc5l6TABvDUntt+itYkHPw='
$myBackupShipping.ActionType=[ActionType]::Copy
$myBackupShipping.RetainDaysOnDestination='CustomRule01'
$myBackupShipping.TransferedFileDescriptionSuffix='Transfereds'
$myBackupShipping.BackupShippingCatalogTableName='TransferredFiles'
$myBackupShipping.WinScpPath='U:\Install\WinSCP\WinSCPnet.dll'
$myBackupShipping.Set_DestinationCredential($myCredentialStoreName)
$myBackupShipping.Transfer_Backup()

#--Sample #4:   Use Direct username and hashed password then shipp files to destination
[string]$myCredentialStoreName='SqlDeepCred'
$myBackupShipping=[BackupShipping]::New()
$myBackupShipping.LogWriter=$myLogWriter
$myBackupShipping.SourceInstanceConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True'
$myBackupShipping.Databases=$myDatabases
$myBackupShipping.BackupTypes=([BackupType]::FULL,[BackupType]::DIFF,[BackupType]::LOG)
$myBackupShipping.HoursToScanForUntransferredBackups=24
$myBackupShipping.DestinationType=[DestinationType]::SCP
$myBackupShipping.Destination='172.20.5.200'
$myBackupShipping.DestinationFolderStructure='/bk_sql/tst/{CustomRule01}/{CustomRule02(J)}/{ServerName}_{InstanceName}'
$myBackupShipping.SshHostKeyFingerprint='ssh-ed25519 256 bvhJwBAktcr3rfS3Hm+dnKc5l6TABvDUntt+itYkHPw='
$myBackupShipping.ActionType=[ActionType]::Copy
$myBackupShipping.RetainDaysOnDestination='CustomRule01'
$myBackupShipping.TransferedFileDescriptionSuffix='Transfereds'
$myBackupShipping.BackupShippingCatalogTableName='TransferredFiles'
$myBackupShipping.WinScpPath='U:\Install\WinSCP\WinSCPnet.dll'
$myByteKey=(8,7,1,3,3,3,7,9,7,3,5,3,1,2,5,5,6,0,7,4,6,3,7,8,4,6,3,4,3,8,1,1)    #32 byte
$myCipheredPassword="DFGBFDGbfdg042SDFBDFBJ<MJGK<AVgA1AFIAUgA5ADEANQB1ADcAVgBvAHoAUwsdfvdsfbAGEAYQBlADAAYgAzAGYAOABkADEAZAA3ADYANwA0ADAANgBiADMANwA1AGMANgBmADkANgBjADIAYQBhADgAMAA0ADYAZQAzAGEAZQAzADIAMABmAGQAYQA1ADkAYwAzADYANAA4ADAANQAxADYAYgA="
$myBackupShipping.Set_DestinationCredential('sqldeepbackup',$myCipheredPassword,$myByteKey)
$myBackupShipping.Transfer_Backup()

#--Sample #5:   Get Credential via GUI and shipp files to destination
$myBackupShipping=[BackupShipping]::New()
$myBackupShipping.LogWriter=$myLogWriter
$myBackupShipping.SourceInstanceConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True'
$myBackupShipping.Databases=$myDatabases
$myBackupShipping.BackupTypes=([BackupType]::FULL,[BackupType]::DIFF,[BackupType]::LOG)
$myBackupShipping.HoursToScanForUntransferredBackups=24
$myBackupShipping.DestinationType=[DestinationType]::UNC
$myBackupShipping.Destination='\\DB-MN-DLV01\Repo'
$myBackupShipping.DestinationFolderStructure='tst\{CustomRule01}\{CustomRule02(J)}\{ServerName}_{InstanceName}'
$myBackupShipping.ActionType=[ActionType]::Copy
$myBackupShipping.RetainDaysOnDestination='CustomRule01'
$myBackupShipping.TransferedFileDescriptionSuffix='Transfereds'
$myBackupShipping.BackupShippingCatalogTableName='TransferredFiles'
$myBackupShipping.WinScpPath='U:\Install\WinSCP\WinSCPnet.dll'
[System.Net.NetworkCredential]$myCredential=Get-Credential
$myBackupShipping.Set_DestinationCredential($myCredential)
$myBackupShipping.Transfer_Backup()

#--Sample #6:   Get Credential via GUI and Delete deprecated shipped files from destination
$myBackupShipping=[BackupShipping]::New()
$myBackupShipping.LogWriter=$myLogWriter
$myBackupShipping.SourceInstanceConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=Tempdb;Integrated Security=True;TrustServerCertificate=True;Encrypt=True'
$myBackupShipping.Databases=$myDatabases
$myBackupShipping.BackupTypes=([BackupType]::FULL,[BackupType]::DIFF,[BackupType]::LOG)
$myBackupShipping.HoursToScanForUntransferredBackups=24
$myBackupShipping.DestinationType=[DestinationType]::UNC
$myBackupShipping.Destination='\\DB-MN-DLV01\Repo'
$myBackupShipping.DestinationFolderStructure='tst\{CustomRule01}\{CustomRule02(J)}\{ServerName}_{InstanceName}'
$myBackupShipping.ActionType=[ActionType]::Copy
$myBackupShipping.RetainDaysOnDestination='CustomRule01'
$myBackupShipping.TransferedFileDescriptionSuffix='Transfereds'
$myBackupShipping.BackupShippingCatalogTableName='TransferredFiles'
$myBackupShipping.WinScpPath='U:\Install\WinSCP\WinSCPnet.dll'
[System.Net.NetworkCredential]$myCredential=Get-Credential
$myBackupShipping.Set_DestinationCredential($myCredential)
$myBackupShipping.Delete_DepricatedBackup()