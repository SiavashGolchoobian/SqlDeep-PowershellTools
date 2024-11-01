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

    BackupFileCleaner([bool]$HasDirectory, [string]$FilePath, [int32]$ThroughDay, [LogWriter]$Logger) {
        $this.Init($HasDirectory, $FilePath, ".bak", 10, $ThroughDay, $Logger)
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
    
    hidden [BackupFile[]] GetBackupFileList([string]$ConnectionString, [int]$FromDate, [int]$ThroughDay) {
        [BackupFile[]]$myAnswer = $null
        $myCommand = "
            DECLARE @myToday AS DATE
            DECLARE @myThroughDay AS INT
            DECLARE @myFromDate AS INT
            SET @myFromDate = -1*('" + $FromDate.ToString() + "')
            SET @myThroughDay = -1*('" + $ThroughDay.ToString() + "')
            SET @myToday=CAST(GETDATE() AS DATE)
           
            SELECT
                myMediaSet.physical_device_name as PhysicalFile
               -- ,myBackupSet.backup_start_date as BackupDate
            FROM
                master.sys.databases as myDatabase WITH (READPAST)
                LEFT OUTER JOIN master.sys.dm_hadr_availability_replica_states as myHA WITH (READPAST) on myDatabase.replica_id=myHa.replica_id
                LEFT OUTER JOIN msdb.dbo.backupset as myBackupSet WITH (READPAST) ON myBackupSet.database_name=myDatabase.name AND myBackupSet.backup_start_date BETWEEN  CAST(DATEADD(DAY,@myThroughDay,@myToday) AS DATETIME) AND CAST(DATEADD(DAY,@myFromDate,@myToday) AS DATETIME)
                LEFT OUTER JOIN msdb.dbo.backupmediafamily as myMediaSet WITH (READPAST) on myBackupSet.media_set_id=myMediaSet.media_set_id
            WHERE
                myDatabase.state=0 --online
                AND (myHA.role =1 or myHA.role is null)
                AND myMediaSet.physical_device_name  IS NOT NULL
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
        Get-ChildItem -Path $FolderPath -Recurse  | Where-Object {$_.Extension -eq $FileExtension -and $_.LastWriteTime -lt $OlderThan} | ForEach-Object{$myBackupFilePath.Add([BackupFile]::New($_.FullName))}
        $myAnswer=$myBackupFilePath.ToArray([BackupFile])
        }
        catch [Exception] {
            $this.Logger.Write($($_.Exception.Message), [LogType]::ERR)
        }
        return $myAnswer
    }

    [void] CleanFiles() {
        # Validate input parameters
        if ($null -eq $this.FileExtension -or $this.FileExtension.Trim().Length -ne 3) {
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
            $myFileList = $this.GetBackupFileList($myConnectionString, $this.DaysOld, $this.ThroughDay) | Where-Object {$_.PhysicalFile} #-lt $myDateLimit
        }
        # Loop through the files and delete them
        foreach ($myFile in $myFileList) {
            try {
               # $this.Logger.Write("Delete backup files List is " + $myFile.PhysicalFile, [LogType]::INF)
                if (Test-Path -Path $myFile.PhysicalFile -PathType Leaf) {
                    $this.Logger.Write("Delete backup files of " + $myFile.PhysicalFile, [LogType]::INF)
                    Remove-Item $myFile.PhysicalFile -Force
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
    Write-Verbose "Creating New-DatabaseShipping"
   # [bool]$hasDirectory=$false
   # if ($hasDirectory){$myhasDirectory=$true}
   # [BackupFileCleaner]::new($myhasDirectory, $FileExtension, $DaysOld, $ThroughDay, $Logger)

    if ($PSCmdlet.ParameterSetName -eq 'Directory') {
        [BackupFileCleaner]::new($true, $FilePath, $FileExtension, $DaysOld, $ThroughDay, $Logger)
        
    } else {
        [BackupFileCleaner]::new($false, "", $FileExtension, $DaysOld, $ThroughDay, $Logger)
    }

    Write-Verbose "New-DatabaseShipping Created"

}
#endregion

#region Export
Export-ModuleMember -Function New-BackupFileCleaner

# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDcV1uO3avxO3yB
# XkdvpEXZgS0af+1ovSZ5SHVgQAxTG6CCFhswggMUMIIB/KADAgECAhAT2c9S4U98
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
# BCB1VDaLKfbMQ0Ry2UZRI2YSy2hCcHmdWkDgCPG3TwhHpTANBgkqhkiG9w0BAQEF
# AASCAQDBNnCT2lh8aqlJwKmcjpFhqZC3zvmYsPVpDL3KAdTEXHb3oGO+OVGY5vfP
# yMXSvOXJUE/0MXt8BkyAWkCMJdaHH3m2jZDqEmif8mqIOnoUrJ0GYhgkEnMilmTX
# t0+fbxtluIeCWi7/FQo2B3MkkIL705MHtW4mOKEKWw4tDRHoewrgv75yDTfzH0SC
# lCh0cd3AfP707st6Ii1hqc2eJ/BDeg6bSCmRk89AHEeVB2CKveecTFqrf41JJHAD
# zTCIoVUvsl9toWJrj+7gySgNWB/h/24as48H9e823ezL7zE/Fe+Kjvh7VrA3o7uI
# nV4aGcb9rN3Q4fJKcue6DFUablC1oYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTEwMTIw
# MjQzN1owLwYJKoZIhvcNAQkEMSIEILnSgXxx67QS8Zqe6Gmh8bP67Bf1D7sD5NOL
# ZBdquDLXMA0GCSqGSIb3DQEBAQUABIICAG6+rsNW/NTXWr3Lm87cKSzBHKqUDUZB
# M+bsiPvN6jDgh1WMuOadV3BKKDb2NsPJvAADGxFBHAj40wPdZe7h07W9OJTBnOX1
# Ax2OE8oNqzt3qVBR9IWVP/rJHHBM9COIuAx9lyPd+smK3fmYCZFQTmVem0CSqL8f
# /9YI22TIsTzI4UWCbD/4lcJ5ATlvsMfsoxu4oUMl3FYIIgilWqpNVywBOYMV02Tp
# DpjqEHJWiHt/xWZgCv9CmQRVBUii3/9Xqx43ZR6u+4nGdDbTRXvUoBEHzBHlOme6
# VxJy5sSV2UWtbRqqjzBwSb6cUza29QJDwTYzMKwrt3ry6hxf81JjduDPvvN0Q2CK
# 9uC0khSlFsJBbVdKXjWWyEzOWXVVRtxMaiXvK7YLurog4OV5ZDwlP+dUPziQkr6I
# Ta3PviW9nHXbx2XN0C870bz+ouNgXrdVKc0SH63N9QAzShG2ABSse8fxH9JMeQSU
# KWNiHros/tN6FFVJDs7a8EkZhrUNg7WTSSRCnwfFNhZNAmErpY8DTyxqX3u1rNCE
# bUMr1GUOs3LM2moL+kaPfYuaZqouXzbs7TNd09HHEduVh/TWiqD1D18zWvMJ9hfh
# 1QwCtetTXbwht/s7ydpjvO5YQenMdzMW7jRPmyeYFt3pLHwuJZHq4xurXolotNCS
# GmY8S0z4insr
# SIG # End signature block
