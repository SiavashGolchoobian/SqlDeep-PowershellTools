using module .\SqlDeepLogWriter.psm1
using module .\SqlDeepBackupTest.psm1
using module .\SqlDeepCommon.psm1

$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "BackupTest" -LogToConsole -LogToFile -LogFilePath "C:\Temp\BackupTest_{Database}_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-BK-DBV02.SAIPACORP.COM\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[myTestTable]"
$myBackupTest=[BackupTest]::New()
$myBackupTest.LogWriter=$myLogWriter
#$myShip=New-DatabaseShipping -SourceInstanceConnectionString "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-DR-DGV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -FileRepositoryUncPath "\\db-dr-dgv01\Backups" -DestinationRestoreMode ([DatabaseRecoveryMode]::RESTOREONLY) -LogWrite $myLogWriter -LimitMsdbScanToRecentHours 24 -RestoreFilesToIndividualFolders

#Sample 2:
[BackupTest]$myDatabaseTest=$null
$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=DB-C1-DLV16.SAIPACORP.COM\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-BK-DBV02.SAIPACORP.COM\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "myTestTable"
<#
$myDatabaseTest.StartDate=(Get-Date).AddDays(-2) 
$myDatabaseTest.EndDate=Get-Date
$myDatabaseTest.TestAllDatabases("sqldeep")
$myDatabaseTest.TestDatabase("sqldeep")
#$myDatabaseTest.RestoreTime or $myDatabaseTest.RestoreTo

#Sample 3 :
$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=DB-MN-DLV02.SAIPACORP.COM\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-BK-DLV01.SAIPACORP.COM\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "myTestTable"
#>

$myDatabaseTest.TestDatabase("MixI")