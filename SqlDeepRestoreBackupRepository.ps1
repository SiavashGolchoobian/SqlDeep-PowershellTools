<#  
.SYNOPSIS  
    Restores databases from backup files Repository.  
.DESCRIPTION  
    This script restores all databases from the specified backup repository  
    and moves the data and log files to defined directories.  
.AUTHOR  
    Fatemeh Moniri 
.DATE  
    2024-09-20  
#>  
function RestoreAllDatabasesFromRepository {
    param (
        [string]$RepositoryPath,
        [string]$RestoreConnectionString,
        [string]$NewDataPath,
        [string]$NewLogPath
    )

    # Get all backup files from the repository
    $myBackupFiles = Get-ChildItem -Path $repositoryPath -Filter *.bak

    foreach ($myFile in $myBackupFiles) {
        # Initialize variables  
        $myDatabaseName = $null  
        $myFileList = $null  
        $myHeaderInfo = $null  
        # Get the logical names of the files in the backup
        try {
            $myFileList = Invoke-Sqlcmd -ConnectionString $RestoreConnectionString -Query "RESTORE FILELISTONLY FROM DISK = '$($myFile.FullName)'"
        }
        catch {
            Write-Host "Error retrieving file list for '$($myFile.FullName)'. Error: $_"  
            continue  # Skip to the next backup file  
        }
        
        try {
            $myHeaderInfoQuery = "RESTORE HEADERONLY FROM DISK = N'$($myFile.FullName)';"  
            $myHeaderInfo = Invoke-Sqlcmd -Query $myHeaderInfoQuery -ConnectionString $RestoreConnectionString  
        }
        catch {
            Write-Host "Error retrieving header information for '$($myFile.FullName)'. Error: $_"  
            continue  # Skip to the next backup file  
        }

        
        $myDatabaseName = $myHeaderInfo.DatabaseName
        $myNewDataPath = $NewDataPath+$myDatabaseName
        $myNewLogPath = $NewLogPath+$myDatabaseName
        # Construct the MOVE options for the RESTORE command
        $MymoveCommand = @()
        foreach ($file in $myFileList) {
            if ($file.Type -eq 'D') {
                if (-not (Test-Path -Path $myNewDataPath)) {  
                    New-Item -ItemType Directory -Path $myNewDataPath  
                } 
                $MymoveCommand += "MOVE '$($file.LogicalName)' TO '$myNewDataPath\$($file.LogicalName).$($file.PhysicalName.Split('.')[-1])'"
            } elseif ($file.Type -eq 'L') {
                if (-not (Test-Path -Path $myNewLogPath)) {  
                    New-Item -ItemType Directory -Path $myNewLogPath  
                } 
                $MymoveCommand += "MOVE '$($file.LogicalName)' TO '$myNewLogPath\$($file.LogicalName).$($file.PhysicalName.Split('.')[-1])'"
            }
        }

        # Join the MOVE options into a single string
        $myMoveCommandString = $MymoveCommand -join ", "

        # Restore the database
        try {
            $myQuery = "RESTORE DATABASE [$myDatabaseName] FROM DISK = '$($myFile.FullName)' WITH $myMoveCommandString, NORECOVERY ,STATS =10 "
            Write-Host $myQuery
            Invoke-Sqlcmd  -ConnectionString $RestoreConnectionString -Query $myQuery -ConnectionTimeout 0 -QueryTimeout 0
            Write-Host "Successfully restored database '$myDatabaseName' from '$($myFile.FullName)'."  
        }
        catch {
            
            Write-Host "Error restoring database '$myDatabaseName' from '$($myFile.FullName)'. Error: $_"  
        }
    }
}

# SIG # Begin signature block
# MIIb6gYJKoZIhvcNAQcCoIIb2zCCG9cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCABNlQXpMhMe+Qx
# Vb1Uh3OoQ5R1EKuVhz05gR7KQtMQZ6CCFjowggL8MIIB5KADAgECAhBuGGiP9rFT
# sEjfxjEo89WdMA0GCSqGSIb3DQEBCwUAMBYxFDASBgNVBAMMC3NxbGRlZXAuY29t
# MB4XDTI2MDcyODEyMjQ1MVoXDTI3MDcyODEyNDQ1MVowFjEUMBIGA1UEAwwLc3Fs
# ZGVlcC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDNOXX1vdSL
# U0u489johy9jEFIcvpJoJx0CWOasotOkoW0AJKh8abBNWcGUMbz+BONVSvr9lEMV
# 8HaWBUpnst/7Y7di49A/sVJgljT26H2K7jJ0Ot5342TKYp5NlMZWS+yLugHXXpQ8
# pAHwjeU0E6IIqDZUMc3aXcz13lxH2Lmomifx7h80JdjTnKg3VEGSt9Nk7Bt3kTHW
# AHZo6a/uVQuTNRVpFHg5baZs6pW4rmcyF2GrZYC1bbuwS3RfI442GB67oqS+EZv5
# lGRn0ZGKisoJ5sVHzsZrZnDKtATEY7j93diosWk4Ylh/isl56RFBVSp0q5Wh3Y7u
# TlBepciv+YhhAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggr
# BgEFBQcDAzAdBgNVHQ4EFgQUpj47586JqBg2vR/KExFCqFUrEgMwDQYJKoZIhvcN
# AQELBQADggEBAEynF/H5ccJzVOfxmFmOaK/sPCFaJeAoU0kfACVVkjVcfzvYoJSu
# LIio+7fihza5JI6UcrK67NPU6DKLM3mGrdh0XFG7lAVGQ8u0f22+PC8liPib9G2V
# g6QDM04Y5/jdJolxmV4lyAO5rRaU5GQ9Nv9wQP0bpKOtVu2BC+synzlqSSRp23wD
# x3dgi06D+j2OIjGP50bJhdrPagmtT2+UeOWTDHBkvRtAh3hwwbPM7kl0oxRZsJnM
# AjPgc7CxptFxtyylL9noP/48/HW/gm6AN4HWfJglprZFrEUX31BaROBcG65zTt0a
# ZxvHT7NkSYvZ+pawSBBfrc0NXUhK5IPBJLcwggWNMIIEdaADAgECAhAOmxiO+dAt
# 5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBa
# Fw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3E
# MB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKy
# unWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsF
# xl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU1
# 5zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJB
# MtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObUR
# WBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6
# nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxB
# YKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5S
# UUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+x
# q4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIB
# NjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMC
# AYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0Nc
# Vec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnov
# Lbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65Zy
# oUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFW
# juyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPF
# mCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9z
# twGpn1eqXijiuZQwgga0MIIEnKADAgECAhANx6xXBf8hmS5AQyIMOkmGMA0GCSqG
# SIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRy
# dXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0zODAxMTQyMzU5NTlaMGkx
# CzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4
# RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYg
# MjAyNSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC0eDHTCphB
# cr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGPNRcybEKq+RuwOnPhof6p
# vF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHe
# HYNnQxqXmRinvuNgxVBdJkf77S2uPoCj7GH8BLuxBG5AvftBdsOECS1UkxBvMgEd
# gkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDReb6e3mmdglTcaarps0wjU
# jsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBURJg6zMUjZa/zbCclF83bR
# VFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeS
# LsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQskBBBnGy3tW/AMOMCZIV
# NSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL
# 6s36czwzsucuoKs7Yk/ehb//Wx+5kMqIMRvUBDx6z1ev+7psNOdgJMoiwOrUG2Zd
# SoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFU
# eEY0qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/
# BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6yuKQVvYv1Ensy04wHwYDVR0j
# BBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0
# cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0
# cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8E
# PDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVz
# dGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEw
# DQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/
# T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQM2qEJPe36zwbSI/mS83afsl3YTj+IQhQ
# E7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9r
# EVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y
# 1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1UH410ANVko43+Cdmu4y81hjajV/gx
# dEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3t
# y9qIijanrUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8cipDoq7+qNNjqFzeGxcy
# tL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRzW6AxnJll38F0cuJG7uEB
# YTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud
# /v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx9yHbxtl5TPau1j/1MIDpMPx0LckTetiS
# uEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPSxyZsq8WhbaM2tszWkPZP
# ubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN8QWC0cR2p5V0aDANBgkqhkiG9w0BAQsF
# ADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNV
# BAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hB
# MjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAwMDAwMFoXDTM2MDkwMzIzNTk1OVowYzEL
# MAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJE
# aWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVzcG9uZGVyIDIwMjUg
# MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANBGrC0Sxp7Q6q5gVrMr
# V7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx+wvA69HFTBdwbHwBSOeLpvPnZ8ZN+vo8
# dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvNZh6wW2R6kSu9RJt/4QhguSssp3qome7M
# rxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlLnh00Cll8pjrUcCV3K3E0zz09ldQ//nBZ
# ZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmncOOMA3CoB/iUSROUINDT98oksouTMYFO
# nHoRh6+86Ltc5zjPKHW5KqCvpSduSwhwUmotuQhcg9tw2YD3w6ySSSu+3qU8DD+n
# igNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL4Q1OpbybpMe46YceNA0LfNsnqcnpJeIt
# K/DhKbPxTTuGoX7wJNdoRORVbPR1VVnDuSeHVZlc4seAO+6d2sC26/PQPdP51ho1
# zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCyFG1roSrgHjSHlq8xymLnjCbSLZ49kPmk
# 8iyyizNDIXj//cOgrY7rlRyTlaCCfw7aSUROwnu7zER6EaJ+AliL7ojTdS5PWPsW
# eupWs7NpChUk555K096V1hE0yZIXe+giAwW00aHzrDchIc2bQhpp0IoKRR7YufAk
# prxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGjggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0G
# A1UdDgQWBBTkO/zyMe39/dfzkXFjGVBDz2GM6DAfBgNVHSMEGDAWgBTvb1NK6eQG
# fHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEy
# NTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vY3JsMy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hB
# MjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcB
# MA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3xHCcEua5gQezRCESeY0ByIfjk9iJP2zWL
# pQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh8/YmRDfxT7C0k8FUFqNh+tshgb4O6Lgj
# g8K8elC4+oWCqnU/ML9lFfim8/9yJmZSe2F8AQ/UdKFOtj7YMTmqPO9mzskgiC3Q
# YIUP2S3HQvHG1FDu+WUqW4daIqToXFE/JQ/EABgfZXLWU0ziTN6R3ygQBHMUBaB5
# bdrPbF6MRYs03h4obEMnxYOX8VBRKe1uNnzQVTeLni2nHkX/QqvXnNb+YkDFkxUG
# tMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq8/gVutDojBIFeRlqAcuEVT0cKsb+zJNE
# suEB7O7/cuvTQasnM9AWcIQfVjnzrvwiCZ85EE8LUkqRhoS3Y50OHgaY7T/lwd6U
# Arb+BOVAkg2oOvol/DJgddJ35XTxfUlQ+8Hggt8l2Yv7roancJIFcbojBcxlRcGG
# 0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1R9xJgKf47CdxVRd/ndUlQ05oxYy2zRWV
# FjF7mcr4C34Mj3ocCVccAvlKV9jEnstrniLvUxxVZE/rptb7IRE2lskKPIJgbaP5
# t2nGj/ULLi49xTcBZU8atufk+EMF/cWuiC7POGT75qaL6vdCvHlshtjdNXOCIUjs
# arfNZzGCBQYwggUCAgEBMCowFjEUMBIGA1UEAwwLc3FsZGVlcC5jb20CEG4YaI/2
# sVOwSN/GMSjz1Z0wDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAig
# AoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgEL
# MQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgzCuX2PC2WwttxmiiNteZ
# F5qD/ub1DhgLzXHyYMgDEfwwDQYJKoZIhvcNAQEBBQAEggEAWadT21yK21m9k7Pk
# Ztrdv7y+qCzg2g9UIfWM7rj5ms7/Ghpi/tfMO/8V4G/FDJ5yMZMV5OWeAyfOlpn3
# sgmdj4QdOtXELR4+ecxfbYeQ5m9qCTE0RpyNBJYNu/PQjaTSgdP0zzrg7um8lbgS
# 4WI99SH6DGZd4n15jtu7w8ICzxIkrzpDFd42uMgRObwidoRG6v4Am3UpPXZ5ZHM4
# b5L4N85KoN9pOmS8Xj/WUG4ntHMynYmFumSrw/0ujg5IkNULvc7UbuWVZTXoZ8Lq
# 0SGTlv9PP8AI/sfL8wIPlE4vOsN0e2s/498FI4UED5XCis8vXDJp91n/oFUzBnQH
# +aX4laGCAyYwggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYT
# AlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQg
# VHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEC
# EAqA7xhLjfEFgtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA5MDMwOTI1NTRaMC8GCSqG
# SIb3DQEJBDEiBCDwHzUSv8Y1XdDG4Oi9S76UYXf9SMyieJqpkTvC06gNsjANBgkq
# hkiG9w0BAQEFAASCAgBHSCHlCZciD41QL3cEqSm96f41JEKebK33RGp/Flw/MieX
# igw9h7EamSJwwKBQYu7uyU2/NdBI/3BSi7gQ5yRQb87M2a1BTxuXP1+hcn1GimOx
# eYe591t4YEXqXm7dkCIzc+aJZUmp7EcV+Bndt5BLiPd61EoYeehtQ6xzAryfD6+P
# slVf2bJOOtuXL0dHmx+Ua5v/+m2mvYYLPaTMf/lJSDto5QvYxYtG8HW6NwJssfBC
# eUQT88/Zdn6muQVZopInTXA05PZNaL2JPRDtm9NMaquzH7rYD1Q6bz+EgE+RAC2X
# obkfRSXbpwt1aRkQj2nRYvTm0eMTVa57PHGN0MUPdNCtcINFswrFijKSs4N56bFt
# g+DTiyQ9DMyx5+mQ3FA243pP9Rof809HnzUajDRAWPRHHLafFjC0lVwwAU52Xq/h
# 7zLeihJZTvO4U+vUaese7IDKEX+igTqHTj/rFcfpfsnAglsFufJ0naK1WDfBphjo
# Zt5gt4I9k6vYTlH1n9jymZc6t2cdfjt5EJfSxPshjZ93qw0AZBcj2qKAvWR3O7mF
# VQ2zo4MZ/764mrFull7EX7ADWbFqYbuhChZ2l5MlIAsWs5NTpPSwAKPkv9snV4RC
# hXPiDVJhp+vKcXUJew1yOwauV/hafGwcBQ5qUDImSqp1pYK1ddC0dObFx8hEEQ==
# SIG # End signature block
