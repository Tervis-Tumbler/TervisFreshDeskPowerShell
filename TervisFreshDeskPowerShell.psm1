function Set-TervisFreshDeskAPIKey {
    $APIKey = Get-PasswordstatePassword -ID 5470 | Select-Object -ExpandProperty Password
    Set-FreshDeskAPIKey -APIKey $APIKey
}

function Set-TervisFreshDeskEnvironment {
    Set-TervisFreshDeskAPIKey
    Set-FreshDeskDomain -Domain Tervis
}

function Get-TervisFreshDeskTicketField {
    if (-not $Script:TicketFields) {
        $Script:TicketFields = Get-FreshDeskTicketField
    }

    $Script:TicketFields
}