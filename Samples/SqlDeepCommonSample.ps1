Using module .\SqlDeepCommon.psm1

#Sample 1:  Clear input text from any ProhibitedPhrases
[string[]]$myBlackList=@(';','WHERE')
'SELECT name FROM sys.databases WHERE 1=1;','SELECT name FROM sys.databases WHERE 2=2;','Hello World' | ForEach-Object{Clear-Text -Text $_ -ProhibitedPhrases $myBlackList}

#Sample 2:  Clear parameter value from any bad characters
"SELECT name FROM sys.databases WHERE 1={1};","SELECT name FROM sys.databases WHERE name like '%';","Hello World" | ForEach-Object{Clear-SqlParameter -ParameterValue $_ -RemoveWildcard -RemoveBraces}

#Sample 3.1:  Download BLOB from database to a file
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Export-DatabaseBlob -ConnectionString $myConnectionString -CommandText "SELECT CAST('Hello World' AS VARBINARY(MAX)) AS BlobData" -DestinationFilePath "E:\Log\test.txt"
$mySqlQueryResult

#Sample 3.2:  Download multiple BLOB from database to a directory
[hashtable]$myFileListQuery;    #This Hashtable should have filename as hashtable item key and BLOB retrive query as hastable item value
[string]$myConnectionString="Data Source=DB-MN-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=EventLog;Integrated Security=True;TrustServerCertificate=True;Encrypt=True";
[string]$myDestinationFolderPath="C:\Repo";
[bool]$myAnswer=$false;
$myFileQueryList=@{}
$myFileQueryList.("file1.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file1.txt'"
$myFileQueryList.("file2.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file2.txt'"
$myFileQueryList.("file3.txt")="SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [IsEnabled]=1 AND [ItemChecksum]=[SubscriberItemChecksum] AND [ItemName]=N'file3.txt'"
<#
--OR to fill Hashtable via query you can use bellow statements
[string]$myCommand="SELECT [myItems].[ItemName],[myItems].[SubscriberItemId] FROM [SqlDeep].[repository].[dbafn_get_subscriber_item_and_dependencies] ('Saipa_SqlDeepDatabaseShipping.ps1',Null,Null) AS myItems WHERE [myItems].[IsEnabled]=1"
$myRecord=Invoke-Sqlcmd -ConnectionString $myConnectionString -Query $myCommand -OutputSqlErrors $true -QueryTimeout 0 -OutputAs DataRows -ErrorAction Stop
$myRecord
if ($null -ne $myRecord) {
    foreach ($myRow in $myRecord){
        $myFileQueryList.Add($myRow.ItemName.ToString(),"SELECT TOP 1 [ItemContent] FROM [SqlDeep].[repository].[Subscriber] WITH (READPAST) WHERE [SubscriberItemId]=" + $myRow.SubscriberItemId.ToString())
    }
}
#>
try{
    [int]$myRequestCount=$myFileQueryList.Count
    [int]$myDownloadedCount=0
    [bool]$myDownloadResult=$false
    if ($myDestinationFolderPath[-1] -ne "\") {$myDestinationFolderPath+="\"}
    foreach ($myItem in $myFileQueryList.GetEnumerator()) {
        [string]$myFile=$myItem.Key.ToString().Trim()
        [string]$myBlobQuery=$myItem.Value.ToString().Trim()
        $myFilePath=$myDestinationFolderPath + $myFile
        If ($myFile.Length -gt 0 -and $myDestinationFolderPath.Length -gt 0) {
            Write-Output ("Multiple file downloader: Downloading " + $myFilePath + " ...")
            $myDownloadResult=Export-DatabaseBlob -ConnectionString $myConnectionString -CommandText $myBlobQuery -DestinationFilePath $myFilePath
        } else {
            $myDownloadResult=$false
        }
        if ($myDownloadResult) {$myDownloadedCount+=1}
    }
    if ($myDownloadedCount -eq $myRequestCount) {$myAnswer=$true}
} catch {
    $myAnswer=$false
    Write-Error($_.ToString())
}
Write-Output $myAnswer

#Sample 4:  Query from database
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Read-SqlQuery -ConnectionString $myConnectionString -Query "SELECT database_id,name FROM sys.databases"
$mySqlQueryResultUnionAll="SELECT database_id,name FROM sys.databases","select 1 as database_id,name from sys.all_objects" | ForEach-Object{Read-SqlQuery -ConnectionString $myConnectionString -Query $_}
$mySqlQueryResultUnionAll

#Sample 5:  Invoke Sql Command
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Invoke-SqlCommand -ConnectionString $myConnectionString -Command "CREATE Database Test01"

#Sample 6:  Test Database Connection
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
Test-DatabaseConnection -ConnectionString $myConnectionString -DatabaseName 'Test'

#Sample 7:  Test Instance Connection
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
Test-InstanceConnection -ConnectionString $myConnectionString

#Sample 8:  Get Instance Info
[string]$myConnectionString='Data Source=DB-C1-DLV01.SQLDEEP.LOCAL\NODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;User=sa;Password=P@ssW0rd'
$mySqlQueryResult=Get-InstanceInformation -ConnectionString $myConnectionString -ShowRelatedInstanceOnly
$mySqlQueryResult=Get-InstanceInformation

#Sample 9:  Get Instance Info From Register Server
[string]$myConnectionString='Data Source=DB-MN-DLV02.SQLDEEP.LOCALNODE,49149;Initial Catalog=master;TrustServerCertificate=True;Encrypt=True;Integrated Security=True;'
$myExeptionSeverList = "DB-BK-DBV02.SQLDEEP.LOCAL\NODE,49149' ,'DB-DR-DGV01.SQLDEEP.LOCAL\NODE,49149" #'DB-TEST-DTV04.SQLDEEP.LOCAL\NODE,49149'
$myFilter = "Test"
$myServerList = Get-InfoFromSqlRegisteredServers -MonitoringConnectionString $myConnectionString -ExeptionList $myExeptionSeverList -FilterGroup $myFilter 

#Sample 10:  Get database Info 
$myConnectionStringList ="...\SSISDB,49149",".....SqlDeep\node,49149"
$myExeptionDatabaseList ="SSISDB","SqlDeep"
$myConnectionStringList | Get-DatabaseList -ExcludedList $myExeptionDatabaseList
# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDZLIrU15yk1twV
# TwsbpJO0530Pyl+qpsJMpxtZoydD+aCCFhswggMUMIIB/KADAgECAhAT2c9S4U98
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
# BCA117VLtQPq5sNs4xtNYp71M8SdWZL/XshVJCc7zxJ/ljANBgkqhkiG9w0BAQEF
# AASCAQA1zluuBSpH6qDPUmif7dp7kzmSNG8txclQ5cT+NQLkVhOQCqduQJP5j1bR
# EyqKqcG5nSVw28vIQtICMPO8M/4kun96rTA1FyUqpnwJ6jW5bjN/kqqt4z8gCPVv
# xmcPUxl5Gw4zdiIprV32nMKjeq8PE0gwKN0hDW6XLX/rw3+ZAmW0YpU67RJEUWSC
# kqOH8x5ylm+sA6Nmo8n51WW+WFUlX7aHa/oqgwq5UbLaf9K0d0bqLm0PrFmwWkcV
# HW4tetHmCUd/itpKATKvGSA6CoAKwCCJT7/tQ5YSpy2i+eXS7wkigALLE6BROEYj
# wiFwo42xz6HUAq+KmZF/IWcd4KcloYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTEwNDIw
# MDc1MVowLwYJKoZIhvcNAQkEMSIEIJtltGE6bVj6Fm/jkhJ02rV7q+FpRfJi4KMy
# wdtqXo+xMA0GCSqGSIb3DQEBAQUABIICAGRFVGREZWMFVYazXhoUyBF8XBqCAAzV
# 3PnEEkbWpjTHsihuyZ0C+k8n0htzHkq7QnRQcGkho0wPFfBisMWm/YO0Xxly5t5b
# 9jydbyrJaR1lm1jacamUfNInWi+plab//CF09MWrTER8wT+2/ClRqpm9ve6mCe1e
# 4jtno+JHk15HgcleRwRVhl0tN1WB/0DglwBm9iGJjpNqeDmVPSMlFIn+t8ymz4Jc
# j+o6KB+E3VPdh+saFExcWVpKx+xdweQYdCaQTIveaWzt3dhYmTb68LOeceNDOoW+
# YJSem+BX5439ZFb4wWEqz3QmP7LLjKOoo3RXWYWVVqrjYqE3BOvo5kGFLCA5QQmy
# lG11NLRR15bGQupZI0qIhxL83W4ItKmqRT9sYz9HSC247uyu8Y9lmE+abKdMz9eL
# 3ot+k8qSoq1Dmi4MVY6ozVyaYr6joKqnkQvzljfxksCC5DQBynNUkP6CJLkxRWLE
# 661ZDmtyYt6G+Kubg5quOSOpN+BZIiTXvBpzS/Reoz+MmKbhiRzEibx9qpCGjdsc
# 2ZjChc3Fk/SXJZCRaRR3xMI5L1BJkW59FbWcFLUOIjZWlVNHyLSc7I3qq7cX0ZW1
# l8u6XgzXktRqVBnLaAswU/NBwFvm/314sIo1mGVgLc+Io1FHHs22Cysj6X7sukf2
# WLEeGva42FWm
# SIG # End signature block
