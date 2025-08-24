#Create self-signed certificate, Encrypt file by Certificate Public Key, Decrypt file by Certificate Private Key, Export Public key for others
#--------------------------------------------------------------Parameters.
Param(
    [Parameter(Mandatory=$true)][ValidateSet("EncryptText","DecryptText","EncryptFile","DecryptFile","CreateCert","ExportPublicKey","ExportPrivateAndPublicKey")][string]$Action,
	[Parameter(Mandatory=$false)][string]$CertSubjectName,
    [Parameter(Mandatory=$false)][string]$InputText,
    [Parameter(Mandatory=$false)][string]$InputFilePath,
	[Parameter(Mandatory=$false)][string]$OutputFilePath,
    [Parameter(Mandatory=$false)][string]$PrivateKeyPassword
    )

function Create-Certificte {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Certificate name")][string]$CertSubjectName,
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="How many years this cert should be valid")][int]$ValidYears=5
    )
    begin{}
    process{
        [string]$myAnswer=$null
        [X509Certificate] $myCert
        if ($CertSubjectName.StartsWith('cn=') -eq $false) {$CertSubjectName='cn='+$CertSubjectName}
        $myCert=Get-Childitem -Path Cert:\CurrentUser\My -DocumentEncryptionCert | Where-Object -Property Subject -eq $CertSubjectName
        if(!($myCert)) {
            $myCert=New-SelfSignedCertificate -DnsName $CertSubjectName -CertStoreLocation "Cert:\CurrentUser\My" -KeyUsage KeyEncipherment,DataEncipherment,KeyAgreement,DigitalSignature -KeyAlgorithm "RSA" -KeyLength 2048 -Type DocumentEncryptionCert -NotAfter (Get-Date).AddYears($ValidYears)
        } else {
            Write-Host "Certificat is already exist." -ForegroundColor Red
        }
        $myAnswer=$myCert.Thumbprint.ToString()
        return $myAnswer
    }
    end{}
}
function Export-CertifictePublicKey {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Certificate name")][string]$CertSubjectName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Output file name")][string]$OutputFile
    )
    begin{}
    process{
        [string]$myAnswer=$null
        [X509Certificate] $myCert
        if ($CertSubjectName.StartsWith('cn=') -eq $false) {$CertSubjectName='cn='+$CertSubjectName}
        $myCert=Get-Childitem -Path Cert:\CurrentUser\My -DocumentEncryptionCert | Where-Object -Property Subject -eq $CertSubjectName

        if(($myCert) -and ($OutputFile)) {
            Export-Certificate -Cert $myCert -FilePath $OutputFile
            $myAnswer=$OutputFile
        } else {
            Write-Host "Certificat does not exist or OutputFile is empty." -ForegroundColor Red
        }
        return $myAnswer
    }
    end{}
}
function Export-CertifictePrivateAndPublicKeyAsPfx {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Certificate name")][string]$CertSubjectName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Output file name")][string]$OutputFile,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Private key password")][string]$PrivateKeyPassword
    )
    begin{}
    process{
        [string]$myAnswer=$null
        [X509Certificate] $myCert
        if ($CertSubjectName.StartsWith('cn=') -eq $false) {$CertSubjectName='cn='+$CertSubjectName}
        $myCert=Get-Childitem -Path Cert:\CurrentUser\My -DocumentEncryptionCert | Where-Object -Property Subject -eq $CertSubjectName

        if(($myCert) -and ($OutputFile)) {
            Export-PfxCertificate -Cert $myCert -FilePath $OutputFile -Password (ConvertTo-SecureString -AsPlainText $PrivateKeyPassword -Force)
            $myAnswer=$OutputFile
        } else {
            Write-Host "Certificat does not exist or OutputFile is empty." -ForegroundColor Red
        }
        return $myAnswer
    }
    end{}
}
function Encrypt-File {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Certificate name")][string]$CertSubjectName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input file to encrypt")][string]$InputFile,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Encrypted Output file")][string]$OutputFile
    )
    begin{}
    process{
        [string]$myAnswer=$null
        if ($CertSubjectName.StartsWith('cn=') -eq $false) {$CertSubjectName='cn='+$CertSubjectName}
        if (($InputFile) -and (Test-Path -Path $InputFile)) {
            $myTempInputFilePath=$InputFile+".temp"
            certutil -encode $InputFile $myTempInputFilePath
            Get-Content $myTempInputFilePath | Protect-CmsMessage -To $CertSubjectName -OutFile $OutputFile
            Remove-Item -Path $myTempInputFilePath -Force
            $myAnswer=$OutputFile
        } else {
            Write-Host "Certificate or InputFile does not exist." -ForegroundColor Red
        }
        return $myAnswer
    }
    end{}
}
function Decrypt-File {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input file to decrypt")][string]$InputFile,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Decrypted Output file")][string]$OutputFile
    )
    begin{}
    process{
        [string]$myAnswer=$null
        if (($InputFile) -and (Test-Path -Path $InputFile)) {
            $myTempInputFilePath=$InputFilePath+".temp"
            Unprotect-CmsMessage -Path $InputFile | Out-File -FilePath $myTempInputFilePath
            certutil -decode $myTempInputFilePath $OutputFile
            Remove-Item -Path $myTempInputFilePath -Force
            $myAnswer=$OutputFile
        } else {
            Write-Host "InputFile does not exist." -ForegroundColor Red
        }
        return $myAnswer
    }
    end{}
}
function Encrypt-Text {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Certificate name")][string]$CertSubjectName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input text to encrypt")][string]$Content
    )
    begin{}
    process{
        [string]$myAnswer=$null
        if ($CertSubjectName.StartsWith('cn=') -eq $false) {$CertSubjectName='cn='+$CertSubjectName}
        if ($Content) {
            $myAnswer=Protect-CmsMessage -To $CertSubjectName -Content $Content
        } else {
            Write-Host "Certificate or Content does not exist." -ForegroundColor Red
        }
        return $myAnswer
    }
    end{}
}
function Decrypt-Text {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,HelpMessage="Input text to decrypt")][string]$Content
    )
    begin{}
    process{
        [string]$myAnswer=$null
        if ($Content) {
            $myAnswer=Unprotect-CmsMessage -Content $Content
        } else {
            Write-Host "Certificate or Content does not exist." -ForegroundColor Red
        }
        return $myAnswer
    }
    end{}
}

[string]$myAnswer=$null
switch ($Action.ToUpper()) {
	"ENCRYPTTEXT" {  
		$myAnswer=Encrypt-Text -CertSubjectName $CertSubjectName -Content $InputText
		return $myAnswer
	}
	"DECRYPTTEXT" {
		$myAnswer=Decrypt-Text -Content $InputText
		return $myAnswer
	}
	"ENCRYPTFILE" {  
		$myAnswer=Encrypt-File -CertSubjectName $CertSubjectName -InputFile $InputFilePath -OutputFile $OutputFilePath
		return $myAnswer
	}
	"DECRYPTFILE" {
		$myAnswer=Decrypt-File -InputFile $InputFilePath -OutputFile $OutputFilePath
		return $myAnswer
	}
	"CREATECERT" {
		$myAnswer=Create-Certificte -CertSubjectName $CertSubjectName -ValidYears 5
		return $myAnswer
	}
	"EXPORTPUBLICKEY" {
		$myAnswer=Export-CertifictePublicKey -CertSubjectName $CertSubjectName -OutputFile $OutputFilePath
		return $myAnswer
	}
	"EXPORTPRIVATEANDPUBLICKEY" {   #Export as pfx file
		$myAnswer=Export-CertifictePrivateAndPublicKeyAsPfx -CertSubjectName $CertSubjectName -OutputFile $OutputFilePath -PrivateKeyPassword $PrivateKeyPassword            
		return $myAnswer
	}
}

# SIG # Begin signature block
# MIIcAgYJKoZIhvcNAQcCoIIb8zCCG+8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCnHddfAMUwZu/z
# tI9nk9SkhT9tNFm+tYqseD0D2WkLoKCCFlIwggMUMIIB/KADAgECAhAT2c9S4U98
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
# 9w0BCQQxIgQgSfVf4UdB1kIglMe13QfG7QwmfH1rKSs8LrQiQul7lA4wDQYJKoZI
# hvcNAQEBBQAEggEAvEgigWNOz3VlHWpAAYQEkLjhlLhztILdihYi0KMfYkHKbAYc
# L/vF3qNZAW00DTfz/Tyye1ScOldE3eavsFv0RtV40FOSGxEc6CUpn5cFhU0hqxF1
# +rzZ3vR/5oKR9/FR6w1wivB+gPc42gEwOZp5VnX2MU+j4t9y/22FM6VkLgPoqSz2
# JLW0LhwxEHXSItOLBCHpmqWdvQXxah1cCH5mrzIuInE/QFsKzutX6UT67RjdqwC6
# nyR4aA5SrDd3X6r7s9wsxVek0n+/joaypEjdFb3x97IxtkbYTr4dpSU12mkzwNtp
# T5T1DVAMWKc2AMm3QqgKkgsyQCYK3ZYrNt06QaGCAyYwggMiBgkqhkiG9w0BCQYx
# ggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcg
# UlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEFgtHEdqeVdGgwDQYJYIZI
# AWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJ
# BTEPFw0yNTA4MjQxNzMzMjRaMC8GCSqGSIb3DQEJBDEiBCADDAF1H0qCJpqZgMoe
# eYHBolMdeoRpkHtoHcUE0cuJzTANBgkqhkiG9w0BAQEFAASCAgCqo4pJCQK1CWuA
# SIEUQLD3Y/xMESqnEmD6O2009ZwuEmYmwtlidE0X/82vAH9qjTZC8yoQRCZ9pR2w
# JQxxCKdC74izaJphjPw9Xac7OAgv1aZrffqvJkKXyT6kMZsGTI0O7G0lkuaq7BVU
# +ytsMdaf/4d/qK9TEZv3RPikZdm/NFTO9XW2HEtAJ9qZasLzCv+aqQystLsJcAuD
# 2SuP7Ex/5SVtkuw4ECX++8XNWMI4NIbMn3TbIOAb3iumPwDt3SnGm6u7mfdFfeho
# kvMFTVcgsVK3+jWU5sZKJM3ZB5lPXZjJEiJu4XG0o2DFU6xZTKUYCfvcRUvp3i1z
# x2H2dtDuKXs6ZLd/YVhz/kKGqpZjZ/wJo6V2tFUKWbZIRmS3Z1HD39NHY/PykTtu
# qFQoxuvhWwvAFA8zk2pZR3EWKcZbX2U/+AnMxbySoeyx7WNv73/tRDUsb5mYa+BD
# Qg4HPlCnTNmFrcGpvbCEtXgGcObie3c3ibMR8jlGiVkxZVsTcv/BZt/P3RIi8YCs
# /4qJHT0NNcGcmsG8FBTEZEHfLLIG4S4L9CpaTmRkrjnnZQm+AJNfdr2nFcpWNfe6
# i3ovCT6du2ur5eQyWQyqpw2KKeQGEeso7eha08QlKXrfqDZnHNfTz81bDbuOWSmo
# Q8srCPVm8r4+FnlfrqWIm/iTIJkqxg==
# SIG # End signature block
