using module .\SqlDeepLogWriter.psm1
using module .\SqlDeepBackupTest.psm1
using module .\SqlDeepCommon.psm1

$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "BackupTest" -LogToConsole -LogToFile -LogFilePath "C:\Temp\BackupTest_{Database}_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-BK-DBV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[myTestTable]"
$myBackupTest=[BackupTest]::New()
$myBackupTest.LogWriter=$myLogWriter
#$myShip=New-DatabaseShipping -SourceInstanceConnectionString "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-DR-DGV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -FileRepositoryUncPath "\\db-dr-dgv01\Backups" -DestinationRestoreMode ([DatabaseRecoveryMode]::RESTOREONLY) -LogWrite $myLogWriter -LimitMsdbScanToRecentHours 24 -RestoreFilesToIndividualFolders

#Sample 1:
[BackupTest]$myDatabaseTest=$null
#$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=DB-C1-DLV16.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-BK-DBV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "myTestTable" # -FileRepositoryUncPath "\\DB-BK-DBV02\U$\Databases\Backup"
$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=DB-C1-DLV16.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-BK-DBV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "myTestTable" # -FileRepositoryUncPath "\\DB-BK-DBV02\U$\Databases\Backup"

$myDatabaseTest.StartDate=(Get-Date).AddDays(-2) 
$myDatabaseTest.EndDate=Get-Date
#$myDatabaseTest.TestAllDatabases("sqldeep")
#$myDatabaseTest.TestDatabase("sqldeep")
$myDatabaseTest.TestDatabase("MixI")

#$myDatabaseTest.RestoreTime or $myDatabaseTest.RestoreTo
<#
#Sample 2 :
$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=DB-MN-DLV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-BK-DBV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "myTestTable"

[string[]]$ExcludedDatabaseList = "sqldeep","DWDiagnostics","SSISDB"
$myDatabaseTest.TestAllDatabases($ExcludedDatabaseList)

$SourceInstanceConnectionString = "Data Source=DB-C1-DLV16.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" 

#Sample 3 :
$myDatabaseTest=New-DatabaseTest -SourceInstanceConnectionString "Data Source=DB-MN-DLV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-BK-DBV02.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogWrite $myLogWriter -BackupTestCatalogTableName "myTestTable"

[string[]]$ExcludedDatabaseList = "sqldeep","DWDiagnostics","SSISDB"
[string[]]$ExcludedInstanceList = "DB-C1-DLV11.SQLDEEP.LOCAL\NODE,49149","DB-C1-DLV12.SQLDEEP.LOCAL\NODE,49149","DB-C1-DLV13.SQLDEEP.LOCAL\NODE,49149","DB-C1-DLV14.SQLDEEP.LOCAL\NODE,49149","DB-C1-DLV15.SQLDEEP.LOCAL\NODE,49149","DB-C1-DLV16.SQLDEEP.LOCAL\NODE,49149","DB-SH-DLV01.SQLDEEP.LOCAL\SHAREPOINT,49149"

$myDatabaseTest.TestFromRegisterServer($ExcludedInstanceList,$ExcludedDatabaseList)

#>
