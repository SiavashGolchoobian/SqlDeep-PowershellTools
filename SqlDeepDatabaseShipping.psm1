Using module .\SqlDeepLogWriter.psm1

enum DatabaseRecoveryMode {
    RESTOREONLY
    RECOVERY
}
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
enum RestoreStrategy {
    NotExist = 0
    FullDiffLog = 1
    FullLog = 2
    DiffLog = 3
    Log = 4
}
enum DatabaseFileType {
    DATA = 0
    LOG = 1
}
Class BackupFile {
    [int]$StrategyNo
    [int]$ID
    [string]$DatabaseName
    [int]$Position
    [datetime]$BackupStartTime
    [datetime]$BackupFinishTime
    [decimal]$FirstLsn
    [decimal]$LastLsn
    [string]$BackupType
    [int]$MediaSetId
    [string]$FilePath
    [string]$RemoteSourceFilePath
    [string]$RemoteRepositoryUncFilePath
    
    BackupFile([string]$SourceServerName,[string]$FileRepositoryUncPath,[int]$StrategyNo,[int]$ID,[string]$DatabaseName,[int]$Position,[datetime]$BackupStartTime,[datetime]$BackupFinishTime,[decimal]$FirstLsn,[decimal]$LastLsn,[string]$BackupType,[int]$MediaSetId,[string]$FilePath){
        $this.StrategyNo=$StrategyNo
        $this.ID=$ID
        $this.DatabaseName=$DatabaseName
        $this.Position=$Position
        $this.BackupStartTime=$BackupStartTime
        $this.BackupFinishTime=$BackupFinishTime
        $this.FirstLsn=$FirstLsn
        $this.LastLsn=$LastLsn
        $this.BackupType=$BackupType
        $this.MediaSetId=$MediaSetId
        $this.FilePath=$FilePath
        $this.RemoteSourceFilePath=$this.CalcRemoteSourceFilePath($SourceServerName)
        $this.RemoteRepositoryUncFilePath=$this.CalcRemoteRepositoryUncFilePath($FileRepositoryUncPath)
    }
    hidden [string]CalcRemoteSourceFilePath([string]$Server) {    #Converting local path to UNC path
        Write-Verbose "Processing Started."
        [string]$myAnswer=$null
        if ($this.FilePath.Contains('\\') -eq $false) {
            $myUncPath='\\' + $Server + "\" + ($this.FilePath.Split(':') -Join '$')
            $myAnswer=$myUncPath
        }else {
            $myAnswer=$this.FilePath
        }
        return $myAnswer
    }
    hidden [string]CalcRemoteRepositoryUncFilePath ([string]$FileRepositoryUncPath) {    #Converting local path to Shared Repository UNC path
        Write-Verbose "Processing Started."
        [string]$myAnswer=$null
        $myAnswer=$FileRepositoryUncPath + "\" + ($this.FilePath.Split('\')[-1])
        return $myAnswer
    }
}
Class DatabaseShipping {
    [string]$SourceInstanceConnectionString
    [string]$DestinationInstanceConnectionString
    [string]$FileRepositoryUncPath
    [int]$LimitMsdbScanToRecentDays=0
    [bool]$RestoreFilesToIndividualFolders=$true
    [DatabaseRecoveryMode]$DestinationRestoreMode=[DatabaseRecoveryMode]::RESTOREONLY
    [RestoreStrategy[]]$PreferredStrategies=[RestoreStrategy]::FullDiffLog,[RestoreStrategy]::FullLog,[RestoreStrategy]::DiffLog,[RestoreStrategy]::Log
    hidden [LogWriter]$LogWriter

    DatabaseShipping([string]$SourceInstanceConnectionString,[string]$DestinationInstanceConnectionString,[string]$FileRepositoryUncPath,[LogWriter]$LogWriter){
        $this.Init($SourceInstanceConnectionString,$DestinationInstanceConnectionString,$FileRepositoryUncPath,30,$true,[DatabaseRecoveryMode]::RESTOREONLY,$LogWriter)
    }
    DatabaseShipping([string]$SourceInstanceConnectionString,[string]$DestinationInstanceConnectionString,[string]$FileRepositoryUncPath,[int]$LimitMsdbScanToRecentDays,[bool]$RestoreFilesToIndividualFolders,[DatabaseRecoveryMode]$DestinationRestoreMode,[LogWriter]$LogWriter){
        $this.Init($SourceInstanceConnectionString,$DestinationInstanceConnectionString,$FileRepositoryUncPath,$LimitMsdbScanToRecentDays,$RestoreFilesToIndividualFolders,$DestinationRestoreMode,$LogWriter)
    }
    hidden Init([string]$SourceInstanceConnectionString,[string]$DestinationInstanceConnectionString,[string]$FileRepositoryUncPath,[int]$LimitMsdbScanToRecentDays,[bool]$RestoreFilesToIndividualFolders,[DatabaseRecoveryMode]$DestinationRestoreMode,[LogWriter]$LogWriter){
        $this.SourceInstanceConnectionString=$SourceInstanceConnectionString
        $this.DestinationInstanceConnectionString=$DestinationInstanceConnectionString
        $this.FileRepositoryUncPath=$this.Path_CorrectFolderPathFormat($FileRepositoryUncPath)
        $this.LimitMsdbScanToRecentDays=$LimitMsdbScanToRecentDays
        $this.RestoreFilesToIndividualFolders=$RestoreFilesToIndividualFolders
        $this.DestinationRestoreMode=$DestinationRestoreMode
        $this.LogWriter=$LogWriter
    }
#region Functions
    hidden [string]Path_CorrectFolderPathFormat ([string]$FolderPath) {    #Correcting folder path format
        if ($this.LogWriter) {
            $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        } else {
            Write-Verbose "Processing Started."
        }
        [string]$myAnswer=$null
        $FolderPath=$FolderPath.Trim()
        if ($FolderPath.ToCharArray()[-1] -eq "\") {$FolderPath=$FolderPath.Substring(0,$FolderPath.Length)}    
        $myAnswer=$FolderPath
        return $myAnswer
    }
    hidden [bool]Path_IsWritable ([string]$FolderPath) {    #Check writable path
        $this.LogWriter.Write("Processing Started.", [LogType]::INF) 
        [bool]$myAnswer=$false
        $FolderPath=$this.Path_CorrectFolderPathFormat($FolderPath)
        if ((Test-Path -Path $FolderPath -PathType Container) -eq $true) {
            $myFilename=((New-Guid).ToString())+".lck"
            try {
                Add-Content -Path ($FolderPath+"\"+$myFilename) -Value ""
                if ((Test-Path -Path ($FolderPath+"\"+$myFilename) -PathType Leaf) -eq $true) {
                    Remove-Item -Path ($FolderPath+"\"+$myFilename) -Force
                    $myAnswer=$true
                }else{
                    $myAnswer=$false
                }
            }Catch{
                $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR) 
                $myAnswer=$false
            }
        }else{
            $myAnswer=$false
        }

        return $myAnswer
    }
    hidden [bool]Instance_ConnectivityTest([string]$ConnectionString,[string]$DatabaseName) {  #Test Instance connectivity
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [bool]$myAnswer=$false
        [string]$myCommand="
            USE [master];
            SELECT TOP 1 1 AS Result FROM [master].[sys].[databases] WHERE name = '" + $DatabaseName + "';
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$true} else {$myAnswer=$false}
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [DestinationDbStatus]Database_GetDatabaseStatus([string]$ConnectionString,[string]$DatabaseName) {  #Check database status
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [DestinationDbStatus]$myAnswer=[DestinationDbStatus]::NotExist
        [string]$myCommand="
            USE [master];
            SELECT TOP 1 [myDatabase].[state] FROM [master].[sys].[databases] AS myDatabase WHERE [myDatabase].[name] = '" + $DatabaseName + "';
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$myRecord.state} else {$myAnswer=[DestinationDbStatus]::NotExist}
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [System.Object]Database_GetDatabaseLSN([string]$ConnectionString,[string]$DatabaseName) {  #Get database latest LSN
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [System.Object]$myAnswer=New-Object PsObject -Property @{LastLsn = [decimal]0; DiffBackupBaseLsn = [decimal]0;}
        [string]$myCommand="
            USE [master];
            SELECT TOP 1
                [myDatabaseLsn].[redo_start_lsn] AS LastLsn,
                [myDatabaseLsn].[differential_base_lsn] AS DiffBackupBaseLsn
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
            if ($null -ne $myRecord) {$myAnswer.LastLsn = [decimal]$myRecord.LastLsn; $myAnswer.DiffBackupBaseLsn = [decimal]$myRecord.DiffBackupBaseLsn}
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [string]Get_StrategiesToString([RestoreStrategy[]]$Strategies) {
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myAnswer=$null
        [string]$myAcceptedStrategies=""

        $Strategies | ForEach-Object{$myAcceptedStrategies+=($_.value__).ToString()+","}
        if ($myAcceptedStrategies[-1] -eq ",") {$myAcceptedStrategies=$myAcceptedStrategies.Substring(0,$myAcceptedStrategies.Length-1)}
        $myAnswer=$myAcceptedStrategies
        $this.LogWriter.Write(("Strategies are: " + $myAnswer), [LogType]::INF)

        return $myAnswer
    }
    hidden [BackupFile[]]Database_GetBackupFileList([string]$ConnectionString,[string]$DatabaseName,[Decimal]$LatestLSN,[Decimal]$DiffBackupBaseLsn) {    #Get List of backup files combination neede to restore
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [BackupFile[]]$myAnswer=$null

        $this.LogWriter.Write("Get Source instance server name.",[LogType]::INF)
        $mySourceServerName=$this.Database_GetServerName($ConnectionString)
        if ($null -eq $mySourceServerName) {
            $this.LogWriter.Write("Source server name is empty.",[LogType]::ERR)
            throw "Source server name is empty."
        }

        [string]$myAcceptedStrategies=""
        if ($LatestLSN -eq 0 -and $DiffBackupBaseLsn -eq 0){
            [RestoreStrategy[]]$Strategies=[RestoreStrategy]::FullDiffLog,[RestoreStrategy]::FullLog
            $myAcceptedStrategies=$this.Get_StrategiesToString($Strategies)
        }else{
            $myAcceptedStrategies=$this.Get_StrategiesToString($this.PreferredStrategies)
        }

        if ($null -eq $myAcceptedStrategies -or $myAcceptedStrategies.Trim().Length -eq 0) {
            $this.LogWriter.Write("PreferredStrategies is empty.",[LogType]::ERR)
            throw "PreferredStrategies is empty."
        }

        [string]$myCommand = "
        USE [tempdb];
        DECLARE @myDBName AS NVARCHAR(255);
        DECLARE @myLatestLsn NUMERIC(25,0);
        DECLARE @myDiffBackupBaseLsn NUMERIC(25,0);
        DECLARE @myRecoveryDate AS NVARCHAR(50);
        DECLARE @myLowerBoundOfFileScan DATETIME;
        DECLARE @myNumberOfDaysToScan INT;
        SET @myDBName=N'"+ $DatabaseName + "';
        SET @myLatestLsn="+ $LatestLSN.ToString() + ";
        SET @myDiffBackupBaseLsn="+ $DiffBackupBaseLsn.ToString() + ";
        SET @myNumberOfDaysToScan="+ $this.LimitMsdbScanToRecentDays.ToString() +";
        SET @myRecoveryDate = getdate();
        SET @myLowerBoundOfFileScan= CASE WHEN @myNumberOfDaysToScan=0 THEN CAST('1753-01-01' AS DATETIME) ELSE CAST(DATEADD(DAY,-1*ABS(@myNumberOfDaysToScan),GETDATE()) AS DATE) END
        -------------------------------------------Create required functions in tempdb
        IF NOT EXISTS (SELECT 1 FROM [tempdb].[sys].[all_objects] WHERE type='FN' AND name = 'fn_FileExists')
        BEGIN
            DECLARE @myStatement NVARCHAR(MAX);
            SET @myStatement = N'
                CREATE FUNCTION dbo.fn_FileExists(@path varchar(512))
                RETURNS BIT
                AS
                BEGIN
                        DECLARE @result INT
                        EXEC master.dbo.xp_fileexist @path, @result OUTPUT
                        RETURN cast(@result as bit)
                END
            ';
            EXEC sp_executesql @myStatement;
        END
        -------------------------------------------Extract Files with Grater than or equal LSN
        CREATE TABLE #myFileExistCache 
        (
            MediaSetId INT,
            IsFilesExists BIT DEFAULT(1),
            INDEX myFileExistCacheUNQ UNIQUE CLUSTERED (MediaSetId) WITH (IGNORE_DUP_KEY=ON)
        );
        CREATE TABLE #myResult
        (
            ID INT IDENTITY,
            DatabaseName sysname,
            Position INT,
            BackupStartTime DATETIME,
            BackupFinishTime DATETIME,
            FirstLsn NUMERIC(25, 0),
            LastLsn NUMERIC(25, 0),
            CheckpointLsn NUMERIC(25, 0),
            DatabaseBackupLsn NUMERIC(25, 0),
            BackupType CHAR(1),
            MediaSetId INT,
            BackupFileCount INT,
            BackupFileSizeMB BIGINT,
            StrategyNo Tinyint,
            IsContiguous BIT
        );
        CREATE TABLE #myRoadMaps
        (
            ID INT,
            DatabaseName sysname,
            Position INT,
            BackupStartTime DATETIME,
            BackupFinishTime DATETIME,
            FirstLsn NUMERIC(25, 0),
            LastLsn NUMERIC(25, 0),
            BackupType CHAR(1),
            MediaSetId INT,
            BackupFileCount INT,
            BackupFileSizeMB BIGINT,
            StrategyNo Tinyint,
            ParentID INT,
            [Level] INT,
            Cost REAL,
        );
        CREATE TABLE #mySolutions
        (
            RoamapID INT IDENTITY,
            LogID INT,
            DiffID INT,
            FullID INT,
            RoadmapStartTime DATETIME,
            RoadmapFinishTime DATETIME,
            RoadmapFirstLsn NUMERIC(25, 0),
            RoadmapLastLsn NUMERIC(25, 0),
            RoadmapSizeMB REAL,
            RoadmapFileCount INT,
            StrategyNo Tinyint
        );
        --========================================
        --========================================1st strategy: All latest existed full backup + latest existed and related incremental backup + all log backups after that incremental backup
        --========================================
        ----------------------Step1.1:	Extract all existed full backups
            TRUNCATE TABLE #myResult
            INSERT INTO #myResult (DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, CheckpointLsn, DatabaseBackupLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, IsContiguous)
            SELECT
                [myDatabase].[name] AS DatabaseName,
                [myBackupset].[position],
                [myBackupset].[backup_start_date],
                [myBackupset].[backup_finish_date],
                [myBackupset].[first_lsn],
                [myBackupset].[last_lsn],
                [myBackupset].[checkpoint_lsn],
                [myBackupset].[database_backup_lsn],
                [myBackupset].[type],
                [myBackupset].[media_set_id],
                [myMediaIsAvailable].[BackupFileCount],
                ISNULL([myBackupset].[compressed_backup_size],[myBackupset].[backup_size])/(1024*1024) AS BackupFileSizeMB,
                CAST(1 AS tinyint) AS StrategyNo,
                1 AS IsContiguous
            FROM
                [master].[sys].[databases] AS myDatabase WITH (READPAST)
                INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
                INNER JOIN (
                    SELECT
                        [myBackupFamily].[media_set_id],
                        Count(1) AS BackupFileCount,
                        CAST(MIN(CASE WHEN [tempdb].[dbo].[fn_FileExists]([myBackupFamily].[physical_device_name])=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'D'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND [myBackupset].[backup_start_date] >= @myLowerBoundOfFileScan
                AND 1 IN (" + $myAcceptedStrategies + ")
            
            INSERT INTO #myFileExistCache (MediaSetId, IsFilesExists) SELECT MediaSetId, 1 FROM #myResult   --Update Cache
        ----------------------Step1.2:	Extract latest existed and related incremental backups
        IF EXISTS (SELECT COUNT(1) FROM #myResult WHERE StrategyNo=1 AND BackupType='D')
        BEGIN
            INSERT INTO #myResult (DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, CheckpointLsn, DatabaseBackupLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, IsContiguous)
            SELECT
                [myDatabase].[name] AS DatabaseName,
                [myBackupset].[position],
                [myBackupset].[backup_start_date],
                [myBackupset].[backup_finish_date],
                [myBackupset].[first_lsn],
                [myBackupset].[last_lsn],
                [myBackupset].[checkpoint_lsn],
                [myBackupset].[database_backup_lsn],
                [myBackupset].[type],
                [myBackupset].[media_set_id],
                [myMediaIsAvailable].[BackupFileCount],
                ISNULL([myBackupset].[compressed_backup_size],[myBackupset].[backup_size])/(1024*1024) AS BackupFileSizeMB,
                CAST(1 AS tinyint) AS StrategyNo,
                1 AS IsContiguous
            FROM
                [master].[sys].[databases] AS myDatabase WITH (READPAST)
                INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
                INNER JOIN #myResult AS myFullBackupsList ON [myFullBackupsList].[CheckpointLsn]=[myBackupset].[database_backup_lsn] AND [myFullBackupsList].[StrategyNo]=1
                INNER JOIN (
                    SELECT
                        [myBackupFamily].[media_set_id],
                        Count(1) AS BackupFileCount,
                        CAST(MIN(CASE WHEN [tempdb].[dbo].[fn_FileExists]([myBackupFamily].[physical_device_name])=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'I'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND 1 IN (" + $myAcceptedStrategies + ")

            INSERT INTO #myFileExistCache (MediaSetId, IsFilesExists) SELECT MediaSetId, 1 FROM #myResult   --Update Cache
            DELETE FROM #myResult WHERE StrategyNo=1 AND BackupType='D' AND CheckpointLsn NOT IN (SELECT DatabaseBackupLsn FROM #myResult WHERE StrategyNo=1 AND BackupType='I' GROUP BY DatabaseBackupLsn)	--Delete full backups without any available incremental backups
            IF NOT EXISTS (SELECT 1 FROM #myResult WHERE StrategyNo=1 AND BackupType IN ('D'))
                DELETE FROM #myResult WHERE StrategyNo=1
        END
        ELSE
            DELETE FROM #myResult WHERE StrategyNo=1
        ----------------------Step1.3:	Extract all log backups after that incremental backup
        IF EXISTS (SELECT COUNT(1) FROM #myResult WHERE StrategyNo=1)
        BEGIN
            INSERT INTO #myResult (DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, CheckpointLsn, DatabaseBackupLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, IsContiguous)
            SELECT
                [myDatabase].[name] AS DatabaseName,
                [myBackupset].[position],
                [myBackupset].[backup_start_date],
                [myBackupset].[backup_finish_date],
                [myBackupset].[first_lsn],
                [myBackupset].[last_lsn],
                [myBackupset].[checkpoint_lsn],
                [myBackupset].[database_backup_lsn],
                [myBackupset].[type],
                [myBackupset].[media_set_id],
                [myMediaIsAvailable].[BackupFileCount],
                ISNULL([myBackupset].[compressed_backup_size],[myBackupset].[backup_size])/(1024*1024) AS BackupFileSizeMB,
                CAST(1 AS tinyint) AS StrategyNo,
                CASE WHEN LAG([myBackupset].[last_lsn],1,0) OVER (Order by [myBackupset].[first_lsn]) = [myBackupset].[first_lsn] THEN 1 ELSE 0 END AS IsContiguous
            FROM
                [master].[sys].[databases] AS myDatabase WITH (READPAST)
                INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
                INNER JOIN (
                    SELECT
                        [myBackupFamily].[media_set_id],
                        Count(1) AS BackupFileCount,
                        CAST(MIN(CASE WHEN [tempdb].[dbo].[fn_FileExists]([myBackupFamily].[physical_device_name])=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'L'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND	(
                    [myBackupset].[first_lsn] >= (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=1)
                    OR
                    (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=1) BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
                    )
                AND 1 IN (" + $myAcceptedStrategies + ")
            
            INSERT INTO #myFileExistCache (MediaSetId, IsFilesExists) SELECT MediaSetId, 1 FROM #myResult   --Update Cache
            UPDATE #myResult SET IsContiguous=1 WHERE StrategyNo=1 AND BackupType='L' AND ID = (SELECT MIN(ID) FROM #myResult WHERE StrategyNo=1 AND BackupType='L')	    --First log file is not uncontiguous
            DELETE FROM #myResult WHERE StrategyNo=1 AND BackupType='L' AND ID <= (SELECT MAX(ID) FROM #myResult WHERE StrategyNo=1 AND BackupType='L' AND IsContiguous=0)	--Delete log backups without continious chain
            DELETE FROM #myResult WHERE StrategyNo=1 AND BackupType='I' AND LastLsn < (SELECT MIN(FirstLsn) FROM #myResult WHERE StrategyNo=1 AND BackupType='L')	--Delete differential backups without continious log backup chain
            DELETE FROM #myResult WHERE StrategyNo=1 AND BackupType='D' AND CheckpointLsn NOT IN (SELECT DatabaseBackupLsn FROM #myResult WHERE StrategyNo=1 AND BackupType='I' GROUP BY DatabaseBackupLsn)	--Delete full backups without any available incremental backups
            IF NOT EXISTS (SELECT 1 FROM #myResult WHERE StrategyNo=1 AND BackupType IN ('D','I'))
                DELETE FROM #myResult WHERE StrategyNo=1
        END
        ELSE
            DELETE FROM #myResult WHERE StrategyNo=1
        ----------------------Step1.4:	Generate Roadmaps
        IF EXISTS (SELECT COUNT(1) FROM #myResult WHERE StrategyNo=1)
        BEGIN
            ;With myStrategy1 AS (
                SELECT	--FullBackups
                    [myFullBackups].*,
                    CAST(NULL AS INT) AS [ParentID],
                    CAST(1 AS INT) AS [Level],
                    CAST([myFullBackups].[BackupFileSizeMB] AS REAL) AS Cost
                FROM 
                    #myResult AS myFullBackups
                WHERE 
                    [myFullBackups].[StrategyNo]=1 AND [myFullBackups].[BackupType]='D'
                UNION ALL
                SELECT	--DiffBackups
                    [myDiffBackups].*,
                    CAST([myFullBackups].[ID] AS INT) AS [ParentID],
                    [myFullBackups].[Level]+1 AS [Level],
                    [myFullBackups].[Cost]+CAST([myDiffBackups].[BackupFileSizeMB] AS REAL) AS Cost
                FROM 
                    myStrategy1 AS myFullBackups
                    INNER JOIN #myResult AS myDiffBackups ON [myFullBackups].[CheckpointLsn]=[myDiffBackups].[DatabaseBackupLsn]
                WHERE 
                    [myFullBackups].[StrategyNo]=1 AND [myFullBackups].[BackupType]='D'
                    AND [myDiffBackups].[StrategyNo]=1 AND [myDiffBackups].[BackupType]='I'
                UNION ALL
                SELECT	--LogBackups
                    [myLogBackups].*,
                    CAST([myDiffBackups].[ID] AS INT) AS [ParentID],
                    [myDiffBackups].[Level]+1 AS [Level],
                    [myDiffBackups].[Cost]+CAST([myLogBackups].[BackupFileSizeMB] AS REAL) AS Cost
                FROM 
                    myStrategy1 AS myDiffBackups
                    INNER JOIN #myResult AS myLogBackups ON [myLogBackups].[FirstLsn] >= [myDiffBackups].[FirstLsn] OR [myDiffBackups].[FirstLsn] BETWEEN [myLogBackups].[FirstLsn] AND [myLogBackups].[LastLsn] 
                WHERE 
                    [myDiffBackups].[StrategyNo]=1 AND [myDiffBackups].[BackupType]='I'
                    AND [myLogBackups].[StrategyNo]=1 AND [myLogBackups].[BackupType]='L'
                )
        
            INSERT INTO #myRoadMaps (ID, DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, ParentID, [Level], Cost)
            SELECT ID,DatabaseName,Position,BackupStartTime,BackupFinishTime,FirstLsn,LastLsn,BackupType,MediaSetId,BackupFileCount,BackupFileSizeMB,StrategyNo,ParentID,[Level],Cost FROM myStrategy1 ORDER BY [Level],[ParentID],[ID]
        
            INSERT INTO #mySolutions (LogID, DiffID, FullID, RoadmapStartTime, RoadmapFinishTime, RoadmapFirstLsn, RoadmapLastLsn, RoadmapSizeMB, RoadmapFileCount, StrategyNo)
            SELECT 
                [myLog].[ID] AS LogID,
                [myDiff].[ID] AS DiffID,
                [myFull].[ID] AS FullID,
                [myFull].[BackupStartTime],
                [myLog].[BackupFinishTime],
                [myFull].[FirstLsn],
                [myLog].[LastLsn],
                [myLog].[Cost],
                [myDiff].[BackupFileCount] + [myFull].[BackupFileCount],
                [myLog].[StrategyNo]
            FROM 
                #myRoadMaps AS myLog
                INNER JOIN #myRoadMaps AS myDiff ON [myLog].[ParentID]=[myDiff].[ID] AND [myDiff].[StrategyNo]=1 AND [myDiff].[BackupType]='I'
                INNER JOIN #myRoadMaps AS myFull ON [myDiff].[ParentID]=[myFull].[ID] AND [myFull].[StrategyNo]=1 AND [myFull].[BackupType]='D'
            WHERE 
                [myLog].[BackupType]='L'
                AND [myLog].[StrategyNo]=1
                AND [myLog].[ID]=(SELECT MAX(ID) FROM #myRoadMaps WHERE [StrategyNo]=1 AND [BackupType]='L')
            UPDATE mySolutions SET RoadmapFileCount=[mySolutions].[RoadmapFileCount]+[myLogFileStats].[LogFileCount] FROM #mySolutions AS mySolutions INNER JOIN (SELECT [ParentID] AS DiffID, SUM([BackupFileCount]) AS LogFileCount FROM #myRoadMaps WHERE BackupType='L' AND StrategyNo=1 GROUP BY [ParentID]) AS myLogFileStats ON [mySolutions].[DiffID]=[myLogFileStats].[DiffID] WHERE [mySolutions].[StrategyNo]=1
        END
        ELSE
            DELETE FROM #myResult WHERE StrategyNo=1
        --========================================
        --========================================2nd strategy: All latest existed full backup + all corresponding log backups after that full backup
        --========================================
        ----------------------Step2.1:	Extract all existed full backups
            TRUNCATE TABLE #myResult
            INSERT INTO #myResult (DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, CheckpointLsn, DatabaseBackupLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, IsContiguous)
            SELECT
                [myDatabase].[name] AS DatabaseName,
                [myBackupset].[position],
                [myBackupset].[backup_start_date],
                [myBackupset].[backup_finish_date],
                [myBackupset].[first_lsn],
                [myBackupset].[last_lsn],
                [myBackupset].[checkpoint_lsn],
                [myBackupset].[database_backup_lsn],
                [myBackupset].[type],
                [myBackupset].[media_set_id],
                [myMediaIsAvailable].[BackupFileCount],
                ISNULL([myBackupset].[compressed_backup_size],[myBackupset].[backup_size])/(1024*1024) AS BackupFileSizeMB,
                CAST(2 AS tinyint) AS StrategyNo,
                1 AS IsContiguous
            FROM
                [master].[sys].[databases] AS myDatabase WITH (READPAST)
                INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
                INNER JOIN (
                    SELECT
                        [myBackupFamily].[media_set_id],
                        Count(1) AS BackupFileCount,
                        CAST(MIN(CASE WHEN ISNULL([myCache].[IsFilesExists],[tempdb].[dbo].[fn_FileExists]([myBackupFamily].[physical_device_name]))=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'D'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND [myBackupset].[backup_start_date] >= @myLowerBoundOfFileScan
                AND 2 IN (" + $myAcceptedStrategies + ")
            
            INSERT INTO #myFileExistCache (MediaSetId, IsFilesExists) SELECT MediaSetId, 1 FROM #myResult   --Update Cache
        ----------------------Step2.2:	Extract all log backups after that full backup
        IF EXISTS (SELECT COUNT(1) FROM #myResult WHERE StrategyNo=2)
        BEGIN
            INSERT INTO #myResult (DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, CheckpointLsn, DatabaseBackupLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, IsContiguous)
            SELECT
                [myDatabase].[name] AS DatabaseName,
                [myBackupset].[position],
                [myBackupset].[backup_start_date],
                [myBackupset].[backup_finish_date],
                [myBackupset].[first_lsn],
                [myBackupset].[last_lsn],
                [myBackupset].[checkpoint_lsn],
                [myBackupset].[database_backup_lsn],
                [myBackupset].[type],
                [myBackupset].[media_set_id],
                [myMediaIsAvailable].[BackupFileCount],
                ISNULL([myBackupset].[compressed_backup_size],[myBackupset].[backup_size])/(1024*1024) AS BackupFileSizeMB,
                CAST(2 AS tinyint) AS StrategyNo,
                CASE WHEN LAG([myBackupset].[last_lsn],1,0) OVER (Order by [myBackupset].[first_lsn]) = [myBackupset].[first_lsn] THEN 1 ELSE 0 END AS IsContiguous
            FROM
                [master].[sys].[databases] AS myDatabase WITH (READPAST)
                INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
                INNER JOIN (
                    SELECT
                        [myBackupFamily].[media_set_id],
                        Count(1) AS BackupFileCount,
                        CAST(MIN(CASE WHEN ISNULL([myCache].[IsFilesExists],[tempdb].[dbo].[fn_FileExists]([myBackupFamily].[physical_device_name]))=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'L'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND	(
                    [myBackupset].[first_lsn] >= (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=2)
                    OR
                    (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=2) BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
                    )
                AND 2 IN (" + $myAcceptedStrategies + ")
            
            INSERT INTO #myFileExistCache (MediaSetId, IsFilesExists) SELECT MediaSetId, 1 FROM #myResult   --Update Cache
            UPDATE #myResult SET IsContiguous=1 WHERE StrategyNo=2 AND BackupType='L' AND ID = (SELECT MIN(ID) FROM #myResult WHERE StrategyNo=2 AND BackupType='L')	    --First log file is not uncontiguous
            DELETE FROM #myResult WHERE StrategyNo=2 AND BackupType='L' AND ID <= (SELECT MAX(ID) FROM #myResult WHERE StrategyNo=2 AND BackupType='L' AND IsContiguous=0)	--Delete log backups without continious chain
            DELETE FROM #myResult WHERE StrategyNo=2 AND BackupType='D' AND LastLsn < (SELECT MIN(FirstLsn) FROM #myResult WHERE StrategyNo=2 AND BackupType='L')	--Delete full backups without continious log backup chain
            IF NOT EXISTS (SELECT 1 FROM #myResult WHERE StrategyNo=2 AND BackupType IN ('D'))
                DELETE FROM #myResult WHERE StrategyNo=2
        END
        ELSE
            DELETE FROM #myResult WHERE StrategyNo=2
        ----------------------Step2.3:	Generate Roadmaps
        IF EXISTS (SELECT COUNT(1) FROM #myResult WHERE StrategyNo=2)
        BEGIN
            ;With myStrategy2 AS (
                SELECT	--FullBackups
                    [myFullBackups].*,
                    CAST(NULL AS INT) AS [ParentID],
                    CAST(1 AS INT) AS [Level],
                    CAST([myFullBackups].[BackupFileSizeMB] AS REAL) AS Cost
                FROM 
                    #myResult AS myFullBackups
                WHERE 
                    [myFullBackups].[StrategyNo]=2 AND [myFullBackups].[BackupType]='D'
                UNION ALL
                SELECT	--LogBackups
                    [myLogBackups].*,
                    CAST([myFullBackups].[ID] AS INT) AS [ParentID],
                    [myFullBackups].[Level]+1 AS [Level],
                    [myFullBackups].[Cost]+CAST([myLogBackups].[BackupFileSizeMB] AS REAL) AS Cost
                FROM 
                    myStrategy2 AS myFullBackups
                    INNER JOIN #myResult AS myLogBackups ON [myLogBackups].[FirstLsn] >= [myFullBackups].[FirstLsn] OR [myFullBackups].[FirstLsn] BETWEEN [myLogBackups].[FirstLsn] AND [myLogBackups].[LastLsn] 
                WHERE 
                    [myFullBackups].[StrategyNo]=2 AND [myFullBackups].[BackupType]='D'
                    AND [myFullBackups].[StrategyNo]=2 AND [myLogBackups].[BackupType]='L'
                )
        
            INSERT INTO #myRoadMaps (ID, DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, ParentID, [Level], Cost)
            SELECT ID,DatabaseName,Position,BackupStartTime,BackupFinishTime,FirstLsn,LastLsn,BackupType,MediaSetId,BackupFileCount,BackupFileSizeMB,StrategyNo,ParentID,[Level],Cost FROM myStrategy2 ORDER BY [Level],[ParentID],[ID]
        
            INSERT INTO #mySolutions (LogID, DiffID, FullID, RoadmapStartTime, RoadmapFinishTime, RoadmapFirstLsn, RoadmapLastLsn, RoadmapSizeMB, RoadmapFileCount, StrategyNo)
            SELECT 
                [myLog].[ID] AS LogID,
                NULL AS DiffID,
                [myFull].[ID] AS FullID,
                [myFull].[BackupStartTime],
                [myLog].[BackupFinishTime],
                [myFull].[FirstLsn],
                [myLog].[LastLsn],
                [myLog].[Cost],
                [myFull].[BackupFileCount],
                [myLog].[StrategyNo]
            FROM 
                #myRoadMaps AS myLog
                INNER JOIN #myRoadMaps AS myFull ON [myLog].[ParentID]=[myFull].[ID] AND [myFull].[StrategyNo]=2 AND [myFull].[BackupType]='D'
            WHERE 
                [myLog].[BackupType]='L'
                AND [myLog].[StrategyNo]=2
                AND [myLog].[ID]=(SELECT MAX(ID) FROM #myRoadMaps WHERE [StrategyNo]=2 AND [BackupType]='L')
            UPDATE mySolutions SET RoadmapFileCount=[mySolutions].[RoadmapFileCount]+[myLogFileStats].[LogFileCount] FROM #mySolutions AS mySolutions INNER JOIN (SELECT [ParentID] AS FullID, SUM([BackupFileCount]) AS LogFileCount FROM #myRoadMaps WHERE BackupType='L' AND StrategyNo=2 GROUP BY [ParentID]) AS myLogFileStats ON [mySolutions].[FullID]=[myLogFileStats].[FullID] WHERE [mySolutions].[StrategyNo]=2
        END
        ELSE
            DELETE FROM #myResult WHERE StrategyNo=2
        --========================================
        --========================================3rd strategy: Latest existed and related incremental backup + all corresponding log backups after that incremental backup
        --========================================
        ----------------------Step3.1:	Extract latest existed and related incremental backups
            TRUNCATE TABLE #myResult
            INSERT INTO #myResult (DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, CheckpointLsn, DatabaseBackupLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, IsContiguous)
            SELECT
                [myDatabase].[name] AS DatabaseName,
                [myBackupset].[position],
                [myBackupset].[backup_start_date],
                [myBackupset].[backup_finish_date],
                [myBackupset].[first_lsn],
                [myBackupset].[last_lsn],
                [myBackupset].[checkpoint_lsn],
                [myBackupset].[database_backup_lsn],
                [myBackupset].[type],
                [myBackupset].[media_set_id],
                [myMediaIsAvailable].[BackupFileCount],
                ISNULL([myBackupset].[compressed_backup_size],[myBackupset].[backup_size])/(1024*1024) AS BackupFileSizeMB,
                CAST(3 AS tinyint) AS StrategyNo,
                1 AS IsContiguous
            FROM
                [master].[sys].[databases] AS myDatabase WITH (READPAST)
                INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
                INNER JOIN (
                    SELECT
                        [myBackupFamily].[media_set_id],
                        Count(1) AS BackupFileCount,
                        CAST(MIN(CASE WHEN ISNULL([myCache].[IsFilesExists],[tempdb].[dbo].[fn_FileExists]([myBackupFamily].[physical_device_name]))=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'I'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND [myBackupset].[database_backup_lsn]=@myDiffBackupBaseLsn
                AND CASE WHEN @myDiffBackupBaseLsn = 0 THEN @myLowerBoundOfFileScan ELSE [myBackupset].[backup_start_date] END >= @myLowerBoundOfFileScan
                AND 3 IN (" + $myAcceptedStrategies + ")
            
            INSERT INTO #myFileExistCache (MediaSetId, IsFilesExists) SELECT MediaSetId, 1 FROM #myResult   --Update Cache
        ----------------------Step3.2:	Extract all log backups after that incremental backup
        IF EXISTS (SELECT COUNT(1) FROM #myResult WHERE StrategyNo=3)
        BEGIN
            INSERT INTO #myResult (DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, CheckpointLsn, DatabaseBackupLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, IsContiguous)
            SELECT
                [myDatabase].[name] AS DatabaseName,
                [myBackupset].[position],
                [myBackupset].[backup_start_date],
                [myBackupset].[backup_finish_date],
                [myBackupset].[first_lsn],
                [myBackupset].[last_lsn],
                [myBackupset].[checkpoint_lsn],
                [myBackupset].[database_backup_lsn],
                [myBackupset].[type],
                [myBackupset].[media_set_id],
                [myMediaIsAvailable].[BackupFileCount],
                ISNULL([myBackupset].[compressed_backup_size],[myBackupset].[backup_size])/(1024*1024) AS BackupFileSizeMB,
                CAST(3 AS tinyint) AS StrategyNo,
                CASE WHEN LAG([myBackupset].[last_lsn],1,0) OVER (Order by [myBackupset].[first_lsn]) = [myBackupset].[first_lsn] THEN 1 ELSE 0 END AS IsContiguous
            FROM
                [master].[sys].[databases] AS myDatabase WITH (READPAST)
                INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
                INNER JOIN (
                    SELECT
                        [myBackupFamily].[media_set_id],
                        Count(1) AS BackupFileCount,
                        CAST(MIN(CASE WHEN ISNULL([myCache].[IsFilesExists],[tempdb].[dbo].[fn_FileExists]([myBackupFamily].[physical_device_name]))=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'L'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND	(
                    [myBackupset].[first_lsn] >= (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=3)
                    OR
                    (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=3) BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
                    )
                AND 3 IN (" + $myAcceptedStrategies + ")
            
            INSERT INTO #myFileExistCache (MediaSetId, IsFilesExists) SELECT MediaSetId, 1 FROM #myResult   --Update Cache
            UPDATE #myResult SET IsContiguous=3 WHERE StrategyNo=1 AND BackupType='L' AND ID = (SELECT MIN(ID) FROM #myResult WHERE StrategyNo=3 AND BackupType='L')	    --First log file is not uncontiguous
            DELETE FROM #myResult WHERE StrategyNo=3 AND BackupType='L' AND ID <= (SELECT MAX(ID) FROM #myResult WHERE StrategyNo=3 AND BackupType='L' AND IsContiguous=0)	--Delete log backups without continious chain
            DELETE FROM #myResult WHERE StrategyNo=3 AND BackupType='I' AND LastLsn < (SELECT MIN(FirstLsn) FROM #myResult WHERE StrategyNo=3 AND BackupType='L')	--Delete differential backups without continious log backup chain
            IF NOT EXISTS (SELECT 1 FROM #myResult WHERE StrategyNo=3 AND BackupType IN ('I'))
                DELETE FROM #myResult WHERE StrategyNo=3
        END
        ELSE
            DELETE FROM #myResult WHERE StrategyNo=3
        ----------------------Step3.3:	Generate Roadmaps
        IF EXISTS (SELECT COUNT(1) FROM #myResult WHERE StrategyNo=3)
        BEGIN
            ;With myStrategy3 AS (
                SELECT	--DiffBackups
                    [myDiffBackups].*,
                    CAST(NULL AS INT) AS [ParentID],
                    CAST(1 AS INT) AS [Level],
                    CAST([myDiffBackups].[BackupFileSizeMB] AS REAL) AS Cost
                FROM 
                    #myResult AS myDiffBackups
                WHERE 
                    [myDiffBackups].[StrategyNo]=3 AND [myDiffBackups].[BackupType]='I'
                UNION ALL
                SELECT	--LogBackups
                    [myLogBackups].*,
                    CAST([myDiffBackups].[ID] AS INT) AS [ParentID],
                    [myDiffBackups].[Level]+1 AS [Level],
                    [myDiffBackups].[Cost]+CAST([myLogBackups].[BackupFileSizeMB] AS REAL) AS Cost
                FROM 
                    myStrategy3 AS myDiffBackups
                    INNER JOIN #myResult AS myLogBackups ON [myLogBackups].[FirstLsn] >= [myDiffBackups].[FirstLsn] OR [myDiffBackups].[FirstLsn] BETWEEN [myLogBackups].[FirstLsn] AND [myLogBackups].[LastLsn] 
                WHERE 
                    [myDiffBackups].[StrategyNo]=3 AND [myDiffBackups].[BackupType]='I'
                    AND [myLogBackups].[StrategyNo]=3 AND [myLogBackups].[BackupType]='L'
                )
        
            INSERT INTO #myRoadMaps (ID, DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, ParentID, [Level], Cost)
            SELECT ID,DatabaseName,Position,BackupStartTime,BackupFinishTime,FirstLsn,LastLsn,BackupType,MediaSetId,BackupFileCount,BackupFileSizeMB,StrategyNo,ParentID,[Level],Cost FROM myStrategy3 ORDER BY [Level],[ParentID],[ID]
        
            INSERT INTO #mySolutions (LogID, DiffID, FullID, RoadmapStartTime, RoadmapFinishTime, RoadmapFirstLsn, RoadmapLastLsn, RoadmapSizeMB, RoadmapFileCount, StrategyNo)
            SELECT 
                [myLog].[ID] AS LogID,
                [myDiff].[ID] AS DiffID,
                NULL AS FullID,
                [myDiff].[BackupStartTime],
                [myLog].[BackupFinishTime],
                [myDiff].[FirstLsn],
                [myLog].[LastLsn],
                [myLog].[Cost],
                [myDiff].[BackupFileCount],
                [myLog].[StrategyNo]
            FROM 
                #myRoadMaps AS myLog
                INNER JOIN #myRoadMaps AS myDiff ON [myLog].[ParentID]=[myDiff].[ID] AND [myDiff].[StrategyNo]=3 AND [myDiff].[BackupType]='I'
            WHERE 
                [myLog].[BackupType]='L'
                AND [myLog].[StrategyNo]=3
                AND [myLog].[ID]=(SELECT MAX(ID) FROM #myRoadMaps WHERE [StrategyNo]=3 AND [BackupType]='L')
            UPDATE mySolutions SET RoadmapFileCount=[mySolutions].[RoadmapFileCount]+[myLogFileStats].[LogFileCount] FROM #mySolutions AS mySolutions INNER JOIN (SELECT [ParentID] AS DiffID, SUM([BackupFileCount]) AS LogFileCount FROM #myRoadMaps WHERE BackupType='L' AND StrategyNo=3 GROUP BY [ParentID]) AS myLogFileStats ON [mySolutions].[DiffID]=[myLogFileStats].[DiffID] WHERE [mySolutions].[StrategyNo]=3
            DELETE FROM #mySolutions WHERE StrategyNo=3 AND @myDiffBackupBaseLsn NOT BETWEEN RoadmapFirstLsn AND RoadmapLastLsn	--Delete outdated LSN solutions
        END
        ELSE
            DELETE FROM #myResult WHERE StrategyNo=3
        --========================================
        --========================================4th strategy: All log backups after announced LSN
        --========================================
        ----------------------Step4.1:	Extract all log backups after specified LatestLSN
            TRUNCATE TABLE #myResult
            INSERT INTO #myResult (DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, CheckpointLsn, DatabaseBackupLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, IsContiguous)
            SELECT
                [myDatabase].[name] AS DatabaseName,
                [myBackupset].[position],
                [myBackupset].[backup_start_date],
                [myBackupset].[backup_finish_date],
                [myBackupset].[first_lsn],
                [myBackupset].[last_lsn],
                [myBackupset].[checkpoint_lsn],
                [myBackupset].[database_backup_lsn],
                [myBackupset].[type],
                [myBackupset].[media_set_id],
                [myMediaIsAvailable].[BackupFileCount],
                ISNULL([myBackupset].[compressed_backup_size],[myBackupset].[backup_size])/(1024*1024) AS BackupFileSizeMB,
                CAST(4 AS tinyint) AS StrategyNo,
                CASE WHEN LAG([myBackupset].[last_lsn],1,[myBackupset].[first_lsn]) OVER (Order by [myBackupset].[first_lsn]) = [myBackupset].[first_lsn] THEN 1 ELSE 0 END AS IsContiguous
            FROM
                [master].[sys].[databases] AS myDatabase WITH (READPAST)
                INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
                INNER JOIN (
                    SELECT
                        [myBackupFamily].[media_set_id],
                        Count(1) AS BackupFileCount,
                        CAST(MIN(CASE WHEN ISNULL([myCache].[IsFilesExists],[tempdb].[dbo].[fn_FileExists]([myBackupFamily].[physical_device_name]))=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'L'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND CASE WHEN @myLatestLsn = 0 THEN @myLowerBoundOfFileScan ELSE [myBackupset].[backup_start_date] END >= @myLowerBoundOfFileScan
                AND	(
                    @myLatestLsn BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
                    OR
                    [myBackupset].[first_lsn] >= @myLatestLsn
                    )
                AND 4 IN (" + $myAcceptedStrategies + ")
            
            INSERT INTO #myFileExistCache (MediaSetId, IsFilesExists) SELECT MediaSetId, 1 FROM #myResult   --Update Cache
            UPDATE #myResult SET IsContiguous=1 WHERE StrategyNo=4 AND BackupType='L' AND ID = (SELECT MIN(ID) FROM #myResult WHERE StrategyNo=4 AND BackupType='L')	    --First log file is not uncontiguous
            DELETE FROM #myResult WHERE StrategyNo=4 AND BackupType='L' AND ID <= (SELECT MAX(ID) FROM #myResult WHERE StrategyNo=4 AND BackupType='L' AND IsContiguous=0)	--Delete log backups without continious chain
        ----------------------Step4.2:	Generate Roadmaps
        IF EXISTS (SELECT COUNT(1) FROM #myResult WHERE StrategyNo=4)
        BEGIN
            ;With myStrategy4 AS (
                SELECT	--LogBackups
                    [myLogBackups].*,
                    CAST(NULL AS INT) AS [ParentID],
                    CAST(1 AS INT) AS [Level],
                    CAST([myLogBackups].[BackupFileSizeMB] AS REAL) AS Cost
                FROM 
                    #myResult AS myLogBackups
                WHERE 
                    [myLogBackups].[StrategyNo]=4 AND [myLogBackups].[BackupType]='L'
                )
        
            INSERT INTO #myRoadMaps (ID, DatabaseName, Position, BackupStartTime, BackupFinishTime, FirstLsn, LastLsn, BackupType, MediaSetId, BackupFileCount, BackupFileSizeMB, StrategyNo, ParentID, [Level], Cost)
            SELECT ID,DatabaseName,Position,BackupStartTime,BackupFinishTime,FirstLsn,LastLsn,BackupType,MediaSetId,BackupFileCount,BackupFileSizeMB,StrategyNo,ParentID,[Level],Cost FROM myStrategy4 ORDER BY [Level],[ParentID],[ID]
        
            IF EXISTS(SELECT 1 FROM #myRoadMaps WHERE [BackupType]='L' AND [StrategyNo]=4)
            BEGIN
                INSERT INTO #mySolutions (LogID, DiffID, FullID, RoadmapStartTime, RoadmapFinishTime, RoadmapFirstLsn, RoadmapLastLsn, RoadmapSizeMB, RoadmapFileCount, StrategyNo)
                SELECT 
                    MAX([myLog].[ID]) AS LogID,
                    NULL AS DiffID,
                    NULL AS FullID,
                    MIN([myLog].[BackupStartTime]),
                    MAX([myLog].[BackupFinishTime]),
                    MIN([myLog].[FirstLsn]),
                    MAX([myLog].[LastLsn]),
                    MAX([myLog].[Cost]),
                    SUM([myLog].[BackupFileCount]),
                    MIN([myLog].[StrategyNo])
                FROM 
                    #myRoadMaps AS myLog
                WHERE 
                    [myLog].[BackupType]='L'
                    AND [myLog].[StrategyNo]=4
            END
            DELETE FROM #mySolutions WHERE StrategyNo=4 AND @myLatestLsn NOT BETWEEN RoadmapFirstLsn AND RoadmapLastLsn	--Delete outdated LSN solutions
        END
        ELSE
            DELETE FROM #myResult WHERE StrategyNo=4
        --========================================
        --========================================Elect and show best solution strategy based on possible solutions cost(cost is equal to total size of reuired files in MB->RoadmapSizeMB)
        --========================================
        DECLARE @myStrategyNo TINYINT
        DECLARE @myFullID INT
        DECLARE @myDiffID INT
        DECLARE @myLogID INT
        
        --SELECT * FROM #mySolutions ORDER BY [RoadmapSizeMB], [RoadmapFileCount]
        SELECT TOP 1 @myStrategyNo=StrategyNo,@myFullID=FullID,@myDiffID=DiffID,@myLogID=LogID FROM #mySolutions ORDER BY [RoadmapSizeMB], [RoadmapFileCount]
        
        SELECT
            [myElectedBackupsets].[StrategyNo],
            [myElectedBackupsets].[ID],
            [myElectedBackupsets].[DatabaseName],
            [myElectedBackupsets].[Position],
            [myElectedBackupsets].[BackupStartTime],
            [myElectedBackupsets].[BackupFinishTime],
            [myElectedBackupsets].[FirstLsn],
            [myElectedBackupsets].[LastLsn],
            [myElectedBackupsets].[BackupType],
            [myElectedBackupsets].[MediaSetId],
            [myBackupFamily].[physical_device_name] AS FilePath
        FROM
            (
            SELECT * FROM #myRoadMaps
            WHERE
                @myStrategyNo=1
                AND StrategyNo=1
                AND (
                    BackupType='D' AND ID=@myFullID AND ParentID IS NULL
                    OR
                    BackupType='I' AND ID=@myDiffID AND ParentID=@myFullID
                    OR
                    BackupType='L' AND ParentID=@myDiffID
                    )
            UNION ALL
            SELECT * FROM #myRoadMaps
            WHERE
                @myStrategyNo=2
                AND StrategyNo=2
                AND (
                    BackupType='D' AND ID=@myFullID AND ParentID IS NULL
                    OR
                    BackupType='L' AND ParentID=@myFullID
                    )
            UNION ALL
            SELECT * FROM #myRoadMaps
            WHERE
                @myStrategyNo=3
                AND StrategyNo=3
                AND (
                    BackupType='I' AND ID=@myDiffID AND ParentID IS NULL
                    OR
                    BackupType='L' AND ParentID=@myDiffID
                    )
            UNION ALL
            SELECT * FROM #myRoadMaps
            WHERE
                @myStrategyNo=4
                AND StrategyNo=4
                AND BackupType='L'
            ) AS myElectedBackupsets
            INNER JOIN [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST) ON [myBackupFamily].[media_set_id] = [myElectedBackupsets].[MediaSetId]
        ORDER BY 
            [myElectedBackupsets].[StrategyNo],[myElectedBackupsets].[Level],[myElectedBackupsets].[ParentID],[myElectedBackupsets].[ID],[myBackupFamily].[physical_device_name]
        
        DROP TABLE #mySolutions;
        DROP TABLE #myRoadMaps;
        DROP TABLE #myResult;
        DROP TABLE #myFileExistCache;
        DROP FUNCTION dbo.fn_FileExists;   
        "
        try{
            #$this.LogWriter.Write($myCommand,[LogType]::INF)
            $this.LogWriter.Write("Query Backupfiles list.",[LogType]::INF)
            [System.Data.DataRow[]]$myRecords=$null
            $myRecords=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecords){
                [System.Collections.ArrayList]$myBackupFileCollection=$null
                $myBackupFileCollection=[System.Collections.ArrayList]::new()
                #[System.Collections.Generic.List[BackupFile]]$myBackupFileCollection=$null
                #$myBackupFileCollection=[System.Collections.Generic.List[BackupFile]]::new()
                $myFileRepositoryUncPath=$this.FileRepositoryUncPath
                $myRecords|ForEach-Object{$myBackupFileCollection.Add([BackupFile]::New($mySourceServerName,$myFileRepositoryUncPath,$_.StrategyNo,$_.ID,$_.DatabaseName,$_.Position,$_.BackupStartTime,$_.BackupFinishTime,$_.FirstLsn,$_.LastLsn,$_.BackupType,$_.MediaSetId,$_.FilePath))}
                $myAnswer=$myBackupFileCollection.ToArray([BackupFile])
            }
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            $myAnswer.Clear()
        }
        return $myAnswer
    }
    hidden [string]Database_GetServerName([string]$ConnectionString) {  #Get database server netbios name
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myAnswer=$null
        [string]$myCommand="
            SELECT @@SERVERNAME, CASE CHARINDEX('\',@@SERVERNAME) WHEN 0 THEN @@SERVERNAME ELSE SUBSTRING(@@SERVERNAME,0,CHARINDEX('\',@@SERVERNAME)) END AS ServerName
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$myRecord.ServerName} else {$myAnswer=$null}
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [bool]Database_DropDatabase([string]$ConnectionString,[string]$DatabaseName) {  #Drop database
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [bool]$myAnswer=$false
        [string]$myCommand="
            USE [master];
            IF EXISTS (SELECT 1 FROM sys.databases WHERE name=N'"+$DatabaseName+"')
            BEGIN
                IF EXISTS(SELECT 1 FROM sys.databases WHERE name=N'"+$DatabaseName+"' AND [state]=1)    --Destination database is in recovery mode
                    RESTORE DATABASE [" + $DatabaseName + "] WITH RECOVERY;
                ALTER DATABASE [" + $DatabaseName + "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [" + $DatabaseName + "];
            END
            SELECT 1 FROM [master].[sys].[databases] WHERE [name] = '" + $DatabaseName + "'
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$false} else {$myAnswer=$true}
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [string]Database_GetDefaultDbFolderLocations([string]$ConnectionString,[DatabaseFileType]$FileType) {  #Get default location of data file and log file
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myAnswer=$null
        [string]$myPropery=switch ($FileType) {
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
            if ($null -ne $myRecord) {$myAnswer=$myRecord.Path} else {$myAnswer=$null}
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [string]Database_CreateFolder([string]$ConnectionString,[string]$FolderPath) {  #Create folder via TSQL
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myAnswer=$null
        [string]$myCommand="
            USE [master];
            DECLARE @DirectoryPath nvarchar(4000);
            DECLARE @folder_exists INT;
            DECLARE @file_results TABLE (
                                        file_exists int,
                                        file_is_a_directory int,
                                        parent_directory_exists int
                                        )
                
            SET @DirectoryPath = N'" + $FolderPath + "';
            INSERT INTO @file_results (file_exists, file_is_a_directory, parent_directory_exists) EXEC master.dbo.xp_fileexist @DirectoryPath
            SELECT @folder_exists = file_is_a_directory FROM @file_results
        
            --script to create directory
            IF @folder_exists = 0
                BEGIN
                    BEGIN TRY
                        print 'Directory is not exists, creating new one'
                        EXECUTE master.dbo.xp_create_subdir @DirectoryPath
                        print @DirectoryPath +  'created on' + @@servername
                        SELECT 1 AS Result
                    END TRY
                    BEGIN CATCH
                        DECLARE @CustomMessage nvarchar(255)
                        SET @CustomMessage='Creating folder error on ' + @DirectoryPath
                        PRINT @CustomMessage
                        SELECT 0 AS Result
                    END CATCH
                END
                ELSE
                BEGIN
                    PRINT @DirectoryPath + 'Directory already exists'
                    SELECT 1 AS Result
                END
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$myRecord.Path} else {$myAnswer=$null}
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [bool]Database_RecoverDatabase([string]$ConnectionString,[string]$DatabaseName) {  #Recover database
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [bool]$myAnswer=$false
        [string]$myCommand="
            USE [master];
            IF EXISTS(SELECT 1 FROM [master].[sys].[databases] WHERE [name] = '" + $DatabaseName + "' AND [state] = 1)  --Database is exists and in restore mode
                RESTORE DATABASE [" + $DatabaseName + "] WITH RECOVERY
            
            SELECT 1 FROM [master].[sys].[databases] WHERE [name] = '" + $DatabaseName + "' AND [state] <> 1
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$true} else {$myAnswer=$false}
        }Catch{
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [string]BackupFileList_MergeBackupFilePath ([BackupFile[]]$Items,[string]$Delimiter=",") {   #Merge RemoteRepositoryUncFilePath property of input array
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myAnswer=""
        foreach ($myItem in $Items) {
            $myAnswer+=($myItem.RemoteRepositoryUncFilePath+$Delimiter)
        }
        if ($myAnswer.Length -ge $Delimiter.Length) {$myAnswer=$myAnswer.Substring(0,$myAnswer.Length-$Delimiter.Length)}
        return $myAnswer
    }
    hidden [string]BackupFileList_GenerateDestinationDatabaseFilesLocationFromBackupFile([string]$ConnectionString,[string]$DatabaseName,[string]$MergedPaths,[string]$PathDelimiter,[string]$DefaultDestinationDataFolderLocation,[string]$DefaultDestinationLogFolderLocation) {    #Generate Destination database file location from backup file list only
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myAnswer=""
        [string]$myBakupFilePaths="DISK = '" + $MergedPaths.Replace($PathDelimiter,"', DISK ='") + "'"
        [string]$myCommand = "RESTORE FILELISTONLY FROM " + $myBakupFilePaths + ";"
        [string]$myRestoreLocation=""
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -eq $myRecord) {
                $this.LogWriter.Write(("Can not determine database files inside backup file(s) from file(s): " + $MergedPaths), [LogType]::ERR)
                throw ("Can not determine database files inside backup file(s) from file(s): " + $MergedPaths)
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
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
            throw
        }
        return $myAnswer
    }
    hidden [string]BackupFileList_GenerateRestoreBackupCommand([string]$DatabaseName,[string]$BackupType,[int]$Position,[string]$MergedPaths,[string]$PathDelimiter,[string]$RestoreLocation) {    #Generate Restore Command
        $this.LogWriter.Write("Processing Started.", [LogType]::INF)
        [string]$myAnswer=""
        [string]$myRestoreLocation=""
        [string]$myRestoreType=switch ($BackupType) {
            "D"{"RESTORE DATABASE"}
            "I"{"RESTORE DATABASE"}
            "L"{"RESTORE LOG"}
            Default {"RESTORE DATABASE"}
        }
        if ($BackupType -eq "D") {$myRestoreLocation = ", " + $RestoreLocation} else {$myRestoreLocation=""}
        [string]$myBakupFilePaths="DISK = '" + $MergedPaths.Replace($PathDelimiter,"', DISK ='") + "'"
        $myAnswer = $myRestoreType + " [" + $DatabaseName + "] FROM " + $myBakupFilePaths + " WITH File = " + $Position.ToString() + $myRestoreLocation + ", NORECOVERY, STATS=5;"
        return $myAnswer
    }
    [void] ShipAllUserDatabases([string]$DestinationSuffix,[string[]]$ExcludedList){  #Ship all sql instance user databases (except/exclude some ones) from source to destination
        Write-Verbose ("ShipAllUserDatabases with " + $DestinationSuffix + " suffix")
        $this.LogWriter.Write(("ShipAllUserDatabases with " + $DestinationSuffix + " suffix"),[LogType]::INF)
        [string]$myExludedDB=""
        [string]$myDestinationDB=$null
        [string]$myOriginalLogFilePath=$null

        $myOriginalLogFilePath=$this.LogWriter.LogFilePath
        if ($null -ne $ExcludedList){
            foreach ($myExceptedDB in $ExcludedList){
                $myExludedDB+=",'" + $myExceptedDB.Trim() + "'"
            }
        }
        if ($null -eq $DestinationSuffix){$DestinationSuffix=""}
        [string]$myCommand="
            SELECT [name] AS [DbName] FROM sys.databases WHERE [state]=0 AND [name] NOT IN ('master','msdb','model','tempdb','SSISDB','DWConfiguration','DWDiagnostics','DWQueue','SqlDeep','distribution'"+$myExludedDB+")
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $this.SourceInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {
                foreach ($mySourceDB in $myRecord){
                    $this.LogWriter.LogFilePath=$myOriginalLogFilePath
                    $myDestinationDB=$mySourceDB.DbName+$DestinationSuffix
                    $this.ShipDatabase(($mySourceDB.DbName),$myDestinationDB)
                }
            }
        }Catch{
            Write-Verbose(($_.ToString()).ToString())
        }
    }
    [void] ShipDatabases([string[]]$SourceDB,[string]$DestinationSuffix){   #Ship list of databases from source to destination
        Write-Verbose ("ShipDatabases("+ $SourceDB.Count.ToString() +") with " + $DestinationSuffix + " suffix")
        [string]$myDestinationDB=$null
        [string]$myOriginalLogFilePath=$null

        $myOriginalLogFilePath=$this.LogWriter.LogFilePath
        if ($null -eq $DestinationSuffix){$DestinationSuffix=""}
        if ($null -ne $SourceDB){
            foreach ($mySourceDB in $SourceDB){
                $this.LogWriter.LogFilePath=$myOriginalLogFilePath
                $myDestinationDB=$mySourceDB+$DestinationSuffix
                $this.ShipDatabase($mySourceDB,$myDestinationDB)
            }
        }
    }
    [void] ShipDatabase([string]$SourceDB,[string]$DestinationDB){  #Ship a databases from source to destination
        try {
            #--=======================Initial Log Modules
            Write-Verbose ("===== ShipDatabase " + $SourceDB + " as " + $DestinationDB + " started. =====")
            $this.LogWriter.LogFilePath=$this.LogWriter.LogFilePath.Replace("{Database}",$DestinationDB)
            $this.LogWriter.Reinitialize
            $this.LogWriter.Write("===== Shipping process started... ===== ", [LogType]::INF) 
            $this.LogWriter.Write(("ShipDatabase " + $SourceDB + " as " + $DestinationDB), [LogType]::INF) 
            $this.LogWriter.Write("Initializing EventsTable.Create.", [LogType]::INF) 

            #--=======================Set constants
            [string]$myDelimiter=","
            [decimal]$myLatestLSN=0
            [decimal]$myDiffBackupBaseLsn=0

            #--=======================Validate input parameters
            if ($SourceDB.Trim().Length -eq 0) {
                $this.LogWriter.Write("Source SourceDB is empty.",[LogType]::INF)
                throw "Source SourceDB is empty."
            }
            if ($null -eq $DestinationDB -or $DestinationDB.Trim().Length -eq 0) {
                $this.LogWriter.Write("DestinationDB is empty, SourceDB name is used as DestinationDB name.",[LogType]::WRN)
                $DestinationDB=$SourceDB
            }

            #--=======================Check source connectivity
            $this.LogWriter.Write(("Check Source Instance Connectivity of " + $this.SourceInstanceConnectionString),[LogType]::INF)
            if ($this.Instance_ConnectivityTest($this.SourceInstanceConnectionString,$SourceDB) -eq $false) {
                $this.LogWriter.Write("Source Instance Connection failure.",[LogType]::ERR)
                throw "Source Instance Connection failure."
            } 

            #--=======================Check destination connectivity
            $this.LogWriter.Write(("Check Destination Instance Connectivity of " + $this.DestinationInstanceConnectionString),[LogType]::INF)
            if ($this.Instance_ConnectivityTest($this.DestinationInstanceConnectionString,"master") -eq $false) {
                $this.LogWriter.Write("Destination Instance Connection failure.",[LogType]::ERR)
                throw "Destination Instance Connection failure."
            } 

            #--=======================Check destination db existance status
            $this.LogWriter.Write(("Check Destination DB existance for " + $DestinationDB),[LogType]::INF)
            $myDestinationDbStatus=[DestinationDbStatus]::Unknown
            $myDestinationDbStatus=[DestinationDbStatus]($this.Database_GetDatabaseStatus($this.DestinationInstanceConnectionString,$DestinationDB))
            $this.LogWriter.Write(("Destination DB status is " + $myDestinationDbStatus),[LogType]::INF)
            If (($myDestinationDbStatus -eq [DestinationDbStatus]::Online) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::NotExist) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::Restoring)){
                $this.LogWriter.Write(("Destination DB status is " + $myDestinationDbStatus),[LogType]::INF)
            }else{
                $this.LogWriter.Write(("Destination database status is not allowd for processing, Destination DB status is " + $myDestinationDbStatus),[LogType]::ERR)
                throw ("Destination database status is not allowd for processing, Destination DB status is " + $myDestinationDbStatus)
            }

            #--=======================Get DB Backup file combinations
            If (($myDestinationDbStatus -eq [DestinationDbStatus]::Online) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::NotExist)){
                $this.LogWriter.Write(("Get DB Backup file combinations, for: " + $DestinationDB),[LogType]::INF)
                $myLatestLSN=[decimal]0
                $myDiffBackupBaseLsn=[decimal]0
            }elseif ($myDestinationDbStatus -eq [DestinationDbStatus]::Restoring) {
                $this.LogWriter.Write(("Get DB Backup file combinations, for: " + $DestinationDB),[LogType]::INF)
                $myLsnAnswers=$this.Database_GetDatabaseLSN($this.DestinationInstanceConnectionString,$DestinationDB)
                $myLatestLSN=$myLsnAnswers.LastLsn
                $myDiffBackupBaseLsn=$myLsnAnswers.DiffBackupBaseLsn
            }
            $this.LogWriter.Write(("Latest LSN is: " + $myLatestLSN.ToString()),[LogType]::INF)
            $this.LogWriter.Write(("DiffBackupBaseLsn is: " + $myDiffBackupBaseLsn.ToString()),[LogType]::INF)

            [BackupFile[]]$myBackupFileList=$null
            $myBackupFileList=$this.Database_GetBackupFileList($this.SourceInstanceConnectionString,$SourceDB,$myLatestLSN,$myDiffBackupBaseLsn)
            if ($null -eq $myBackupFileList -or $myBackupFileList.Count -eq 0) {
                $myRestoreStrategy = [RestoreStrategy]::NotExist
                $this.LogWriter.Write("There is nothing(no files) to restore.",[LogType]::WRN)
                throw "There is nothing(no files) to restore."
            } else {
                $myRestoreStrategy=[RestoreStrategy]($myBackupFileList[0].StrategyNo)
            }
            $this.LogWriter.Write(("Selected strategy is: " + $myRestoreStrategy),[LogType]::INF)

            #--=======================Copy DB Backup files to FileRepositoryPath
            $this.LogWriter.Write("Check Writeable FileRepositoryPath.",[LogType]::INF)
            if ($this.Path_IsWritable($this.FileRepositoryUncPath) -eq $false) {
                $this.LogWriter.Write("FileRepositoryPath is not accesible.",[LogType]::ERR)
                throw "FileRepositoryPath is not accesible."
            }

            foreach ($myBackupFile in $myBackupFileList){
                Copy-Item -Path ($myBackupFile.RemoteSourceFilePath) -Destination ($this.FileRepositoryUncPath) -Force -ErrorAction Stop
                $this.LogWriter.Write(("Copy backup file from " + ($myBackupFile.RemoteSourceFilePath) + " to " + ($this.FileRepositoryUncPath)),[LogType]::INF)
            }

            #--=======================Drop not in restoring mode databases
            If ($myDestinationDbStatus -eq [DestinationDbStatus]::Online -or $myRestoreStrategy -eq [RestoreStrategy]::FullDiffLog -or $myRestoreStrategy -eq [RestoreStrategy]::FullLog){
                $this.LogWriter.Write(("Drop Database : " + $DestinationDB),[LogType]::INF)

                $myExistedDestinationDbDropped=$this.Database_DropDatabase($this.DestinationInstanceConnectionString,$DestinationDB)
                if ($myExistedDestinationDbDropped -eq $false) {
                    $this.LogWriter.Write(("Could not drop destination database: " + $DestinationDB),[LogType]::ERR)
                    throw ("Could not drop destination database: " + $DestinationDB)
                }
            }

            #--=======================Get destination file locations
            $this.LogWriter.Write(("Get destination folder locations of: " + ($this.DestinationInstanceConnectionString)),[LogType]::INF)
            $myDefaultDestinationDataFolderLocation=$this.Database_GetDefaultDbFolderLocations($this.DestinationInstanceConnectionString,[DatabaseFileType]::DATA)
            $myDefaultDestinationLogFolderLocation=$this.Database_GetDefaultDbFolderLocations($this.DestinationInstanceConnectionString,[DatabaseFileType]::LOG)
            If ($null -eq $myDefaultDestinationDataFolderLocation){
                $this.LogWriter.Write(("Default Data folder location is empty on: " + $this.DestinationInstanceConnectionString),[LogType]::ERR)
                throw ("Default Data folder location is empty on: " + $this.DestinationInstanceConnectionString)
            }
            If ($null -eq $myDefaultDestinationLogFolderLocation){
                $this.LogWriter.Write(("Default Log folder location is empty on: " + $this.DestinationInstanceConnectionString),[LogType]::ERR)
                throw ("Default Log folder location is empty on: " + $this.DestinationInstanceConnectionString)
            }

            $this.LogWriter.Write("Calculate RestoreLocation Folder",[LogType]::INF)
            if ($this.RestoreFilesToIndividualFolders) {
                $myDefaultDestinationDataFolderLocation += $DestinationDB.Replace(" ","_") + "\"
                $myDefaultDestinationLogFolderLocation += $DestinationDB.Replace(" ","_") + "\"
            }

            $this.LogWriter.Write(("Data file RestoreLocation folder is " + $myDefaultDestinationDataFolderLocation),[LogType]::INF)
            $this.LogWriter.Write(("Log file RestoreLocation folder is " + $myDefaultDestinationLogFolderLocation),[LogType]::INF)

            $this.LogWriter.Write("Create RestoreLocation folders, if not exists.",[LogType]::INF)
            $this.Database_CreateFolder($this.DestinationInstanceConnectionString,$myDefaultDestinationDataFolderLocation)
            $this.Database_CreateFolder($this.DestinationInstanceConnectionString,$myDefaultDestinationLogFolderLocation)

            $this.LogWriter.Write("Generate RestoreLocation",[LogType]::INF)
            [int]$myMediasetId=$myBackupFileList[0].MediaSetId
            [string]$myMediasetMergedPath=$myBackupFileList | Where-Object -Property MediaSetId -EQ $myMediasetId | Group-Object -Property MediaSetId,Position | ForEach-Object{$this.BackupFileList_MergeBackupFilePath($_.Group,$myDelimiter)}
            [string]$myRestoreLocation = $this.BackupFileList_GenerateDestinationDatabaseFilesLocationFromBackupFile($this.DestinationInstanceConnectionString,$DestinationDB,$myMediasetMergedPath,$myDelimiter,$myDefaultDestinationDataFolderLocation,$myDefaultDestinationLogFolderLocation)
            if ($null -eq $myRestoreLocation -or $myRestoreLocation.Length -eq 0) {
                $this.LogWriter.Write("Can not get Restore location.",[LogType]::ERR)
                throw "Can not get Restore location."
            }else{
                $this.LogWriter.Write(("Restore Location is: " + $myRestoreLocation),[LogType]::INF)
            }

            #--=======================Restoring backup(s) in destination
            $this.LogWriter.Write("Generate RestoreList",[LogType]::INF)
            $myRestoreList=$myBackupFileList | Group-Object -Property MediaSetId,Position | ForEach-Object{[PSCustomObject]@{
                MediaSetId=$_.Name.Split(",")[0]; 
                Order=($_.Group | Sort-Object ID | Select-Object -Last 1 -Property ID).ID;
                RestoreCommand=$($this.BackupFileList_GenerateRestoreBackupCommand($DestinationDB,(($_.Group | Select-Object -Last 1 -Property BackupType).BackupType),($_.Name.Split(",")[1]),($this.BackupFileList_MergeBackupFilePath($_.Group,$myDelimiter)),$myDelimiter,$myRestoreLocation));
            }}

            $this.LogWriter.Write("Run Restore Commands",[LogType]::INF)
            If ($null -ne $myRestoreList){
                try{
                    $myRestoreList | ForEach-Object{
                                                        $this.LogWriter.Write(("Restore Command:" + $_.RestoreCommand),[LogType]::INF);
                                                        try{
                                                            Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString -Query ($_.RestoreCommand) -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
                                                        }catch{
                                                            if ($_.ToString() -like "*Msg 4326, Level 16, State 1*") {     #log file is too early
                                                                $this.LogWriter.Write(($_.ToString()).ToString(),[LogType]::WRN)
                                                            }else{
                                                                $this.LogWriter.Write(($_.ToString()).ToString(),[LogType]::ERR)
                                                                throw
                                                            }
                                                        }
                                                    }
                }Catch{
                    $this.LogWriter.Write(($_.ToString()).ToString(),[LogType]::ERR)
                    throw
                }
            }else{
                $this.LogWriter.Write("There is no commands to execute.",[LogType]::WRN)
            }

            #--=======================Remove copied files
            $this.LogWriter.Write("Remove copied files.",[LogType]::INF)
            $myBackupFileList | ForEach-Object{Remove-Item -Path ($_.RemoteRepositoryUncFilePath); $this.LogWriter.Write(("Remove file " + $_.RemoteRepositoryUncFilePath),[LogType]::INF)}

            #--=======================SetDestinationDBMode
            $this.LogWriter.Write(("Set destination database mode to " + $this.DestinationRestoreMode),[LogType]::INF)
            if ($this.DestinationRestoreMode -eq [DatabaseRecoveryMode]::RECOVERY) {
                $myRecoveryStatus=$this.Database_RecoverDatabase($this.DestinationInstanceConnectionString,$DestinationDB)
                if ($myRecoveryStatus -eq $false) {
                    $this.LogWriter.Write(("Database " + $DestinationDB + " does not exists or could not be recovered."),[LogType]::INF)
                }
            }
        }catch{
            Write-Error ($_.ToString())
            $this.LogWriter.Write(($_.ToString()).ToString(), [LogType]::ERR)
        }finally{
            Write-Verbose ("===== ShipDatabase " + $SourceDB + " as " + $DestinationDB + " finished. =====")
            if ($this.LogWriter.ErrCount -eq 0 -and $this.LogWriter.WrnCount -eq 0) {
                $this.LogWriter.Write("Finished.",[LogType]::INF)
            }elseif ($this.LogWriter.ErrCount -eq 0 -and $this.LogWriter.WrnCount -gt 0) {
                $this.LogWriter.Write(("Finished with " + $this.LogWriter.WrnCount.ToString() + " Warning(s)."),[LogType]::WRN)
            }else{
                $this.LogWriter.Write(("Finished with " + $this.LogWriter.ErrCount.ToString() + " Error(s) and " + $this.LogWriter.WrnCount.ToString() + " Warning(s)."),[LogType]::ERR)
            }
            $this.LogWriter.Write("===== Shipping process finished. ===== ", [LogType]::INF) 
        }
    }

#endregion
}
#region Functions
Function New-DatabaseShipping {
    Param(
        [Parameter(Mandatory=$true)][string]$SourceInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$DestinationInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$FileRepositoryUncPath,
        [Parameter(Mandatory=$false)][int]$LimitMsdbScanToRecentDays=0,
        [Parameter(Mandatory=$false)][switch]$RestoreFilesToIndividualFolders,
        [Parameter(Mandatory=$false)][DatabaseRecoveryMode]$DestinationRestoreMode=[DatabaseRecoveryMode]::RESTOREONLY,
        [Parameter(Mandatory=$true)][LogWriter]$LogWriter
    )
    Write-Verbose "Creating New-DatabaseShipping"
    [string]$mySourceInstanceConnectionString=$SourceInstanceConnectionString
    [string]$myDestinationInstanceConnectionString=$DestinationInstanceConnectionString
    [string]$myFileRepositoryUncPath=$FileRepositoryUncPath
    [int]$myLimitMsdbScanToRecentDays=$LimitMsdbScanToRecentDays
    [bool]$myRestoreFilesToIndividualFolders=$RestoreFilesToIndividualFolders
    [DatabaseRecoveryMode]$myDestinationRestoreMode=$DestinationRestoreMode
    [LogWriter]$myLogWriter=$LogWriter
    [DatabaseShipping]::New($mySourceInstanceConnectionString,$myDestinationInstanceConnectionString,$myFileRepositoryUncPath,$myLimitMsdbScanToRecentDays,$myRestoreFilesToIndividualFolders,$myDestinationRestoreMode,$myLogWriter)
    Write-Verbose "New-DatabaseShipping Created"
}
#endregion

#region Export
Export-ModuleMember -Function New-DatabaseShipping
#endregion