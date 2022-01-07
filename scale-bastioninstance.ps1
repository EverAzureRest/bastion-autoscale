##Azure Runbook to scale Bastion

param(
    $resourceGroupName = "bastion-scale-test"
)

Connect-AzAccount -Identity

$bastion = Get-AzBastion -ResourceGroupName $resourceGroupName

#Get current scale units and increase by 1

$bastion.ScaleUnit++

Set-AzBastion -InputObject $bastion