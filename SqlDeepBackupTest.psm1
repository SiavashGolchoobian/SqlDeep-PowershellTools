Using module .\SqlDeepDatabaseShipping.psm1

Class BackupTest:DatabaseShipping {
    [string]$Text;

    BackupTest(){
        Write-Host 'I am BackupTest'
        $this.Text='Hello World'
    }
    [string]Print(){
        return $this.Text;
    }
}
