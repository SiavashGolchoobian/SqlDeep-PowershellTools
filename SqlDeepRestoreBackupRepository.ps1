<#  
.SYNOPSIS  
    Restores databases from backup files Repository.  
.DESCRIPTION  
    This script restores all databases from the specified backup repository  
    and moves the data and log files to defined directories.  
.AUTHOR  
    Fatemeh Moniri 
.DATE  
    2024-09-20  
#>  
function RestoreAllDatabasesFromRepository {
    param (
        [string]$RepositoryPath,
        [string]$RestoreConnectionString,
        [string]$NewDataPath,
        [string]$NewLogPath
    )

    # Get all backup files from the repository
    $myBackupFiles = Get-ChildItem -Path $repositoryPath -Filter *.bak

    foreach ($myFile in $myBackupFiles) {
        # Initialize variables  
        $myDatabaseName = $null  
        $myFileList = $null  
        $myHeaderInfo = $null  
        # Get the logical names of the files in the backup
        try {
            $myFileList = Invoke-Sqlcmd -ConnectionString $RestoreConnectionString -Query "RESTORE FILELISTONLY FROM DISK = '$($myFile.FullName)'"
        }
        catch {
            Write-Host "Error retrieving file list for '$($myFile.FullName)'. Error: $_"  
            continue  # Skip to the next backup file  
        }
        
        try {
            $myHeaderInfoQuery = "RESTORE HEADERONLY FROM DISK = N'$($myFile.FullName)';"  
            $myHeaderInfo = Invoke-Sqlcmd -Query $myHeaderInfoQuery -ConnectionString $RestoreConnectionString  
        }
        catch {
            Write-Host "Error retrieving header information for '$($myFile.FullName)'. Error: $_"  
            continue  # Skip to the next backup file  
        }

        
        $myDatabaseName = $myHeaderInfo.DatabaseName
        $myNewDataPath = $NewDataPath+$myDatabaseName
        $myNewLogPath = $NewLogPath+$myDatabaseName
        # Construct the MOVE options for the RESTORE command
        $MymoveCommand = @()
        foreach ($file in $myFileList) {
            if ($file.Type -eq 'D') {
                if (-not (Test-Path -Path $myNewDataPath)) {  
                    New-Item -ItemType Directory -Path $myNewDataPath  
                } 
                $MymoveCommand += "MOVE '$($file.LogicalName)' TO '$myNewDataPath\$($file.LogicalName).$($file.PhysicalName.Split('.')[-1])'"
            } elseif ($file.Type -eq 'L') {
                if (-not (Test-Path -Path $myNewLogPath)) {  
                    New-Item -ItemType Directory -Path $myNewLogPath  
                } 
                $MymoveCommand += "MOVE '$($file.LogicalName)' TO '$myNewLogPath\$($file.LogicalName).$($file.PhysicalName.Split('.')[-1])'"
            }
        }

        # Join the MOVE options into a single string
        $myMoveCommandString = $MymoveCommand -join ", "

        # Restore the database
        try {
            $myQuery = "RESTORE DATABASE [$myDatabaseName] FROM DISK = '$($myFile.FullName)' WITH $myMoveCommandString, RECOVERY ,STATS =10 "
            Write-Host $myQuery
            Invoke-Sqlcmd  -ConnectionString $RestoreConnectionString -Query $myQuery
            Write-Host "Successfully restored database '$myDatabaseName' from '$($myFile.FullName)'."  
        }
        catch {
            
            Write-Host "Error restoring database '$myDatabaseName' from '$($myFile.FullName)'. Error: $_"  
        }
    }
}
# Example usage


$ConnectionString =  "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True"   # The target SQL Server instance  
$RepositoryPath = "U:\Databases\Backup\BackupFolderName"   # The repository path where backups are located  
$DataPath="F:\Data01\Databases\Data\" # New folder for move data file
$logPath="F:\Log01\Databases\Log\"   # New folder for move log file
RestoreAllDatabasesFromRepository -RepositoryPath $RepositoryPath -RestoreConnectionString $ConnectionString -NewDataPath $DataPath -NewLogPath $logPath