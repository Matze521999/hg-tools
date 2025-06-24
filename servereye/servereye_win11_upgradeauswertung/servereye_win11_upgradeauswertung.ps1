#Requires -Modules ServerEye.Powershell.Helper, ImportExcel

Param (
    [Parameter(Mandatory=$true)][string]$ApiKey,
    [string]$Dest = ".\",
    [string]$CustomerID
)



function Status {
    Param (
        [string]$Activity,
        [int]$Counter,
        [int]$Max,
        [string]$Status,
        [int]$Id,
        [int]$ParentId
    )
    $PercentComplete = if ($Max) { (($Counter * 100) / $Max) } else { 100 }
    if ($PercentComplete -gt 100) { $PercentComplete = 100 }
    try {
        if ($ParentId) {
            Write-Progress -Activity $Activity -PercentComplete $PercentComplete -Status $Status -Id $Id -ParentId $ParentId
        } else {
            Write-Progress -Activity $Activity -PercentComplete $PercentComplete -Status $Status -Id $Id
        }
    } catch {}
}

function Inventory {
    Param ([Parameter(Mandatory=$true)]$Customer)

    $Hubs = Get-SeApiCustomerContainerList -AuthToken $ApiKey -CId $Customer.Cid | Where-Object { $_.Subtype -eq 2 }
    $SafeCompanyName = $Customer.CompanyName -replace '[<>:"/\\|?*]', '_'
    $XlsFile = Join-Path -Path $Dest -ChildPath "inventory\$SafeCompanyName.xlsx"

    $SummaryList = @()
    $CountH = 0

    foreach ($Hub in $Hubs) {
        $CountH++
        Status -Activity "$($CountH)/$($Hubs.Count) Inventarisiere $($Customer.CompanyName)" -Max $Hubs.Count -Counter $CountH -Status $Hub.Name -Id 2 -ParentId 1

        $HubData = Get-SeApiContainer -AuthToken $ApiKey -CId $Hub.Id
        $State = Get-SeApiContainerStateListbulk -AuthToken $ApiKey -CId $Hub.Id
        $LastDate = if ($null -eq $State.LastDate) { "N/A" } else { [datetime]$State.LastDate }

        if ($LastDate -lt ((Get-Date).AddDays(-60)) -or $State.Message -like '*Verbindung zum Sensorhub verloren*') {
            continue
        }

        $Inventory = Start-Job -ScriptBlock {
            try { Get-SeApiContainerInventory -AuthToken $args[0] -CId $args[1] } catch { @{} }
        } -ArgumentList $ApiKey, $Hub.Id | Wait-Job -Timeout 5 | Receive-Job
        Get-Job | Remove-Job

        if (-not $Inventory) { continue }

        # WIN_11_STATUS korrekt auslesen
        $Win11Status = ""
        if ($Inventory.WIN_11_STATUS -and $Inventory.WIN_11_STATUS.WIN_11_STATUS) {
            $Win11Status = $Inventory.WIN_11_STATUS.WIN_11_STATUS
        }

        # Office-Produkte anhand von PRODUKT erkennen
        $OfficeList = ""
        if ($Inventory.PROGRAMS) {
            $OfficePrograms = $Inventory.PROGRAMS | Where-Object {
                ($_.PRODUKT -like "*Office*") -or
                ($_.PRODUKT -like "*Microsoft 365*") -or
                ($_.PRODUKT -like "*LibreOffice*")
            }
            $OfficeList = ($OfficePrograms | Select-Object -ExpandProperty PRODUKT) -join ", "
        }

        # Eintrag zur Zusammenfassung hinzufügen
        $SummaryList += [PSCustomObject]@{
            MachineName     = $HubData.MachineName
			CPU              = $Inventory.WIN_11_STATUS.CPU
			MemoryMB         = $Inventory.WIN_11_STATUS.MEMORY_TOTAL
			StorageMB        = $Inventory.WIN_11_STATUS.STORAGE_TOTAL
            Hub             = $Hub.Name
            OsName          = $HubData.OsName
            IsVM            = $HubData.IsVM
            IsServer        = $HubData.IsServer
            LastRebootUser  = $HubData.LastRebootInfo.User
            LastDate        = $LastDate
            Win11Status     = $Win11Status
            OfficeInstalled = $OfficeList
        }
    }

    Export-Excel -Path $XlsFile -WorksheetName 'Kompaktübersicht' -AutoFilter -AutoSize -FreezeTopRow -BoldTopRow -KillExcel -InputObject $SummaryList
}

# === Hauptlogik ===
if (!(Test-Path $Dest)) {
    Write-Host "$Dest nicht gefunden"
    exit
}

$InventoryRoot = Join-Path -Path $Dest -ChildPath '\inventory'
if (!(Test-Path $InventoryRoot)) { New-Item -Path $InventoryRoot -ItemType Directory | Out-Null }

$Customers = @()
try {
	try {
		$Customers = Get-SeApiCustomerlist -AuthToken $ApiKey
	} catch {
		Write-Host 'ApiKey falsch'
		exit
	}
	
} catch {
    Write-Host 'ApiKey falsch'
    exit
}

if ($CustomerID) {
    $Customer = $Customers | Where-Object { $_.Cid -eq $CustomerID }
    if (-not $Customer) {
        Write-Host "CustomerID '$CustomerID' nicht gefunden"
        exit
    }

    Write-Host $Customer.CompanyName
    Status -Activity "1/1 Inventarisiere" -Max 1 -Counter 1 -Status $Customer.CompanyName -Id 1
    Inventory $Customer
} else {
    $Count = 0
    foreach ($Customer in $Customers) {
        $Count++
        Write-Host $Customer.CompanyName
        Status -Activity "$($Count)/$($Customers.Count) Inventarisiere" -Max $Customers.Count -Counter $Count -Status $Customer.CompanyName -Id 1
        Inventory $Customer
    }
}

$Count = 0
foreach ($Customer in $Customers) {
    $Count++
    Write-Host $Customer.CompanyName
    Status -Activity "$($Count)/$($Customers.Count) Inventarisiere" -Max $Customers.Count -Counter $Count -Status $Customer.CompanyName -Id 1
    Inventory $Customer
}
