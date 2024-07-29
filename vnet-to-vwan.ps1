# Connect to Azure account
Connect-AzAccount

# Specify the locations
$locations = @("East US", "West US 2")

# Get all subscriptions
$subscriptions = Get-AzSubscription

# Iterate through each subscription
foreach ($subscription in $subscriptions) {
    Write-Output "Processing subscription: $($subscription.Name)"
    Set-AzContext -SubscriptionId $subscription.Id
    
    # Iterate through each specified location
    foreach ($location in $locations) {
        # Get all resource groups in the subscription for the specified location
        $resourceGroups = Get-AzResourceGroup | Where-Object { $_.Location -eq $location }
        
        # Iterate through each resource group and get the VNETs
        foreach ($resourceGroup in $resourceGroups) {
            $vnets = Get-AzVirtualNetwork -ResourceGroupName $resourceGroup.ResourceGroupName
            
            foreach ($vnet in $vnets) {
                Write-Output "VNET: $($vnet.Name) in Resource Group: $($resourceGroup.ResourceGroupName)"
                
                # List the subnets
                foreach ($subnet in $vnet.Subnets) {
                    Write-Output "  Subnet: $($subnet.Name)"
                    
                    # Check if the subnet has a route table
                    if ($subnet.RouteTable) {
                        Write-Output "    Removing Route Table: $($subnet.RouteTable.Id)"
                        
                        # Remove the route table association
                        $subnet.RouteTable = $null
                        
                        # Update the subnet
                        Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnet.Name -AddressPrefix $subnet.AddressPrefix -RouteTable $subnet.RouteTable
                        
                        # Update the VNET
                        Set-AzVirtualNetwork -VirtualNetwork $vnet
                    }
                }

                # List VNET peerings and disconnect them
                $peerings = Get-AzVirtualNetworkPeering -VirtualNetworkName $vnet.Name -ResourceGroupName $resourceGroup.ResourceGroupName
                
                foreach ($peering in $peerings) {
                    Write-Output "Disconnecting VNET peering: $($peering.Name) in VNET: $($vnet.Name)"
                    Remove-AzVirtualNetworkPeering -Name $peering.Name -VirtualNetworkName $vnet.Name -ResourceGroupName $resourceGroup.ResourceGroupName -Force
                    Write-Output "VNET peering $($peering.Name) disconnected"
                }

                # Get all Virtual Hubs in the same location
                $virtualHubs = Get-AzVirtualHub | Where-Object { $_.Location -eq $location }
                
                foreach ($virtualHub in $virtualHubs) {
                    Write-Output "Peering VNET: $($vnet.Name) to Virtual Hub: $($virtualHub.Name)"
                    
                    # Peer the VNET to the Virtual Hub
                    $vnetPeer = New-AzVirtualHubVnetConnection -ResourceGroupName $virtualHub.ResourceGroupName -ParentResourceName $virtualHub.Name -Name "$($vnet.Name)-to-$($virtualHub.Name)" -RemoteVirtualNetworkId $vnet.Id -AllowHubToRemoteVnetTransit -AllowRemoteVnetToUseHubVnetGateways
                    
                    Write-Output "VNET $($vnet.Name) is peered with Virtual Hub $($virtualHub.Name)"
                }
            }
        }
    }
}
