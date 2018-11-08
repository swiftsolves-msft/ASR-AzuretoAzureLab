<# 
    .DESCRIPTION 
        This will create a CSE to execute PS script to update FileZilla on FTP VM. 
         
 
    .NOTES 
        AUTHOR: naswif@microsoft.com 
        LASTEDIT: 19 June, 2018 
#> 
param ( 
        [Object]$RecoveryPlanContext 
      ) 

Write-Output $RecoveryPlanContext

# RecoveryVM Context and VMs
$VMinfo = $RecoveryPlanContext.VmMap | Get-Member | Where-Object MemberType -EQ NoteProperty | select -ExpandProperty Name
$vmMap = $RecoveryPlanContext.VmMap

Try
 {
    "Logging in to Azure..."
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection 
     Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

    "Selecting Azure subscription..."
    Select-AzureRmSubscription -SubscriptionId $Conn.SubscriptionID -TenantId $Conn.tenantid 
 }
Catch
 {
      $ErrorMessage = 'Login to Azure subscription failed.'
      $ErrorMessage += " `n"
      $ErrorMessage += 'Error: '
      $ErrorMessage += $_
      Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
 }
    # Set FTP VM within the Resource Group

 Try
 {
     foreach ($VMID in $VMinfo)
    {
        $vmprop = $vmMap.$VMID
        $VM = Get-AzureRmVM -ResourceGroupName $vmprop.ResourceGroupName -Name $vmprop.RoleName

        If ($VM.Name -match "FTP" ) 
        {
            Write-Output ("FTP VM Found")
            $url = "https://raw.githubusercontent.com/swiftsolves-msft/ASR-HUB-SPOKE-FTP/master/scripts/updatexml.ps1"
            $guid = New-Guid

            Set-AzureRmVMCustomScriptExtension -ResourceGroupName $VM.ResourceGroupName `
            -VMName $VM.Name `
            -Location $VM.Location `
            -FileUri $url `
            -Run 'updatexml.ps1' `
            -Name "UpdateFileZillaConfig-$guid"
        }
        Else 
        {
            Write-Output ("FTP VM NOT Found!")
        }
    }
 }
  Catch
 {
      $ErrorMessage = 'Failed to find any VMs in the Resource Group.'
      $ErrorMessage += " `n"
      $ErrorMessage += 'Error: '
      $ErrorMessage += $_
      Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
 }