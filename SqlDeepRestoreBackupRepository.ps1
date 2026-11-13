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
        [string]$NewLogPath,
        [string]$DatabaseNamePrefix
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

        
        $myDatabaseName = $DatabaseNamePrefix + $myHeaderInfo.DatabaseName
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
            Invoke-Sqlcmd  -ConnectionString $RestoreConnectionString -Query $myQuery -QueryTimeout 0
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBIBclegFE0/NmS
# MAmKh9ftZ1k7yWCuDn9p8GAT6dZO/qCCFjowggL8MIIB5KADAgECAhBuGGiP9rFT
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
# ubdcMIIG7TCCBNWgAwIBAgIQCE/cM09+RU7bww+P+ZIYNTANBgkqhkiG9w0BAQsF
# ADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNV
# BAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hB
# MjU2IDIwMjUgQ0ExMB4XDTI2MDgwNTAwMDAwMFoXDTM3MTEwNDIzNTk1OVowYzEL
# MAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJE
# aWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVzcG9uZGVyIDIwMjYg
# MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALZ7pvLJ/s1K+NSbTGWz
# /TjGMPh8CQ6RucZCLv5anHzWJjF/NWJrFIhy24fcpKXlgRiky4WAawDfU3YP0BMx
# t9l3Dm5oCG5Z69AqEN1kgHg2epx+l+lZBcmJCcN0ASURML5uFIS80sZsDwO3BSkU
# xDjLJhBI+qiZP3aixAC/qEGLjsBNlLol9VZ7pfGEXiMlneJIC5/YKuizVzNFKZZE
# eoy/0B8Zm+nzKBgSWG52lCO1w+nCg6XpCtklTJXeIg283hw7TmmsZXR+SMbjbrEO
# vZ3fP2VxIgeR28Y90ZStd3F9VuA5RVynb/whITPAo9b75Zr4Ta6Mj3URm26QZYMn
# /FnbuTegcoRcFEZ9FOqM5T6MTdtr/n74lIT/ug0eeOzmZ6QTFg33otX+bFRsIolv
# ykE1jive4PuESaT8zzVeFWDAMDtozNgLctkGD1ZjkEyZtJrLl5ya0m5doH/ScpaZ
# CZVl6pNUOCybMc/kxC6EAmSJY24L0yYKD1Nkddsnb/ItVKi/2nXpQNMu1PT5prW8
# 3vV8d67WowuUs0HdY4H8AMLGvdL/WHEj3ZnqMqAQQP9u3Ai9t+5eQ02GDwy0ODjd
# zi0xlp70W+ow63/0++YDEX1M0iwgUHwbrJvfpklkZQvw3+kv3vUPItdwroczk9ic
# flf55W1zOEKAcJVAIXpcMCU9AgMBAAGjggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0G
# A1UdDgQWBBQUyWOKMC7USvtulPPm40B+9ezN4jAfBgNVHSMEGDAWgBTvb1NK6eQG
# fHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEy
# NTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vY3JsMy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hB
# MjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcB
# MA0GCSqGSIb3DQEBCwUAA4ICAQCNxTphHp1SCt+ZrAmAfn0oQLFr0mLywSLaDXQI
# ENoyKqxrFbJblzCVP/pkXmwXOdrOpWygLzlT12os5ipDCy35RBCg2UMeApEtrfGh
# z45F4Wt4WGdNdIbRWt3YTYJmpR+b7lr4d7Uwn+H600u4D7RnOGf8Wj4UNgAdZkfH
# hHv1mx9EVh71SJelcEN/oORSjXzdjfw1iZH9d8Nh/thn6hH23d+VsPAr6GAYyzSA
# 02nXD1nYLI7Ijmiv+xLCiYC41DSFYL3GhTiy0PxpawPtGRyaBVGzq+UiTfM8pD7K
# VyF5aQyWP4KhVGUUTnmm/RlYJoW3TiXA/+t0YcT2oRVBm3JETjajHug2AL+v5jht
# KVnd3D0rbHXEu27o+Q8p4sEWPMqKDB+qbceb6T/6WcwTwXmQ9lOCLLYcsQeSWmvK
# qzpAec9etE14jOQAzLKWdE3w/TCaKtLRaRT7LCkRYVnhA2D73FLje1O5b3HR5eHs
# 0NzU/+xX7NbEdcofy0W3Wdwd1XOqtlpg/JgwtKfZM5dqO94lbUveOiJBI+xZEbGR
# sMNbXmMREUTgu+Oca7Y73MPWcslIx2VhkSKSXjDbD6rgg39H5Mh7QfieAIjWagkJ
# Nt68Yfim6cjEzVSiLSeZfdkr5dtFPTW6jATlWJdYeeDRGCyatf8R1hSjzSvdN8yW
# QPT9gzGCBQYwggUCAgEBMCowFjEUMBIGA1UEAwwLc3FsZGVlcC5jb20CEG4YaI/2
# sVOwSN/GMSjz1Z0wDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAig
# AoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgEL
# MQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgLEbiQt9OFU/6uSnytbWu
# cFJKf/62XuBEoT+7Sqjhw2owDQYJKoZIhvcNAQEBBQAEggEAyvAL3Y3RmQoUrZY8
# Aw8HkPX8sHaWEXb0IIsA9IDPsIbh6hZf+8O+3EuyTxpoQlJdooicqiV4KE1eNH+F
# QM+yHz1EwHWT44jtHK3oVjtl/NGwyj3pNaFrCmQlighympgbSjTkhMeIuvBoRh3z
# gMHQ/DJ1JGwdyro2luad576nLJ6gz7KlLQXRz20hSDDsAi3a2r7E6r1N5z4jHQ7A
# a47uk/o40m2mZoyy6S95Fd7VGtKwRXG5QE21Y8F7hlZXogWtBhL0s6Sc5PAnuuda
# t8Bvs99NMwT0rYNiq4/Qq8MBRdx5aNaVElUNHsyeTwo//n0O8oSoGWD1O6Qzvce2
# HlYDJaGCAyYwggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYT
# AlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQg
# VHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEC
# EAhP3DNPfkVO28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMx
# CwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMTIyMzEzMjJaMC8GCSqG
# SIb3DQEJBDEiBCBpyvcYmNlCzpj/H+qAC9q4KBfk5lPisUvjE1rnOWzJezANBgkq
# hkiG9w0BAQEFAASCAgAkek5dWUOogmMFwITrlVB9tTg3PADTQh23XAd+gk9lZXnE
# 29Ia+ixy5m2Z0usauNFXRXwU9HZd733vix3O0JjWsoi5GEjpyJUjBhHHiwi1WGdp
# ZbjA1a8ZNuVvKc0vDXC+jTzXc7UmOzEjt/zbsFFNq1xw+iSmw3655xRMt8KqBb8R
# T4TnZFnnlBgn410la3nDsrxFaRiwbo5xspOdFD6/kmuibt2I54woj/zXrVwjWEUP
# w+UKKq52Ax28HEHoiTVSPu99wHbNpYdteEnxW8GA3Ej3wzSZM4Pa287/sclr6ZXQ
# 7TDi1tXWWP7ZqBjxHjMj+IaGiuCvXJ5ZTM4DS8tL8N0nXJUUfJ2g5L8gfiIvppZT
# TuUSlPJftnz7/GquJBOse4mmIKfBDyeSu3SnGFNQXbW+Zq40GjQgilTiPOB2NeJv
# nEN8jZPpHpNUZ6sU+oo45JntTKk4meJj6+vDfDrXiZ3MYPoZmsVaHSbCR9HosA0f
# 19Tt89Flw5JVLptsYRF9rPmxIRmscxo6YTSSRJzbPYe/m65RhgLmhbNj/sI5IV+p
# 2c1txW0we2H5VQ98AweRJH2vfGmzVzBOL1gCmr5U87FbiVRYQe0Qct/0cCvK/3Bq
# qwcJWi+KgWXwdw6ZuhwjAtOtA4bNn2mQr/fs7qGiMoRqCxrbkhuXsx0tGo63ig==
# SIG # End signature block
