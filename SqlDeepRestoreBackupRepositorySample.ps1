
Using module .\SqlDeepRestoreBackupRepository.psm1
# Example usage

$ConnectionString =  "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"   # The target SQL Server instance  
$RepositoryPath = "U:\Databases\Backup\BackupFolderName"   # The repository path where backups are located  
$DataPath="F:\Data01\Databases\Data\" # New folder for move data file
$logPath="F:\Log01\Databases\Log\"   # New folder for move log file
RestoreAllDatabasesFromRepository -RepositoryPath $RepositoryPath -RestoreConnectionString $ConnectionString -NewDataPath $DataPath -NewLogPath $logPath