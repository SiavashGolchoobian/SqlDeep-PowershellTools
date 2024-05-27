Using module .\SqlDeepDatabaseShippingEnums.psm1
Import-Module .\SqlDeepDatabaseShipping.psm1
$myShip=New-DatabaseShipping -SourceInstanceConnectionString "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-DR-DGV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -FileRepositoryUncPath "\\db-dr-dgv01\Backups" -DestinationRestoreMode ([DatabaseRecoveryMode]::RESTOREONLY) -LogInstanceConnectionString "Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -LogFilePath "U:\Log\DatabaseShipping_{Database}_{Date}.txt" -LimitMsdbScanToRecentDays 0 -RestoreFilesToIndividualFolders

#Sample1:   Restore signle database [Sampledb1] as [Sampledb_DR] to destination in norecovery mode
$myShip.ShipDatabase("Sampledb1","Sampledb1_DR")

#Sample2:   Restore multiple database ([Sampledb1],[Sampledb2],[Sampledb3]) as [Sampledb1_DR],[Sampledb2_DR],[Sampledb3_DR] to destination in norecovery mode
[string[]]$myDatabases="Sampledb1","Sampledb2","Sampledb3"
$myShip.ShipDatabases($myDatabases,"_DR")

#Sample3:   Restore all user database except someones to destination in norecovery mode
[string[]]$myExcludedList="SqlDeep","Sampledb3"
$myShip.ShipAllUserDatabases("_DR",$myExcludedList)