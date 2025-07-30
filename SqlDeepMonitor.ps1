function ConfigureSqlServerMonitoringObjects{
    [OutputType([bool])]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input connection string")][ValidateNotNullOrEmpty()][string]$ConnectionString,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Extended events saving folder")][ValidateNotNullOrEmpty()][string]$SaveToFolder
    )
    begin {
        [bool]$myAnswer=$true;
        [string]$myQuery=$null;
        try{
            if ($SaveToFolder.EndsWith('\')) {
                $SaveToFolder=$SaveToFolder.Substring(0,$SaveToFolder.Length-1)
            }
            if (!(Test-Path -PathType Container -Path $SaveToFolder)){
                New-Item -ItemType Directory -Force -Path $SaveToFolder
                if (!(Test-Path -PathType Container -Path $SaveToFolder)){
                    Write-Error($SaveToFolder + ' not found');
                    $myAnswer=$false;
                }
            }
        } catch {
            Write-Error($_.ToString());
            $myAnswer=$false;
        }
    }
    process {
        if ($myAnswer -eq $true) {
            try{
                Write-Host 'Creating Blocking XE.'
                $myQuery="
                    USE [master];
                    EXEC sp_configure 'show advanced option', '1';
                    RECONFIGURE;
                    EXEC sp_configure 'blocked process threshold', 5;
                    RECONFIGURE;
                    
                    IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_event_sessions] AS myAllXe WHERE [myAllXe].[name]='SqlDeep_Capture_Blocking')
                    BEGIN
                        CREATE EVENT SESSION [SqlDeep_Capture_Blocking] ON SERVER 
                        ADD EVENT sqlserver.blocked_process_report
                        ADD TARGET package0.event_file(SET filename=N'"+$SaveToFolder+"\SqlDeep_Capture_Blocking.xel')
                        WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=3 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_NODE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON)
                    END
                    IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_event_sessions] AS myAllXe INNER JOIN [master].[sys].[dm_xe_sessions] AS myAllRun ON [myAllXe].[name]=[myAllRun].[name] WHERE [myAllXe].[name]='SqlDeep_Capture_Blocking')
                        ALTER EVENT SESSION [SqlDeep_Capture_Blocking] ON SERVER STATE = START;
                "
                Invoke-SqlCommand -ConnectionString $ConnectionString -Command $myQuery
            } catch {
                Write-Error($_.ToString());
                $myAnswer=$false;
            }

            try{
                Write-Host 'Creating Deadlock XE.'
                $myQuery="
                    USE [master];
                    IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_event_sessions] AS myAllXe WHERE [myAllXe].[name]='SqlDeep_Capture_Deadlock')
                    BEGIN
                        CREATE EVENT SESSION [SqlDeep_Capture_Deadlock] ON SERVER 
                        ADD EVENT sqlserver.xml_deadlock_report
                        ADD TARGET package0.event_file(SET filename=N'"+$SaveToFolder+"\SqlDeep_Capture_Deadlock.xel')
                        WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=3 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_NODE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON)
                    END
                    IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_event_sessions] AS myAllXe INNER JOIN [master].[sys].[dm_xe_sessions] AS myAllRun ON [myAllXe].[name]=[myAllRun].[name] WHERE [myAllXe].[name]='SqlDeep_Capture_Deadlock')
                        ALTER EVENT SESSION [SqlDeep_Capture_Deadlock] ON SERVER STATE = START;
                "
                Invoke-SqlCommand -ConnectionString $ConnectionString -Command $myQuery
            } catch {
                Write-Error($_.ToString());
                $myAnswer=$false;
            }

            try{
                Write-Host 'Creating Long running query XE.'
                $myQuery="
                    USE [master];
                    IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_event_sessions] AS myAllXe WHERE [myAllXe].[name]='SqlDeep_Capture_LongRunningQueries')
                    BEGIN
                        CREATE EVENT SESSION [SqlDeep_Capture_LongRunningQueries] ON SERVER 
                        ADD EVENT sqlserver.sql_statement_completed
                            (ACTION (sqlserver.client_app_name, sqlserver.client_hostname,sqlserver.database_id, sqlserver.session_nt_username,sqlserver.session_id, sqlserver.sql_text,sqlserver.plan_handle)
                            WHERE (
                                    duration > 2000000	--2000 milliseconds in microseconds
                                    AND sql_text NOT LIKE 'WAITFOR (RECEIVE message_body FROM WMIEventProviderNotificationQueue)%' /* Exclude WMI waits */
                                    )
                            )
                        ADD TARGET package0.event_file(SET filename=N'"+$SaveToFolder+"\SqlDeep_Capture_LongRunningQueries.xel')
                        WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=3 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_NODE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON)
                    END
                    IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_event_sessions] AS myAllXe INNER JOIN [master].[sys].[dm_xe_sessions] AS myAllRun ON [myAllXe].[name]=[myAllRun].[name] WHERE [myAllXe].[name]='SqlDeep_Capture_LongRunningQueries')
                        ALTER EVENT SESSION [SqlDeep_Capture_LongRunningQueries] ON SERVER STATE = START;
                "
                Invoke-SqlCommand -ConnectionString $ConnectionString -Command $myQuery
            } catch {
                Write-Error($_.ToString());
                $myAnswer=$false;
            }

            try{
                Write-Host 'Creating SQL Injection XE.'
                $myQuery="
                    USE [master];
                    IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_event_sessions] AS myAllXe WHERE [myAllXe].[name]='SqlDeep_Capture_SqlInjection')
                    BEGIN
                        CREATE EVENT SESSION [SqlDeep_Capture_SqlInjection] ON SERVER 
                        ADD EVENT sqlserver.error_reported(
                            ACTION(sqlserver.client_app_name,sqlserver.client_connection_id,sqlserver.database_name,sqlserver.nt_username,sqlserver.sql_text,sqlserver.username)
                            WHERE ([error_number]=(102) OR [error_number]=(105) OR [error_number]=(205) OR ([error_number]=(207) OR [error_number]=(208) OR [error_number]=(245) OR [error_number]=(2812) OR [error_number]=(18456) OR [sqlserver].[like_i_sql_unicode_string]([message],N'%permission%') OR [sqlserver].[like_i_sql_unicode_string]([message],N'%denied%'))))
                        ADD TARGET package0.event_file(SET filename=N'U:\Databases\Audit\SqlDeep_Capture_SqlInjection.xel')
                        WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=PER_NODE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON)
                    END
                    IF NOT EXISTS (SELECT 1 FROM [master].[sys].[server_event_sessions] AS myAllXe INNER JOIN [master].[sys].[dm_xe_sessions] AS myAllRun ON [myAllXe].[name]=[myAllRun].[name] WHERE [myAllXe].[name]='SqlDeep_Capture_SqlInjection')
                        ALTER EVENT SESSION [SqlDeep_Capture_SqlInjection] ON SERVER STATE = START;
                "
                Invoke-SqlCommand -ConnectionString $ConnectionString -Command $myQuery
            } catch {
                Write-Error($_.ToString());
                $myAnswer=$false;
            }

            try{
                Write-Host 'Configuring Query Store.'
                $myQuery="
                    DECLARE @myCommand nvarchar(2000)
                    SET @myCommand=N'
                    USE [?];
                    DECLARE @myInstanceVersion INT;
                    SELECT @myInstanceVersion=CAST(LEFT(REPLACE(@@VERSION,''Microsoft SQL Server '',''''),4) AS INT);
                    IF @myInstanceVersion>=2016 AND LOWER(DB_NAME()) NOT IN (''master'',''model'',''msdb'',''tempdb'',''dwqueue'',''dwdiagnostics'',''dwconfiguration'',''ssisdb'',''sqldeep'')
                    BEGIN
                        IF NOT EXISTS(SELECT 1 FROM [sys].[database_query_store_options] WHERE [desired_state]=2 AND [actual_state]=2)
                        BEGIN
                            ALTER DATABASE CURRENT SET QUERY_STORE = ON;
                            ALTER DATABASE CURRENT SET QUERY_STORE (OPERATION_MODE = READ_WRITE, CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 3), MAX_STORAGE_SIZE_MB = 1024, MAX_PLANS_PER_QUERY = 100);
                        END
                    END
                    '
                    EXEC sp_MSforeachdb @myCommand
                "
                Invoke-SqlCommand -ConnectionString $ConnectionString -Command $myQuery
            } catch {
                Write-Error($_.ToString());
                $myAnswer=$false;
            }
        }
    }
    end {
        return $myAnswer
    }
 }

 function GetBlocking{
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input connection string")][ValidateNotNullOrEmpty()][string]$ConnectionString
    )
    begin{
        [string]$myQuery=$null;
        [string]$myXeName='SqlDeep_Capture_Blocking';
    }
    process{
        $myQuery="
            CREATE TABLE #myXeTable (RecordId BIGINT IDENTITY PRIMARY KEY, LogDate DATE, LogDateTime DATETIME,CategoryName NVARCHAR(60), event_data XML)
            DECLARE @myFromDate DATETIME;
            DECLARE @myToDate DATETIME;
            DECLARE @myXeName AS NVARCHAR(256);
            DECLARE @myXeFilePath AS NVARCHAR(256);
            DECLARE @myVersionString NVARCHAR(20);
            DECLARE @myServerVersion DECIMAL(10,5);
            DECLARE @mySqlServer2017Version DECIMAL(10,5);
            DECLARE @myLocalDateTime AS DATETIME;
            DECLARE @myUTCDateTime AS DATETIME;
            DECLARE @myLocalDiffToUTC INT;
            DECLARE @mySQLScript NVARCHAR(max);
            DECLARE @myParamDefinition nvarchar(500);
            DECLARE @myNewLine nvarchar(10);

            SET @myFromDate=NULL;
            SET @myToDate=NULL;
            SET @myXeName=LTRIM(RTRIM(N'"+$myXeName+"'));
            SET @myNewLine=CHAR(13)+CHAR(10);
            SET @myVersionString = CAST(SERVERPROPERTY('productversion') AS NVARCHAR(20));
            SET @myServerVersion = CAST(LEFT(@myVersionString,CHARINDEX('.', @myVersionString)) AS DECIMAL(10,5));
            SET @mySqlServer2017Version = 14.0 -- SQL Server 2017

            --Validate extended event name existance
            IF @myXeName IS NULL OR LEN(LTRIM(RTRIM(@myXeName)))=0
                SET @myXeName=N'system_health'
            SELECT TOP 1 @myXeFilePath=LEFT([myXeFiles].[FilePathAndName],CHARINDEX([myXeFiles].[XeName],[myXeFiles].[FilePathAndName])+LEN([myXeFiles].[XeName]))+'*.xel'
                FROM
                    (
                    SELECT 
                        [mySessions].[name] AS XeName,
                        CAST([myTarget].[target_data] AS XML).value('(EventFileTarget/File/@name)[1]', 'NVARCHAR(256)') AS FilePathAndName
                    FROM 
                        [sys].[dm_xe_sessions] AS mySessions WITH (NOLOCK)
                        INNER JOIN [sys].[dm_xe_session_targets] AS myTarget WITH (NOLOCK) ON [mySessions].[address] = [myTarget].[event_session_address]
                    WHERE
                        [myTarget].[target_name] = 'event_file'
                        AND [mySessions].[name] LIKE  '%'+@XeName+'%'
                    ) AS myXeFiles

            --Validate filepath conditions
            IF @myXeFilePath IS NULL
                RETURN

            --Validate date conditions
            IF(@myServerVersion >= @mySqlServer2017Version)
            BEGIN
                IF @myFromDate IS NULL
                    SET @myFromDate = CAST(DATEADD(DAY,-1,CAST(GETDATE() AS DATE)) AS DATETIME)
                IF @myToDate IS NULL
                    SET @myToDate = DATEADD(SECOND,-1,CAST(DATEADD(DAY,1,CAST(GETDATE() AS DATE)) AS DATETIME))
            END
            ELSE
            BEGIN
                SET @myFromDate=GETDATE()
                SET @myToDate=@FromDate
            END

            PRINT CONCAT(N'Performance report from ', @myFromDate, N' To ', @myToDate,N' based on ',@myXeFilePath, CASE WHEN (@myServerVersion < @mySqlServer2017Version) THEN N', but SQL version is under MSSQL 2017 and you can not use date filters.' ELSE N'' END)
            SET @myUTCDateTime=GETUTCDATE()
            SET @myLocalDateTime=GETDATE()
            SET @myLocalDiffToUTC = DATEDIFF(MINUTE,@myUTCDateTime,@myLocalDateTime)
            SET @mySQLScript = CAST(N'' AS NVARCHAR(MAX))
            IF(@myServerVersion >= @mySqlServer2017Version)
            BEGIN
                SET @myParamDefinition = N'@myLocalDiffToUTC INT, @myXeFilePath AS NVARCHAR(256)'
                SET @mySQLScript=@mySQLScript+
                    CAST(
                        @myNewLine+ N'SELECT'+
                        @myNewLine+ N'	CAST(DATEADD(MINUTE,@myLocalDiffToUTC,[myXefile].[timestamp_utc]) AS DATE) AS LogDate,'+
                        @myNewLine+ N'	DATEADD(MINUTE,@myLocalDiffToUTC,[myXefile].[timestamp_utc]) AS LogDateTime,'+
                        @myNewLine+ N'	[myXefile].[object_name] AS CategoryName,'+
                        @myNewLine+ N'	CONVERT(XML, event_data) AS event_data'+
                        @myNewLine+ N'FROM '+
                        @myNewLine+ N'	sys.fn_xe_file_target_read_file(@myXeFilePath, NULL, NULL, NULL) AS myXefile'+
                        @myNewLine+ N'WHERE'+
                        @myNewLine+ N'	[myXefile].[object_name] = N''blocked_process_report'''
                        AS NVARCHAR(MAX))
                INSERT INTO [#myXeTable] ([LogDate], [LogDateTime], [CategoryName], [event_data])
                EXECUTE sp_executesql @mySQLScript, @myParamDefinition, @myLocalDiffToUTC = @myLocalDiffToUTC, @myXeFilePath=@myXeFilePath;
            END
            ELSE
            BEGIN
                SET @myParamDefinition = N'@myFromDate DateTime, @myXeFilePath AS NVARCHAR(256)'
                SET @mySQLScript=@mySQLScript+
                    CAST(
                        @myNewLine+ N'SELECT'+
                        @myNewLine+ N'	CAST(@myFromDate AS DATE) AS LogDate,'+
                        @myNewLine+ N'	@myFromDate AS LogDateTime,'+
                        @myNewLine+ N'	[myXefile].[object_name] AS CategoryName,'+
                        @myNewLine+ N'	CONVERT(XML, event_data) AS event_data'+
                        @myNewLine+ N'FROM '+
                        @myNewLine+ N'	sys.fn_xe_file_target_read_file(@myXeFilePath, NULL, NULL, NULL) AS myXefile'+
                        @myNewLine+ N'WHERE'+
                        @myNewLine+ N'	[myXefile].[object_name] = N''blocked_process_report'''
                        AS NVARCHAR(MAX))
                INSERT INTO [#myXeTable] ([LogDate], [LogDateTime], [CategoryName], [event_data])
                EXECUTE sp_executesql @mySQLScript, @myParamDefinition, @myFromDate = @myFromDate, @myXeFilePath=@myXeFilePath;
            END
            --=====================================Extract Block Parties
            CREATE TABLE #myBlockStat (RecordId BIGINT PRIMARY KEY, BlockFactors XML,HashValue INT, Duration BIGINT, [event_data] XML)
            INSERT INTO [#myBlockStat] ([RecordId], [HashValue],[Duration],[event_data])
            SELECT
                [myBlockCombination].[RecordId],
                BINARY_CHECKSUM(CAST([myBlockCombination].[BlockFactors] AS NVARCHAR(MAX))) AS HashValue,
                [myBlockCombination].[Duration],
                [myBlockCombination].[event_data]
            FROM
                (
                SELECT 
                    [myXefile].[RecordId],
                    CAST(CONCAT(CAST([myXefile].[event_data].query('event/data/value/blocked-process-report/blocked-process/process/inputbuf') AS NVARCHAR(MAX)), CAST([myXefile].[event_data].query('event/data/value/blocked-process-report/blocking-process/process/inputbuf') AS NVARCHAR(MAX))) AS XML) AS BlockFactors,
                    [myXefile].[event_data].value('(/event/data[@name=`"duration`"]/value)[1]','bigint') AS Duration,
                    [myXefile].[event_data]
                FROM
                    [#myXeTable] AS myXefile
                WHERE
                    [myXefile].[LogDateTime] BETWEEN @myFromDate AND @myToDate
                    AND [myXefile].[CategoryName]=N'blocked_process_report'
                    AND [myXefile].[event_data].exist('/event[@name=`"blocked_process_report`"]/data[@name=`"blocked_process`"]/value')=1 
                ) AS myBlockCombination

            SELECT TOP 3 
                [myStat].[HashValue] AS [Id],
                COUNT(1) AS Occurane,
                SUM([myStat].[Duration])/1000 AS TotalDuration_ms,
                AVG([myStat].[Duration])/1000 AS AverageDuration_ms,
                CAST(MAX(CAST([myStat].[event_data] AS NVARCHAR(MAX))) AS XML) AS SampleXmlData
            FROM 
                #myBlockStat AS myStat
            GROUP BY
                [myStat].[HashValue]
            ORDER BY
                TotalDuration_ms DESC,
                Occurane DESC
        "
    }
    end{}
 }