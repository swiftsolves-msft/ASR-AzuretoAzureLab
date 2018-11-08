<# 
    .DESCRIPTION 
        This will update the failed over VNET Custom DNS to point to the failed over ADDC Private IP. 
         
 
    .NOTES 
        AUTHOR: naswif@microsoft.com 
        LASTEDIT: 8 Novemeber, 2018 
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
    # Set Custom DNS on failovered VNET

 Try
 {
     foreach ($VMID in $VMinfo)
    {
        $vmprop = $vmMap.$VMID
        $VM = Get-AzureRmVM -ResourceGroupName $vmprop.ResourceGroupName -Name $vmprop.RoleName

        If ($VM.Name -match "ADDC" ) 
        {

                #Capture ARM NIC
                $ARMNic = Get-AzureRmResource -ResourceId $VM.NetworkProfile.NetworkInterfaces[0].id
                $NIC = Get-AzureRmNetworkInterface -Name $ARMNic.Name -ResourceGroupName $ARMNic.ResourceGroupName

                $subnetid = $NIC.IpConfigurations.Subnet.Id
                $vnetrg = $subnetid.Split("/")[4]
                $vnetname = $subnetid.Split("/")[8]

                $vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $vnetrg -Name $vnetname
                $vnet.DhcpOptions.DnsServers = $NIC.IpConfigurations.PrivateIpAddress
                $vnet.DhcpOptions.DnsServers += "8.8.8.8"
                Set-AzureRmVirtualNetwork -VirtualNetwork $vnet


        }
        Else 
        {
            Write-Output ("ADDC VM NOT Found!")
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


$failType = $RecoveryPlanContext.FailoverType
Write-Output ("$FailType FAILOVER")
$faildirection = $RecoveryPlanContext.FailoverDirection
Write-Output ("Direction: $faildirection")

 If ($RecoveryPlanContext.FailoverType -match "planned" -or $RecoveryPlanContext.FailoverType -match "unplanned" -and $RecoveryPlanContext.FailoverDirection -eq "PrimaryToSecondary") {

    $vnet = Get-AzureRmVirtualNetwork -ResourceGroupName "rgSwiftNetworking" -Name "SWIFT-VNET-WUS-SPOKE-1"
    $vnet.DhcpOptions.DnsServers = $NIC.IpConfigurations.PrivateIpAddress
    $vnet.DhcpOptions.DnsServers += "8.8.8.8"
    Set-AzureRmVirtualNetwork -VirtualNetwork $vnet

 }
 Elseif ($RecoveryPlanContext.FailoverType -match "planned" -or $RecoveryPlanContext.FailoverType -match "unplanned" -and $RecoveryPlanContext.FailoverDirection -eq "SecondaryToPrimary"){
 
    $vnet = Get-AzureRmVirtualNetwork -ResourceGroupName "rgSwiftNetworking" -Name "SWIFT-VNET-EUS-SPOKE-1"
    $vnet.DhcpOptions.DnsServers = $NIC.IpConfigurations.PrivateIpAddress
    $vnet.DhcpOptions.DnsServers += "8.8.8.8"
    Set-AzureRmVirtualNetwork -VirtualNetwork $vnet

 }
 Else {
    Write-Output ("TEST FAILOVER")
 }