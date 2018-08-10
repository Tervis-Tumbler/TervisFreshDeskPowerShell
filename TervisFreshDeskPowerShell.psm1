function Set-TervisFreshDeskAPIKey {
    $APIKey = Get-PasswordstatePassword -ID 5470 | Select-Object -ExpandProperty Password
    Set-FreshDeskAPIKey -APIKey $APIKey
}

function Set-TervisFreshDeskEnvironment {
    Set-TervisFreshDeskAPIKey
    Set-FreshDeskDomain -Domain Tervis
}

function Remove-TervisFreshDeskEnvironment {
    Remove-FreshDeskAPIKey
    Remove-FreshDeskCredential
    Remove-FreshDeskDomain
}

function Get-TervisFreshDeskTicketField {
    param (
        $Credential
    )
    $CredentialParameter = $PSBoundParameters | ConvertFrom-PSBoundParameters -Property Credential -AsHashTable
    if (-not $Script:TicketFields) { 
        $Script:TicketFields = Get-FreshDeskTicketField @CredentialParameter
    }

    $Script:TicketFields
}

function Invoke-TervisUpdateQuantityToQuantityNumber {
    Set-TervisFreshDeskEnvironment
    $Tickets = Import-Csv -Path "C:\Users\cmagnuson\OneDrive - tervis\Downloads\tickets-August-02-2018-18_16.csv" | 
    Add-Member -MemberType ScriptProperty -Name QuantityNumberInt -Value {
        if ($this.QuantityNumber) {
            [int]$this.QuantityNumber
        }
    } -PassThru |
    Add-Member -MemberType ScriptProperty -Name QuantityInt -Value {
        if ($this.Quantity) {
            [int]$this.Quantity
        }
     } -PassThru |
    Add-Member -MemberType ScriptProperty -Name UnifiedQuantity -PassThru -Value {
        if ($This.QuantityNumberInt -and -not $This.QuantityInt) {
            $This.QuantityNumberInt
        } elseif (-not $This.QuantityNumberInt -and $This.QuantityInt) {
            $This.QuantityInt
        } elseif ($This.QuantityNumberInt -and $This.QuantityInt) {
            if ($This.QuantityNumberInt -ge $This.QuantityInt) {
                $This.QuantityNumberInt
            } else {
                $This.QuantityInt
            }
        } 
    } |
    Add-Member -MemberType ScriptProperty -Name QuantityNumberToUpdate -PassThru -Value {
        if ($This.QuantityNumberInt -ne $this.UnifiedQuantity) {
            $this.UnifiedQuantity
        }
    }

    $Tickets |
    Where-Object {
        ($_.QuantityNumber -and $_.Quantity) -and
        ($_.QuantityNumber -ne $_.Quantity)
    } | FT


    if ($ticket.QuantityNumber -and $ticket.Quantity) {
        if ($ticket.QuantityNumber -ge $ticket.Quantity) {
            $ticket.QuantityNumber
        } else {
            $ticket.Quantity
        }
    } 

    $Tickets | 
    Where-Object {$_.QuantityNumberToUpdate} |
    Measure-Object

    $Tickets | Group-Object Quantity | Sort-Object -Descending -Property Count
    $Tickets | Group-Object QuantityNumber | Sort-Object -Descending -Property Count
    $Tickets | Where-Object {$_.QuantityNumberToUpdate} | Group-Object -Property QuantityNumberToUpdate | Sort-Object -Descending -Property Count


    $Tickets | 
    Where-Object {$_.QuantityNumberToUpdate} |
    Select-Object -First 10 -Skip 1000 -ExpandProperty "Ticket ID"

    $Tickets | 
    Where-Object {$_.QuantityNumberToUpdate} |
    ForEach-Object {
        Set-FreshDeskTicket -id $_."Ticket ID" -custom_fields @{cf_quantitynumber = $_.QuantityNumberToUpdate} | Out-Null
        Start-Sleep -Seconds 1.2
    }
}