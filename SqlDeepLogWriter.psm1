<#
.SYNOPSIS
    A script module that provides some functionality.

.DESCRIPTION
    A detailed description of what the script module does.

.PARAMETER Input
    The input parameter for the Get-SomeData function.

.PARAMETER Output
    The output parameter for the Set-SomeData function.

.EXAMPLE
    Import-Module .\\MyModule.psm1

    Get-SomeData -Input C:\\input.txt | Set-SomeData -Output C:\\output.txt

    Imports the script module and runs the Get-SomeData and Set-SomeData functions with the specified input and output files.
#>
Enum LogType {
    INF
    WRN
    ERR
};
Enum ArchiveTimeScale {
    ByYear
    ByMonth
    ByDay
    ByHour
    ByTime
};
Class LogWriter {
    [string]$EventSource=$env:COMPUTERNAME
    [string]$Module="UNKNOWN"
    [bool]$LogToConsole
    [bool]$LogToFile
    [string]$LogFilePath
    [bool]$LogToTable
    [string]$LogInstanceConnectionString
    [string]$LogTableName="[dbo].[Events]"
    [int]$ErrCount=0
    [int]$WrnCount=0
    hidden[string]$LogFilePathPattern
    
    LogWriter(){
        $this.Init($null,"UNKNOWN",$true,$false,$null,$false,$null,$null)
    }
    LogWriter([string]$EventSource,[string]$Module){
        $this.Init($EventSource,$Module,$true,$false,$null,$false,$null,$null)
    }
    LogWriter([string]$EventSource,[string]$Module,[bool]$LogToConsole){
        $this.Init($EventSource,$Module,$LogToConsole,$false,$null,$false,$null,$null)
    }
    LogWriter([string]$EventSource,[string]$Module,[bool]$LogToFile,[string]$LogFilePath){
        $this.Init($EventSource,$Module,$true,$LogToFile,$LogFilePath,$false,$null,$null)
    }
    LogWriter([string]$EventSource,[string]$Module,[bool]$LogToTable,[string]$LogInstanceConnectionString,[string]$LogTableName){
        $this.Init($EventSource,$Module,$true,$false,$null,$LogToTable,$LogInstanceConnectionString,$LogTableName)
    }
    LogWriter([string]$EventSource,[string]$Module,[bool]$LogToConsole,[bool]$LogToFile,[string]$LogFilePath,[bool]$LogToTable,[string]$LogInstanceConnectionString,[string]$LogTableName){
        $this.Init($EventSource,$Module,$LogToConsole,$LogToFile,$LogFilePath,$LogToTable,$LogInstanceConnectionString,$LogTableName)
    }
    Reinitialize(){
        $this.Init($this.EventSource,$this.Module,$this.LogToConsole,$this.LogToFile,$this.LogToTable,$this.LogInstanceConnectionString,$this.LogTableName)
    }
    hidden Init([string]$EventSource,[string]$Module,[bool]$LogToConsole,[bool]$LogToFile,[string]$LogFilePath,[bool]$LogToTable,[string]$LogInstanceConnectionString,[string]$LogTableName){
        $mySysToday = (Get-Date -Format "yyyyMMdd").ToString()
        $mySysTodayTime = (Get-Date -Format "yyyyMMdd_HHmm").ToString()
        $this.EventSource=$EventSource
        $this.Module=$Module
        $this.LogToConsole=$LogToConsole
        $this.LogToFile=$LogToFile
        $this.LogFilePathPattern=$LogFilePath
        $this.LogFilePath=($LogFilePath.Replace("{Date}",$mySysToday)).Replace("{DateTime}",$mySysTodayTime)
        $this.LogToTable=$LogToTable
        $this.LogInstanceConnectionString=$LogInstanceConnectionString
        $this.LogTableName=$LogTableName
        $this.ErrCount=0
        $this.WrnCount=0

        if ($null -eq $this.EventSource -or $this.EventSource.Trim.Length -eq 0) {$this.EventSource=$env:COMPUTERNAME}
        if ($null -eq $this.Module -or $this.Module.Trim.Length -eq 0) {$this.Module="UNKNOWN"}
        if ($null -eq $this.LogFilePath -or $this.LogFilePath.Trim.Length -eq 0) {$this.LogToFile=$false}
        if ($null -eq $this.LogInstanceConnectionString -or $this.LogInstanceConnectionString -eq 0) {$this.LogToTable=$false}
        if ($null -eq $this.LogTableName -or $this.LogTableName -eq 0) {$this.LogTableName="[dbo].[Events]"}
        if ($this.LogToTable) {$this.LogToTable=$this.CreateLogTable()}
    }

    #region Functions
    hidden [bool]CreateLogTable() {   #Create Events Table to Write Logs to a database table if not exists
        [bool]$myAnswer=[bool]$true
        [string]$myCommand="
        DECLARE @myTableName nvarchar(255)
        SET @myTableName=N'"+ $this.LogTableName +"'
        
        IF NOT EXISTS (
            SELECT 
                1
            FROM 
                sys.all_objects AS myTable
                INNER JOIN sys.schemas AS mySchema ON myTable.schema_id=mySchema.schema_id
            WHERE 
                mySchema.name + '.' + myTable.name = REPLACE(REPLACE(@myTableName,'[',''),']','')
        ) BEGIN
            CREATE TABLE" + $this.LogTableName + "(
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
            Invoke-Sqlcmd -ConnectionString ($this.LogInstanceConnectionString) -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop
        }Catch{
            Write-Error ($_.ToString()).ToString()
            $myAnswer=[bool]$false
        }
        return $myAnswer
    }
    hidden [string]GetFunctionName ([int]$StackNumber = 1) { #Create Log Table if not exists
        return [string]$(Get-PSCallStack)[$StackNumber].FunctionName
    }
    [void] Write([string]$Content) {
        $this.Write($Content,[LogType]::INF,$false,$false,$null)
    }
    [void] Write([string]$Content, [LogType]$Type) {
        $this.Write($Content,$Type,$false,$false,$null)
    }
    [void] Write([string]$Content, [LogType]$Type, [bool]$Terminate){
        $this.Write($Content,$Type,$Terminate,$false,$null)
    }
    [void] Write([string]$Content, [LogType]$Type, [bool]$Terminate, [bool]$IsSMS){
        $this.Write($Content,$Type,$Terminate,$IsSMS,$null)
    }
    [void] Write([string]$Content, [LogType]$Type, [bool]$Terminate, [bool]$IsSMS, [string]$EventTimeStamp){    #Fill Log file
        Write-Verbose "Write-Log started."
        [string]$myIsSMS="0"
        [string]$myEventTimeStamp=(Get-Date).ToString()
        [string]$myContent=""
        [string]$myColor="White"

        Switch ($Type) {
            INF {$myColor="White";$myIsSMS="0"}
            WRN {$myColor="Yellow";$myIsSMS="1";$this.WrnCount+=1}
            ERR {$myColor="Red";$myIsSMS="1";$this.ErrCount+=1}
            Default {$myColor="White"}
        }
        if ($IsSMS){$myIsSMS="1"} else {$myIsSMS="0"}
        try {
            $myEventTimeStamp=([datetime]$EventTimeStamp).ToString()
        }
        catch {
            $myEventTimeStamp=(Get-Date).ToString()
        }
        

        $myContent = $myEventTimeStamp + "`t" + $Type + "`t(" + ($this.GetFunctionName(3)) +")`t"+ $Content
        if ($Terminate) { $myContent+=$myContent + "`t" + ". Prcess terminated with " + $this.ErrCount.ToString() + " Error count and " + $this.WrnCount.ToString() + " Warning count."}

        #-----Write to stdout
        Write-Output $myContent
        #-----Write to console
        If ($this.LogToConsole) {
            Write-Host $myContent -ForegroundColor $myColor
        }
        #-----Write to file
        If ($this.LogToFile) {
            try {
                Add-Content -Path ($this.LogFilePath) -Value $myContent
            }
            catch {
                Write-Error ("Log to file " + $this.LogFilePath + " exception. LogToFile is disabled.")
                Write-Error ($_.ToString()).ToString()
                $this.LogToFile=$false
            }
        }
        #-----Write to database table
        if ($this.LogToTable) {
            try{
                $myCommand=
                    "
                    INSERT INTO "+ $this.LogTableName +" ([EventSource],[Module],[EventTimeStamp],[Serverity],[Description],[IsSMS])
                    VALUES(N'"+$this.EventSource+"',N'"+ $this.Module +"',CAST('"+$myEventTimeStamp+"' AS DATETIME),N'"+$Type+"',N'"+$Content.Replace("'",'"')+"',"+$myIsSMS+")
                    "
                Invoke-Sqlcmd -ConnectionString ($this.LogInstanceConnectionString) -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Ignore
            }
            catch {
                Write-Error ("Log to table " + $this.LogTableName + " exception. LogToTable is disabled.")
                Write-Error ($_.ToString()).ToString()
                $this.LogToTable=$false
            }
        }
        if ($Terminate){Exit}
        Write-Verbose "Write-Log finished."
    }
    [void] ArchiveLogFilesToZipFile([string]$ArchiveFolder,[ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2,[int]$BatchCount=5,[bool]$RemoveSourceFiles=$true){
        Write-Verbose "ArchiveLogFilesToZipFile started."
        [int]$myBatchCount=5
        [string]$mySourceFolder=$null
        [string]$mySourceFile=$null
        [string]$mySourceFilePattern=$null
        [string]$myZipPathTemplate=$null
        [string]$myGroupByPattern=$null
        
        if ($this.LogToFile) {
            if ($BatchCount -gt 0){$myBatchCount=$BatchCount}
            if ($null -eq $ArchiveFolder -or $ArchiveFolder.Trim().Length -eq 0) {$ArchiveFolder=(Split-Path -Parent ($this.LogFilePath)).Trim()}
            if ($ArchiveFolder[-1] -ne "\") {$ArchiveFolder+="\"}
            $mySourceFolder=(Split-Path -Parent ($this.LogFilePath)).Trim()
            if ($mySourceFolder[-1] -ne "\") {$mySourceFolder+="\"}
            $mySourceFile=Split-Path -Path ($this.LogFilePathPattern) -Leaf
            $mySourceFilePattern="^"+($mySourceFile.Replace("{Date}","([0-9]{8})").Replace("{DateTime}","([0-9]{8})_([0-9]{4})"))+"$"
            $myZipPathTemplate = $ArchiveFolder + $mySourceFile.Replace("{Date}","").Replace("{DateTime}","") + "{myGroup}.zip"

            Switch ($ArchiveFileTemplate) {
                ByYear {$myGroupByPattern="yyyy"}
                ByMonth {$myGroupByPattern="yyyyMM"}
                ByDay {$myGroupByPattern="yyyyMMdd"}
                ByHour {$myGroupByPattern="yyyyMMddHH"}
                ByTime {$myGroupByPattern="yyyyMMddHHmmss"}
                Default {$myGroupByPattern="yyyyMMdd"}
            }

            Write-Output ("SourceFolder is: "+$mySourceFolder)
            Write-Output ("SourceFilePattern is: "+$mySourceFilePattern)
            Write-Output ("ArchiveFolder is: "+$ArchiveFolder)
            Write-Output ("ZipPathTemplate is: "+$myZipPathTemplate)

            $mySelectedFiles = Get-ChildItem -Path $mySourceFolder | Where-Object -Property Name -match $mySourceFilePattern | Sort-Object -Property LastWriteTime | Select-Object -SkipLast $KeepLatestFilesCount
            $myGroupedFiles = $mySelectedFiles | Group-Object -Property {$_.LastWriteTime.ToString($myGroupByPattern)}
            ForEach ($myGroup in $myGroupedFiles) {
                $myGroupCountOfFiles=[math]::Ceiling($myGroup.Count/$myBatchCount)
                For ($myCounter=1; $myCounter -le $myGroupCountOfFiles; $myCounter+=1) {
                    try{
                        $myCurrentZipPath = $myZipPathTemplate.Replace('{myGroup}',$myGroup.Name)
                        Write-Output ("Compressing files to " + $myCurrentZipPath + " (" + $myCounter.ToString() + " of " + $myGroupCountOfFiles.ToString() + ")...")
                        $myGroupChunk = $myGroup.Group | Select-Object -Skip (($myCounter-1)*$myBatchCount) -First $myBatchCount
                        $myGroupChunk | Compress-Archive -DestinationPath $myCurrentZipPath -CompressionLevel Optimal -Update
                        $myGroupChunk | ForEach-Object{Write-Output ($_.Name + " is compressed to " + $myCurrentZipPath + ".")}
                        Write-Output ("Batch Compression finished.")
                        if ($RemoveSourceFiles){
                            Write-Output ("Removing source files started.")
                            $myGroupChunk | Remove-Item 
                            Write-Output ("Source files removed.")
                        }
                    }catch{
                        Write-Error ($_.ToString()).ToString()
                    }
                }
            }
        }else{
            Write-Output ("Log to files is disabled.")
        }
        Write-Verbose "ArchiveLogFilesToZipFile finished."
    }
    [void] DeleteArchiveFiles([string]$ArchiveFolder,[ArchiveTimeScale]$ArchiveFileTemplate,[int]$KeepLatestFilesCount=2){
        Write-Verbose "DeleteArchiveFiles started."
        [string]$mySourceFile=$null
        [string]$myZipPathTemplate=$null
        
        if ($this.LogToFile) {
            $mySourceFile=Split-Path -Path ($this.LogFilePathPattern) -Leaf
            if ($null -eq $ArchiveFolder -or $ArchiveFolder.Trim().Length -eq 0) {$ArchiveFolder=(Split-Path -Parent ($this.LogFilePath)).Trim()}
            if ($ArchiveFolder[-1] -ne "\") {$ArchiveFolder+="\"}
            $myZipPathTemplate=$mySourceFile.Replace("{Date}","").Replace("{DateTime}","") + "{myGroup}.zip"
            
            Switch ($ArchiveFileTemplate) {
                ByYear {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{4})\")+"$"}
                ByMonth {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{6})\")+"$"}
                ByDay {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{8})\")+"$"}
                ByHour {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{10})\")+"$"}
                ByTime {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{14})\")+"$"}
                Default {$myZipPathTemplate="^"+$myZipPathTemplate.Replace("{myGroup}","([0-9]{4})\")+"$"}
            }

            Write-Output ("SourceFilePattern is: "+$mySourceFile)
            Write-Output ("ArchiveFolder is: "+$ArchiveFolder)
            Write-Output ("ZipPathTemplate is: "+$myZipPathTemplate)

            try{
                $mySelectedFiles = Get-ChildItem -Path $ArchiveFolder | Where-Object -Property Name -match $myZipPathTemplate | Sort-Object -Property LastWriteTime | Select-Object -SkipLast $KeepLatestFilesCount
                Write-Output ("Removing archive files started.")
                $mySelectedFiles | Remove-Item 
                $mySelectedFiles | ForEach-Object{Write-Output ($_.Name + " is removed.")}
                Write-Output ("Archive files removed.")
            }catch{
                Write-Error ($_.ToString()).ToString()
            }
        }else{
            Write-Output ("Log to files is disabled.")
        }
        Write-Verbose "DeleteArchiveFiles finished."
    }
    #endregion
}

#region Functions
Function New-LogWriter {  #Create new LogWriter instance
    Param
        (
            [Parameter(Mandatory=$true)][string]$EventSource,
            [Parameter(Mandatory=$true)][string]$Module,
            [Parameter(Mandatory=$false)][Switch]$LogToConsole=$false,
            [Parameter(Mandatory=$false)][Switch]$LogToFile=$false,
            [Parameter(Mandatory=$false)][string]$LogFilePath,
            [Parameter(Mandatory=$false)][Switch]$LogToTable=$false,
            [Parameter(Mandatory=$false)][string]$LogInstanceConnectionString,
            [Parameter(Mandatory=$false)][string]$LogTableName="[dbo].[Events]"
         )

    Write-Verbose "Creating New-LogWriter"
    [string]$myEventSource=$EventSource
    [string]$myModule=$Module
    [bool]$myLogToConsole=$LogToConsole
    [bool]$myLogToFile=$LogToFile
    [string]$myLogFilePath=$LogFilePath
    [bool]$myLogToTable=$LogToTable
    [string]$myLogInstanceConnectionString=$LogInstanceConnectionString
    [string]$myLogTableName=$LogTableName

    [LogWriter]::New($myEventSource,$myModule,$myLogToConsole,$myLogToFile,$myLogFilePath,$myLogToTable,$myLogInstanceConnectionString,$myLogTableName)
    Write-Verbose "New-LogWriter Created"
}
#endregion

#region Export
Export-ModuleMember -Function New-LogWriter
#endregion