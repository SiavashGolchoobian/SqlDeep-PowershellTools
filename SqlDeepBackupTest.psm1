Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepDatabaseShipping.psm1
Using module .\SqlDeepCommon.psm1

enum TestResult {
    Succseed = 1
    CopyFail = -1
    RestoreFullBackupFail = -2
    RestoreDiffBackupFail = -3
    RestoreLogBackupFail = -4
    CheckDbFail = -5
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
        [Int]$MinimumDate ;
        [Int]$MaximumDate 


        # [string]$RestoreInstance
        # [string]$MonitoringServer
        # [string]$DatabaseReportStore
        # [string]$DestinationPath
        # [string]$LogFilePath
        # [string]$DataFilePath
        # [string]$ErrorFile
        # [int]$MaximumTryCountToFindUncheckedBackup = 5

    BackupTest(
        [string]$myBackupTestCatalogTableName = $null,
        [Int]$myMinimumDate = 1,
        [Int]$myMaximumDate = 5

        # [string]$restoreInstance,
        # [string]$monitoringServer,
        # [string]$databaseReportStore,
        # [string]$destinationPath,
        # [string]$logFilePath,
        # [string]$dataFilePath,
        # [string]$errorFile
    ) 
    {
        $this.BackupTestCatalogTableName = $myBackupTestCatalogTableName   
        $this.MaximumDate =$myMinimumDate
        $this.MaximumDate =$myMaximumDate
        # $this.RestoreInstance = $restoreInstance
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

        # $this.RestoreInstance = $restoreInstance
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
    hidden[datetime] GenerateRandomDate([int]$minNumber, [int]$maxNumber) {
    return (Get-Date).AddDays(- (Get-Random -Minimum $minNumber -Maximum $maxNumber))
    $this.LogWriter()
    }
    hidden [bool]Create_BackupTestCatalog() {   #Create Log Table to Write Logs of transfered files in a table, if not exists
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
            Invoke-Sqlcmd -ConnectionString ($this.LogWriter.LogInstanceConnectionString) -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myAnswer=[bool]$false
        }
        return $myAnswer
    }
    hidden[bool] IsTested([string]$SourceInstanceName, [datetime]$RecoveryDateTime, [string]$DatabaseName,[string]$RestoreInstance,[string]$DatabaseReportStore) {
        $myQuery = 
        "
        DECLARE @myHashValue AS INT
        DECLARE @myRecoveryDateTime AS DateTime
        DECLARE @myDBName AS NVARCHAR(50)

        SET @myHashValue = BINARY_CHECKSUM('"+ $DatabaseName + "','"+ $SourceInstanceName + "')
        SET @myRecoveryDateTime = CAST('" + $RecoveryDateTime + "' AS DATETIME)

        SELECT COUNT(1) As myResult
        FROM [dbo].[BackupTestResult]
        Where [HashValue] = @myHashValue 
        AND @myRecoveryDateTime BETWEEN [BackupStartTime] AND [BackupRestoredTime]
        "
    $myResultCheckDate = Invoke-Sqlcmd -ServerInstance $this.RestoreInstance -Database $this.DatabaseReportStore -Query $myQuery -OutputSqlErrors $true -OutputAs DataRows
    if ($myResultCheckDate[0] -eq 0 ) {
        $myResult = $false
    }
    else {
        $myResult = $true
    }
    return $myResult
    }
    [bool] CheckDB($ExecutionId,$DestinationDatabaseName) {
        $myCommand = "
        DECLARE @myDBName AS NVARCHAR(100)
        DECLARE @myExecutionId INT
        SET @myExecutionId = CAST('" + $ExecutionId.ToString() + "' AS INT);
        SET @myDBName = CAST(CONCAT('"+$DestinationDatabaseName +"', '_', @myExecutionId) AS NVARCHAR(100));
        
        IF (SELECT state_desc FROM sys.databases WHERE name = @myDBName) = 'RESTORING'
        RESTORE DATABASE @myDBName WITH RECOVERY;
        
        DBCC CHECKDB (@myDBName) WITH NO_INFOMSGS;
        "
        
        $ResultCheckTest = Invoke-Sqlcmd -ServerInstance $this.InstanceName -Database "master" -Query $myCommand -OutputSqlErrors $true -OutputAs DataTables -ErrorAction Stop -EncryptConnection
        
        Write-Host $ResultCheckTest
        
        return $null -eq $ResultCheckTest
        }

    [void] Test([string]$SourceConnectionString,[string]$DatabaseName){
        [int]$myMaximumNumber = 1000
        [int]$myExecutionId =$this.GenerateRandomDate($this.MinimumDate,$myMaximumNumber)
        [string]$myDestinationDatabaseName=$DatabaseName+$myExecutionId
        
        $this.ShipDatabase($DatabaseName,$myDestinationDatabaseName)
        
    }
#endregion
}