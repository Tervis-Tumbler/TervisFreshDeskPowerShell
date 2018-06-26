function Set-TervisFreshDeskAPIKey {
    $APIKey = Get-PasswordstatePassword -ID 5470 | Select-Object -ExpandProperty Password
    Set-FreshDeskAPIKey -APIKey $APIKey
}

function Set-TervisFreshDeskEnvironment {
    Set-TervisFreshDeskAPIKey
    Set-FreshDeskDomain -Domain Tervis
}

function Get-TervisFreshDeskTicketFields {
    if (-not $Script:TicketFields) {
        $Script:TicketFields = Get-FreshDeskTicketFields
    }

    $Script:TicketFields
}