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
