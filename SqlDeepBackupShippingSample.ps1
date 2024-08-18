Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepBackupShipping.psm1

#--Sample #1
[string[]]$myDatabases=('SqlDeep')
$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module 'BackupShipping' -LogToConsole -LogToFile -LogFilePath 'U:\Databases\Audit\BackupShipping_{Date}.txt' -LogToTable -LogInstanceConnectionString 'Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True' -LogTableName '[dbo].[Events]'
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

#--Sample #2
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