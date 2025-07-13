Using module .\SqlDeepLogWriter.psm1
Class BackupFile {
    [string]$PhysicalFile
    
    BackupFile([string]$PhysicalFile){
        $this.PhysicalFile=$PhysicalFile
    }
}
class BackupFileCleaner {
    [bool]$HasDirectory = $false
    [string]$FilePath = ""
    [string]$FileExtension = ".bak"
    [int]$DaysOld = 10
    [int]$ThroughDay = 100
    hidden [LogWriter]$Logger

    BackupFileCleaner([bool]$HasDirectory, [string]$FileExtension, [string]$FilePath, [int32]$ThroughDay, [LogWriter]$Logger) {
        $this.Init($HasDirectory, $FilePath, $FileExtension, 10, $ThroughDay, $Logger)
    }

    BackupFileCleaner([bool]$HasDirectory, [string]$FilePath, [string]$FileExtension, [int32]$DaysOld, [int32]$ThroughDay, [LogWriter]$Logger) {
        $this.Init($HasDirectory, $FilePath, $FileExtension, $DaysOld, $ThroughDay, $Logger)
    }

    Init([bool]$HasDirectory, [string]$FilePath, [string]$FileExtension, [int32]$DaysOld, [int32]$ThroughDay, [LogWriter]$Logger) {
        $this.HasDirectory = $HasDirectory
        $this.FilePath = $FilePath
        $this.FileExtension = $FileExtension
        $this.DaysOld = $DaysOld
        $this.ThroughDay = $ThroughDay
        $this.Logger = $Logger
    }
  #  $Logger = [WriteLog]::new($this.ErrorFile)
#region functions
    hidden [string] GetCurrentInstance() {
        [string]$myAnswer = ""
        try {
            $myInstanceName = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
            $myMachineName = $env:COMPUTERNAME
            $myRegFilter = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.' + $myInstanceName + '\MSSQLServer\SuperSocketNetLib\Tcp\IPAll'
            $myPort = (Get-ItemProperty -Path $myRegFilter).TcpPort.Split(',')[0]
            $myDomainName = (Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem).Domain
            $myConnection = $myMachineName
            if ($myDomainName) { $myConnection += '.' + $myDomainName }
            if ($myInstanceName -ne "MSSQLSERVER") { $myConnection += '\' + $myInstanceName }
            if ($myPort) { $myConnection += ',' + $myPort }
            $myAnswer = $myConnection
        }
        catch {
            $this.Logger.Write((($_.ToString()).ToString(),[LogType]::WRN))
        }
        return $myAnswer
    }
    
    hidden [BackupFile[]] GetBackupFileList([string]$ConnectionString, [int]$FromDate, [int]$ThroughDay, [string]$FileExtension) {
        [BackupFile[]]$myAnswer = $null
        $myCommand = "
            DECLARE @myToday AS DATE
            DECLARE @myThroughDay AS INT
            DECLARE @myFromDate AS INT
            DECLARE @myFileExtension AS CHAR(4)

            SET @myFromDate = -1*ABS(" + $FromDate.ToString() + ")
            SET @myThroughDay = -1*ABS(" + $ThroughDay.ToString() + ")
            SET @myToday=CAST(GETDATE() AS DATE)
            SET @myFileExtension = '" + $FileExtension + "'
               
            CREATE TABLE #myReplicaId (replica_id UNIQUEIDENTIFIER )
            INSERT INTO #myReplicaId (replica_id)
	            SELECT myHA.Replica_id FROM  master.sys.dm_hadr_availability_replica_states AS myHA WITH (READPAST)  WHERE  ( myHA.role = 1 OR myHA.role IS NULL )


            SELECT 
                myMediaSet.physical_device_name AS PhysicalFile
            -- ,myBackupSet.backup_start_date as BackupDate
            FROM
                master.sys.databases AS myDatabase WITH (READPAST)
                LEFT OUTER JOIN #myReplicaId AS myHA WITH (READPAST)  ON myDatabase.replica_id = myHA.replica_id
                LEFT OUTER JOIN msdb.dbo.backupset AS myBackupSet WITH (READPAST)  ON myBackupSet.database_name = myDatabase.name
                AND myBackupSet.backup_start_date  BETWEEN CAST(DATEADD(DAY, @myThroughDay, @myToday) AS DATETIME) AND CAST(DATEADD(DAY, @myFromDate, @myToday) AS DATETIME)
                LEFT OUTER JOIN msdb.dbo.backupmediafamily AS myMediaSet WITH (READPAST) ON myBackupSet.media_set_id = myMediaSet.media_set_id
            WHERE myDatabase.state = 0 --online
     
                    AND myMediaSet.physical_device_name IS NOT NULL
                    AND RIGHT(myMediaSet.physical_device_name, 4) = @myFileExtension

            DROP TABLE IF EXISTS #myReplicaId
"
 
        try {
            [System.Data.DataRow[]]$myRecords=$null
                $myRecords = Invoke-Sqlcmd -ServerInstance $ConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -ErrorAction Stop 
                [System.Collections.ArrayList]$myBackupFilePath=$null
                $myBackupFilePath=[System.Collections.ArrayList]::new()
                $myRecords|ForEach-Object{$myBackupFilePath.Add([BackupFile]::New($_.PhysicalFile))}
                $myAnswer=$myBackupFilePath.ToArray([BackupFile])
            }
        catch [Exception] {
            $this.Logger.Write($($_.Exception.Message), [LogType]::ERR)
        }
        return $myAnswer
    }

    hidden [BackupFile[]] GetBackupFileList([string]$FolderPath,[string]$FileExtension,[datetime]$OlderThan){
        try {
        [BackupFile[]]$myAnswer = $null
        [System.Collections.ArrayList]$myBackupFilePath=$null
        $myBackupFilePath=[System.Collections.ArrayList]::new()
       # Get-ChildItem -Path $FolderPath -Recurse  | ForEach-Object{Write-Host ($_.FullName + $_.Extension + $_.LastWriteTime)} #|  Where-Object {$_.Extension -eq $FileExtension -and $_.LastWriteTime -lt $OlderThan} | ForEach-Object{$myBackupFilePath.Add([BackupFile]::New($_.FullName))}
        Get-ChildItem -Path $FolderPath -Recurse  |  Where-Object {$_.Extension -eq $FileExtension -and $_.LastWriteTime -lt $OlderThan} | ForEach-Object{$myBackupFilePath.Add([BackupFile]::New($_.FullName))}
        $myAnswer=$myBackupFilePath.ToArray([BackupFile])
        }
        catch [Exception] {
            $this.Logger.Write($($_.Exception.Message), [LogType]::ERR)
        }
        return $myAnswer
    }

    [void] CleanFiles() {
        # Validate input parameters
        if ($null -eq $this.FileExtension -or $this.FileExtension.Trim().Length -ne 4) {
            $this.Logger.Write("FileExtension is not true, use it .bak.", [LogType]::WRN)
            $this.FileExtension = ".bak"
        }

        # Calculate the date limit
        [BackupFile[]]$myFileList=$null
        [datetime]$myDateLimit = (Get-Date).AddDays(-$this.DaysOld)

        # Get all files in the target path with the specified extension that are older than the date limit
        $this.Logger.Write("Get backupFile List for delete from "+ $this.HasDirectory , [LogType]::INF) 
        if ($this.HasDirectory) {
            $myFileList=$this.GetBackupFileList($this.FilePath,$this.FileExtension,$myDateLimit)
        } else {
            $myConnectionString = $this.GetCurrentInstance()
            $this.Logger.Write("Get Backup File List for delete from " + $myConnectionString , [LogType]::INF)
            $myFileList = $this.GetBackupFileList($myConnectionString, $this.DaysOld, $this.ThroughDay ,$this.FileExtension) | Where-Object {$_.PhysicalFile} #-lt $myDateLimit
        }
        # Loop through the files and delete them
        foreach ($myFile in $myFileList.PhysicalFile) {
            try {
               # $this.Logger.Write("Delete backup files List is " + $myFile.PhysicalFile, [LogType]::INF)
                if (Test-Path -Path $myFile -PathType Leaf) {
                    $this.Logger.Write("Delete backup files of " + $myFile, [LogType]::INF)
                    Remove-Item $myFile -Force
                }
            }
            catch [Exception] {
                $this.Logger.Write($($_.Exception.Message), [LogType]::ERR)
            }
        }
    }
#endregion
}

#region Functions
Function New-BackupFileCleaner {
    [CmdletBinding(DefaultParameterSetName = 'Directory')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Directory')][string]$FilePath,
        [Parameter(Mandatory = $false, ParameterSetName = 'Instance')][switch]$UseCurrentInstance,
        [Parameter(Mandatory = $false)][string]$FileExtension,
        [Parameter(Mandatory = $false)][int32]$DaysOld,
        [Parameter(Mandatory = $false)][int32]$ThroughDay,
        [Parameter(Mandatory = $true)][LogWriter]$Logger
    )
    Write-Verbose "Creating New-BackupFileCleaner"

    if ($PSCmdlet.ParameterSetName -eq 'Directory') {
        [BackupFileCleaner]::new($true, $FilePath, $FileExtension, $DaysOld, $ThroughDay, $Logger)
        
    } else {
        [BackupFileCleaner]::new($false, "", $FileExtension, $DaysOld, $ThroughDay, $Logger)
    }

    Write-Verbose "New-BackupFileCleaner Created"

}
#endregion

#region Export
Export-ModuleMember -Function New-BackupFileCleaner
#endregion

# SIG # Begin signature block
# MIIcAgYJKoZIhvcNAQcCoIIb8zCCG+8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAudeT85jl+WZ15
# 7RzO0lgGEaOJll2ONaK8IUYV6aU0oaCCFlIwggMUMIIB/KADAgECAhAT2c9S4U98
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
# /xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQwgga0MIIEnKADAgEC
# AhANx6xXBf8hmS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcw
# MDAwMDBaFw0zODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1l
# U3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZ
# loMsVO1DahGPNRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM
# 2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj
# 7GH8BLuxBG5AvftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQ
# Sku2Ws3IfDReb6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZ
# lDwFt+cVFBURJg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+
# 8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRx
# ykvq6gbylsXQskBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yG
# OP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqI
# MRvUBDx6z1ev+7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm
# 1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBj
# UwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729T
# SunkBnx6yuKQVvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4c
# D08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUF
# BwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEG
# CCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAX
# MAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaA
# HP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQ
# M2qEJPe36zwbSI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt
# 6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7
# bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmS
# Nq1UH410ANVko43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69
# M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnF
# RsjsYg39OlV8cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmM
# Thi0vw9vODRzW6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oa
# Qf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx
# 9yHbxtl5TPau1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3
# /BAPvIXKUjPSxyZsq8WhbaM2tszWkPZPubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN
# 8QWC0cR2p5V0aDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQg
# VGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAw
# MDAwMFoXDTM2MDkwMzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRp
# Z2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBU
# aW1lc3RhbXAgUmVzcG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBANBGrC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx
# +wvA69HFTBdwbHwBSOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvN
# Zh6wW2R6kSu9RJt/4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlL
# nh00Cll8pjrUcCV3K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmn
# cOOMA3CoB/iUSROUINDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhw
# UmotuQhcg9tw2YD3w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL
# 4Q1OpbybpMe46YceNA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnD
# uSeHVZlc4seAO+6d2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCy
# FG1roSrgHjSHlq8xymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7a
# SUROwnu7zER6EaJ+AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+gi
# AwW00aHzrDchIc2bQhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGj
# ggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBD
# z2GM6DAfBgNVHSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8E
# BAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGF
# MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUH
# MAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRH
# NFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBW
# MFSgUqBQhk5odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# RzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkw
# FzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3x
# HCcEua5gQezRCESeY0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh
# 8/YmRDfxT7C0k8FUFqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZS
# e2F8AQ/UdKFOtj7YMTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/
# JQ/EABgfZXLWU0ziTN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1u
# NnzQVTeLni2nHkX/QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq
# 8/gVutDojBIFeRlqAcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwi
# CZ85EE8LUkqRhoS3Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ
# +8Hggt8l2Yv7roancJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1
# R9xJgKf47CdxVRd/ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstr
# niLvUxxVZE/rptb7IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWu
# iC7POGT75qaL6vdCvHlshtjdNXOCIUjsarfNZzGCBQYwggUCAgEBMCowFjEUMBIG
# A1UEAwwLc3FsZGVlcC5jb20CEBPZz1LhT3yMSHZ6qu04YqIwDQYJYIZIAWUDBAIB
# BQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYK
# KwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG
# 9w0BCQQxIgQgoUf5kAgk8Iz9Sx1OfFeZLpPp2AI4ugh0nrvQeQDN6gUwDQYJKoZI
# hvcNAQEBBQAEggEAps4I4DdFxLNPm+xz0Dg+D6D12kZm+LzPgN+cDaGoagpu+lJj
# Qhasjfcjz5KN/ijKXVIx0bIq5myvnrVPcZ0RIvhBoxOJM0j1ffQnsmbrvtk85hh/
# Tn6ElDAP3ksevVo0FaG5y+yTfgCFR4J24OT4YfY0wNfvfamgxKAbHCdAswV0+GWt
# UMdg51rIjwPA3am6nNjJIE+SUD4/ZrQASmicfQK0NFGG5UwPor2cXI2Po0CzCk5V
# 4jP4IxQg7QITIkKMEtntJd4X3pHeN79GKeptlmdq/vr+MHVd0CWes5TMGYD7wRts
# YzudVp8fyKfLDNPAjlNTjG5VmMd209iF6mIiG6GCAyYwggMiBgkqhkiG9w0BCQYx
# ggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcg
# UlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEFgtHEdqeVdGgwDQYJYIZI
# AWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJ
# BTEPFw0yNTA3MTMxMDIxMDdaMC8GCSqGSIb3DQEJBDEiBCDhdDx0iToVIGtW5Gwe
# Gxnv3noH1F75kJ2hR9rBAsPdYTANBgkqhkiG9w0BAQEFAASCAgDFt8gOl9lemqvg
# nDMXbd900xnFyOE5ntvtfM/GNxUcC449i3B8AGO4y/IIivXuXXxONNUg2H7sK6yc
# SLAWFyU+OnxBuNaTiEK2gho7Ip8rehVpZSJFm1mZB6H85wPjICN5dsM8xxr7QW6v
# oWMTtZGvwe0pZAFEIJtd/2W7h4CS+aKiYehU9vhQFaEp19elKN90It5FAxvzOdFI
# k6DiAXIAM/f5kLinKSLk1m9RY2DVrnp3FmTcmEX2Dpi+pKl5fyPatgesTfp3wPda
# XA5PB7feI+ICug/d6jtBfqCS0swMSaZ2K0UFSxMCEkGLb6k78DcU93XnioLwGYwX
# 73N9NHVUKXR2sYJvi3BFawEKGyaQgNQDxhzNerHKqMu5TLno/RHU2v8qK2T9tN3o
# h0MhN+FaVfPhZ57dUjVAQVYBkUmjKJEkdtjHDETO89lTLioEi+wTwbMxqOKFy/o2
# F3a7xvgq4d71fkaLODeTxhRLFKbkY+Tr5XJy1l0cOr2xJpREL1URgRQVn3izXlnW
# WtWn+kb14zL92Jz6D7DmYoWER5pYTDug1JSPzJ701DQHX5fip0NF2o3dET/D5HMD
# LWrE2uo8J4W4s6NCjUVdM0Uz4nj2TOquiS5QPqF8dzmVt93wq3WXeVf87BbmpPoF
# wMxwQVekBiN3iDbsmTNdBcMmL6XLOA==
# SIG # End signature block
