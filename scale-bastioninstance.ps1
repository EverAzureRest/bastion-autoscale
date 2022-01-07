##Azure Runbook to scale Bastion
[OutputType("PSAzureOperationResponse")]
param
(
    [Parameter (Mandatory=$false)]
    [object] $WebhookData
)
$ErrorActionPreference = "stop"
if ($WebhookData)
    {
    
    $WebhookBody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)
    $schemaId = $WebhookBody.schemaId
    Write-Verbose "schemaId: $schemaId" -Verbose
    
    if ($schemaId -eq "AzureMonitorMetricAlert") {
        # This is the near-real-time Metric Alert schema
        $AlertContext = [object] ($WebhookBody.data).context
        $SubId = $AlertContext.subscriptionId
        $ResourceGroupName = $AlertContext.resourceGroupName
        $ResourceType = $AlertContext.resourceType
        $ResourceName = $AlertContext.resourceName
        $status = ($WebhookBody.data).status
    }

    if ((Connect-AzAccount -Identity).Context.Subscription.Id -ne $SubId)
        {
            set-azcontext -SubscriptionId $SubId -Force
        }

    

    $bastion = Get-AzBastion -Name $ResourceName -ResourceGroupName $resourceGroupName

    #Get current scale units and increase by 1

    Write-Output "The current scale unit number is $($bastion.ScaleUnit)"

    $bastion.ScaleUnit++

    try {
        Set-AzBastion -InputObject $bastion -Confirm:$false
        Write-Output "Bastion successfully scaled to $($bastion.ScaleUnit)"
    }
    catch {
        Write-Output "Error $($exception.message) "
    }
}
else {
    # Error
    Write-Error "This runbook is meant to be started from an Azure alert webhook only."
}