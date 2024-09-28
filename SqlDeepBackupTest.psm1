Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepDatabaseShipping.psm1
Using module .\SqlDeepCommon.psm1

enum TestResult {
    RestoreSuccseed = 1
    RestoreFail = -1
    CheckDbSuccseed = 2
    CheckDbFail = -2
    }
<#
Class BackupTest:DatabaseShipping {
    [string]$Text;

    BackupTest(){
        $this.Text='Hello World'
    }
    [string]Print(){
        return $this.Text;
    }
}

#Test inherited class
$myBackupTest=[BackupTest]::New()
#>
Class BackupTestCatalogItem {
    [bigint]$Id
    [string]$InstanceName
    [string]$DatabaseName
    [int]$TestResult
    [datetime]$BackupRestoredTime
    [datetime]$BackupStartTime
    [string]$LogFilePath
    [datetime]$SysRowVersion
    [string]$TestResultDescription
    [bigint]$HashValue
    [datetime]$FinishTime
   
    BackupTestCatalogItem([bigint]$Id,[string]$InstanceName,[string]$DatabaseName,[int]$TestResult,[datetime]$BackupRestoredTime,[datetime]$BackupStartTime,[string]$LogFilePath,[datetime]$SysRowVersion,[string]$TestResultDescription,[bigint]$HashValue,[datetime]$FinishTime){
        Write-Verbose 'BackupCatalogItem object initializing started'
        $this.Id=$Id
        $this.InstanceName=$InstanceName
        $this.DatabaseName=$DatabaseName
        $this.TestResult=$TestResult
        $this.BackupRestoredTime=$BackupRestoredTime
        $this.BackupStartTime=$BackupStartTime
        $this.LogFilePath=$LogFilePath
        $this.SysRowVersion=$SysRowVersion
        $this.TestResultDescription=$TestResultDescription
        $this.HashValue=$HashValue
        $this.FinishTime=$FinishTime
        Write-Verbose 'BackupCatalogItem object initialized'
    }
}
<
Class BackupTest:DatabaseShipping {
        <#
        [string]$SourceInstanceConnectionString;
        [string[]]$Databases;
        [BackupType[]]$BackupTypes;
        [int]$HoursToScanForUntransferredBackups;
        [DestinationType]$DestinationType;
        [string]$Destination;
        [string]$DestinationFolderStructure;
        [string]$SshHostKeyFingerprint;
        [ActionType]$ActionType;
        [string]$RetainDaysOnDestination;
        [string]$TransferedFileDescriptionSuffix;
        [string]$BackupShippingCatalogTableName;
        [string]$WinScpPath='C:\Program Files (x86)\WinSCP\WinSCPnet.dll';
        [System.Net.NetworkCredential]$DestinationCredential;
        hidden [LogWriter]$LogWriter;
        hidden [string]$BatchUid;
        hidden [string]$LogStaticMessage='';
        #>
        BackupTest() : base() {}
        # Additional initialization if needed
        [string]$BackupTestCatalogTableName;
        [datetime]$StartDate ;
        [datetime]$EndDate ;
       # [string]$RestoreInstanceConnectionString;
        [string]$RestoreInstance
        [datetime]$RestoreTime;
         
        # [string]$MonitoringServer
        # [string]$DatabaseReportStore
        # [string]$DestinationPath
        # [string]$LogFilePath
        # [string]$DataFilePath
        # [string]$ErrorFile
        # [int]$MaximumTryCountToFindUncheckedBackup = 5

    BackupTest(
        [string]$myBackupTestCatalogTableName = $null,
        [datetime]$myStartDate = 1,
        [datetime]$myEndDate = 5,
        [string]$myRestoreInstance,
        [datetime]$myRestoreTime
        
        # [string]$monitoringServer,
        # [string]$databaseReportStore,
        # [string]$destinationPath,
        # [string]$logFilePath,
        # [string]$dataFilePath,
        # [string]$errorFile
    ) 
    {
        $this.BackupTestCatalogTableName = $myBackupTestCatalogTableName   
        $this.EndDate =$myStartDate
        $this.EndDate =$myEndDate
        $this.RestoreInstance = $myRestoreInstance
        $this.RestoreTime=$myRestoreTime

        # $this.MonitoringServer = $monitoringServer
        # $this.DatabaseReportStore = $databaseReportStore
        # $this.DestinationPath = $destinationPath
        # $this.LogFilePath = $logFilePath
        # $this.DataFilePath = $dataFilePath
        # $this.ErrorFile = $errorFile
    }
   init ([string]$BackupTestCatalogTableName ,[string]$restoreInstance, [string]$monitoringServer,[string]$databaseReportStore,[string]$destinationPath,[string]$logFilePath,[string]$dataFilePath,[string]$errorFile)
   {  
        $this.BackupTestCatalogTableName = $BackupTestCatalogTableName

        $this.RestoreInstance = $restoreInstance
        # $this.MonitoringServer = $monitoringServer
        # $this.DatabaseReportStore = $databaseReportStore
        # $this.DestinationPath = $destinationPath
        # $this.LogFilePath = $logFilePath
        # $this.DataFilePath = $dataFilePath
        # $this.ErrorFile = $errorFile

        if($null -eq $this.BackupTestCatalogTableName){$this.BackupTestCatalogTableName='BackupTest'}
    }
   #$myShip=New-DatabaseShipping -SourceInstanceConnectionString "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-DR-DGV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -FileRepositoryUncPath "\\db-dr-dgv01\Backups" -DestinationRestoreMode ([DatabaseRecoveryMode]::RESTOREONLY) -LogWrite $myLogWriter -LimitMsdbScanToRecentHours 24 -RestoreFilesToIndividualFolders

#region Functions
    hidden[datetime] GenerateRandomDate([DateTime]$StartDate, [DateTime]$EndDate) {
        [DateTime]$myStartDate = $StartDate
        [DateTime]$myEndDate = $EndDate
        
        if($null -eq $myStartDate -and $null -eq $myEndDate)
        {
            $this.LogWriter.Write($this.LogStaticMessage+'StartDate and EndDate is empty . set random date between 5 days ago.', [LogType]::INF)
            $myStartDate =  (Get-Date).AddDays(-5) 
            $myEndDate = Get-Date
        }
        elseif ($myStartDate -gt $myEndDate) {  
            $this.LogWriter.Write($this.LogStaticMessage+'StartDate must be less than or equal to EndDate .', [LogType]::INF)
            $myStartDate=$EndDate
            $myEndDate=$StartDate
        }  
        $myRandomDate = Get-Random -Minimum $myStartDate.Ticks -Maximum $myEndDate.Ticks
     return $myRandomDate =[datetime]::FromFileTime($myRandomDate)
    }
    hidden [bool] CreateBackupTestCatalog() {   #Create Log Table to Write Logs of transfered files in a table, if not exists
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [bool]$myAnswer=[bool]$true
        [string]$myCommand=$null
    
        $this.BackupTestCatalogTableName=Clear-SqlParameter -ParameterValue $this.BackupTestCatalogTableName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        $myCommand="
        DECLARE @myTableName nvarchar(255)
        SET @myTableName=N'"+ $this.BackupTestCatalogTableName +"'
        
        IF NOT EXISTS (
            SELECT 
                1
            FROM 
                [sys].[all_objects] AS myTable
                INNER JOIN [sys].[schemas] AS mySchema ON [myTable].[schema_id]=[mySchema].[schema_id]
            WHERE 
                [mySchema].[name] + '.' + [myTable].[name] = [mySchema].[name] + '.' + REPLACE(REPLACE(@myTableName,'[',''),']','')
        ) BEGIN
         CREATE TABLE [dbo].[" + $this.BackupTestCatalogTableName + "](
       
            [Id] [BIGINT] IDENTITY(1,1) NOT NULL,
            [InstanceName] [NVARCHAR](128) NOT NULL,
            [DatabaseName] [NVARCHAR](128) NOT NULL,
            [TestResult] [INT] NOT NULL,
            [BackupRestoredTime] [DATETIME] NOT NULL,
            [BackupStartTime] [DATETIME] NULL,
            [LogFilePath] [NVARCHAR](255) NULL,
            [SysRowVersion] [TIMESTAMP] NOT NULL,
            [TestResultDescription] [NCHAR](50) NULL,
            [HashValue]  AS (BINARY_CHECKSUM([InstanceName],[DatabaseName])),
            [FinishTime] [DATETIME] NULL,
         CONSTRAINT [PK_dbo."+$this.BackupTestCatalogTableName+"] PRIMARY KEY CLUSTERED 
        (
            [Id] ASC
        )WITH (PAD_INDEX = ON, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [Index_All]
        ) ON [Index_All]
        GO
    
        ALTER TABLE [dbo].["+$this.BackupTestCatalogTableName+"] ADD  CONSTRAINT [DF_"+$this.BackupTestCatalogTableName+"_FinishDate]  DEFAULT (GETDATE()) FOR [FinishTime]
        GO
        "
        try{
            Write-Verbose $myCommand
            Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myAnswer=[bool]$false
        }
        return $myAnswer
    }
    hidden [bool] IsTested([string]$SourceInstanceName, [datetime]$RecoveryDateTime, [string]$DatabaseName) {
        $this.BackupTestCatalogTableName=Clear-SqlParameter -ParameterValue $this.BackupTestCatalogTableName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        $SourceInstanceName=Clear-SqlParameter -ParameterValue $SourceInstanceName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        [bool]$myResult=$false
        [string]$myQuery = 
        "
        DECLARE @myHashValue AS INT
        DECLARE @myRecoveryDateTime AS DateTime
        DECLARE @myDBName AS NVARCHAR(50)

        SET @myHashValue = BINARY_CHECKSUM('"+ $DatabaseName + "','"+ $SourceInstanceName + "')
        SET @myRecoveryDateTime = CAST('" + $RecoveryDateTime.ToString() + "' AS DATETIME)

        SELECT COUNT(1) As myResult
        FROM [dbo].["+$this.BackupTestCatalogTableName+"]
        Where [HashValue] = @myHashValue 
        AND @myRecoveryDateTime BETWEEN [BackupStartTime] AND [BackupRestoredTime]
        "
        try{
            $myResultCheckDate = Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString  -Database $this.BackupTestCatalogTableName -Query $myQuery -OutputSqlErrors $true -OutputAs DataRows
            if ($myResultCheckDate[0] -eq 0 ) {
                $myResult = $false
            }
            else {
                $myResult = $true
            }
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myResult=[bool]$false
        }
    return $myResult
    }
    hidden [bool] TestDatabaseIntegrity([string]$DestinationDatabaseName) {
        [bool]$myResult = $false
        $myCommand = "
        DECLARE @myDBName AS NVARCHAR(100)
        SET @myDBName = CAST('"+$DestinationDatabaseName +"') AS NVARCHAR(100));
        
        DBCC CHECKDB (@myDBName) WITH NO_INFOMSGS;
        "
        #return ($null -eq $ResultCheckTest)
        try{
            $myResult = Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString -Database "master" -Query $myCommand -OutputSqlErrors $true -OutputAs DataTables -ErrorAction Stop -EncryptConnection
            if ($null -eq $myResult) {$myResult=$true}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myResult=$false
        }
    return $myResult
    }
    hidden [void] SaveResultToBackupTestCatalog([string]$DatabaseName,[string]$RestoreInstance,[TestResult]$TestResult) {
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)

        $myCommand = "
        DECLARE @myRecoveryDateTime AS DateTime
        DECLARE @myBackupStartTime AS DateTime
        SET @myBackupStartTime = CAST('"+$this.BackupStartTime.ToString()+"' AS DATETIME)
        SET @myRecoveryDateTime = CAST('"+$this.RestoreTime.ToString()+"' AS DATETIME)
        INSERT INTO [dbo].[BackupTestResult] ([InstanceName], [DatabaseName], [TestResult], [TestResultDescription], [BackupRestoredTime], [BackupStartTime], [LogFilePath])
        VALUES (N'"+ $RestoreInstance +"', N'"+ $DatabaseName +"', "+($TestResult.value__)+","+ $TestResult+", @myRecoveryDateTime, @myBackupStartTime, N'$($this.ErrorFileAddress)')
        "
   
       # Invoke-Sqlcmd -ServerInstance $this.RestoreInstance -Database $this.DatabaseReportStore -Query $myInsertCommand -OutputSqlErrors $true -QueryTimeout 0 -EncryptConnection
        try{
            Write-Verbose $myCommand
            Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
    }
    hidden [void] DropDatabase ($DatabaseName){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [string]$myCommand=

        "
            DROP DATABASE IF EXISTS [" + $DatabaseName + "]
        "
        try{
            Invoke-Sqlcmd -ServerInstance $this.RestoreInstance -Query $myCommand -Database "master" -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
    }

    [void] Test([string]$SourceConnectionString,[string]$DatabaseName){
        #Set Constr
        [int]$myExecutionId =Get-Random -Minimum 1 -Maximum 1000
        $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        $SourceConnectionString=Clear-SqlParameter -ParameterValue $SourceConnectionString -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
      
        [string]$myDestinationDatabaseName=$DatabaseName+$myExecutionId
        
        #Determine candidate server(s)
        $this.LogWriter.Write($this.LogStaticMessage+'Get Source instance server name.',[LogType]::INF)
        $mySourceInstanceInfo=Get-InstanceInformation -ConnectionString $this.SourceInstanceConnectionString -ShowRelatedInstanceOnly
        if ($mySourceInstanceInfo.PsObject.Properties.Name -eq 'MachineName') {
            $mySourceServerName=$mySourceInstanceInfo.MachineName
            $mySourceInstanceName=$mySourceInstanceInfo.InstanceName
            $this.LogWriter.Write($this.LogStaticMessage+'Source server name is ' + $mySourceServerName + ' and Instance name is ' + $mySourceInstanceName,[LogType]::INF)
        } else {
            $this.LogWriter.Write($this.LogStaticMessage+'Get-InstanceInformation failure.', [LogType]::ERR) 
            throw ('Get-InstanceInformation failure.')
        }
        if ($null -eq $mySourceServerName -or $mySourceServerName.Length -eq 0) {
            $this.LogWriter.Write($this.LogStaticMessage+'Source server name is empty.',[LogType]::ERR)
            throw 'Source server name is empty.'
        }
        ##Determine restoresd server
        $myDestinationInstanceInfo=Get-InstanceInformation -ConnectionString $this.DestinationInstanceConnectionString -ShowRelatedInstanceOnly
        $myDestinationInstanceName=$myDestinationInstanceInfo.InstanceName
 
        
        #Initial Log Modules
        Write-Verbose ('===== Testbackup database  ' + $DatabaseName + ' as ' + $mySourceInstanceName + ' started. =====')
        $this.LogStaticMessage= "{""SourceDB"":""" + $DatabaseName + ' as ' + """,""SourceInstance"":""" + $mySourceInstanceName+"""} : "
       # $this.LogWriter.LogFilePath=$this.LogWriter.LogFilePath.Replace('{Database}',$myDestinationDatabaseName)
        $this.LogWriter.Reinitialize()
        $this.LogWriter.Write($this.LogStaticMessage+'===== BackupTest process started... ===== ', [LogType]::INF) 
        $this.LogWriter.Write($this.LogStaticMessage+('TestDatabase ' + $DatabaseName + ' as ' + $mySourceInstanceName), [LogType]::INF) 
        $this.LogWriter.Write($this.LogStaticMessage+'Initializing EventsTable.Create.', [LogType]::INF) 
        
        if($null -eq $this.RestoreTime)
        {
            $this.RestoreTime=GenerateRandomDate($this.StartDate,$this.EndDate)
            $this.LogWriter.Write($this.LogStaticMessage+('RestoreTime is :' + $this.RestoreTime),[LogType]::INF);
        }
        #Has this database been tested on this date?
        $this.LogWriter.Write($this.LogStaticMessage+('in time :' + $this.RestoreTime+'does not have any test record'),[LogType]::INF);
        if($this.IsTested($mySourceInstanceName,$this.RestoreTime,$DatabaseName) -eq $false){

            if ($myDestinationInstanceName -ne $mySourceInstanceName) { #Do not restore any database when Source instance is equal to Destination instance (Because of operational database replacement)
                try { #Restore database to destination
                    $this.LogWriter.Write($this.LogStaticMessage+('restored database with name:' + $myDestinationDatabaseName),[LogType]::INF);
                    $this.DestinationRestoreMode=[DatabaseRecoveryMode]::RECOVERY
                    $this.PreferredStrategies=[RestoreStrategy]::FullDiffLog,[RestoreStrategy]::FullLog,[RestoreStrategy]::DiffLog,[RestoreStrategy]::Log
                    $this.ShipDatabase($DatabaseName,$myDestinationDatabaseName)
                    $myTestResult = [TestResult]::RestoreSuccseed
                    $this.SaveResultToBackupTestCatalog($DatabaseName,$mySourceInstanceName,$myTestResult)
                }
                catch {
                    $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                    $myTestResult = [TestResult]::RestoreFailed
                    SaveResultToBackupTestCatalog($DatabaseName,$mySourceInstanceName,$myTestResult)
                }

                try { #Checkdb 
                    $this.LogWriter.Write($this.LogStaticMessage+('checkdb on database:' + $myDestinationDatabaseName),[LogType]::INF); 
                    $this.TestDatabaseIntegrity($myDestinationDatabaseName)
                    $myTestResult = [TestResult]::CheckDbSuccseed
                    $this.SaveResultToBackupTestCatalog($DatabaseName,$mySourceInstanceName,$myTestResult)
                }
                catch {
                    $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                    $myTestResult = [TestResult]::CheckDbFail
                    SaveResultToBackupTestCatalog($DatabaseName,$mySourceInstanceName,$myTestResult)
                }
                try { #Remove database
                    $this.LogWriter.Write($this.LogStaticMessage+('remove database:' + $myDestinationDatabaseName),[LogType]::INF); 
                    DropDatabase($myDestinationDatabaseName)
                }
                catch {
                    $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                    $this.
                }
            } else {
                $this.LogWriter.Write($this.LogStaticMessage+('Destination instance is same as Source instance.'),[LogType]::ERR); 
            }
        }        

    }
#endregion
}