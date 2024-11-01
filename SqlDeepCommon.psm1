#region Functions
    function Clear-FolderPath { #Remove latest '\' char from folder path
        [OutputType([string])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input folder path to evaluate")][AllowEmptyString()][AllowNull()][string]$FolderPath
        )
        begin{}
        process{
            $FolderPath=$FolderPath.Trim()
            if ($FolderPath.ToCharArray()[-1] -eq '\') {$FolderPath=$FolderPath.Substring(0,$FolderPath.Length-1)}    
            return $FolderPath
        }
        end{}    
    }
    function IsNumeric {  #Check if input value is numeric
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input value to evaluate")][AllowEmptyString()][AllowNull()]$Value
        )
        begin{}
        process{
            return ($Value -match "^[\d\.]+$")
        }
        end{}
    }
    function Clear-Text {
        [OutputType([string])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][AllowEmptyString()][AllowNull()][string]$Text,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][AllowEmptyCollection()][AllowNull()][string[]]$ProhibitedPhrases
        )
        begin {}
        process {
            [string]$myAnswer=$null;
            try{
                $myAnswer=$Text;
                foreach ($ProhibitedPhrase in $ProhibitedPhrases){
                    $myAnswer=$myAnswer.Replace($ProhibitedPhrase,"");
                }
            }catch{
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end{}
    }
    function Clear-SqlParameter {
        [OutputType([string])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage='Input string to cleanup')][AllowEmptyString()][AllowNull()][string]$ParameterValue,
            [Parameter(Mandatory=$false,HelpMessage='Remove space( ) character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveSpace,
            [Parameter(Mandatory=$false,HelpMessage='Remove wildecard(%) character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveWildcard,
            [Parameter(Mandatory=$false,HelpMessage='Remove braces([]) character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveBraces,
            [Parameter(Mandatory=$false,HelpMessage='Remove single quote character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveSingleQuote,
            [Parameter(Mandatory=$false,HelpMessage='Remove double quote(") character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveDoubleQuote,
            [Parameter(Mandatory=$false,HelpMessage='Remove doller sign ($) character')][AllowEmptyCollection()][AllowNull()][switch]$RemoveDollerSign
            )
        begin {
            [string[]]$myProhibitedPhrases=$null;
            $myProhibitedPhrases+=';';
            if ($RemoveSpace){$myProhibitedPhrases+=' '};
            if ($RemoveWildcard){$myProhibitedPhrases+='%'};
            if ($RemoveBraces){$myProhibitedPhrases+='[',']','{','}'};
            if ($RemoveSingleQuote){$myProhibitedPhrases+="'"};
            if ($RemoveDoubleQuote){$myProhibitedPhrases+='"'};
            if ($RemoveDollerSign){$myProhibitedPhrases+='$'};
        } 
        process {
            [string]$myAnswer=$null;

            try{
                $myAnswer = Clear-Text -Text $ParameterValue -ProhibitedPhrases $myProhibitedPhrases
            }catch{
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Export-DatabaseBlob {
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$CommandText,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$DestinationFilePath
        )
        begin {
            $mySqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $mySqlCommand = $mySqlConnection.CreateCommand();
            $mySqlConnection.Open(); 
        }
        process {
            [bool]$myAnswer=$false;
            try
            {
                $mySqlCommand.CommandText = $CommandText;                      
                # New Command and Reader
                $myReader = $mySqlCommand.ExecuteReader();
        
                # Create a byte array for the stream.
                $myBufferSize = 8192*8;
                $myOut = [array]::CreateInstance('Byte', $myBufferSize)

                # Looping through records
                While ($myReader.Read())
                {
                    #Create Directory if not exists and remove any Existing item
                    $myFolderPath=Split-Path $DestinationFilePath
                    IF (-not (Test-Path -Path $myFolderPath -PathType Container)) {
                        New-Item -Path $myFolderPath -ItemType Directory -Force
                        #$myDestinationFolderPath=$DestinationFilePath.Substring(0,($DestinationFilePath.Length-$DestinationFilePath.Split("\")[-1].Length))
                        #New-Item -ItemType Directory -Path $myDestinationFolderPath -Force
                    }
                    IF (Test-Path -Path $DestinationFilePath -PathType Leaf) {Move-Item -Path $DestinationFilePath -Force}
            
                    # New BinaryWriter, write content to specified file on (zero based) first column (FileContent)
                    $myFileStream = New-Object System.IO.FileStream $DestinationFilePath, Create, Write;
                    $myBinaryWriter = New-Object System.IO.BinaryWriter $myFileStream;

                    $myStart = 0;
                    # Read first byte stream from (zero based) first column (FileContent)
                    $myReceived = $myReader.GetBytes(0, $myStart, $myOut, 0, $myBufferSize - 1);
                    While ($myReceived -gt 0)
                    {
                        $myBinaryWriter.Write($myOut, 0, $myReceived);
                        $myBinaryWriter.Flush();
                        $myStart += $myReceived;
                        # Read next byte stream from (zero based) first column (FileContent)
                        $myReceived = $myReader.GetBytes(0, $myStart, $myOut, 0, $myBufferSize - 1);
                    }

                    $myBinaryWriter.Close();
                    $myFileStream.Close();
                    
                    if (-not (Test-Path -Path $DestinationFilePath) -or -not ($myFileStream)) {
                        $myAnswer=$false;
                    } else {
                        $myAnswer=$true;
                    }
                    
                    # Closing & Disposing all objects
                    if ($myFileStream) {$myFileStream.Dispose()};
                }
                $myReader.Close();
                return $myAnswer
            }
            catch
            {       
                $myAnswer=$false;
                Write-Error($_.ToString());
                Throw;
            }
            return $myAnswer;
        }
        end {
            $mySqlCommand.Dispose();
            $mySqlConnection.Close();
            $mySqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
    }
    function Read-SqlQuery {
        [OutputType([System.Data.DataTable])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$Query
        )
        begin {
            $mySqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $mySqlCommand = $mySqlConnection.CreateCommand();
            $mySqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter;
            $myDataTable = New-Object System.Data.DataTable;
            $mySqlConnection.Open(); 
        }
        process {
            try
            {
                [System.Data.DataTable]$myAnswer=$null;
                $mySqlCommand.CommandText = $Query;                      
                $mySqlDataAdapter.SelectCommand = $mySqlCommand;
                $null=$mySqlDataAdapter.Fill($myDataTable);
                $myAnswer=$myDataTable;
            }
            catch
            {       
                $myAnswer=$null;
                Write-Error($_.ToString());
                Throw;
            }
            return $myAnswer;
        }
        end {
            $mySqlCommand.Dispose();
            $mySqlConnection.Close();
            $mySqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
    }
    function Invoke-SqlCommand {
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$Command
        )
        begin {
            $mySqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $mySqlCommand = $mySqlConnection.CreateCommand();
            $mySqlConnection.Open(); 
        }
        process {
            [bool]$myAnswer=$false;
            try
            {
                $mySqlCommand.CommandText = $Command;                      
                $mySqlCommand.ExecuteNonQuery();
                $myAnswer=$true;
            }
            catch
            {       
                $myAnswer=$false;
                Write-Error($_.ToString());
                Throw;
            }
            return $myAnswer;
        }
        end {
            $mySqlCommand.Dispose();
            $mySqlConnection.Close();
            $mySqlConnection.Dispose();
            #[System.Data.SqlClient.SqlConnection]::ClearAllPools();  
        }
    }
    function Test-DatabaseConnection {
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$DatabaseName,
            [Parameter(Mandatory=$false,HelpMessage='Check database is accesible')][switch]$AccesibilityCheck
        )
        begin {}
        process {
            [bool]$myAnswer=$false;
            [string]$myCommand=$null;
            [string]$myUsedDatabaseName=$null;
            
            $DatabaseName=Clear-SqlParameter -ParameterValue $DatabaseName -RemoveWildcard -RemoveBraces ;
            if ($AccesibilityCheck -eq $true){
                $myUsedDatabaseName=$DatabaseName
            } else {
                $myUsedDatabaseName='master'
            }

            $myCommand="
                USE ["+$myUsedDatabaseName+"];
                SELECT [name] AS Result FROM [master].[sys].[databases] WHERE name = '" + $DatabaseName + "';
                ";
            try{
                $myRecord=Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop;
                if ($null -ne $myRecord) {$myAnswer=$true} else {$myAnswer=$false}
            }Catch{
                $myAnswer=$false;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer
        }
        end {}
    }
    function Test-InstanceConnection {
        [OutputType([bool])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString
        )
        begin {}
        process {
            [bool]$myAnswer=$false;
            try{
                $myAnswer=Test-DatabaseConnection -ConnectionString $ConnectionString -DatabaseName 'master';
            }Catch{
                $myAnswer=$false;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Get-InstanceInformationFromRegistery {
        [OutputType([PSCustomObject[]])]
        param ()
        begin {}
        process {
            [PSCustomObject[]]$myAnswer=$null;
            [string]$myMachineName=$null;
            [string]$myDomainName=$null;
            [string]$myRegInstanceFilter=$null;

            try {
                [System.Collections.ArrayList]$myInstanceCollection=$null;
                $myInstanceCollection=[System.Collections.ArrayList]::new();
                $myMachineName=($env:computername);
                $myDomainName=(Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem).Domain;
                $myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL';
                $myRegKey=Get-ItemProperty -Path $myRegInstanceFilter;
                $myRegKey.psobject.Properties | Where-Object -Property Name -NotIn ("PSPath","PSParentPath","SQL","PSChildName","PSDRIVE","PSProvider") | ForEach-Object{Write-Host ($myMachineName+","+$myDomainName+","+$_.Name+","+$_.Value);
                    $myInstanceObject=[PSCustomObject]@{
                        MachineName=$myMachineName
                        DomainName=$myDomainName
                        InstanceName=$_.Name
                        InstanceRegName=$_.Value
                        InstancePort="1433"
                        ForceEncryption=$false
                        DefaultDataPath=""
                        DefaultLogPath=""
                        DefaultBackupPath=""
                        Collation=""
                        PatchLevel=""
                    };
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name InstanceMajorVersion -Value {return [int]($this.PatchLevel.Split('.')[0])}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameInstanceName -Value {$myInstanceName="";if ($this.InstanceName -and $this.InstanceName.Trim().Length -gt 0) {$myInstanceName="\" + $this.InstanceName}; return $this.MachineName+$myInstanceName}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameDomainNameInstanceName -Value {$myInstanceName="";$myDomainName="";if ($this.InstanceName -and $this.InstanceName.Trim().Length -gt 0) {$myInstanceName="\" + $this.InstanceName};if ($this.DomainName -and $this.DomainName.Trim().Length -gt 0) {$myDomainName="." + $this.DomainName}; return $this.MachineName+$myDomainName+$myInstanceName}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameDomainNameInstanceNamePortNumber -Value {return $this.MachineNameDomainNameInstanceName+","+$this.InstancePort.Split(',')[0]}
                     $myInstanceCollection.Add($myInstanceObject)};
                #$myRegKey.psobject.Properties | Where-Object -Property Name -NotIn ("PSPath","PSParentPath","SQL","PSChildName","PSDRIVE","PSProvider") | ForEach-Object{Write-Host ($myMachineName+","+$myDomainName+","+$_.Name+","+$_.Value);$myInstanceCollection.Add([InstanceObject]::New($myMachineName,$myDomainName,$_.Name,$_.Value,'1433',$false,"","","","",""))};
                $myInstanceCollection | ForEach-Object{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$_.InstanceRegName+'\MSSQLServer\SuperSocketNetLib\Tcp\IPAll';$_.InstancePort=(Get-ItemProperty -Path $myRegInstanceFilter).TcpPort};
                $myInstanceCollection | ForEach-Object{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$_.InstanceRegName+'\MSSQLServer\SuperSocketNetLib';$_.ForceEncryption=(Get-ItemProperty -Path $myRegInstanceFilter).ForceEncryption};
                $myInstanceCollection | ForEach-Object{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$_.InstanceRegName+'\MSSQLServer';$_.DefaultDataPath=(Get-ItemProperty -Path $myRegInstanceFilter).DefaultData;$_.DefaultLogPath=(Get-ItemProperty -Path $myRegInstanceFilter).DefaultLog;$_.DefaultBackupPath=(Get-ItemProperty -Path $myRegInstanceFilter).BackupDirectory};
                $myInstanceCollection | ForEach-Object{$myRegInstanceFilter='HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\'+$_.InstanceRegName+'\Setup';$_.Collation=(Get-ItemProperty -Path $myRegInstanceFilter).Collation;$_.PatchLevel=(Get-ItemProperty -Path $myRegInstanceFilter).PatchLevel};
                $myAnswer=$myInstanceCollection.ToArray([PSCustomObject]);
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Get-InstanceInformationFromSql {
        [OutputType([PSCustomObject[]])]
        param (
            [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][ValidateNotNullOrEmpty()][string]$ConnectionString,
            [Parameter(Mandatory=$false)][Switch]$ShowRelatedInstanceOnly
        )
        begin {
            [string]$myCommand=$null;
            [string]$myShowRelatedInstanceCommand="";
            if ($ShowRelatedInstanceOnly) {$myShowRelatedInstanceCommand=" WHERE [InstanceName]=@@ServiceName"}
            $myCommand="
                DECLARE @myMachineName NVARCHAR(255)
                DECLARE @myDomainName NVARCHAR(255)
                DECLARE @myInstanceName NVARCHAR(255)
                DECLARE @myInstanceRegName NVARCHAR(255)
                DECLARE @myInstancePort NVARCHAR(255)
                DECLARE @myForceEncryption BIT
                DECLARE @myDefaultDataPath NVARCHAR(255)
                DECLARE @myDefaultLogPath NVARCHAR(255)
                DECLARE @myDefaultBackupPath NVARCHAR(255)
                DECLARE @myCollation NVARCHAR(255)
                DECLARE @myPatchLevel NVARCHAR(255)
                DECLARE @myRegInstanceFilter NVARCHAR(255)
                CREATE TABLE #myInstance (InstanceName sysname,InstanceRegName NVARCHAR(255))
                CREATE TABLE #myInstanceInfo (MachineName NVARCHAR(255), DomainName NVARCHAR(255), InstanceName sysname,InstanceRegName NVARCHAR(255), InstancePort NVARCHAR(255), ForceEncryption BIT, DefaultDataPath NVARCHAR(255), DefaultLogPath NVARCHAR(255), DefaultBackupPath NVARCHAR(255), Collation NVARCHAR(255), PatchLevel NVARCHAR(255))

                SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
                INSERT INTO #myInstance EXECUTE master.dbo.xp_regenumvalues 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter
                DECLARE myCursor CURSOR FOR SELECT [InstanceName],[InstanceRegName] FROM [#myInstance] " + $myShowRelatedInstanceCommand + "
                OPEN myCursor
                FETCH NEXT FROM myCursor INTO @myInstanceName,@myInstanceRegName
                WHILE @@FETCH_STATUS = 0
                BEGIN
                    INSERT INTO #myInstanceInfo ([InstanceName],[InstanceRegName]) VALUES (@myInstanceName,@myInstanceRegName)
                    SET @myRegInstanceFilter='SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'ComputerName',@myMachineName OUTPUT
                    SET @myRegInstanceFilter='SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'Domain',@myDomainName OUTPUT
                    SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\'+@myInstanceRegName+'\MSSQLServer\SuperSocketNetLib\Tcp\IPAll'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'TcpPort',@myInstancePort OUTPUT
                    SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\'+@myInstanceRegName+'\MSSQLServer\SuperSocketNetLib'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'ForceEncryption',@myForceEncryption OUTPUT
                    SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\'+@myInstanceRegName+'\MSSQLServer'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'DefaultData',@myDefaultDataPath OUTPUT
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'DefaultLog',@myDefaultLogPath OUTPUT
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'BackupDirectory',@myDefaultBackupPath OUTPUT
                    SET @myRegInstanceFilter='SOFTWARE\Microsoft\Microsoft SQL Server\'+@myInstanceRegName+'\Setup'
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'Collation',@myCollation OUTPUT
                    EXECUTE master.dbo.xp_regread 'HKEY_LOCAL_MACHINE',@myRegInstanceFilter,'PatchLevel',@myPatchLevel OUTPUT

                    UPDATE #myInstanceInfo SET 
                        [MachineName]=@myMachineName,
                        [DomainName]=@myDomainName,
                        [InstancePort]=@myInstancePort,
                        [ForceEncryption]=@myForceEncryption,
                        [DefaultDataPath]=@myDefaultDataPath,
                        [DefaultLogPath]=@myDefaultLogPath,
                        [DefaultBackupPath]=@myDefaultBackupPath,
                        [Collation]=@myCollation,
                        [PatchLevel]=@myPatchLevel
                    WHERE [InstanceName]=@myInstanceName
                    FETCH NEXT FROM myCursor INTO @myInstanceName,@myInstanceRegName
                END 
                CLOSE myCursor;
                DEALLOCATE myCursor;
                SELECT MachineName,DomainName,InstanceName,InstanceRegName,InstancePort,ForceEncryption,DefaultDataPath,DefaultLogPath,DefaultBackupPath,Collation,PatchLevel FROM [#myInstanceInfo]

                DROP TABLE [#myInstance]
                DROP TABLE [#myInstanceInfo]
            "
        }
        process {
            [PSCustomObject[]]$myAnswer=$null;
            try {
                [System.Collections.ArrayList]$myInstanceCollection=$null;
                $myInstanceCollection=[System.Collections.ArrayList]::new();
                $myResult=Read-SqlQuery -ConnectionString $ConnectionString -Query $myCommand
                $null=$myResult | ForEach-Object{
                    $myInstanceObject=[PSCustomObject]@{
                    MachineName=$_.MachineName
                    DomainName=$_.DomainName
                    InstanceName=$_.InstanceName
                    InstanceRegName=$_.InstanceRegName
                    InstancePort=$_.InstancePort
                    ForceEncryption=$_.ForceEncryption
                    DefaultDataPath=$_.DefaultDataPath
                    DefaultLogPath=$_.DefaultLogPath
                    DefaultBackupPath=$_.DefaultBackupPath
                    Collation=$_.Collation
                    PatchLevel=$_.PatchLevel}; 
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name InstanceMajorVersion -Value {return [int]($this.PatchLevel.Split('.')[0])}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameInstanceName -Value {$myInstanceName="";if ($this.InstanceName -and $this.InstanceName.Trim().Length -gt 0) {$myInstanceName="\" + $this.InstanceName}; return $this.MachineName+$myInstanceName}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameDomainNameInstanceName -Value {$myInstanceName="";$myDomainName="";if ($this.InstanceName -and $this.InstanceName.Trim().Length -gt 0) {$myInstanceName="\" + $this.InstanceName};if ($this.DomainName -and $this.DomainName.Trim().Length -gt 0) {$myDomainName="." + $this.DomainName}; return $this.MachineName+$myDomainName+$myInstanceName}
                    Add-Member -InputObject $myInstanceObject -MemberType ScriptProperty -Name MachineNameDomainNameInstanceNamePortNumber -Value {return $this.MachineNameDomainNameInstanceName+","+$this.InstancePort.Split(',')[0]}
                    $myInstanceCollection.Add($myInstanceObject);
                };
                $myAnswer=($myInstanceCollection.ToArray([PSCustomObject]))
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Get-InstanceInformation {
        [OutputType([PSCustomObject[]])]
        param (
            [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input string to cleanup")][string]$ConnectionString,
            [Parameter(Mandatory=$false)][Switch]$ShowRelatedInstanceOnly
        )
        begin {}
        process {
            [PSCustomObject[]]$myAnswer=$null;
            try {
                if ($ConnectionString) {
                    if ($ShowRelatedInstanceOnly){
                        $myAnswer=Get-InstanceInformationFromSql -ConnectionString $ConnectionString -ShowRelatedInstanceOnly
                    }else{
                        $myAnswer=Get-InstanceInformationFromSql -ConnectionString $ConnectionString
                    }
                } else {
                    $myAnswer=Get-InstanceInformationFromRegistery
                }
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer;
        }
        end {}
    }
    function Get-InfoFromSqlRegisteredServers {
        [OutputType([PSCustomObject[]])]
        Param (
            [parameter(Mandatory = $true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][string]$MonitoringConnectionString,
            [parameter(Mandatory = $false)][string[]]$ExcludedList,
            [parameter(Mandatory = $false)][string]$FilterGroup
        )
        begin{
            [PSCustomObject[]]$myAnswer=$null
            [string]$myQuery=$null
            [string]$myWhereCondition=''    
            [string]$myExludedString=''

            if ($null -ne $ExcludedList){
                foreach ($myExcludedItem in $ExcludedList){
                    $myExludedString+=",'" + $myExcludedItem.Trim() + "'"
                }
            }
    
            $myExludedString=Clear-SqlParameter -ParameterValue $myExludedString -RemoveWildcard -RemoveDoubleQuote -RemoveDollerSign -RemoveBraces
            $FilterGroup=Clear-SqlParameter -ParameterValue $FilterGroup -RemoveDoubleQuote -RemoveDollerSign
    
            if($null -eq $myExludedString) {$myExludedString=''}
            if($null -ne $FilterGroup -and  $FilterGroup.Trim() -ne '') {$myWhereCondition="AND myGroups.name LIKE '"+$FilterGroup+"'"}
        }
        process {
            $myMonitoringInstancInfo=Get-InstanceInformation -ConnectionString $MonitoringConnectionString -ShowRelatedInstanceOnly
            $myMonitoringInstanceName=$myMonitoringInstancInfo.MachineNameDomainNameInstanceNamePortNumber
            $myQuery = "
                SELECT Distinct
                    myGroups.name AS ServerGroupName,
                    myServer.server_name AS InstanceName,
                    'Data Source='+myServer.server_name+';Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;Integrated Security=True;' AS EncryptConnectionString,
                    'Data Source='+myServer.server_name+';Initial Catalog=master;Integrated Security=True;' AS ConnectionString
                FROM
                    msdb.dbo.sysmanagement_shared_server_groups_internal As myGroups WITH (READPAST)
                    INNER JOIN msdb.dbo.sysmanagement_shared_registered_servers_internal As myServer  WITH (READPAST) ON myGroups.server_group_id = myServer.server_group_id
                WHERE
                    myServer.server_name NOT IN('"+$myMonitoringInstanceName+"'"+$myExludedString+")
                    " + $myWhereCondition

            try {
                [System.Collections.ArrayList]$myServerCollection=$null;
                $myServerCollection=[System.Collections.ArrayList]::new();
        
                $myResult= Invoke-Sqlcmd -ConnectionString $MonitoringConnectionString -Query $myQuery -OutputSqlErrors $true
                $null=$myResult | ForEach-Object{
                    $myInstanceObject=[PSCustomObject]@{
                    ServerGroupName=$_.ServerGroupName
                    InstanceName=$_.InstanceName
                    EncryptConnectionString=$_.EncryptConnectionString
                    ConnectionString=$_.ConnectionString}; 
                    $myServerCollection.Add($myInstanceObject);
                };
                $myAnswer=($myServerCollection.ToArray([PSCustomObject]))
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer
        }
        end {}
    }
    function Get-DatabaseList {
        [OutputType([PSCustomObject[]])]
        Param (
            [parameter(Mandatory = $true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][string]$ConnectionString,
            [parameter(Mandatory = $false)][string[]]$ExcludedList
        )
    
        begin {
            $myAnswer=$null
            [string]$myQuery=$null
            [string]$myExludedDB=''
    
            if ($null -ne $ExcludedList){
                foreach ($myExceptedDB in $ExcludedList){
                    $myExludedDB+=",'" + $myExceptedDB.Trim() + "'"
                }
            }
            $myExludedDB=Clear-SqlParameter -ParameterValue $myExludedDB -RemoveWildcard -RemoveDoubleQuote -RemoveDollerSign -RemoveBraces
    
            $myQuery = 
            "
            SELECT 
                [myDatabase].[name]
            FROM 
                master.sys.databases myDatabase WITH (READPAST)
                LEFT OUTER JOIN master.sys.dm_hadr_availability_replica_states AS myHA WITH (READPAST) on myDatabase.replica_id=myHa.replica_id
            WHERE
                [myDatabase].[name] NOT IN ('master','msdb','model','tempdb'"+$myExludedDB+") 
                AND [myDatabase].[state] = 0
                AND [myDatabase].[source_database_id] IS NULL -- REAL DBS ONLY (Not Snapshots)
                AND [myDatabase].[is_read_only] = 0
                AND ([myHA].[role]=1 or [myHA].[role] is null)
            "
        }
        process {
            try {
                [System.Collections.ArrayList]$myDatabaseCollection=$null;
                $myDatabaseCollection=[System.Collections.ArrayList]::new();
        
                $myResult= Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $myQuery -OutputSqlErrors $true
                $null=$myResult | ForEach-Object{
                    $myDatabaseObject=[PSCustomObject]@{
                    DatabaseName=$_.name}; 
                    $myDatabaseCollection.Add($myDatabaseObject);
                };
                $myAnswer=($myDatabaseCollection.ToArray([PSCustomObject]))
            }
            catch
            {
                $myAnswer=$null;
                Write-Error($_.ToString());
                throw;
            }
            return $myAnswer
        }
        end {}
    }
#endregion

#region Export
    Export-ModuleMember -Function IsNumeric,Clear-FolderPath,Clear-Text,Clear-SqlParameter,Export-DatabaseBlob,Read-SqlQuery,Invoke-SqlCommand,Test-DatabaseConnection,Test-InstanceConnection,Get-InstanceInformation,Get-InfoFromSqlRegisteredServers,Get-DatabaseList
#endregion

# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC8S0nN8yo1PsT6
# HY9Mrr9ew+fqmkm0ijH0H5hxx7utGaCCFhswggMUMIIB/KADAgECAhAT2c9S4U98
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
# BCCZWde1e0W9nItt4FsIS/vMYk6V3O+pwXqYivtzLoeNqjANBgkqhkiG9w0BAQEF
# AASCAQDDaPzrwya8Z8F5KfrGdfUPeVtP0+4qVv9imH1zJwN/rnjLnN9Ff89dsq21
# aDBcO2h75MZk9CbkDpmvO89i4uDGtY+BIoLVFwdVdWdBxpu12fl1sKiJwkzT53to
# cnHlbZSgA55nlO0771PEbEo5Kpw1IqYFcoVHxexH3VJIEMRWItGbuURNZTyJyUSw
# m+xA0sX3Ed5twEocx2rBZ2sC6aLipXZN2WRnpQAZJwV70b1F3shBAKcXMzqKYjVR
# LEv2KHwITpc3q+3WjRZJ/rpS1km5IN5yZpN1SKam+i/QsMWDjkh/kAs9LMMcYqlJ
# 2p6JHhm1S00XPRSOUtxVCRlvi2x0oYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTEwMTIw
# MjQzOFowLwYJKoZIhvcNAQkEMSIEIE8Savn/JiqTPslwZ0rXHwZYQWP+lSq2x2G9
# NKzYqDdFMA0GCSqGSIb3DQEBAQUABIICAHHLLmUTfePM0fTFdzSSiRQPebcQbrxE
# qf5xQb8pAqbxMqptgS2jrfa6UFctMRQLIJfYfGtKnlc/zpFXG5xHvvOB36lmAblU
# 4/iA8MqQZylXfsp7jvS2KAE0RCBxqnB5N3T2jD9UdtuXl7DYC4d2hVliV0NCWxEu
# X5E0WAEyaHdZ9s5xHZC0DttxswtmpRY6Z5T4k/XoC7CXz1OTq0vbGd6veUzQJNQ/
# IEAArn6ch5Q8Bw7P/PnOGVQ3IkeXAnkzwKbRYCS7R2YiCMLnt/0OSfBdKl4OrlIZ
# 4N/shuwjXSI0zhZOYqG94am2Wwu7te2G5KKhTHiXbIn2IJK6OLElKttEgLDxIdEM
# vqf0fCj2t/JIyfoAHQhi2mLlxjpg22d5Dt7oTA5QTzrQaMLdP2G9QVUSFQ5cKrt2
# oLBoUKKB/nY3KHbn6pD3PTxiD3LcOkT9hPfOXMrrCChgeC+70HmeWBqdu0SypL7U
# MRfR1SCGDGUhEOSUzHEu2/uSDcXDsxh8x7csoYbiFVxhdr3Ot5ytcZHM3nOERiy0
# DPrNKmeeWkcCGWwBs739WGntotdFFIaTmqYQ8UXNVb2S0GnKAAEai1C7JGRbDDjx
# 7PwCm/UU9mxqxQlDqMEFrb2PvIAS/UXCd6apIPZPfeyr9JtClpcVWuBfn0hhNxBm
# g3QpdpPHaSNw
# SIG # End signature block
