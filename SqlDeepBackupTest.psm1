Using module .\SqlDeepLogWriter.psm1
Using module .\SqlDeepDatabaseShipping.psm1
Using module .\SqlDeepCommon.psm1

enum TestResult {
    RestoreSuccseed = 1
    RestoreFailed = -1
    CheckDbSuccseed = 2
    CheckDbFailed = -2
    }
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
Class BackupTest:DatabaseShipping {
    [string]$BackupTestCatalogTableName;
    [nullable[datetime]]$StartDate ;
    [nullable[datetime]]$EndDate ;
     
BackupTest():base() {
    $this.Init($null)
}
BackupTest([string]$BackupTestCatalogTableName) : base() {
    $this.Init($BackupTestCatalogTableName)
}
hidden Init ([string]$BackupTestCatalogTableName)
{  
    $this.LimitMsdbScanToRecentHours=24;
    if($null -eq $this.BackupTestCatalogTableName -or $this.BackupTestCatalogTableName.Trim().Length -eq 0){$this.BackupTestCatalogTableName='BackupTest'}
}
   #$myShip=New-DatabaseShipping -SourceInstanceConnectionString "Data Source=LSNR.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -DestinationInstanceConnectionString "Data Source=DB-DR-DGV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True" -FileRepositoryUncPath "\\db-dr-dgv01\Backups" -DestinationRestoreMode ([DatabaseRecoveryMode]::RESTOREONLY) -LogWrite $myLogWriter -LimitMsdbScanToRecentHours 24 -RestoreFilesToIndividualFolders

#region Functions
    hidden [datetime] GenerateRandomDate([nullable[DateTime]]$StartDate, [nullable[DateTime]]$EndDate) {
        [nullable[DateTime]]$myStartDate = $StartDate
        [nullable[DateTime]]$myEndDate = $EndDate
        
        if($null -eq $myStartDate -and $null -eq $myEndDate)
        {
            $this.LogWriter.Write($this.LogStaticMessage+'StartDate and EndDate is empty . set random date between 5 days ago.', [LogType]::INF)
            $myStartDate =  (Get-Date).AddDays(-5) 
            $myEndDate = Get-Date
        }
        elseif ($null -eq $myStartDate -and $null -ne $myEndDate) {  
            $this.LogWriter.Write($this.LogStaticMessage + ' StartDate is empty. Setting StartDate to EndDate - 5 days.', [LogType]::INF)  
            $myStartDate = $myEndDate.AddDays(-5)  
        }  
        # Check if only EndDate is null  
        elseif ($null -ne $myStartDate -and $null -eq $myEndDate) {  
            $this.LogWriter.Write($this.LogStaticMessage + ' EndDate is empty. Setting EndDate to StartDate + 5 days.', [LogType]::INF)  
            $myEndDate = $myStartDate.AddDays(5)  
        }  
        elseif ($myStartDate -gt $myEndDate) {  
            $this.LogWriter.Write($this.LogStaticMessage+'StartDate must be less than or equal to EndDate .', [LogType]::INF)
            $myStartDate=$EndDate
            $myEndDate=$StartDate
        }  
        $myRandomDate = Get-Random -Minimum $myStartDate.Ticks -Maximum $myEndDate.Ticks
     return $myRandomDate =[datetime]($myRandomDate)
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
        )WITH (PAD_INDEX = ON, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 100, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
        ) ON [PRIMARY];
        
    
        ALTER TABLE [dbo].["+$this.BackupTestCatalogTableName+"] ADD  CONSTRAINT [DF_"+$this.BackupTestCatalogTableName+"_FinishDate]  DEFAULT (GETDATE()) FOR [FinishTime];
		END
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
            $myResultCheckDate = Invoke-Sqlcmd -ConnectionString ($this.LogWriter.LogInstanceConnectionString) -Query $myQuery -OutputSqlErrors $true -OutputAs DataRows
            if ($null -ne $myResultCheckDate) {
                $myResult = $false
            } else {
                if ($myResultCheckDate[0] -eq 0 ) {
                    $myResult = $false
                }
                else {
                    $myResult = $true
                }
            }
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myResult=$false
        }
    return $myResult
    }
    hidden [bool] TestDatabaseIntegrity([string]$DestinationDatabaseName) {
        [bool]$myResult = $false
        $myCommand = "
        DECLARE @myDBName AS NVARCHAR(100)
        SET @myDBName = CAST('"+$DestinationDatabaseName+"' AS NVARCHAR(100));
        
        DBCC CHECKDB (@myDBName) WITH NO_INFOMSGS;
        "
        try{
            $myResult = Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString  -Query $myCommand -OutputSqlErrors $true -OutputAs DataTables -ErrorAction Stop 
            if ($null -eq $myResult) {$myResult=$true}
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
            $myResult=$false
        }
    return $myResult
    }
    hidden [void] SaveResultToBackupTestCatalog([string]$DatabaseName,[TestResult]$TestResult, [datetime]$RecoveryDateTime,$BackupStartDate) {
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)

        $mySourceInstanceInstanceInfo=Get-InstanceInformation -ConnectionString $this.SourceInstanceConnectionString -ShowRelatedInstanceOnly
        $mySourceInstanceName=$mySourceInstanceInstanceInfo.MachineNameDomainNameInstanceNamePortNumber
        $myCommand = "
        DECLARE @myRecoveryDateTime AS DateTime
        DECLARE @myBackupStartTime AS DateTime
        SET @myRecoveryDateTime = CAST('" + ($RecoveryDateTime.ToString()) + "' AS DATETIME)
        SET @myBackupStartTime = CAST('" + ($BackupStartDate.ToString()) + "' AS DATETIME)
  
        INSERT INTO[dbo].["+$this.BackupTestCatalogTableName+"] ([InstanceName], [DatabaseName], [TestResult], [TestResultDescription], [BackupRestoredTime],[BackupStartTime])
        VALUES (N'"+ $mySourceInstanceName +"', N'"+ $DatabaseName +"', "+($TestResult.value__).ToString() +", N'"+ $TestResult +"', @myRecoveryDateTime ,@myBackupStartTime)
        "
    
       # Invoke-Sqlcmd -ServerInstance $this.RestoreInstance -Database $this.DatabaseReportStore -Query $myInsertCommand -OutputSqlErrors $true -QueryTimeout 0 -EncryptConnection
        try{
            Write-Verbose $myCommand
            Invoke-Sqlcmd -ConnectionString ($this.LogWriter.LogInstanceConnectionString) -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
    }
    hidden [void] DropDatabase ([string]$DatabaseName){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        [string]$myCommand=
        "
        DECLARE @myDatabaseName sysname
        SET @myDatabaseName = '" + $DatabaseName + "'
        IF EXISTS (SELECT 1 FROM sys.databases WHERE [name] = @myDatabaseName)
            BEGIN
                DROP DATABASE " + $DatabaseName + "
            END
        "
        try{
            Invoke-Sqlcmd -ConnectionString $this.DestinationInstanceConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
        }Catch{
            $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
        }
    }
    [void] TestAllDatabases([string[]]$ExcludedDatabaseList){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        $myDatabaseList=Get-DatabaseList -ConnectionString $this.SourceInstanceConnectionString -ExcludedList $ExcludedDatabaseList
        foreach($myDatabase in $myDatabaseList){
            $this.TestDatabase($myDatabase.DatabaseName)
        }
    }
    [void] TestFromRegisterServer([string[]]$ExcludedInstanceList,[string[]]$ExcludedDatabaseList,[string]$RegisteryCategoryName){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        $myServerList = Get-InfoFromSqlRegisteredServers -MonitoringConnectionString $this.SourceInstanceConnectionString -ExcludedList $ExcludedInstanceList -FilterGroup $RegisteryCategoryName # Get Server list from MSX
        
        foreach ($myServer in $myServerList){
            $this.SourceInstanceConnectionString=$myServer.EncryptConnectionString
            $this.TestAllDatabases($ExcludedDatabaseList)
        }
    }
    [void] TestDatabase([string]$DatabaseName){
        $this.LogWriter.Write($this.LogStaticMessage+'Processing Started.', [LogType]::INF)
        #Set Constr
        [int]$myExecutionId=1
        [string]$myDestinationDatabaseName=$null

        $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        $myExecutionId=Get-Random -Minimum 1 -Maximum 1000
        $myDestinationDatabaseName=$DatabaseName+$myExecutionId
        
        #Determine candidate server(s)
        $this.LogWriter.Write($this.LogStaticMessage+'Get Source instance server name: '+$this.SourceInstanceConnectionString,[LogType]::INF)
        $mySourceInstanceInfo=Get-InstanceInformation -ConnectionString $this.SourceInstanceConnectionString -ShowRelatedInstanceOnly
        if ($mySourceInstanceInfo.PsObject.Properties.Name -eq 'MachineName') {  
            $mySourceServerName=$mySourceInstanceInfo.MachineName
            $mySourceInstanceName=$mySourceInstanceInfo.MachineNameDomainNameInstanceNamePortNumber
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

        $this.LogWriter.Write($this.LogStaticMessage+'Get Destination instance server name: ' + $this.DestinationInstanceConnectionString,[LogType]::INF)
        $myDestinationInstanceInfo=Get-InstanceInformation -ConnectionString $this.DestinationInstanceConnectionString -ShowRelatedInstanceOnly
        $myDestinationInstanceName=$myDestinationInstanceInfo.MachineNameDomainNameInstanceNamePortNumber

        #Initial Log Modules
        Write-Verbose ('===== Testbackup database  ' + $DatabaseName + ' as ' + $mySourceInstanceName + ' started. =====')
        $this.LogStaticMessage= '{"SourceDB":"' + $DatabaseName + ' as ' + '","SourceInstance":"' + $mySourceInstanceName+'"} : '
       # $this.LogWriter.LogFilePath=$this.LogWriter.LogFilePath.Replace('{Database}',$myDestinationDatabaseName)
        $this.LogWriter.Reinitialize()
        $this.LogWriter.Write($this.LogStaticMessage+'===== BackupTest process started... ===== ', [LogType]::INF) 
        $this.LogWriter.Write($this.LogStaticMessage+('TestDatabase ' + $DatabaseName + ' as ' + $mySourceInstanceName), [LogType]::INF) 
        $this.LogWriter.Write($this.LogStaticMessage+'Initializing EventsTable.Create.', [LogType]::INF) 
       # $this.RestoreTo=Clear-SqlParameter -ParameterValue $this.RestoreTo -RemoveSpace -RemoveWildcard -RemoveBraces -RemoveSingleQuote -RemoveDoubleQuote -RemoveDollerSign
        if($null -eq $this.RestoreTo)
        {
            Write-Host $this.RestoreTo
            $this.RestoreTo=$this.GenerateRandomDate($this.StartDate,$this.EndDate)
            $this.LogWriter.Write($this.LogStaticMessage+('RestoreTo is :' + $this.RestoreTo),[LogType]::INF);
        }
        #--=======================Check shipped files catalog table connectivity
        $this.LogWriter.Write($this.LogStaticMessage+'Test catalog table connectivity.', [LogType]::INF) 
        if ((Test-DatabaseConnection -ConnectionString ($this.LogWriter.LogInstanceConnectionString) -DatabaseName 'master') -eq $false) {
            $this.LogWriter.Write($this.LogStaticMessage+'Can not connect to sql instance on ' + $this.LogWriter.LogInstanceConnectionString, [LogType]::ERR) 
            throw ($this.LogStaticMessage+'Can not connect to sql instance.')
        }
        $this.LogWriter.Write($this.LogStaticMessage+'Initializing  catalog table.', [LogType]::INF)
        if ($this.CreateBackupTestCatalog() -eq $false)  {
            $this.LogWriter.Write($this.LogStaticMessage+'Can not initialize table to save catalog on ' + $this.LogWriter.LogInstanceConnectionString + ' to ' + $this.BackupShippingCatalogTableName + ' table.', [LogType]::ERR) 
            throw ($this.LogStaticMessage+' catalog initialization failed.')
        }
        #Has this database been tested on this date?
        $this.LogWriter.Write($this.LogStaticMessage+('in time :' + $this.RestoreTo+'does not have any test record'),[LogType]::INF);
        Write-Host $mySourceInstanceName,$this.RestoreTo.DateTime,$DatabaseName
        if($this.IsTested($mySourceInstanceName,($this.RestoreTo.DateTime),$DatabaseName) -eq $false){

##            if ($myDestinationInstanceName -ne $mySourceInstanceName) { #Do not restore any database when Source instance is equal to Destination instance (Because of operational database replacement)
                try { #Restore database to destination
                    $this.LogWriter.Write($this.LogStaticMessage+('restored database with name:' + $myDestinationDatabaseName),[LogType]::INF);
                    $this.DestinationRestoreMode=[DatabaseRecoveryMode]::RECOVERY
                    $this.PreferredStrategies=[RestoreStrategy]::FullDiffLog,[RestoreStrategy]::FullLog,[RestoreStrategy]::DiffLog,[RestoreStrategy]::Log
                    $this.ShipDatabase($DatabaseName,$myDestinationDatabaseName)
                    $myTestResult = [TestResult]::RestoreSuccseed
                    [DateTime]$myBackupStartDate = ($this.BackupFileList | Where-Object -Property DatabaseName -EQ $DatabaseName | Sort-Object -Property BackupStartTime |Select-Object -Property BackupStartTime -First 1).BackupStartTime
                    $this.SaveResultToBackupTestCatalog($DatabaseName,$myTestResult,($this.RestoreTo.DateTime),$myBackupStartDate)
                    

                }
                catch {
                    $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                    $myTestResult = [TestResult]::RestoreFailed
                    $this.SaveResultToBackupTestCatalog($DatabaseName,$myTestResult,($this.RestoreTo.DateTime),$myBackupStartDate)
                }
                try { #Checkdb 
                    $this.LogWriter.Write($this.LogStaticMessage+('checkdb on database:' + $myDestinationDatabaseName),[LogType]::INF); 
                    $this.TestDatabaseIntegrity($myDestinationDatabaseName)
                    $myTestResult = [TestResult]::CheckDbSuccseed
                    [DateTime]$myBackupStartDate = ($this.BackupFileList | Where-Object -Property DatabaseName -EQ $DatabaseName | Sort-Object -Property BackupStartTime |Select-Object -Property BackupStartTime -First 1).BackupStartTime
                    $this.SaveResultToBackupTestCatalog($DatabaseName,$myTestResult,($this.RestoreTo.DateTime),$myBackupStartDate)
                }
                catch {
                    $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                    $myTestResult = [TestResult]::CheckDbFailed
                    $this.SaveResultToBackupTestCatalog($DatabaseName,$myTestResult,($this.RestoreTo.DateTime),$myBackupStartDate)
                }
                try { #Remove database
                    $this.LogWriter.Write($this.LogStaticMessage+('remove database:' + $myDestinationDatabaseName),[LogType]::INF); 
                    $this.DropDatabase($myDestinationDatabaseName)
                }
                catch {
                    $this.LogWriter.Write($this.LogStaticMessage+($_.ToString()).ToString(), [LogType]::ERR)
                }
    ##        } else {
     ##           $this.LogWriter.Write($this.LogStaticMessage+('Destination instance is same as Source instance.'),[LogType]::ERR); 
      ##      }
        }        

    }
 
#endregion
}
#region Functions
Function New-DatabaseTest {
    Param(
        [Parameter(Mandatory=$true)][string]$SourceInstanceConnectionString,
        [Parameter(Mandatory=$true)][string]$DestinationInstanceConnectionString,
        [Parameter(Mandatory=$false)][string]$BackupTestCatalogTableName,
        [Parameter(Mandatory=$true)][string]$FileRepositoryUncPath,
        [Parameter(Mandatory=$true)][LogWriter]$LogWriter
    )
    Write-Verbose 'Creating New-DatabaseTest'
    [BackupTest]$myAnswer=$null
    [string]$mySourceInstanceConnectionString=$SourceInstanceConnectionString
    [string]$myDestinationInstanceConnectionString=$DestinationInstanceConnectionString
    [string]$myBackupTestCatalogTableName=$BackupTestCatalogTableName
    [LogWriter]$myLogWriter=$LogWriter
    $myAnswer=[BackupTest]::New($myBackupTestCatalogTableName)
    $myAnswer.SourceInstanceConnectionString=$mySourceInstanceConnectionString
    $myAnswer.DestinationInstanceConnectionString=$myDestinationInstanceConnectionString
    $myAnswer.FileRepositoryUncPath = $FileRepositoryUncPath
    $myAnswer.LogWriter=$myLogWriter
    Write-Verbose 'New-DatabaseTest Created'
    Return $myAnswer
}
#endregion

#region Export
Export-ModuleMember -Function New-DatabaseTest
#endregion   
    
