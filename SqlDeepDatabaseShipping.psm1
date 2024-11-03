Using module .\SqlDeepCommon.psm1
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
        Write-Verbose 'Processing Started.'
        [string]$myAnswer=$null
        if ($this.FilePath.Contains('\\') -eq $false) {
            $myUncPath='\\' + $Server + '\' + ($this.FilePath.Split(':') -Join '$')
            $myAnswer=$myUncPath
        }else {
            $myAnswer=$this.FilePath
        }
        return $myAnswer
    }
    hidden [string]CalcRemoteRepositoryUncFilePath ([string]$FileRepositoryUncPath) {    #Converting local path to Shared Repository UNC path
        Write-Verbose 'Processing Started.'
        [string]$myAnswer=$null
        $myAnswer=$FileRepositoryUncPath + '\' + ($this.FilePath.Split('\')[-1])
        return $myAnswer
    }
}
Class DatabaseShipping {
    [string]$SourceInstanceConnectionString
    [string]$DestinationInstanceConnectionString
    [string]$FileRepositoryUncPath
    [int]$LimitMsdbScanToRecentHours=(31*24)
    [string]$DataFolderRestoreLoation='DEFAULT'
    [string]$LogFolderRestoreLoation='DEFAULT'
    [bool]$RestoreFilesToIndividualFolders=$true
    [DatabaseRecoveryMode]$DestinationRestoreMode=[DatabaseRecoveryMode]::RESTOREONLY
    [RestoreStrategy[]]$PreferredStrategies=[RestoreStrategy]::FullDiffLog,[RestoreStrategy]::FullLog,[RestoreStrategy]::DiffLog,[RestoreStrategy]::Log
    [bool]$SkipBackupFilesExistenceCheck=$false
    [nullable[datetime]]$RestoreTo=$null
    hidden [LogWriter]$LogWriter
    hidden [string]$LogStaticMessage=''
    hidden [BackupFile[]]$BackupFileList=$null  #This property used to return list of all selected backup files to module consumers, This property should not be used for producation usage inside this module because it's writeable for outsiders

    DatabaseShipping(){

    }
    DatabaseShipping([string]$SourceInstanceConnectionString,[string]$DestinationInstanceConnectionString,[string]$FileRepositoryUncPath,[LogWriter]$LogWriter){
        $this.Init($SourceInstanceConnectionString,$DestinationInstanceConnectionString,$FileRepositoryUncPath,(31*24),$true,[DatabaseRecoveryMode]::RESTOREONLY,$LogWriter)
    }
    DatabaseShipping([string]$SourceInstanceConnectionString,[string]$DestinationInstanceConnectionString,[string]$FileRepositoryUncPath,[int]$LimitMsdbScanToRecentHours,[bool]$RestoreFilesToIndividualFolders,[DatabaseRecoveryMode]$DestinationRestoreMode,[LogWriter]$LogWriter){
        $this.Init($SourceInstanceConnectionString,$DestinationInstanceConnectionString,$FileRepositoryUncPath,$LimitMsdbScanToRecentHours,$RestoreFilesToIndividualFolders,$DestinationRestoreMode,$LogWriter)
    }
    hidden Init([string]$SourceInstanceConnectionString,[string]$DestinationInstanceConnectionString,[string]$FileRepositoryUncPath,[int]$LimitMsdbScanToRecentHours,[bool]$RestoreFilesToIndividualFolders,[DatabaseRecoveryMode]$DestinationRestoreMode,[LogWriter]$LogWriter){
        $this.SourceInstanceConnectionString=$SourceInstanceConnectionString
        $this.DestinationInstanceConnectionString=$DestinationInstanceConnectionString
        $this.LimitMsdbScanToRecentHours=$LimitMsdbScanToRecentHours
        $this.RestoreFilesToIndividualFolders=$RestoreFilesToIndividualFolders
        $this.DestinationRestoreMode=$DestinationRestoreMode
        $this.FileRepositoryUncPath=$FileRepositoryUncPath
        $this.LogWriter=$LogWriter
    }
#region Functions
    hidden [bool]Path_IsWritable ([string]$FolderPath) {    #Check writable path
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF) 
        [bool]$myAnswer=$false
        $FolderPath=Clear-FolderPath -FolderPath $FolderPath
        if ((Test-Path -Path $FolderPath -PathType Container) -eq $true) {
            $myFilename=((New-Guid).ToString())+'.lck'
            try {
                Add-Content -Path ($FolderPath+'\'+$myFilename) -Value ''
                if ((Test-Path -Path ($FolderPath+'\'+$myFilename) -PathType Leaf) -eq $true) {
                    Remove-Item -Path ($FolderPath+'\'+$myFilename) -Force
                    $myAnswer=$true
                }else{
                    $myAnswer=$false
                }
            }Catch{
                $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR) 
                $myAnswer=$false
            }
        }else{
            $myAnswer=$false
        }

        return $myAnswer
    }
    hidden [bool]Instance_ConnectivityTest([string]$ConnectionString,[string]$DatabaseName) {  #Test Instance connectivity
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [bool]$myAnswer=$false
        [string]$myCommand="
            USE [master];
            SELECT TOP 1 1 AS Result FROM [master].[sys].[databases] WHERE name = '" + $DatabaseName + "';
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$true} else {$myAnswer=$false}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [DestinationDbStatus]Database_GetDatabaseStatus([string]$ConnectionString,[string]$DatabaseName) {  #Check database status
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [DestinationDbStatus]$myAnswer=[DestinationDbStatus]::NotExist
        [string]$myCommand="
            USE [master];
            SELECT TOP 1 [myDatabase].[state] FROM [master].[sys].[databases] AS myDatabase WHERE [myDatabase].[name] = '" + $DatabaseName + "';
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$myRecord.state} else {$myAnswer=[DestinationDbStatus]::NotExist}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [System.Object]Database_GetDatabaseLSN([string]$ConnectionString,[string]$DatabaseName) {  #Get database latest LSN
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [System.Object]$myAnswer=New-Object PsObject -Property @{LastLsn = [decimal]0; DiffBackupBaseLsn = [decimal]0; KnownRecoveryFork = [string]''}
        [string]$myCommand="
            USE [master];
            SELECT TOP 1
                [myDatabaseLsn].[redo_start_lsn] AS LastLsn,
                [myDatabaseLsn].[differential_base_lsn] AS DiffBackupBaseLsn,
                ISNULL( CAST([myDatabaseLsn].[redo_start_fork_guid] AS NVARCHAR(50)) , CAST(N'' AS NVARCHAR(50)) ) AS KnownRecoveryFork
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
            if ($null -ne $myRecord) {
                                        $myAnswer.LastLsn = [decimal]$myRecord.LastLsn; 
                                        $myAnswer.DiffBackupBaseLsn = [decimal]$myRecord.DiffBackupBaseLsn
                                        $myAnswer.KnownRecoveryFork = [string]$myRecord.KnownRecoveryFork
                                    }
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [string]Get_StrategiesToString([RestoreStrategy[]]$Strategies) { #Get restore strategies as a comma seperated string
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [string]$myAnswer=$null
        [string]$myAcceptedStrategies=''

        $Strategies | ForEach-Object{$myAcceptedStrategies+=($_.value__).ToString()+','}
        if ($myAcceptedStrategies[-1] -eq ',') {$myAcceptedStrategies=$myAcceptedStrategies.Substring(0,$myAcceptedStrategies.Length-1)}
        $myAnswer=$myAcceptedStrategies
        $this.LogWriter.Write($this.LogStaticMessage+('Strategies are: ' + $myAnswer), [LogType]::INF)

        return $myAnswer
    }
    hidden [BackupFile[]]Database_GetBackupFileList([string]$ConnectionString,[string]$DatabaseName,[Decimal]$LatestLSN,[Decimal]$DiffBackupBaseLsn,[string]$KnownRecoveryFork) {    #Get List of backup files combination neede to restore
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [BackupFile[]]$myAnswer=$null
        
        $this.LogWriter.Write($this.LogStaticMessage+'Generate random suffix name.',[LogType]::INF)
        [string]$myExecutionId=$null;
        $myExecutionId=(Get-Random -Minimum 1 -Maximum 1000).ToString()

        $this.LogWriter.Write($this.LogStaticMessage+'Get Source instance server name.',[LogType]::INF)
        [string]$mySourceServerName=$null
        $mySourceServerName=$this.Database_GetServerName($ConnectionString)
        if ($null -eq $mySourceServerName) {
            $this.LogWriter.Write($this.LogStaticMessage+'Source server name is empty.',[LogType]::ERR)
            throw 'Source server name is empty.'
        }

        # Generate acceptable strategies list for TSQL
        $this.LogWriter.Write($this.LogStaticMessage+'Determine PreferredStrategies started.',[LogType]::INF)
        [RestoreStrategy[]]$Strategies=$null
        [string]$myAcceptedStrategies=$null
        if ($LatestLSN -eq 0 -and $DiffBackupBaseLsn -eq 0){    #In this case Diff and Log backups are not usable and we should use strategies containes Full backup files
            $Strategies = $this.PreferredStrategies | Where-Object -Property value__ -NotIn ( ([RestoreStrategy]::DiffLog).value__ , ([RestoreStrategy]::Log).value__ ) #Removing any non-full backup strategies from list
            if (!($Strategies -contains [RestoreStrategy]::FullDiffLog) -and !($this.PreferredStrategies -contains [RestoreStrategy]::FullLog)){    #Add all full backup strategies to the list, if there is not atleast one full backup strategy found in the list
                $Strategies=[RestoreStrategy]::FullDiffLog,[RestoreStrategy]::FullLog
            }
            $myAcceptedStrategies=$this.Get_StrategiesToString($Strategies)
        }else{
            $myAcceptedStrategies=$this.Get_StrategiesToString($this.PreferredStrategies)
        }

        if ($null -eq $myAcceptedStrategies -or $myAcceptedStrategies.Trim().Length -eq 0) {
            $this.LogWriter.Write($this.LogStaticMessage+'PreferredStrategies is empty.',[LogType]::ERR)
            throw 'PreferredStrategies is empty.'
        }

        # Generate FileExistenceCheck command
        $this.LogWriter.Write($this.LogStaticMessage+'Determine File Existence Check according to SkipBackupFilesExistenceCheck started.',[LogType]::INF)
        [string]$myBackupFileExistenceCheckCommand=$null
        if ($this.SkipBackupFilesExistenceCheck){
            $myBackupFileExistenceCheckCommand='CAST(1 AS BIT) AS IsFilesExists'
        }else{
            $myBackupFileExistenceCheckCommand="CAST(MIN(CASE WHEN [tempdb].[dbo].[fn_FileExists"+$myExecutionId+"]([myBackupFamily].[physical_device_name])=1 THEN 1 ELSE 0 END) AS BIT) AS IsFilesExists"
        }

        # Generate RecoveryTime
        [string]$myRestoreTo=$null
        $myRestoreTo=(Get-Date).ToString()
        if ($this.RestoreTo) {$myRestoreTo=($this.RestoreTo).ToString()}

        # Generate BackupFileListQuery
        [string]$myCommand=$null
        $myCommand = "
        USE [tempdb];
        DECLARE @myDBName AS NVARCHAR(255);
        DECLARE @myLatestLsn NUMERIC(25,0);
        DECLARE @myDiffBackupBaseLsn NUMERIC(25,0);
        DECLARE @myRestoreTo AS DATETIME;
		DECLARE @myRestoreToLatestFullBackupsetId AS INT;
		DECLARE @myRestoreToLatestDiffBackupsetId AS INT;
		DECLARE @myRestoreToLatestLogBackupsetId AS INT;
        DECLARE @myLowerBoundOfFileScan DATETIME;
        DECLARE @myNumberOfHoursToScan INT;
        DECLARE @myLatestRecoveryFork UNIQUEIDENTIFIER;
        DECLARE @myLatestRecoveryForkString NVARCHAR(50);
        DECLARE @myKnownRecoveryForkString NVARCHAR(50);
        DECLARE @myIsFullBackupStrategyForced BIT;
        SET @myDBName=N'"+ $DatabaseName + "';
        SET @myLatestLsn="+ $LatestLSN.ToString() + ";
        SET @myDiffBackupBaseLsn="+ $DiffBackupBaseLsn.ToString() + ";
        SET @myNumberOfHoursToScan="+ $this.LimitMsdbScanToRecentHours.ToString() +";
        SET @myKnownRecoveryForkString='"+ $KnownRecoveryFork.ToString() +"';
        SET @myRestoreTo = CAST('"+ $myRestoreTo +"' AS DATETIME);
        SET @myLowerBoundOfFileScan= CASE WHEN @myNumberOfHoursToScan=0 THEN CAST('1753-01-01' AS DATETIME) ELSE CAST(DATEADD(HOUR,-1*ABS(@myNumberOfHoursToScan),GETDATE()) AS DATE) END
        SET @myLatestRecoveryFork= (SELECT TOP 1 [last_recovery_fork_guid] FROM [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) WHERE [myBackupset].[is_copy_only] = 0 AND [myBackupset].[database_name] = @myDBName AND [myBackupset].[backup_finish_date] IS NOT NULL AND [myBackupset].[backup_start_date] >= @myLowerBoundOfFileScan ORDER BY [myBackupset].[backup_start_date] DESC)
        SET @myIsFullBackupStrategyForced= 0
        IF @myKnownRecoveryForkString != CAST(@myLatestRecoveryFork AS NVARCHAR(50))
            SET @myIsFullBackupStrategyForced= 1

        SELECT  --Detect Latest usefull backupset according to @myRestoreTo time
			@myRestoreToLatestFullBackupsetId=myPivot.D,
			@myRestoreToLatestDiffBackupsetId=myPivot.I,
			@myRestoreToLatestLogBackupsetId=myPivot.L
		FROM
			(
			SELECT 
				[myBackupset].[type],
				MIN([myBackupset].[backup_set_id]) AS [backup_set_id]
			FROM 
				[master].[sys].[databases] AS myDatabase WITH (READPAST)
				INNER JOIN [msdb].[dbo].[backupset] AS myBackupset WITH (READPAST) ON [myBackupset].[database_name] = [myDatabase].[name]
			WHERE 
				[myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
				AND [myBackupset].[is_copy_only] = 0
				AND [myDatabase].[name] = @myDBName
				AND [myBackupset].[backup_finish_date] IS NOT NULL
				AND [myBackupset].[backup_start_date] > @myRestoreTo
			GROUP BY
				[myBackupset].[type]
			) AS myLatestBackupSetId
			PIVOT (
				MAX([backup_set_id])
				FOR [type] IN ([D],[I],[L])
			) AS myPivot

        -------------------------------------------Create required functions in tempdb
        IF NOT EXISTS (SELECT 1 FROM [tempdb].[sys].[all_objects] WHERE type='FN' AND name = 'fn_FileExists"+$myExecutionId+"')
        BEGIN
            DECLARE @myStatement NVARCHAR(MAX);
            SET @myStatement = N'
                CREATE FUNCTION dbo.fn_FileExists"+$myExecutionId+"(@path varchar(512))
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
            IsFilesExists BIT DEFAULT(1)
        );
        CREATE UNIQUE CLUSTERED INDEX myFileExistCacheUNQ"+$myExecutionId+" ON #myFileExistCache (MediaSetId) WITH (IGNORE_DUP_KEY=ON);
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
                        "+$myBackupFileExistenceCheckCommand+"
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
                AND [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'D'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myBackupset].[backup_start_date] >= @myLowerBoundOfFileScan
                AND (CASE WHEN @myRestoreToLatestFullBackupsetId IS NULL THEN 0 ELSE [myBackupset].[backup_set_id] END) <= (CASE WHEN @myRestoreToLatestFullBackupsetId IS NULL THEN 0 ELSE @myRestoreToLatestFullBackupsetId END)
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND (@myIsFullBackupStrategyForced=1 OR 1 IN (" + $myAcceptedStrategies + "))
            
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
                        "+$myBackupFileExistenceCheckCommand+"
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
                AND [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'I'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND (CASE WHEN @myRestoreToLatestDiffBackupsetId IS NULL THEN 0 ELSE [myBackupset].[backup_set_id] END) <= (CASE WHEN @myRestoreToLatestDiffBackupsetId IS NULL THEN 0 ELSE @myRestoreToLatestDiffBackupsetId END)
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND (@myIsFullBackupStrategyForced=1 OR 1 IN (" + $myAcceptedStrategies + "))

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
                        "+$myBackupFileExistenceCheckCommand+"
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
                AND [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'L'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND (CASE WHEN @myRestoreToLatestLogBackupsetId IS NULL THEN 0 ELSE [myBackupset].[backup_set_id] END) <= (CASE WHEN @myRestoreToLatestLogBackupsetId IS NULL THEN 0 ELSE @myRestoreToLatestLogBackupsetId END)
                AND	(
                    [myBackupset].[first_lsn] >= (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=1)
                    OR
                    (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=1) BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
                    )
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND (@myIsFullBackupStrategyForced=1 OR 1 IN (" + $myAcceptedStrategies + "))
            
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
                        "+$myBackupFileExistenceCheckCommand+"
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
                AND [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'D'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND [myBackupset].[backup_start_date] >= @myLowerBoundOfFileScan
                AND (CASE WHEN @myRestoreToLatestFullBackupsetId IS NULL THEN 0 ELSE [myBackupset].[backup_set_id] END) <= (CASE WHEN @myRestoreToLatestFullBackupsetId IS NULL THEN 0 ELSE @myRestoreToLatestFullBackupsetId END)
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND (@myIsFullBackupStrategyForced=1 OR 2 IN (" + $myAcceptedStrategies + "))
            
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
                        "+$myBackupFileExistenceCheckCommand+"
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
                AND [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'L'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND (CASE WHEN @myRestoreToLatestLogBackupsetId IS NULL THEN 0 ELSE [myBackupset].[backup_set_id] END) <= (CASE WHEN @myRestoreToLatestLogBackupsetId IS NULL THEN 0 ELSE @myRestoreToLatestLogBackupsetId END)
                AND	(
                    [myBackupset].[first_lsn] >= (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=2)
                    OR
                    (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=2) BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
                    )
                AND [myMediaIsAvailable].[IsFilesExists]=1
                AND (@myIsFullBackupStrategyForced=1 OR 2 IN (" + $myAcceptedStrategies + "))
            
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
                        "+$myBackupFileExistenceCheckCommand+"
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
                AND [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'I'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND (CASE WHEN @myRestoreToLatestDiffBackupsetId IS NULL THEN 0 ELSE [myBackupset].[backup_set_id] END) <= (CASE WHEN @myRestoreToLatestDiffBackupsetId IS NULL THEN 0 ELSE @myRestoreToLatestDiffBackupsetId END)
                AND CASE WHEN @myDiffBackupBaseLsn = 0 THEN @myLowerBoundOfFileScan ELSE [myBackupset].[backup_start_date] END >= @myLowerBoundOfFileScan
                AND [myBackupset].[database_backup_lsn]=@myDiffBackupBaseLsn
                AND [myMediaIsAvailable].[IsFilesExists]=1
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
                        "+$myBackupFileExistenceCheckCommand+"
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
                AND [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'L'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND (CASE WHEN @myRestoreToLatestLogBackupsetId IS NULL THEN 0 ELSE [myBackupset].[backup_set_id] END) <= (CASE WHEN @myRestoreToLatestLogBackupsetId IS NULL THEN 0 ELSE @myRestoreToLatestLogBackupsetId END)
                AND	(
                    [myBackupset].[first_lsn] >= (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=3)
                    OR
                    (SELECT MIN([FirstLsn]) FROM #myResult WHERE [StrategyNo]=3) BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
                    )
                AND [myMediaIsAvailable].[IsFilesExists]=1
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
                        "+$myBackupFileExistenceCheckCommand+"
                    FROM
                        [msdb].[dbo].[backupmediafamily] AS myBackupFamily WITH (READPAST)
                        LEFT OUTER JOIN #myFileExistCache AS myCache ON [myCache].[MediaSetId]=[myBackupFamily].[media_set_id]
                    GROUP BY
                        [myBackupFamily].[media_set_id]
                    ) AS myMediaIsAvailable ON [myMediaIsAvailable].[media_set_id] = [myBackupset].[media_set_id]
            WHERE 
                [myBackupset].[last_recovery_fork_guid] = @myLatestRecoveryFork
                AND [myBackupset].[is_copy_only] = 0
                AND [myDatabase].[name] = @myDBName
                AND [myBackupset].[type] = 'L'
                AND [myBackupset].[backup_finish_date] IS NOT NULL
                AND (CASE WHEN @myRestoreToLatestLogBackupsetId IS NULL THEN 0 ELSE [myBackupset].[backup_set_id] END) <= (CASE WHEN @myRestoreToLatestLogBackupsetId IS NULL THEN 0 ELSE @myRestoreToLatestLogBackupsetId END)
                AND CASE WHEN @myLatestLsn = 0 THEN @myLowerBoundOfFileScan ELSE [myBackupset].[backup_start_date] END >= @myLowerBoundOfFileScan
                AND	(
                    @myLatestLsn BETWEEN [myBackupset].[first_lsn] AND [myBackupset].[last_lsn]
                    OR
                    [myBackupset].[first_lsn] >= @myLatestLsn
                    )
                AND [myMediaIsAvailable].[IsFilesExists]=1
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
        DROP FUNCTION dbo.fn_FileExists"+$myExecutionId+";   
        "
        try{
            #$this.LogWriter.Write($this.LogStaticMessage+$myCommand,[LogType]::INF)
            $this.LogWriter.Write($this.LogStaticMessage+'Query Backupfiles list.',[LogType]::INF)
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
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myAnswer.Clear()
        }
        return $myAnswer
    }
    hidden [string]Database_GetServerName([string]$ConnectionString) {  #Get database server netbios name
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [string]$myAnswer=$null
        [string]$myCommand="
            SELECT @@SERVERNAME, CASE CHARINDEX('\',@@SERVERNAME) WHEN 0 THEN @@SERVERNAME ELSE SUBSTRING(@@SERVERNAME,0,CHARINDEX('\',@@SERVERNAME)) END AS ServerName
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$myRecord.ServerName} else {$myAnswer=$null}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [bool]Database_DropDatabase([string]$ConnectionString,[string]$DatabaseName) {  #Drop database
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
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
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [string]Database_GetDefaultDbFolderLocations([string]$ConnectionString,[DatabaseFileType]$FileType) {  #Get default location of data file and log file
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [string]$myAnswer=$null
        [string]$myPropery=switch ($FileType) {
            'DATA'{'InstanceDefaultDataPath'}
            'LOG'{'InstanceDefaultLogPath'}
            Default {'InstanceDefaultDataPath'}
        }
        $myCommand="
            USE [master];
            SELECT SERVERPROPERTY('" + $myPropery + "') AS Path;
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {$myAnswer=$myRecord.Path} else {$myAnswer=$null}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [string]Database_CreateFolder([string]$ConnectionString,[string]$FolderPath) {  #Create folder via TSQL
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
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
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [bool]Database_RecoverDatabase([string]$ConnectionString,[string]$DatabaseName) {  #Recover database
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
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
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
        return $myAnswer
    }
    hidden [string]BackupFileList_MergeBackupFilePath ([BackupFile[]]$Items,[string]$Delimiter=',') {   #Merge RemoteRepositoryUncFilePath property of input array
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [string]$myAnswer=''
        foreach ($myItem in $Items) {
            $myAnswer+=($myItem.RemoteRepositoryUncFilePath+$Delimiter)
        }
        if ($myAnswer.Length -ge $Delimiter.Length) {$myAnswer=$myAnswer.Substring(0,$myAnswer.Length-$Delimiter.Length)}
        return $myAnswer
    }
    hidden [string]BackupFileList_GenerateDestinationDatabaseFilesLocationFromBackupFile([string]$ConnectionString,[string]$DatabaseName,[string]$MergedPaths,[string]$PathDelimiter,[string]$DefaultDestinationDataFolderLocation,[string]$DefaultDestinationLogFolderLocation) {    #Generate Destination database file location from backup file list only
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [string]$myAnswer=''
        [string]$myBakupFilePaths="DISK = '" + $MergedPaths.Replace($PathDelimiter,"', DISK ='") + "'"
        [string]$myCommand = "RESTORE FILELISTONLY FROM " + $myBakupFilePaths + ";"
        [string]$myRestoreLocation=''
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -eq $myRecord) {
                $this.LogWriter.Write($this.LogStaticMessage+('Can not determine database files inside backup file(s) from file(s): ' + $MergedPaths), [LogType]::ERR)
                throw ('Can not determine database files inside backup file(s) from file(s): ' + $MergedPaths)
            }
            foreach ($myDbFile in $myRecord) {
                [string]$myFolderLocation=''
                [string]$myFileName=''
                if ($myDbFile.Type -eq 'L') {
                    $myFolderLocation=$DefaultDestinationLogFolderLocation
                }else{
                    $myFolderLocation=$DefaultDestinationDataFolderLocation
                }
                $myFileName=$myDbFile.PhysicalName.Split('\')[-1]
                $myRestoreLocation+="MOVE '" + ($myDbFile.LogicalName) + "' TO '" + $myFolderLocation + $DatabaseName + '_' + $myFileName +"',"
            }
            $myAnswer=$myRestoreLocation.Substring(0,$myRestoreLocation.Length-1)
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            throw
        }
        return $myAnswer
    }
    hidden [string]BackupFileList_GenerateRestoreBackupCommand([string]$DatabaseName,[string]$BackupType,[int]$Position,[string]$MergedPaths,[string]$PathDelimiter,[string]$RestoreLocation) {    #Generate Restore Command
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [string]$myAnswer=''
        [string]$myRestoreLocation=''
        [string]$myBakupFilePaths=''
        [string]$myStopAt=''
        [string]$myRestoreType=switch ($BackupType) {
            'D'{'RESTORE DATABASE'}
            'I'{'RESTORE DATABASE'}
            'L'{'RESTORE LOG'}
            Default {'RESTORE DATABASE'}
        }
        if (($this.RestoreTo) -and ($BackupType -eq 'L') -and ($this.DestinationRestoreMode -eq [DatabaseRecoveryMode]::RECOVERY)) {$myStopAt=", STOPAT = '" + ($this.RestoreTo).ToString() + "' "}
        if ($BackupType -eq 'D') {$myRestoreLocation = ', ' + $RestoreLocation} else {$myRestoreLocation=''}
        $myBakupFilePaths="DISK = '" + $MergedPaths.Replace($PathDelimiter,"', DISK ='") + "'"
        $myAnswer = $myRestoreType + ' [' + $DatabaseName + '] FROM ' + $myBakupFilePaths + ' WITH File = ' + $Position.ToString() + $myRestoreLocation + $myStopAt + ', NORECOVERY, STATS=5;'
        return $myAnswer
    }
    [void] ShipAllUserDatabases([string]$DestinationPrefix,[string[]]$ExcludedList){  #Ship all sql instance user databases (except/exclude some ones) from source to destination
        Write-Verbose ('ShipAllUserDatabases with ' + $DestinationPrefix + ' Prefix')
        $this.LogWriter.Write($this.LogStaticMessage+('ShipAllUserDatabases with ' + $DestinationPrefix + ' Prefix'),[LogType]::INF)
        [string]$myExludedDB=''
        [string]$myDestinationDB=$null
        [string]$myOriginalLogFilePath=$null

        $myOriginalLogFilePath=$this.LogWriter.LogFilePathPattern
        if ($null -ne $ExcludedList){
            foreach ($myExceptedDB in $ExcludedList){
                $myExludedDB+=",'" + $myExceptedDB.Trim() + "'"
            }
        }
        if ($null -eq $DestinationPrefix){$DestinationPrefix=''}
        [string]$myCommand="
            SELECT [name] AS [DbName] FROM sys.databases WHERE [state]=0 AND [name] NOT IN ('master','msdb','model','tempdb','SSISDB','DWConfiguration','DWDiagnostics','DWQueue','SqlDeep','distribution'"+$myExludedDB+") ORDER BY [name]
            "
        try{
            $myRecord=Invoke-Sqlcmd -ConnectionString $this.SourceInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
            if ($null -ne $myRecord) {
                foreach ($mySourceDB in $myRecord){
                    $this.LogWriter.LogFilePath=$myOriginalLogFilePath
                    $myDestinationDB=$DestinationPrefix+$mySourceDB.DbName
                    $this.ShipDatabase(($mySourceDB.DbName),$myDestinationDB)
                }
            }
        }Catch{
            Write-Verbose(($_.ToString()).ToString())
        }
    }
    [void] ShipDatabases([string[]]$SourceDB,[string]$DestinationPrefix){   #Ship list of databases from source to destination
        Write-Verbose ('ShipDatabases('+ $SourceDB.Count.ToString() +') with ' + $DestinationPrefix + ' Prefix')
        [string]$myDestinationDB=$null
        [string]$myOriginalLogFilePath=$null

        $myOriginalLogFilePath=$this.LogWriter.LogFilePathPattern
        if ($null -eq $DestinationPrefix){$DestinationPrefix=''}
        if ($null -ne $SourceDB){
            foreach ($mySourceDB in $SourceDB){
                $this.LogWriter.LogFilePath=$myOriginalLogFilePath
                $myDestinationDB=$DestinationPrefix+$mySourceDB
                $this.ShipDatabase($mySourceDB,$myDestinationDB)
            }
        }
    }
    [void] ShipDatabase([string]$SourceDB,[string]$DestinationDB){  #Ship a databases from source to destination
        try {
            #--=======================Initial Log Modules
            Write-Verbose ('===== ShipDatabase ' + $SourceDB + ' as ' + $DestinationDB + ' started. =====')
            $this.LogStaticMessage= "{""SourceDB"":""" + $SourceDB + """,""DestinationDB"":""" + $DestinationDB+"""} : "
            $this.LogWriter.LogFilePath=$this.LogWriter.LogFilePath.Replace('{Database}',$DestinationDB)
            $this.LogWriter.Reinitialize()
            $this.LogWriter.Write($this.LogStaticMessage+'===== Shipping process started... ===== ', [LogType]::INF) 
            $this.LogWriter.Write($this.LogStaticMessage+('ShipDatabase ' + $SourceDB + ' as ' + $DestinationDB), [LogType]::INF) 
            $this.LogWriter.Write($this.LogStaticMessage+'Initializing EventsTable.Create.', [LogType]::INF) 

            #--=======================Set constants
            [string]$myDelimiter=','
            [decimal]$myLatestLSN=0
            [decimal]$myDiffBackupBaseLsn=0
            [string]$myKnownRecoveryFork=''
            [string]$myCurrentMachineName=([Environment]::MachineName).ToUpper()
            [string]$mySourceBackupMachineName=$null
            [string]$mySourceBackupFilePath=$null
            $myMediaSetHashTable=@{}
            $this.FileRepositoryUncPath=Clear-FolderPath -FolderPath ($this.FileRepositoryUncPath)

            #--=======================Validate input parameters
            if ($SourceDB.Trim().Length -eq 0) {
                $this.LogWriter.Write($this.LogStaticMessage+'Source SourceDB is empty.',[LogType]::INF)
                throw ($this.LogStaticMessage+'Source SourceDB is empty.')
            }
            if ($null -eq $DestinationDB -or $DestinationDB.Trim().Length -eq 0) {
                $this.LogWriter.Write($this.LogStaticMessage+'DestinationDB is empty, SourceDB name is used as DestinationDB name.',[LogType]::WRN)
                $DestinationDB=$SourceDB
            }

            #--=======================Check source connectivity
            $this.LogWriter.Write($this.LogStaticMessage+('Check Source Instance Connectivity of ' + $this.SourceInstanceConnectionString),[LogType]::INF)
            if ($this.Instance_ConnectivityTest($this.SourceInstanceConnectionString,$SourceDB) -eq $false) {
                $this.LogWriter.Write($this.LogStaticMessage+'Source Instance Connection failure.',[LogType]::ERR)
                throw ($this.LogStaticMessage+'Source Instance Connection failure.')
            }

            #--=======================Check destination connectivity
            $this.LogWriter.Write($this.LogStaticMessage+('Check Destination Instance Connectivity of ' + $this.DestinationInstanceConnectionString),[LogType]::INF)
            if ($this.Instance_ConnectivityTest($this.DestinationInstanceConnectionString,'master') -eq $false) {
                $this.LogWriter.Write($this.LogStaticMessage+'Destination Instance Connection failure.',[LogType]::ERR)
                throw ($this.LogStaticMessage+'Destination Instance Connection failure.')
            } 

            #--=======================Check destination db existance status
            $this.LogWriter.Write($this.LogStaticMessage+('Check Destination DB existance for ' + $DestinationDB),[LogType]::INF)
            $myDestinationDbStatus=[DestinationDbStatus]::Unknown
            $myDestinationDbStatus=[DestinationDbStatus]($this.Database_GetDatabaseStatus($this.DestinationInstanceConnectionString,$DestinationDB))
            $this.LogWriter.Write($this.LogStaticMessage+('Destination DB status is ' + $myDestinationDbStatus),[LogType]::INF)
            If (($myDestinationDbStatus -eq [DestinationDbStatus]::Online) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::NotExist) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::Restoring)){
                $this.LogWriter.Write($this.LogStaticMessage+('Destination DB status is ' + $myDestinationDbStatus),[LogType]::INF)
            }else{
                $this.LogWriter.Write($this.LogStaticMessage+('Destination database status is not allowd for processing, Destination DB status is ' + $myDestinationDbStatus),[LogType]::ERR)
                throw ($this.LogStaticMessage+'Destination database status is not allowd for processing, Destination DB status is ' + $myDestinationDbStatus)
            }

            #--=======================Get DB Backup file combinations
            If (($myDestinationDbStatus -eq [DestinationDbStatus]::Online) -or ($myDestinationDbStatus -eq [DestinationDbStatus]::NotExist)){
                $this.LogWriter.Write($this.LogStaticMessage+('Get DB Backup file combinations, for: ' + $DestinationDB),[LogType]::INF)
                $myLatestLSN=[decimal]0
                $myDiffBackupBaseLsn=[decimal]0
                $myKnownRecoveryFork=[string]''
            }elseif ($myDestinationDbStatus -eq [DestinationDbStatus]::Restoring) {
                $this.LogWriter.Write($this.LogStaticMessage+('Get DB Backup file combinations, for: ' + $DestinationDB),[LogType]::INF)
                $myLsnAnswers=$this.Database_GetDatabaseLSN($this.DestinationInstanceConnectionString,$DestinationDB)
                $myLatestLSN=$myLsnAnswers.LastLsn
                $myDiffBackupBaseLsn=$myLsnAnswers.DiffBackupBaseLsn
                $myKnownRecoveryFork=$myLsnAnswers.KnownRecoveryFork
            }
            $this.LogWriter.Write($this.LogStaticMessage+('Latest LSN is: ' + $myLatestLSN.ToString()),[LogType]::INF)
            $this.LogWriter.Write($this.LogStaticMessage+('DiffBackupBaseLsn is: ' + $myDiffBackupBaseLsn.ToString()),[LogType]::INF)
            $this.LogWriter.Write($this.LogStaticMessage+('KnownRecoveryFork is: ' + $myKnownRecoveryFork.ToString()),[LogType]::INF)

            [BackupFile[]]$myBackupFileList=$null
            $myBackupFileList=$this.Database_GetBackupFileList($this.SourceInstanceConnectionString,$SourceDB,$myLatestLSN,$myDiffBackupBaseLsn,$myKnownRecoveryFork)
            if ($null -eq $myBackupFileList -or $myBackupFileList.Count -eq 0) {
                $myRestoreStrategy = [RestoreStrategy]::NotExist
                $this.LogWriter.Write($this.LogStaticMessage+'There is nothing(no files) to restore.',[LogType]::WRN)
                return
                #throw ($this.LogStaticMessage+'There is nothing(no files) to restore.')
            } else {
                $myRestoreStrategy=[RestoreStrategy]($myBackupFileList[0].StrategyNo)
                $this.BackupFileList+=$myBackupFileList     #Populate all usable backup file list for all shipped databases for module cunsumer users, This property should not be used for producation usage inside this module because it's writeable for outsiders
            }
            $this.LogWriter.Write($this.LogStaticMessage+('Selected strategy is: ' + $myRestoreStrategy),[LogType]::INF)

            #--=======================Copy DB Backup files to FileRepositoryPath
            $this.LogWriter.Write($this.LogStaticMessage+'Check Writeable FileRepositoryPath.',[LogType]::INF)
            if ($this.Path_IsWritable($this.FileRepositoryUncPath) -eq $false) {
                $this.LogWriter.Write($this.LogStaticMessage+'FileRepositoryPath is not accesible.',[LogType]::ERR)
                throw ($this.LogStaticMessage+'FileRepositoryPath is not accesible.')
            }

            $myCurrentMachineName=([Environment]::MachineName).ToUpper()
            $mySourceBackupMachineName = $this.Database_GetServerName($this.SourceInstanceConnectionString).ToUpper()
            foreach ($myBackupFile in $myBackupFileList){
                $myMediaSetHashTable[$myBackupFile.FilePath]+=1  #Count number of files transferred for each mediasetid (this variable is useful for preventing multiple backup file copy)
                if ($myMediaSetHashTable[$myBackupFile.FilePath] -eq 1) { #Copy only untransfeered file (in case of one backup file for multiple backupsets)
                    if ($myCurrentMachineName -eq $mySourceBackupMachineName) {     #Decide to use local path of source server backup file(s) or UNC path of backup file(s)
                        $mySourceBackupFilePath=$myBackupFile.FilePath
                    } else {
                        $mySourceBackupFilePath=$myBackupFile.RemoteSourceFilePath
                    }
                    Copy-Item -Path $mySourceBackupFilePath -Destination ($this.FileRepositoryUncPath) -Force -ErrorAction Stop
                    $this.LogWriter.Write($this.LogStaticMessage+('Copy backup file from ' + $mySourceBackupFilePath + ' to ' + ($this.FileRepositoryUncPath)),[LogType]::INF)
                }
            }

            #--=======================Drop not in restoring mode databases
            If ($myDestinationDbStatus -eq [DestinationDbStatus]::Online -or $myRestoreStrategy -eq [RestoreStrategy]::FullDiffLog -or $myRestoreStrategy -eq [RestoreStrategy]::FullLog){
                $this.LogWriter.Write($this.LogStaticMessage+('Drop Database : ' + $DestinationDB),[LogType]::INF)

                $myExistedDestinationDbDropped=$this.Database_DropDatabase($this.DestinationInstanceConnectionString,$DestinationDB)
                if ($myExistedDestinationDbDropped -eq $false) {
                    $this.LogWriter.Write($this.LogStaticMessage+('Could not drop destination database: ' + $DestinationDB),[LogType]::ERR)
                    throw ($this.LogStaticMessage+'Could not drop destination database: ' + $DestinationDB)
                }
            }

            #--=======================Get destination file locations
            $this.LogWriter.Write($this.LogStaticMessage+('Get destination folder locations of: ' + ($this.DestinationInstanceConnectionString)),[LogType]::INF)
            $myDefaultDestinationDataFolderLocation=$this.Database_GetDefaultDbFolderLocations($this.DestinationInstanceConnectionString,[DatabaseFileType]::DATA)
            $myDefaultDestinationLogFolderLocation=$this.Database_GetDefaultDbFolderLocations($this.DestinationInstanceConnectionString,[DatabaseFileType]::LOG)
            #Assign user locations if available
            if ($null -ne $this.DataFolderRestoreLoation -and $this.DataFolderRestoreLoation.Trim().Length -gt 0 -and $this.DataFolderRestoreLoation.ToUpper() -ne 'DEFAULT') {
                $myDefaultDestinationDataFolderLocation=$this.DataFolderRestoreLoation
            }
            if ($null -ne $this.LogFolderRestoreLoation -and $this.LogFolderRestoreLoation.Trim().Length -gt 0 -and $this.LogFolderRestoreLoation.ToUpper() -ne 'DEFAULT') {
                $myDefaultDestinationLogFolderLocation=$this.LogFolderRestoreLoation
            }

            #Check having location path
            If ($null -eq $myDefaultDestinationDataFolderLocation){
                $this.LogWriter.Write($this.LogStaticMessage+('Default Data folder location is empty on: ' + $this.DestinationInstanceConnectionString),[LogType]::ERR)
                throw ($this.LogStaticMessage+'Default Data folder location is empty on: ' + $this.DestinationInstanceConnectionString)
            }
            If ($null -eq $myDefaultDestinationLogFolderLocation){
                $this.LogWriter.Write($this.LogStaticMessage+('Default Log folder location is empty on: ' + $this.DestinationInstanceConnectionString),[LogType]::ERR)
                throw ($this.LogStaticMessage+'Default Log folder location is empty on: ' + $this.DestinationInstanceConnectionString)
            }

            #Make sure location paths ending with \ character
            $myDefaultDestinationDataFolderLocation=(Clear-FolderPath -FolderPath $myDefaultDestinationDataFolderLocation)+'\'
            $myDefaultDestinationLogFolderLocation=(Clear-FolderPath -FolderPath $myDefaultDestinationLogFolderLocation)+'\'

            $this.LogWriter.Write($this.LogStaticMessage+'Calculate RestoreLocation Folder',[LogType]::INF)
            if ($this.RestoreFilesToIndividualFolders) {
                $myDefaultDestinationDataFolderLocation += $DestinationDB.Replace(' ','_') + '\'
                $myDefaultDestinationLogFolderLocation += $DestinationDB.Replace(' ','_') + '\'
            }

            $this.LogWriter.Write($this.LogStaticMessage+('Data file RestoreLocation folder is ' + $myDefaultDestinationDataFolderLocation),[LogType]::INF)
            $this.LogWriter.Write($this.LogStaticMessage+('Log file RestoreLocation folder is ' + $myDefaultDestinationLogFolderLocation),[LogType]::INF)

            $this.LogWriter.Write($this.LogStaticMessage+'Create RestoreLocation folders, if not exists.',[LogType]::INF)
            $this.Database_CreateFolder($this.DestinationInstanceConnectionString,$myDefaultDestinationDataFolderLocation)
            $this.Database_CreateFolder($this.DestinationInstanceConnectionString,$myDefaultDestinationLogFolderLocation)

            $this.LogWriter.Write($this.LogStaticMessage+'Generate RestoreLocation',[LogType]::INF)
            [int]$myMediasetId=$myBackupFileList[0].MediaSetId
            [string]$myMediasetMergedPath=$myBackupFileList | Where-Object -Property MediaSetId -EQ $myMediasetId | Group-Object -Property MediaSetId,Position | ForEach-Object{$this.BackupFileList_MergeBackupFilePath($_.Group,$myDelimiter)}
            [string]$myRestoreLocation = $this.BackupFileList_GenerateDestinationDatabaseFilesLocationFromBackupFile($this.DestinationInstanceConnectionString,$DestinationDB,$myMediasetMergedPath,$myDelimiter,$myDefaultDestinationDataFolderLocation,$myDefaultDestinationLogFolderLocation)
            if ($null -eq $myRestoreLocation -or $myRestoreLocation.Length -eq 0) {
                $this.LogWriter.Write($this.LogStaticMessage+'Can not get Restore location.',[LogType]::ERR)
                throw ($this.LogStaticMessage+'Can not get Restore location.')
            }else{
                $this.LogWriter.Write($this.LogStaticMessage+('Restore Location is: ' + $myRestoreLocation),[LogType]::INF)
            }

            #--=======================Restoring backup(s) in destination
            $this.LogWriter.Write($this.LogStaticMessage+'Generate RestoreList',[LogType]::INF)
            $myRestoreList=$myBackupFileList | Group-Object -Property MediaSetId,Position | ForEach-Object{[PSCustomObject]@{
                MediaSetId=$_.Name.Split(',')[0]; 
                Order=($_.Group | Sort-Object ID | Select-Object -Last 1 -Property ID).ID;
                RestoreCommand=$($this.BackupFileList_GenerateRestoreBackupCommand($DestinationDB,(($_.Group | Select-Object -Last 1 -Property BackupType).BackupType),($_.Name.Split(',')[1]),($this.BackupFileList_MergeBackupFilePath($_.Group,$myDelimiter)),$myDelimiter,$myRestoreLocation));
            }}

            $this.LogWriter.Write($this.LogStaticMessage+'Run Restore Commands',[LogType]::INF)
            If ($null -ne $myRestoreList){
                try{
                    $myRestoreList | ForEach-Object{
                                                        $this.LogWriter.Write($this.LogStaticMessage+('Restore Command:' + $_.RestoreCommand),[LogType]::INF);
                                                        try{
                                                            Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString -Query ($_.RestoreCommand) -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
                                                        }catch{
                                                            if ($_.ToString() -like "*Msg 4326, Level 16, State 1*" -or $_.ToString() -like "*is too early*") {     #log file is too early
                                                                $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(),[LogType]::WRN)
                                                            }else{
                                                                $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(),[LogType]::ERR)
                                                                throw
                                                            }
                                                        }
                                                    }
                }Catch{
                    $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(),[LogType]::ERR)
                    throw
                }
            }else{
                $this.LogWriter.Write($this.LogStaticMessage+'There is no commands to execute.',[LogType]::WRN)
            }

            #--=======================Remove copied files
            $this.LogWriter.Write($this.LogStaticMessage+'Remove copied files.',[LogType]::INF)
            $myBackupFileList | Select-Object -Unique -Property RemoteRepositoryUncFilePath | ForEach-Object{Remove-Item -Path ($_.RemoteRepositoryUncFilePath); $this.LogWriter.Write($this.LogStaticMessage+('Remove file ' + $_.RemoteRepositoryUncFilePath),[LogType]::INF)}

            #--=======================SetDestinationDBMode
            $this.LogWriter.Write($this.LogStaticMessage+('Set destination database mode to ' + $this.DestinationRestoreMode),[LogType]::INF)
            if ($this.DestinationRestoreMode -eq [DatabaseRecoveryMode]::RECOVERY) {
                $myRecoveryStatus=$this.Database_RecoverDatabase($this.DestinationInstanceConnectionString,$DestinationDB)
                if ($myRecoveryStatus -eq $false) {
                    $this.LogWriter.Write($this.LogStaticMessage+('Database ' + $DestinationDB + ' does not exists or could not be recovered.'),[LogType]::INF)
                }
            }
        }catch{
            Write-Error ($_.ToString())
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }finally{
            [string]$myLastBackupFilePath=''
            [string]$myLastBackupStartTime=''
            Write-Verbose ('===== ShipDatabase ' + $SourceDB + ' as ' + $DestinationDB + ' finished. =====')
            $this.LogWriter.Write($this.LogStaticMessage+('ShipDatabase ' + $SourceDB + ' as ' + $DestinationDB + ' finished.'), [LogType]::INF) 
            if ($null -ne $myBackupFileList -and $myBackupFileList.Count -ne 0) {
                    $myLastBackupFilePath=$myBackupFileList[-1].FilePath 
                    $myLastBackupStartTime=$myBackupFileList[-1].BackupStartTime.ToString()
                }

            if ($this.LogWriter.ErrCount -eq 0 -and $this.LogWriter.WrnCount -eq 0) {
                $this.LogWriter.Write($this.LogStaticMessage+'Finished.',[LogType]::INF)
                $this.LogWriter.Write($this.LogStaticMessage+('ProceessInfo->SourceDB:' + $SourceDB + ',DestinationDB:' + $DestinationDB + ',LatestRestoredFile:' + $myLastBackupFilePath + ',LatestRestoreFileTime:' + $myLastBackupStartTime), [LogType]::INF) 
            }elseif ($this.LogWriter.ErrCount -eq 0 -and $this.LogWriter.WrnCount -gt 0) {
                $this.LogWriter.Write($this.LogStaticMessage+('Finished with ' + $this.LogWriter.WrnCount.ToString() + ' Warning(s).'),[LogType]::WRN)
                $this.LogWriter.Write($this.LogStaticMessage+('ProceessInfo->SourceDB:' + $SourceDB + ',DestinationDB:' + $DestinationDB + ',LatestRestoredFile:' + $myLastBackupFilePath + ',LatestRestoreFileTime:' + $myLastBackupStartTime), [LogType]::INF) 
            }else{
                $this.LogWriter.Write($this.LogStaticMessage+('Finished with ' + $this.LogWriter.ErrCount.ToString() + ' Error(s) and ' + $this.LogWriter.WrnCount.ToString() + ' Warning(s).'),[LogType]::ERR)
                $this.LogWriter.Write($this.LogStaticMessage+('ProceessInfo->SourceDB:' + $SourceDB + ',DestinationDB:' + $DestinationDB + ',LatestRestoredFile:ERROR,LatestRestoreFileTime:ERROR'), [LogType]::INF) 
            }
            $this.LogWriter.Write($this.LogStaticMessage+'===== Shipping process finished. ===== ', [LogType]::INF) 
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
        [Parameter(Mandatory=$false)][int]$LimitMsdbScanToRecentHours=(31*24),
        [Parameter(Mandatory=$false)][switch]$RestoreFilesToIndividualFolders,
        [Parameter(Mandatory=$false)][DatabaseRecoveryMode]$DestinationRestoreMode=[DatabaseRecoveryMode]::RESTOREONLY,
        [Parameter(Mandatory=$true)][LogWriter]$LogWriter
    )
    Write-Verbose 'Creating New-DatabaseShipping'
    [string]$mySourceInstanceConnectionString=$SourceInstanceConnectionString
    [string]$myDestinationInstanceConnectionString=$DestinationInstanceConnectionString
    [string]$myFileRepositoryUncPath=$FileRepositoryUncPath
    [int]$myLimitMsdbScanToRecentHours=$LimitMsdbScanToRecentHours
    [bool]$myRestoreFilesToIndividualFolders=$RestoreFilesToIndividualFolders
    [DatabaseRecoveryMode]$myDestinationRestoreMode=$DestinationRestoreMode
    [LogWriter]$myLogWriter=$LogWriter
    [DatabaseShipping]::New($mySourceInstanceConnectionString,$myDestinationInstanceConnectionString,$myFileRepositoryUncPath,$myLimitMsdbScanToRecentHours,$myRestoreFilesToIndividualFolders,$myDestinationRestoreMode,$myLogWriter)
    Write-Verbose 'New-DatabaseShipping Created'
}
#endregion

#region Export
Export-ModuleMember -Function New-DatabaseShipping
#endregion

# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCJwZzPyNDHRe5z
# G+hbNMI79J00kiyldsPxRsxsLOLMEqCCFhswggMUMIIB/KADAgECAhAT2c9S4U98
# jEh2eqrtOGKiMA0GCSqGSIb3DQEBBQUAMBYxFDASBgNVBAMMC3NxbGRlZXAuY29t
# MB4XDTI0MTAyMzEyMjAwMloXDTI2MTAyMzEyMzAwMlowFjEUMBIGA1UEAwwLc3Fs
# ZGVlcC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDivSzgGDqW
# woiD7OBa8twT0nzHGNakwZtEzvq3HcL8bCgfDdp/0kpzoS6IKpjt2pyr0xGcXnTL
# SvEtJ70XOgn179a1TlaRUly+ibuUfO15inrwPf1a6fqgvPMoXV6bMxpsbmx9vS6C
# UBYO14GUN10GtlQgpUYY1N0czabC7yXfo8EwkO1ZTGoXADinHBF0poKffnR0EX5B
# iL7/WGRfT3JgFZ8twYMoKOc4hJ+GZbudtAptvnWzAdiWM8UfwQwcH8SJQ7n5whPO
# PV8e+aICbmgf9j8NcVAKUKqBiGLmEhKKjGKaUow53cTsshtGCndv5dnMgE2ppkxh
# aWNn8qRqYdQFAgMBAAGjXjBcMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggr
# BgEFBQcDAzAWBgNVHREEDzANggtzcWxkZWVwLmNvbTAdBgNVHQ4EFgQUwoHZNhYd
# VvtzY5g9WlOViG86b8EwDQYJKoZIhvcNAQEFBQADggEBAAvLzZ9wWrupREYXkcex
# oLBwbxjIHueaxluMmJs4MSvfyLG7mzjvkskf2AxfaMnWr//W+0KLhxZ0+itc/B4F
# Ep4cLCZynBWa+iSCc8iCF0DczTjU1exG0mUff82e7c5mXs3oi6aOPRyy3XBjZqZd
# YE1HWl9GYhboC5kY65Z42ZsbNyPOM8nhJNzBKq9V6eyNE2JnxlrQ1v19lxXOm6WW
# Hgnh++tUf9k8DI1D7Da3bQqsj8O+ACHjhjMVzWKqAtnDxydaOOjRhKWIlHUQ7fLW
# GYFZW2JXnogqxFR2tzdpZxsNgD4vHFzt1CspiHzhIsMwfQFxIg44Ny/U96l2aVpR
# 6lUwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUA
# MGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsT
# EHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQg
# Um9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNV
# BAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdp
# Y2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqcl
# LskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YF
# PFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu34LzB4TmdDttceIt
# DBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0QF+xembud8hIqGZX
# V59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1
# ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2Tox
# RJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdp
# ekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF
# 30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9
# t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQ
# UOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXk
# aS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1Ud
# DgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEt
# UYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAw
# DQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX979XB72arKGHLOyF
# XqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offyct4kvFIDyE7QKt76
# LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8L
# punyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2
# CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si
# /xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQwggauMIIElqADAgEC
# AhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMjAzMjMw
# MDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0
# MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE8pE3qZdRodbSg9GeTKJtoLDMg/la
# 9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBMLJnOWbfhXqAJ9/UO0hNoR8XOxs+4r
# gISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU5ygt69OxtXXnHwZljZQp09nsad/Z
# kIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLydkf3YYMZ3V+0VAshaG43IbtArF+y
# 3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFkdECnwHLFuk4fsbVYTXn+149zk6ws
# OeKlSNbwsDETqVcplicu9Yemj052FVUmcJgmf6AaRyBD40NjgHt1biclkJg6OBGz
# 9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9abJTyUpURK1h0QCirc0PO30qhHGs4
# xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwYSH8UNM/STKvvmz3+DrhkKvp1KCRB
# 7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80VgvCONWPfcYd6T/jnA+bIwpUzX6ZhK
# WD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5FBASA31fI7tk42PgpuE+9sJ0sj8e
# CXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9Rp6103a50g5rmQzSM7TNsQIDAQAB
# o4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUuhbZbU2FL3Mp
# dpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYD
# VR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGsw
# aTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUF
# BzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# Um9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeB
# DAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAH1ZjsCTtm+YqUQi
# AX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp+3CKDaopafxpwc8dB+k+YMjYC+Vc
# W9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9qVbPFXONASIlzpVpP0d3+3J0FNf/
# q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8ZCaHbJK9nXzQcAp876i8dU+6Wvep
# ELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6ZJxurJB4mwbfeKuv2nrF5mYGjVoar
# CkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnEtp/Nh4cku0+jSbl3ZpHxcpzpSwJS
# pzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fxZsNBzU+2QJshIUDQtxMkzdwdeDrk
# nq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV77QpfMzmHQXh6OOmc4d0j/R0o08f5
# 6PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT1ObyF5lZynDwN7+YAN8gFk8n+2Bn
# FqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkPCr2B2RP+v6TR81fZvAT6gt4y3wSJ
# 8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvmfxqkhQ/8mJb2VVQrH4D6wPIOK+XW
# +6kvRBVK5xMOHds3OBqhK/bt1nz8MIIGvDCCBKSgAwIBAgIQC65mvFq6f5WHxvnp
# BOMzBDANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGln
# aUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5
# NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTI0MDkyNjAwMDAwMFoXDTM1MTEy
# NTIzNTk1OVowQjELMAkGA1UEBhMCVVMxETAPBgNVBAoTCERpZ2lDZXJ0MSAwHgYD
# VQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQAD
# ggIPADCCAgoCggIBAL5qc5/2lSGrljC6W23mWaO16P2RHxjEiDtqmeOlwf0KMCBD
# Er4IxHRGd7+L660x5XltSVhhK64zi9CeC9B6lUdXM0s71EOcRe8+CEJp+3R2O8oo
# 76EO7o5tLuslxdr9Qq82aKcpA9O//X6QE+AcaU/byaCagLD/GLoUb35SfWHh43rO
# H3bpLEx7pZ7avVnpUVmPvkxT8c2a2yC0WMp8hMu60tZR0ChaV76Nhnj37DEYTX9R
# eNZ8hIOYe4jl7/r419CvEYVIrH6sN00yx49boUuumF9i2T8UuKGn9966fR5X6kgX
# j3o5WHhHVO+NBikDO0mlUh902wS/Eeh8F/UFaRp1z5SnROHwSJ+QQRZ1fisD8UTV
# DSupWJNstVkiqLq+ISTdEjJKGjVfIcsgA4l9cbk8Smlzddh4EfvFrpVNnes4c16J
# idj5XiPVdsn5n10jxmGpxoMc6iPkoaDhi6JjHd5ibfdp5uzIXp4P0wXkgNs+CO/C
# acBqU0R4k+8h6gYldp4FCMgrXdKWfM4N0u25OEAuEa3JyidxW48jwBqIJqImd93N
# Rxvd1aepSeNeREXAu2xUDEW8aqzFQDYmr9ZONuc2MhTMizchNULpUEoA6Vva7b1X
# CB+1rxvbKmLqfY/M/SdV6mwWTyeVy5Z/JkvMFpnQy5wR14GJcv6dQ4aEKOX5AgMB
# AAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNVHSUB
# Af8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1s
# BwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxqII+eyG8wHQYDVR0OBBYEFJ9X
# LAN3DigVkGalY17uT5IfdqBbMFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZUaW1l
# U3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGDMIGAMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYBBQUHMAKGTGh0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFJTQTQwOTZTSEEyNTZU
# aW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQELBQADggIBAD2tHh92mVvjOIQS
# R9lDkfYR25tOCB3RKE/P09x7gUsmXqt40ouRl3lj+8QioVYq3igpwrPvBmZdrlWB
# b0HvqT00nFSXgmUrDKNSQqGTdpjHsPy+LaalTW0qVjvUBhcHzBMutB6HzeledbDC
# zFzUy34VarPnvIWrqVogK0qM8gJhh/+qDEAIdO/KkYesLyTVOoJ4eTq7gj9UFAL1
# UruJKlTnCVaM2UeUUW/8z3fvjxhN6hdT98Vr2FYlCS7Mbb4Hv5swO+aAXxWUm3Wp
# ByXtgVQxiBlTVYzqfLDbe9PpBKDBfk+rabTFDZXoUke7zPgtd7/fvWTlCs30VAGE
# sshJmLbJ6ZbQ/xll/HjO9JbNVekBv2Tgem+mLptR7yIrpaidRJXrI+UzB6vAlk/8
# a1u7cIqV0yef4uaZFORNekUgQHTqddmsPCEIYQP7xGxZBIhdmm4bhYsVA6G2WgNF
# YagLDBzpmk9104WQzYuVNsxyoVLObhx3RugaEGru+SojW4dHPoWrUhftNpFC5H7Q
# EY7MhKRyrBe7ucykW7eaCuWBsBb4HOKRFVDcrZgdwaSIqMDiCLg4D+TPVgKx2EgE
# deoHNHT9l3ZDBD+XgbF+23/zBjeCtxz+dL/9NWR6P2eZRi7zcEO1xwcdcqJsyz/J
# ceENc2Sg8h3KeFUCS7tpFk7CrDqkMYIFADCCBPwCAQEwKjAWMRQwEgYDVQQDDAtz
# cWxkZWVwLmNvbQIQE9nPUuFPfIxIdnqq7ThiojANBglghkgBZQMEAgEFAKCBhDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEi
# BCDj0jHwO0bGySM4sZ5wgus8Amkhqn0WiG/OQTdlzJqO6TANBgkqhkiG9w0BAQEF
# AASCAQAEIRnwN61oShjY31/TXbZuSgRKhGsujRCRGuRr491cumKO/DUZQydf/t0R
# coKad+OLeOaYnbB3Ge0bAq+WJIdGlRdCTJxop2erszGstBYTOkz3Gej3Of/k5LkA
# RzqMigVbHe/zp0BoLvBH8BkbT+emeXjZVy5skYcOlbpGjozhQzFHJJaVY6RVkp49
# TNkFAJQWrPE5FfADVHmEnEH+qOhLt9rZmdy0Rrey6a6MQNajvsQR4Y6v/Rx4MyvF
# l58vIUyZ5mi1oX37rC4gx64m1hLaqiD8KQJsjJ4DgwvI4M4zwQ6AFQ2iRcpzuHfT
# BYPnnVsJeNYL+/HJwTD2opl86UTtoYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTEwMzA1
# MTExNlowLwYJKoZIhvcNAQkEMSIEIKeBKqlWhwQvYhKHwQG7TFrMDTSDK913gO7Q
# K5l7ZL1GMA0GCSqGSIb3DQEBAQUABIICACQyIxNbIMu1Tp6zoCg508tGzBY57qlf
# YKT70dek8qYOqSvXCi+HQ1i/ZtzHfsv1YBG8RW51iDLBIS2/teYr13nHDM1JTnMF
# JK1LVPPklzgoCXyyKNBOQ8pOGP36VrdmKh8k29ZW+7dR2aNLuIkMC5IVKSmXu+b1
# y6vo/Hbuv3nBPeGkFacQBC2Y+ZMlPd06uZceVcPnf+a1TSoUHUKgK+20Ha9Lk5jZ
# LJ/5QtNaAHUezGL3qcyclG12y8d7fPF0/WPEZ4gdQdUUUnrBmMKUm+QcTWxXuBFk
# U8IgLpMtHdEkY/dA39IN7sSkoybg0SjDdV8vdL/J4E6kHqFItDKq2N7rxzFQaZ3u
# DWBJDNYqNMU4GJQG5DHcQ9BAT5OajikrEkNMqjNKZp8jk8AzKWrY+JtgtUr/BFay
# szsnQSEQCV6LZVngs443Jl8vifyMfzMF/yIz9zL7ulCTIhd5QM1P5UtSleiYgfHN
# NrnngRFaaPdTjsXl5RA+3H2TIXPYteR/gf6RlXNU6KqY+h4cRXu9PTBQtCrei3It
# wyO4qmb4nUMGD77TFMqlSYvM3TsU9mvUN9rBzy1n4qDlyqNMXt80zqfip96gEIZe
# TWIryLWaCVrFB/nrqW4y2OtwH3hr7CtJF23dknFxlMEeZDDoYSAAVGMpn2vvbzjx
# imTz87cm2dzi
# SIG # End signature block
