Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepDatabaseShipping.psm1

$myLogWriter=New-LogWriter -EventSource ($env:computername) -Module "DatabaseShipping" -LogToConsole -LogToFile -LogFilePath "U:\Audit\DatabaseShipping_{Database}_{Date}.txt" -LogToTable -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogTableName "[dbo].[Events]"
$myShip=New-DatabaseShipping -SourceInstanceConnectionString "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-DR-DGV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -FileRepositoryUncPath "\\db-dr-dgv01\Backups" -DestinationRestoreMode ([DatabaseRecoveryMode]::RESTOREONLY) -LogWrite $myLogWriter -LimitMsdbScanToRecentHours 24 -RestoreFilesToIndividualFolders

#Sample1:   Restore signle database [Sampledb1] as [DR_Sampledb] to destination in norecovery mode
$myShip.ShipDatabase("Sampledb1","Sampledb1_DR")

#Sample2:   Restore and recover signle database [Sampledb1] as [DR_Sampledb] to 6/31/2024 20:05:00 on destination server (PTR only supports in [DatabaseRecoveryMode]::RECOVERY mode)
$myShip.RestoreTo=[datetime]"6/31/2024 20:05:00"
$myShip.DatabaseRecoveryMode=[DatabaseRecoveryMode]::RECOVERY
$myShip.ShipDatabase("Sampledb1","Sampledb1_DR")

#Sample3:   Restore multiple database ([Sampledb1],[Sampledb2],[Sampledb3]) as [DR_Sampledb1],[DR_Sampledb2],[DR_Sampledb3] to destination in norecovery mode
[string[]]$myDatabases="Sampledb1","Sampledb2","Sampledb3"
$myShip.ShipDatabases($myDatabases,"DR_")

#Sample4:   Restore all user database except someones to destination in norecovery mode
[string[]]$myExcludedList="SqlDeep","Sampledb3"
$myShip.ShipAllUserDatabases("DR_",$myExcludedList)

#Sample5:   Restore all user database except "SqlDeep","Sampledb3" to destination in norecovery mode also it tryies to use only Log files restoration if possible
[string[]]$myExcludedList="SqlDeep","Sampledb3"
$myShip.PreferredStrategies=[RestoreStrategy]::Log
$myShip.ShipAllUserDatabases("DR_",$myExcludedList)

#Sample6:   Restore all user database except "SqlDeep","Sampledb3" to destination in norecovery mode also it tryies to use only Log files restoration if possible
[string]$ExcludedList="SqlDeep,Sampledb3"
[string]$Prefix=""
[string[]]$myExcludedList=$null
if ($null -ne $ExcludedList -and $ExcludedList.Trim().Length -gt 0){$myExcludedList=$ExcludedList.Split(",")}else{$myExcludedList=$null}
$myShip.SkipBackupFilesExistenceCheck=$true                #Don't check backup file existence on source (because of performance penalty)
$myShip.PreferredStrategies=[RestoreStrategy]::Log
$myShip.ShipAllUserDatabases($Prefix,$myExcludedList)

#Sample7:   Restore signle database [Sampledb1] as [DR_Sampledb] to destination in norecovery mode and change it's Data and Log folder location to another Path
$myShip.DataFolderRestoreLoation="F:\Data02\Databases\Data"
$myShip.LogFolderRestoreLoation="F:\Log02\Databases\Data"
$myShip.ShipDatabase("Sampledb1","Sampledb1_DR")