#Samples (Use this script to create new drive without any prompt) New-ShadowCopy -Drive D: -Confirm:$false

#This script is part of powersploit project
#region Get-ShadowCopy
function Get-ShadowCopy
{
    Param(
          [Parameter(Position=0, 
                     Mandatory=$false)]
          [string] $ComputerName = "localhost",
          [Parameter(Mandatory=$false)]
          [string] $Id
        )

    if( Test-IsAdmin )
    {
        $shadowCopies = Get-WMIObject -Class Win32_ShadowCopy -Computer $ComputerName

        $copies = @()

        foreach( $c in $shadowCopies)
        {
            $tmp = get-driveletter $c.volumename $ComputerName
            $c | Add-Member -MemberType NoteProperty -Name Drive -Value $tmp

            $tmp = $c.ConvertToDateTime($c.InstallDate)
            $c | Add-Member -MemberType NoteProperty -Name Date -Value $tmp

            $copies += $c
        }

        if ($PSBoundParameters.ContainsKey('Id'))
        {
            $copies | Where-Object { $_.Id -eq $Id } | Select-Object -Property Id, Date, Drive
        }
        else
        {
            $copies | Select-Object -Property Id, Date, Drive
        }
    }
    else
    {
        Write-Error "This command should be run with administrator level access."
    }
}
#endregion

#region New-ShadowCopy
function New-ShadowCopy
{
    [cmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = "High"
    )]

    Param(
          [Parameter(Position=0, 
                     Mandatory=$true)]
        [string] $Drive,
          [Parameter(Position=1, 
                     Mandatory=$false)]
        [string] $ComputerName = "localhost"
        )

    if( Test-IsAdmin )
    {
        if($PSCmdlet.ShouldProcess($Drive))
        {
            $s = (gwmi -List Win32_ShadowCopy -ComputerName $ComputerName).Create($Drive + "\", "ClientAccessible")
            $id = $s.GetPropertyValue("ShadowID")
            Get-ShadowCopy -Id $id
        }
    }
    else
    {
        Write-Error "This command should be run with administrator level access."
    }
}
#endregion

#region Remove-ShadowCopy
function Remove-ShadowCopy
{
    [cmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = "High"
    )]

    Param(
          [Parameter(Position=0, 
                     Mandatory=$true, 
                     ValueFromPipeline=$true,
                     ValueFromPipelineByPropertyName=$true)]
                        [String[]]$Id,
          [Parameter(Position=1, 
                     Mandatory=$false)]
          [string] $ComputerName = "localhost"
        )

    Begin {}

    Process
    {
        if( Test-IsAdmin )
        {
            $shadowCopies = Get-WMIObject -Class Win32_ShadowCopy -Computer $ComputerName
            foreach( $sc in $shadowCopies)
            {
                if( $sc.ID -eq $Id)
                {
                    if($PSCmdlet.ShouldProcess($id))
                    {
                        $sc.Delete()
                    }
                }
            }
        }
        else
        {
            Write-Error "This command should be run with administrator level access."
        }
    }
    
    End {}    
}
#endregion

#region Mount-ShadowCopy
function Mount-ShadowCopy
{
    [cmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = "High"
    )]

    Param(
          [Parameter(Position=0, 
                     Mandatory=$true, 
                     ValueFromPipeline=$true,
                     ValueFromPipelineByPropertyName=$true)]
                        [String]$Id,
        [string] $Path
        )
    
    if( Test-IsAdmin )
    {
        if( Test-Path $Path )
        {
            Write-Error "Destination already exists."
        }
        else
        {
            $s2 = gwmi Win32_ShadowCopy | ? { $_.ID -eq $ID }
            $d  = $s2.DeviceObject + "\"
            if($PSCmdlet.ShouldProcess($id))
            {
                cmd /c mklink /d $Path $d
            }
        }
    }
    else
    {
        Write-Error "Command must be run with administrator level access."
    }
}
#endregion

#region Unmount-ShadowCopy
function Unmount-ShadowCopy
{
    [cmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = "High"
    )]

    Param(
          [Parameter(Position=0, 
                     Mandatory=$true)]
                        [String]$Path
        )

    if( Test-IsAdmin )
    {
        #Test if target path exists and is a directory
        if( Test-Path($Path) -PathType Container)
        {
            $p = resolve-path $Path    
            if($PSCmdlet.ShouldProcess($Path))
            {          
                cmd /c rd "$p"
            }
        }
        else
        {
            Write-Error "Target path does not exist or is not a directory."
        }
    }
    else
    {
        Write-Error "Command must be run with administrator level access."
    }
}
#endregion

#region Helper Functions that are not exposed
Function Test-IsAdmin   
{  
<#
.SYNOPSIS
   Function used to detect if current user is an Administrator.
      
.DESCRIPTION
   Function used to detect if current user is an Administrator.
             
.EXAMPLE
    Test-IsAdmin
       
    
Description
-----------
Command will check the current user to see if an Administrator.
#>  
    [cmdletbinding()]  
    Param()  
      
# Write-Verbose "Checking to see if current user context is Administrator"
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))  
    {  
        return $false
    }  
    Else   
    {  
        return $true
    }  
}

# This function returns the driveletter of a volume givven the volume id
function get-driveletter()
{
    Param(
        [string] $VolumeID,
        [string] $ComputerName = "localhost"
        )

    $var = Get-WMIObject -Class Win32_Volume -ComputerName $ComputerName
    $var2 = $var | Where-Object {$_.deviceid -eq $VolumeID }
    return $var2.driveletter
}
#endregion

#region Exports
Export-ModuleMember -function New-ShadowCopy
Export-ModuleMember -function Get-ShadowCopy
Export-ModuleMember -function Remove-ShadowCopy
Export-ModuleMember -function Mount-ShadowCopy
Export-ModuleMember -function Unmount-ShadowCopy
#endregion
# SIG # Begin signature block
# MIIbxQYJKoZIhvcNAQcCoIIbtjCCG7ICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCFkVNj5O3xrvLY
# 4N2DhqszafT4NU/wusDHTASaSHLn8qCCFhswggMUMIIB/KADAgECAhAT2c9S4U98
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
# BCC51ZQUWIiS5JLPEsK5W6hQFCXw1QbHK8wywjMzlr97azANBgkqhkiG9w0BAQEF
# AASCAQClrobHcox6ThUbSDZ6PQOZ8KrYtBokb/hbs6W3akLqIS53Bz+qpPVG+mL7
# jaxnS1NzYt5Qo5lc8nIwU9C6KfvjLT/wjbeL4DdNyIl/idyv/yyQPQroxdCAOfTI
# qxeyX45cyyLAj7uRIdQHbAh3AERQ8yH6JB44VGwQNxcsvvnl1QeCGkqDpa190+Xr
# bW4trqkfghXseHmrpwjAMdm/RXDpwYcRanRToYO+PaCsTr/fAomBJyYkcVyVkQRS
# 2ZY1yMhpGbH0fSV0/cKhVFa1W4TZNPdpub3/gTjEdgmNkm4ZxAbkkp/u72BfgHNn
# A1yUf6pSD26LO4jc3VWGitoMdrcXoYIDIDCCAxwGCSqGSIb3DQEJBjGCAw0wggMJ
# AgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQQIQC65mvFq6f5WHxvnpBOMzBDANBglghkgBZQMEAgEFAKBpMBgG
# CSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI0MTEyNzA1
# MDcwNlowLwYJKoZIhvcNAQkEMSIEIBNYd6KFmft0fN75C3jfeK7sia7kIskCIDS5
# aSZefwhXMA0GCSqGSIb3DQEBAQUABIICAAC7/bn4nO49SrtmfnXND0XIt1dnF2FL
# v22lKuBX9kaodEQrjJUcjhfhY2Re951ya5UYEBexmVOxJeB0ZDdoiKTs0TohwbP/
# q7EjRWv2Vox1LuIr6ku/EJ/WN2gDZUNIwbTzSjCngdo+IGXA0BWvbFYZ0hS5hIkg
# WPCGivM+NOuOB7EQWCgOOOv6PI7LmL7uK48+bUX8xRHIRHb4YcIoDq44LSWPiugD
# cVOPEh1p/SDqYw95UyE4JKgvI245o3MyQBgPEZ4NmdJktN7VsTjZsMQYrYGFt4LP
# eh/vzXMgjiVuqKVSDYl6Z7+BrLtiiU/KBMT60C38gwBrzGBboP8hT3uFcryQBwI8
# cOkto+iZINKCpYCqGCvAJFYiYEEkmg+eI86brx8Xp8IK2liCa8J5jhOs0nLku98m
# Dj5D4X05D6jfmJhTRBlzV0YL0wjliOWXzGHbDgFTNJPTQs94CToh2nVItN6jWN5a
# Of+lynSoBT0ogNLe8S5IB4XGxtjRzBxS5PghCVQmSnCzQCUXbPMm4A15znP0QqvW
# W1PxcabVIo9krLPvZJc/O/BUq2HjgDjUSfnoRHFvt5cmXuWxPmHA43K5QWNjLjU2
# UOHKR9QI6KmIH8uv6VZ8fz2nsUpd+YksTSYmnuwtVSi24lnEhRaK6O4K8sf6HZpW
# GMOJ4atCbWTC
# SIG # End signature block
