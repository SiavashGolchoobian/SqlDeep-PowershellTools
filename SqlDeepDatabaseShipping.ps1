#--------------------------------------------------------------Parameters.
#---Copy and Restore full,diff and log backups from Source Server to Target Server (Golchoobian)
#$SourceInstanceConnectionString="Data Source=LSNRIDEA.SAIPACORP.COM,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;"
#$DestinationInstanceConnectionString="Data Source=DB-DR-DGV01.SAIPACORP.COM\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;"
#$SourceDB="IdeaDB"
#$DestinationDB="IdeDB_DR"
#$FileRepositoryUncPath="\\DB-DR-DGV01.saipacorp.com\Backup"
#$SetDestinationDBToMode="RESTOREONLY"
#$LogInstanceConnectionString="Data Source=DB-MN-DLV02.SAIPACORP.COM\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;"
#$LogTableName="[dbo].[Events]"
#$LogFilePath="U:\Databases\Audit\DatabaseShipping_DB_C1_DLV11_{DateTime}.txt"

Param(
   [Parameter(Mandatory=$true)][string]$SourceInstanceConnectionString,
   [Parameter(Mandatory=$true)][string]$DestinationInstanceConnectionString,
   [Parameter(Mandatory=$true)][string]$SourceDB,
   [Parameter(Mandatory=$true)][string]$DestinationDB,
   [Parameter(Mandatory=$true)][string]$FileRepositoryUncPath,
   [Parameter(Mandatory=$false)][ValidateSet("RECOVER","RESTOREONLY")][string]$SetDestinationDBToMode="RESTOREONLY",
   [Parameter(Mandatory=$true)][string]$LogInstanceConnectionString,
   [Parameter(Mandatory=$false)][string]$LogTableName="[dbo].[Events]",
   [Parameter(Mandatory=$false)][string]$LogFilePath="U:\Databases\Audit\DatabaseShipping_DB_C1_DLV11_{DateTime}.txt"
   )
#---------------------------------------------------------FUNCTIONS
Function Get-FunctionName ([int]$StackNumber = 1) { #Create Log Table if not exists
    return [string]$(Get-PSCallStack)[$StackNumber].FunctionName
}
Function EventsTable.Create {   #Create Events Table to Write Logs to a database table if not exists
    Param
        (
        [Parameter(Mandatory=$true)][string]$LogInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$TableName
        )

        $myAnswer=[bool]$true
        $myCommand="
        DECLARE @myTableName nvarchar(255)
        SET @myTableName=N'"+ $TableName +"'
        
        IF NOT EXISTS (
            SELECT 
                1
            FROM 
                sys.all_objects AS myTable
                INNER JOIN sys.schemas AS mySchema ON myTable.schema_id=mySchema.schema_id
            WHERE 
                mySchema.name + '.' + myTable.name = REPLACE(REPLACE(@myTableName,'[',''),']','')
        ) BEGIN
            CREATE TABLE" + $TableName + "(
                [Id] [bigint] IDENTITY(1,1) NOT NULL,
                [Module] [nvarchar](255) NOT NULL,
                [EventTimeStamp] [datetime] NOT NULL,
                [Serverity] [nvarchar](50) NULL,
                [Description] [nvarchar](max) NULL,
                [InsertTime] [datetime] NOT NULL DEFAULT (getdate()),
                [IsSMS] [bit] NOT NULL DEFAULT (0),
                [IsSent] [bit] NOT NULL DEFAULT (0),
                PRIMARY KEY CLUSTERED ([Id] ASC) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 85, Data_Compression=Page) ON [PRIMARY]
            ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
        END
    "
    try{
        Invoke-Sqlcmd -ConnectionString $LogInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
    }Catch{
        Write-Log -Type ERR -Content ($_.ToString()).ToString()
        $myAnswer=[bool]$false
    }
    return $myAnswer
}
Function Write-Log {    #Fill Log file
    Param
        (
        [Parameter(Mandatory=$false)][string]$LogFilePath = $LogFilePath,
        [Parameter(Mandatory=$true)][string]$Content,
        [Parameter(Mandatory=$false)][ValidateSet("INF","WRN","ERR")][string]$Type="INF",
        [Switch]$Terminate=$false,
        [Switch]$LogToTable=$mySysEventsLogToTableFeature,  #$false
        [Parameter(Mandatory=$false)][string]$LogInstanceConnectionString = $LogInstanceConnectionString,
        [Parameter(Mandatory=$false)][string]$LogTableName = $LogTableName,
        [Parameter(Mandatory=$false)][string]$EventSource = $mySysSourceInstanceName
        )
    
    Switch ($Type) {
        "INF" {$myColor="White";$myIsSMS="0"}
        "WRN" {$myColor="Yellow";$myIsSMS="1";$mySysWrnCount+=1}
        "ERR" {$myColor="Red";$myIsSMS="1";$mySysErrCount+=1}
        Default {$myColor="White"}
    }
    $myEventTimeStamp=(Get-Date).ToString()
    $myContent = $myEventTimeStamp + "`t" + $Type + "`t(" + (Get-FunctionName -StackNumber 2) +")`t"+ $Content
    if ($Terminate) { $myContent+=$myContent + "`t" + ". Prcess terminated with " + $mySysErrCount.ToString() + " Error count and " + $mySysWrnCount.ToString() + " Warning count."}
    Write-Host $myContent -ForegroundColor $myColor
    Add-Content -Path $LogFilePath -Value $myContent
    if ($LogToTable) {
        $myCommand=
            "
            INSERT INTO "+ $LogTableName +" ([EventSource],[Module],[EventTimeStamp],[Serverity],[Description],[IsSMS])
            VALUES(N'"+$EventSource+"',N'DatabaseShipping',CAST('"+$myEventTimeStamp+"' AS DATETIME),N'"+$Type+"',N'"+$Content.Replace("'",'"')+"',"+$myIsSMS+")
            "
            Invoke-Sqlcmd -ConnectionString $LogInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Ignore
        }
    if ($Terminate){Exit}
}
Function Path.CorrectFolderPathFormat {    #Correcting folder path format
    Param
        (
        [Parameter(Mandatory=$false)][string]$FolderPath
        )
    $FolderPath=$FolderPath.Trim()
    if ($FolderPath.ToCharArray()[-1] -eq "\") {$FolderPath=$FolderPath.Substring(0,$FolderPath.Length)}    

    return $FolderPath
}
Function Path.IsWritable {    #Check writable path
    Param
        (
        [Parameter(Mandatory=$false)][string]$FolderPath
        )
    
    Write-Log -LogToTable:$myLogToTable -Type INF -Content "Processing Started."
    $myAnswer=$false
    $FolderPath=Path.CorrectFolderPathFormat -FolderPath $FolderPath
    if ((Test-Path -Path $FolderPath -PathType Container) -eq $true) {
        $myFilename=((New-Guid).ToString())+".lck"
        try {
            Add-Content -Path ($FolderPath+"\"+$myFilename) -Value $myContent
            if ((Test-Path -Path ($FolderPath+"\"+$myFilename) -PathType Leaf) -eq $true) {
                Remove-Item -Path ($FolderPath+"\"+$myFilename) -Force
                $myAnswer=$true
            }else{
                $myAnswer=$false
            }
        }Catch{
            Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
            $myAnswer=$false
        }
    }else{
        $myAnswer=$false
    }

    return $myAnswer
}
Function Path.ConvertLocalPathToUNC {    #Converting local path to UNC path
    Param
        (
        [Parameter(Mandatory=$false)][string]$Server,
        [Parameter(Mandatory=$false)][string]$Path
        )
    
    if ($Path.Contains('\\') -eq $false) {
        $myUncPath='\\' + $Server + "\" + ($Path.Split(':') -Join '$')
    }
    return $myUncPath
}
Function Path.ConvertLocalPathToSharedRepoPath {    #Converting local path to Shared Repository UNC path
    Param
        (
        [Parameter(Mandatory=$false)][string]$FileRepositoryUncPath,
        [Parameter(Mandatory=$false)][string]$Path
        )
    
        $myAnswer=$FileRepositoryUncPath + "\" + ($Path.Split('\')[-1])
    return $myAnswer
}
Function Instance.ConnectivityTest {  #Test Instance connectivity
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][string]$DatabaseName
        )

    Write-Log -LogToTable:$myLogToTable -Type INF -Content "Processing Started."
    $myCommand="
        USE [master];
        SELECT TOP 1 1 AS Result FROM [master].[sys].[databases] WHERE name = '" + $DatabaseName + "';
        "
    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    if ($null -ne $myRecord) {$myAnswer=[bool]$true} else {$myAnswer=[bool]$false}
    return $myAnswer
}
Function Database.GetDatabaseStatus {  #Check database status
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][string]$DatabaseName
        )

    Write-Log -LogToTable:$myLogToTable -Type INF -Content "Processing Started."
    $myCommand="
        USE [master];
        SELECT TOP 1 [myDatabase].[state] FROM [master].[sys].[databases] AS myDatabase WHERE [myDatabase].[name] = '" + $DatabaseName + "';
        "
    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    if ($null -ne $myRecord) {$myAnswer=$myRecord.state} else {$myAnswer=[DestinationDbStatus]::NotExist}
    return $myAnswer
}
Function Database.GetDatabaseLSN {  #Get database latest LSN
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][string]$DatabaseName
        )

    Write-Log -LogToTable:$myLogToTable -Type INF -Content "Processing Started."
    $myCommand="
        USE [master];
        SELECT TOP 1
            [myDatabaseLsn].[redo_start_lsn] AS LastLsn
        FROM 
            [master].[sys].[databases] AS myDatabase
            INNER JOIN [master].[sys].[master_files] AS myDatabaseLsn ON [myDatabase].[database_id]=[myDatabaseLsn].[database_id]
        WHERE 
            [myDatabase].[name] = '" + $DatabaseName + "'
            AND [myDatabase].[state] = 1    --Restoring state
            AND [myDatabaseLsn].[redo_start_lsn] IS NOT NULL
        "
    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    if ($null -ne $myRecord) {$myAnswer=$myRecord.LastLsn} else {$myAnswer=-1}
    return $myAnswer
}
Function Database.GetBackupFileList {    #Get List of backup files combination neede to restore
    Param (
        [parameter (Mandatory = $True)][string]$ConnectionString,
        [parameter (Mandatory = $True)][string]$DatabaseName,
        [parameter (Mandatory = $false)][Decimal]$LatestLSN=0
    )
    $myCommand = "
    DECLARE @myRecoveryDate AS NVARCHAR(50);
    DECLARE @myDBName AS NVARCHAR(255);    
    DECLARE @myLatestLsn NUMERIC(25, 0);
    DECLARE @myStartLsn NUMERIC(25, 0);

    SET @myRecoveryDate = getdate();
    SET @myDBName = N'"+ $DatabaseName + "';
    SET @myLatestLsn = "+ $LatestLSN.ToString() + ";

    CREATE TABLE #myResult
    (
        ID INT IDENTITY,
        DatabaseName sysname,
        FILEPATH NVARCHAR(255),
        Position INT,
        BackupStartTime DATETIME,
        BackupFinishTime DATETIME,
        FirstLsn NUMERIC(25, 0),
        LastLsn NUMERIC(25, 0),
        BackupType CHAR(1),
        MediaSetId INT
    );
    -------------------------------------------Full Backup
    INSERT INTO #myResult
    (DatabaseName, FILEPATH, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, BackupType, MediaSetId)
    SELECT TOP 1 WITH TIES
        [myDatabase].[name] AS DatabaseName,
        [myBackupFamily].[physical_device_name] AS myLogPath,
        [myBackupset].[position],
        [myBackupset].[backup_start_date],
        [myBackupset].[backup_finish_date],
        [myBackupset].[first_lsn],
        [myBackupset].[last_lsn],
        [myBackupset].[type],
        [myBackupset].[media_set_id]
    FROM
        [master].[sys].[databases] AS myDatabase WITH (READPAST)
		INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
        INNER JOIN [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST) ON [myBackupFamily].[media_set_id] = [myBackupset].[media_set_id]
    WHERE 
        [myBackupset].[is_copy_only] = 0
        AND [myBackupset].[type] = 'D'
        AND [myDatabase].[name] = @myDBName 
        AND [myBackupset].[first_lsn] >= @myLatestLsn
        AND @myRecoveryDate >= [myBackupset].[backup_start_date] 
		AND @myRecoveryDate >= [myBackupset].[backup_finish_date]
    ORDER BY 
        [myBackupset].[backup_start_date] DESC;
    -------------------------------------------Diff Backup
    SET @myStartLsn =
    (
        SELECT MAX(FirstLsn) AS myStartLsn FROM #myResult WHERE BackupType = 'D'
    );
    INSERT INTO #myResult
    (DatabaseName, FILEPATH, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, BackupType, MediaSetId)
    SELECT TOP 1 WITH TIES
        [myDatabase].[name] AS DatabaseName,
        [myBackupFamily].[physical_device_name] AS myLogPath,
        [myBackupset].[position],
        [myBackupset].[backup_start_date],
        [myBackupset].[backup_finish_date],
        [myBackupset].[first_lsn],
        [myBackupset].[last_lsn],
        [myBackupset].[type],
        [myBackupset].[media_set_id]
    FROM
        [master].[sys].[databases] AS myDatabase WITH (READPAST)
        INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
        INNER JOIN [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST) ON [myBackupFamily].[media_set_id] = [myBackupset].[media_set_id]
    WHERE 
        [myBackupset].[is_copy_only] = 0
        AND [myBackupset].[type] = 'I'
        AND [myDatabase].[name] = @myDBName
        AND [myBackupset].[backup_finish_date] <= @myRecoveryDate
        AND [myBackupset].[first_lsn] >= @myStartLsn
        AND [myBackupset].[first_lsn] >= ISNULL(@myLatestLsn,@myLatestLsn)
    ORDER BY 
        [myBackupset].[first_lsn] DESC;
    -------------------------------------------Log Backup
    SET @myStartLsn =
    (
        SELECT MAX(FirstLsn) AS myStartLsn
        FROM #myResult
        WHERE BackupType IN ( 'D', 'I' )
    );
    INSERT INTO #myResult
    (DatabaseName,FILEPATH, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, BackupType, MediaSetId)
    SELECT
        [myDatabase].[name] AS DatabaseName,
        [myBackupFamily].[physical_device_name] AS myLogPath,
        [myBackupset].[position],
        [myBackupset].[backup_start_date],
        [myBackupset].[backup_finish_date],
        [myBackupset].[first_lsn],
        [myBackupset].[last_lsn],
        [myBackupset].[type],
        [myBackupset].[media_set_id]
    FROM
        [master].[sys].[databases] AS myDatabase WITH (READPAST)
        INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
        INNER JOIN [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST) ON [myBackupFamily].[media_set_id] = [myBackupset].[media_set_id]
    WHERE 
        [myBackupset].[is_copy_only] = 0
        AND [myBackupset].[type] = 'L'
        AND [myDatabase].[name] = @myDBName
        AND [myBackupset].[backup_start_date] <= @myRecoveryDate
        AND [myBackupset].[first_lsn] >= @myLatestLsn
		AND (
            [myBackupset].[first_lsn] >= ISNULL(@myStartLsn,@myLatestLsn) 
            OR 
            ISNULL(@myStartLsn,@myLatestLsn) BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
            )
    ORDER BY 
        [myBackupset].[first_lsn] ASC;
  
    SELECT ID, DatabaseName, FILEPATH, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, BackupType, MediaSetId FROM #myResult ORDER BY ID;
    DROP TABLE #myResult;
    "
    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    return $myRecord
}
Function Database.GetServerName {  #Get database server netbios name
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString
        )

    Write-Log -LogToTable:$myLogToTable -Type INF -Content "Processing Started."
    $myCommand="
        SELECT @@SERVERNAME, CASE CHARINDEX('\',@@SERVERNAME) WHEN 0 THEN @@SERVERNAME ELSE SUBSTRING(@@SERVERNAME,0,CHARINDEX('\',@@SERVERNAME)) END AS ServerName
        "
    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    if ($null -ne $myRecord) {$myAnswer=$myRecord.ServerName} else {$myAnswer=$null}
    return $myAnswer
}
Function Database.DropDatabase {  #Drop database
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][string]$DatabaseName
        )

    Write-Log -LogToTable:$myLogToTable -Type INF -Content "Processing Started."
    $myCommand="
        USE [master];
        ALTER DATABASE [" + $DatabaseName + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE [" + $DatabaseName + "];
        SELECT 1 FROM [master].[sys].[databases] WHERE [name] = '" + $DatabaseName + "'
        "
    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    if ($null -ne $myRecord) {$myAnswer=$false} else {$myAnswer=$true}
    return $myAnswer
}
Function Database.GetDefaultDbFolderLocations {  #Get default location of data file and log file
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][ValidateSet("DATA","LOG")][string]$FileType
        )

    Write-Log -LogToTable:$myLogToTable -Type INF -Content "Processing Started."
    $myPropery=switch ($FileType) {
        "DATA"{"InstanceDefaultDataPath"}
        "LOG"{"InstanceDefaultLogPath"}
        Default {"InstanceDefaultDataPath"}
    }
    $myCommand="
        USE [master];
        SELECT SERVERPROPERTY('" + $myPropery + "') AS Path;
        "
    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    if ($null -ne $myRecord) {$myAnswer=$myRecord.Path} else {$myAnswer=$null}
    return $myAnswer
}
Function Database.RecoverDatabase {  #Recover database
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][string]$DatabaseName
        )

    Write-Log -LogToTable:$myLogToTable -Type INF -Content "Processing Started."
    $myCommand="
        USE [master];
        IF EXISTS(SELECT 1 FROM [master].[sys].[databases] WHERE [name] = '" + $DatabaseName + "' AND [state] = 1)  --Database is exists and in restore mode
            RESTORE DATABASE [" + $DatabaseName + "] WITH RECOVERY
        
        SELECT 1 FROM [master].[sys].[databases] WHERE [name] = '" + $DatabaseName + "' AND [state] <> 1
        "
    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    if ($null -ne $myRecord) {$myAnswer=$true} else {$myAnswer=$false}
    return $myAnswer
}
Function BackupFileList.MergeBackupFilePath {    #Merge RemoteRepositoryUncFilePath property of input array
    Param
        (
        [Parameter(Mandatory=$true)]$Items,
        [Parameter(Mandatory=$false)][string]$Delimiter=","

        )
    [string]$myAnswer=""
    foreach ($myItem in $Items) {
        $myAnswer+=($myItem.RemoteRepositoryUncFilePath+$Delimiter)
    }
    if ($myAnswer.Length -ge $Delimiter.Length) {$myAnswer=$myAnswer.Substring(0,$myAnswer.Length-$Delimiter.Length)}
    return $myAnswer
}
Function BackupFileList.GenerateDestinationDatabaseFilesLocationFromBackupFile {    #Generate Destination database file location from backup file list only
    Param
        (
        [Parameter(Mandatory=$true)][string]$ConnectionString,
        [Parameter(Mandatory=$true)][string]$DatabaseName,
        [Parameter(Mandatory=$true)][string]$MergedPaths,
        [Parameter(Mandatory=$true)][string]$PathDelimiter,
        [Parameter(Mandatory=$true)][string]$DefaultDestinationDataFolderLocation,
        [Parameter(Mandatory=$true)][string]$DefaultDestinationLogFolderLocation
        )
    
    [string]$myAnswer=""
    $myBakupFilePaths="DISK = '" + $MergedPaths.Replace($PathDelimiter,"', DISK ='") + "'"
    $myCommand = "RESTORE FILELISTONLY FROM " + $myBakupFilePaths + ";"

    try{
        $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
        if ($null -eq $myRecord) {
            Write-Log -Type ERR -Content ("Can not determine database files inside backup file(s) from file(s): " + $MergedPaths) -Terminate
        }
        foreach ($myDbFile in $myRecord) {
            [string]$myFolderLocation=""
            [string]$myFileName=""
            if ($myDbFile.Type -eq "L") {
                $myFolderLocation=$DefaultDestinationLogFolderLocation
            }else{
                $myFolderLocation=$DefaultDestinationDataFolderLocation
            }
            $myFileName=$myDbFile.PhysicalName.Split("\")[-1]
            $myRestoreLocation+="MOVE '" + ($myDbFile.LogicalName) + "' TO '" + $myFolderLocation + $DatabaseName + "_" + $myFileName +"',"
        }
        $myAnswer=$myRestoreLocation.Substring(0,$myRestoreLocation.Length-1)
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
    return $myAnswer
}
Function BackupFileList.GenerateRestoreBackupCommand {    #Generate Restore Command
    Param
        (
        [Parameter(Mandatory=$true)][string]$DatabaseName,
        [Parameter(Mandatory=$true)][string]$BackupType,
        [Parameter(Mandatory=$true)][int]$Position,
        [Parameter(Mandatory=$true)][string]$MergedPaths,
        [Parameter(Mandatory=$true)][string]$PathDelimiter,
        [Parameter(Mandatory=$true)][string]$RestoreLocation
        )
    
    [string]$myAnswer=""
    [string]$myRestoreLocation=""
    $myRestoreType=switch ($BackupType) {
         "D"{"RESTORE DATABASE"}
         "I"{"RESTORE DATABASE"}
         "L"{"RESTORE LOG"}
         Default {"RESTORE DATABASE"}
    }
    if ($BackupType -eq "D") {$myRestoreLocation = ", " + $RestoreLocation} else {$myRestoreLocation=""}
    $myBakupFilePaths="DISK = '" + $MergedPaths.Replace($PathDelimiter,"', DISK ='") + "'"
    $myAnswer = $myRestoreType + " [" + $DatabaseName + "] FROM " + $myBakupFilePaths + " WITH File = " + $Position.ToString() + $myRestoreLocation + ", NORECOVERY, STATS=5;"
    return $myAnswer
}
#---------------------------------------------------------MAIN BODY
#--=======================Constants
enum DestinationDbStatus {
    Unknown = -10
    NotExist = -9
    Exist = -8
    Online = 0
    Restoring = 1
    Recovering = 2
    RecoveryPending = 3
    Suspect = 4
    Emergency = 5
    Offline = 6
    Copying = 7
    OfflineSecondary = 10
}
$mySysEventsLogToTableFeature=[bool]$false
$mySysToday = (Get-Date -Format "yyyyMMdd").ToString()
$mySysTodayTime = (Get-Date -Format "yyyyMMdd_HHmm").ToString()
$LogFilePath=$LogFilePath.Replace("{Date}",$mySysToday)
$LogFilePath=$LogFilePath.Replace("{DateTime}",$mySysTodayTime)
$mySysErrCount=0
$mySysWrnCount=0
#--=======================Initial Log Modules
Write-Log -Type INF -Content "Restore started..."
Write-Log -Type INF -Content ("Initializing EventsTable.Create.")
if ($null -ne $LogInstanceConnectionString) {$mySysEventsLogToTableFeature=EventsTable.Create -LogInstanceConnectionString $LogInstanceConnectionString -TableName $LogTableName} else {$mySysEventsLogToTableFeature=[bool]$false}
if ($mySysEventsLogToTableFeature -eq $false)  {Write-Log -Type WRN -Content "Can not initialize a table to save program logs."}

#--=======================Validate input parameters
$FileRepositoryUncPath=Path.CorrectFolderPathFormat -FolderPath $FileRepositoryUncPath

#--=======================Check source connectivity
Write-Log -Type INF -Content ("Check Source Instance Connectivity of " + $SourceInstanceConnectionString)
if ((Instance.ConnectivityTest -ConnectionString $SourceInstanceConnectionString -DatabaseName $SourceDB) -eq $false) {
    Write-Log -Type ERR -Content ("Source Instance Connection failure.") -Terminate
} 

#--=======================Check destination connectivity
Write-Log -Type INF -Content ("Check Destination Instance Connectivity of " + $DestinationInstanceConnectionString)
if ((Instance.ConnectivityTest -ConnectionString $DestinationInstanceConnectionString -DatabaseName "master") -eq $false) {
    Write-Log -Type ERR -Content ("Destination Instance Connection failure.") -Terminate
} 

#--=======================Check destination db existance status
Write-Log -Type INF -Content ("Check Destination DB existance for " + $DestinationDB)
$myDestinationDbStatus=[DestinationDbStatus]::Unknown
$myDestinationDbStatus=[DestinationDbStatus](Database.GetDatabaseStatus -ConnectionString $DestinationInstanceConnectionString -DatabaseName $DestinationDB)
Write-Log -Type INF -Content ("Destination DB status is " + $myDestinationDbStatus)
If (($myDestinationDbStatus -eq [DestinationDbStatus]::Online) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::NotExist) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::Restoring)){
    Write-Log -Type INF -Content ("Destination DB status is " + $myDestinationDbStatus)
}else{
    Write-Log -Type ERR -Content ("Destination database status is not allowd for processing, Destination DB status is " + $myDestinationDbStatus) -Terminate
}

#--=======================Get DB Backup file combinations
If (($myDestinationDbStatus -eq [DestinationDbStatus]::Online) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::NotExist)){
    Write-Log -Type INF -Content ("Get DB Backup file combinations, for: " + $DestinationDB)
    $myLatestLSN=0
}elseif ($myDestinationDbStatus -eq [DestinationDbStatus]::Restoring) {
    Write-Log -Type INF -Content ("Get DB Backup file combinations, for: " + $DestinationDB)
    $myLatestLSN=Database.GetDatabaseLSN -ConnectionString $DestinationInstanceConnectionString -DatabaseName $DestinationDB
}
Write-Log -Type INF -Content ("Latest LSN is: " + $myLatestLSN.ToString())

$myBackupFileList=Database.GetBackupFileList -ConnectionString $SourceInstanceConnectionString -DatabaseName $SourceDB -LatestLSN $myLatestLSN
if ($null -eq $myBackupFileList) {
    Write-Log -Type WRN -Content ("There is nothing(no files) to restore.") -Terminate
}

#--=======================Copy DB Backup files to FileRepositoryPath
Write-Log -Type INF -Content ("Get Source instance server name.")
$mySourceServerName=Database.GetServerName -ConnectionString $SourceInstanceConnectionString
if ($null -eq $mySourceServerName) {
    Write-Log -Type ERR -Content ("Source server name is empty.") -Terminate
}

Write-Log -Type INF -Content ("Check Writeable FileRepositoryPath.")
if ((Path.IsWritable -FolderPath $FileRepositoryUncPath) -eq $false) {
    Write-Log -Type ERR -Content ("FileRepositoryPath is not accesible.") -Terminate
}

#--Add RemoteSourceFilePath attribute to object array
#Method1:   $myBackupFileList | ForEach-Object {$myRemoteSourceFilePath=Path.ConvertLocalPathToUNC -Server $mySourceServerName -Path ($_.FILEPATH); Copy-Item -Path $myRemoteSourceFilePath -Destination $FileRepositoryUncPath -Force; Write-Log -Type INF -Content ("File " + $myRemoteSourceFilePath + " copied to " + $FileRepositoryUncPath)}
#Method2:   $myBackupFileList | Select-Object FILEPATH, @{Label='RemoteSourceFilePath';Expression={Path.ConvertLocalPathToUNC -Server $mySourceServerName -Path ($_.FILEPATH)}} | ForEach-Object {Copy-Item -Path ($_.RemoteSourceFilePath) -Destination $FileRepositoryUncPath -Force; Write-Log -Type INF -Content ("File " + ($_.RemoteSourceFilePath) + " copied to " + $FileRepositoryUncPath)}
#Method3:
$myBackupFileList | Add-Member -MemberType ScriptProperty -Name RemoteSourceFilePath -Value {Path.ConvertLocalPathToUNC -Server $mySourceServerName -Path ($this.FILEPATH)}
$myBackupFileList | Add-Member -MemberType ScriptProperty -Name RemoteRepositoryUncFilePath -Value {Path.ConvertLocalPathToSharedRepoPath -FileRepositoryUncPath $FileRepositoryUncPath -Path ($this.FILEPATH)}
$myBackupFileList | ForEach-Object {Copy-Item -Path ($_.RemoteSourceFilePath) -Destination $FileRepositoryUncPath -Force -ErrorAction Stop; Write-Log -Type INF -Content ("File " + ($_.RemoteSourceFilePath) + " copied to " + $FileRepositoryUncPath)}

#--=======================Drop not in restoring mode databases
If ($myDestinationDbStatus -eq [DestinationDbStatus]::Online){
    Write-Log -Type INF -Content ("Drop Database : " + $DestinationDB)
    $myExistedDestinationDbDropped=Database.DropDatabase -ConnectionString $DestinationInstanceConnectionString -DatabaseName $DestinationDB
    if ($myExistedDestinationDbDropped -eq $false) {
        Write-Log -Type ERR -Content ("Could not drop destination database: " + $DestinationDB) -Terminate
    }
}

#--=======================Get destination file locations
Write-Log -Type INF -Content ("Get destination folder locations of: " + $DestinationInstanceConnectionString)
$myDefaultDestinationDataFolderLocation=Database.GetDefaultDbFolderLocations -ConnectionString $DestinationInstanceConnectionString -FileType DATA
$myDefaultDestinationLogFolderLocation=Database.GetDefaultDbFolderLocations -ConnectionString $DestinationInstanceConnectionString -FileType LOG
If ($null -eq $myDefaultDestinationDataFolderLocation){
    Write-Log -Type ERR -Content ("Default Data folder location is empty on: " + $DestinationInstanceConnectionString) -Terminate
}
If ($null -eq $myDefaultDestinationLogFolderLocation){
    Write-Log -Type ERR -Content ("Default Log folder location is empty on: " + $DestinationInstanceConnectionString) -Terminate
}
Write-Log -Type INF -Content ("Generate RestoreLocation")
$myDelimiter=","
if ($myBackupFileList.Count -eq 1) {
    $myMediasetId=$myBackupFileList.MediaSetId
}else{
    $myMediasetId=$myBackupFileList[0].MediaSetId
}
$myMediasetMergedPath=$myBackupFileList | Where-Object -Property MediaSetId -EQ $myMediasetId | Group-Object -Property MediaSetId,Position | ForEach-Object{BackupFileList.MergeBackupFilePath -Items ($_.Group) -Delimiter $myDelimiter}
$myRestoreLocation = BackupFileList.GenerateDestinationDatabaseFilesLocationFromBackupFile -ConnectionString $DestinationInstanceConnectionString -DatabaseName $DestinationDB -MergedPaths $myMediasetMergedPath -PathDelimiter $myDelimiter -DefaultDestinationDataFolderLocation $myDefaultDestinationDataFolderLocation -DefaultDestinationLogFolderLocation $myDefaultDestinationLogFolderLocation
if ($null -eq $myRestoreLocation -or $myRestoreLocation.Length -eq 0) {
    Write-Log -Type ERR -Content ("Can not get Restore location.") -Terminate
}else{
    Write-Log -Type INF -Content ("Restore Location is: " + $myRestoreLocation)
}

#--=======================Restoring backup(s) in destination
Write-Log -Type INF -Content ("Generate RestoreList")
$myDelimiter=","
$myRestoreList=$myBackupFileList | Group-Object -Property MediaSetId,Position | ForEach-Object{[PSCustomObject]@{
    MediaSetId=$_.Name.Split(",")[0]; 
    Order=($_.Group | Sort-Object ID | Select-Object -Last 1 -Property ID).ID;
    RestorCommand=$(BackupFileList.GenerateRestoreBackupCommand -DatabaseName $DestinationDB -BackupType (($_.Group | Select-Object -Last 1 -Property BackupType).BackupType) -Position ($_.Name.Split(",")[1]) -MergedPaths (BackupFileList.MergeBackupFilePath -Items ($_.Group) -Delimiter $myDelimiter) -PathDelimiter $myDelimiter -RestoreLocation $myRestoreLocation);
}}
Write-Log -Type INF -Content ("Run Restore Commands")
If ($null -ne $myRestoreList){
    try{
        $myRestoreList | ForEach-Object{Write-Log -Type INF -Content ("Restore Command:" + $_.RestorCommand);Invoke-Sqlcmd -ConnectionString $DestinationInstanceConnectionString -Query ($_.RestorCommand) -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Continue}
    }Catch{
        Write-Log -LogToTable:$myLogToTable -Type ERR -Content ($_.ToString()).ToString()
    }
}else{
    Write-Log -Type WRN -Content ("There is no commands to execute.")
}

#--=======================Remove copied files
Write-Log -Type INF -Content ("Remove copied files.")
$myBackupFileList | ForEach-Object{Remove-Item -Path ($_.RemoteRepositoryUncFilePath); Write-Log -Type INF -Content ("Remove file " + $_.RemoteRepositoryUncFilePath)}

#--=======================SetDestinationDBMode
Write-Log -Type INF -Content ("Set destination database mode to " + $SetDestinationDBToMode)
if ($SetDestinationDBToMode -eq "RECOVER") {
    $myRecoveryStatus=Database.RecoverDatabase -ConnectionString $DestinationInstanceConnectionString -DatabaseName $DestinationDB
    if ($myRecoveryStatus -eq $false) {
        Write-Log -Type INF -Content ("Database " + $DestinationDB + " does not exists or could not be recovered.")
    }
}

if ($mySysErrCount -eq 0 -and $mySysWrnCount -eq 0) {
    Write-Log -Type INF -Content "Finished."
}elseif ($mySysErrCount -eq 0 -and $mySysWrnCount -gt 0) {
    Write-Log -Type WRN -Content "Finished with " + $mySysWrnCount.ToString() + " Warning(s)."
}else{
    Write-Log -Type ERR -Content "Finished with " + $mySysErrCount.ToString() + " and " + $mySysWrnCount.ToString() + " Warning(s)."
}