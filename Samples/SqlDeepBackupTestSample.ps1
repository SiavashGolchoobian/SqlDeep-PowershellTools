using module .\SqlDeepLogWriter.psm1
using module .\SqlDeepBackupTest.psm1
using module .\SqlDeepCommon.psm1

$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "BackupTest" -LogToConsole -LogToFile -LogFilePath "C:\Temp\BackupTest_{Database}_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=MachinName\InstanceName;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[myTestTable]"
$myBackupTest=[BackupTest]::New()
$myBackupTest.LogWriter=$myLogWriter
#$myShip=New-DatabaseShipping -SourceInstanceConnectionString "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-DR-DGV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -FileRepositoryUncPath "\\db-dr-dgv01\Backups" -DestinationRestoreMode ([DatabaseRecoveryMode]::RESTOREONLY) -LogWrite $myLogWriter -LimitMsdbScanToRecentHours 24 -RestoreFilesToIndividualFolders

#Sample 1:
[BackupTest]$myDatabaseTest=$null
$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=MachinName.Domainname\InstanceName,PortNo;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=MachinName.Domainname\InstanceName,PortNo;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "myTestTable" # -FileRepositoryUncPath "\\DB-BK-DBV02\U$\Databases\Backup"

#.$myDatabaseTest.StartDate= "10/14/2024 14:45:00" 
$myDatabaseTest.StartDate=(Get-Date).AddDays(-2) 
$myDatabaseTest.EndDate=Get-Date
#$myDatabaseTest.TestAllDatabases("sqldeep")
#$myDatabaseTest.TestDatabase("sqldeep")
$myDatabaseTest.TestDatabase("MixI")

#$myDatabaseTest.RestoreTime or $myDatabaseTest.RestoreTo
<#
#Sample 2 :
$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=MachinName.Domainname\InstanceName,PortNo;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-BK-DBV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "myTestTable"

[string[]]$ExcludedDatabaseList = "sqldeep","DWDiagnostics","SSISDB"
$myDatabaseTest.TestAllDatabases($ExcludedDatabaseList)

$SourceInstanceConnectionString = "Data Source=MachinName.Domainname\InstanceName,PortNo;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" 

#Sample 3 :
$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=DB-MN-DLV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-BK-DBV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "BackupTestResult" -FileRepositoryUncPath "\\DB-BK-DBV02\U$\Databases\Backup"

[string[]]$ExcludedDatabaseList = "TBSFileServerDB","SSISDB","SqlDeep","DWQueue","DWDiagnostics","DWConfiguration","WSS_Content_archive_engineering","WSS_Content_archive_Personneli","WSS_Content_archive_saipagroup_net","WSS_Content_dealernews","WSS_Content_DMS","TBSFileServerDB"
[string[]]$ExcludedInstanceList = "DB-TEST-DTV04..Domainname\NODE,49149"
[string]$myFilter = "SQL 2019"
$myDatabaseTest.SkipBackupFilesExistenceCheck=$true
$myDatabaseTest.LimitMsdbScanToRecentHours=24
#$myDatabaseTest.RestoreTo=[datetime]"10/12/2024 17:33:05"
$myDatabaseTest.TestFromRegisterServer($ExcludedInstanceList,$ExcludedDatabaseList,$myFilter)

#>


