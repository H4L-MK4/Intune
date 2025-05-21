# =====================================================
# 0) Config + get OAuth token
# =====================================================
$clientId = "<yourClientID>"
$tenantId = "<yourTenantID>"
$clientSecret = "<yourSecretKey>"
$scope        = "https://graph.microsoft.com/.default"

$body = @{
  grant_type    = "client_credentials"
  scope         = $scope
  client_id     = $clientId
  client_secret = $clientSecret
}
try {
  $tok   = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
            -Method Post `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $body
  $token = $tok.access_token
} catch {
  Write-Error "Failed to acquire token: $($_)"
  exit 1
}
$authHeader = @{ Authorization = "Bearer $token" }

# =====================================================
# 1) Preload last 7 days of sign-in logs and build a lookup
# =====================================================
$since     = (Get-Date).ToUniversalTime().AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")
$uri       = "https://graph.microsoft.com/v1.0/auditLogs/signIns" +
             "?`$filter=createdDateTime ge $since" +
             "&`$select=userPrincipalName,deviceDetail,createdDateTime" +
             "&`$top=500"
$allSignIns = @()
do {
  try {
    $batch = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
    $allSignIns += $batch.value
    $uri = $batch.'@odata.nextLink'
  } catch {
    Write-Warning "Error preloading sign-ins: $($_)"
    break
  }
} while ($uri)

$signInMap = @{}
foreach ($entry in $allSignIns) {
  $did = $entry.deviceDetail.deviceId
  if (-not $did) { continue }
  $ts  = [DateTime]$entry.createdDateTime
  if (-not $signInMap.ContainsKey($did) -or $ts -gt $signInMap[$did].time) {
    $signInMap[$did] = @{ user = $entry.userPrincipalName; time = $ts }
  }
}

# =====================================================
# 2) Helper functions
# =====================================================
function Get-LastLoggedOnUser {
  param($aadDeviceId, $intuneDeviceId)
  if ($aadDeviceId -and $signInMap.ContainsKey($aadDeviceId)) {
    return $signInMap[$aadDeviceId].user
  }
  return Get-FallbackUser -deviceId $intuneDeviceId
}

function Get-FallbackUser {
  param($deviceId)
  try {
    $md = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$deviceId" `
            -Headers $authHeader -Method Get
    return $md.userPrincipalName
  } catch {
    Write-Warning "Fallback fetch failed for $($deviceId): $($_)"
    return $null
  }
}

function Get-PrimaryUser {
  param($deviceId)
  $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$deviceId/users"
  try {
    $payload = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
    if ($payload.value.Count -gt 0) {
      $primary = $payload.value |
                 Where-Object { $_.isPrimaryUser -eq $true } |
                 Select-Object -First 1
      if ($primary) {
        return $primary.userPrincipalName
      }
      return ($payload.value | Select-Object -First 1).userPrincipalName
    }
  } catch {
    throw "Error fetching users for $($deviceId): $($_)"
  }
  return $null
}

function Update-PrimaryUser {
  param($deviceId, $newUserUpn)
  # Resolve UPN → object ID
  try {
    $usr    = Invoke-RestMethod `
                -Uri "https://graph.microsoft.com/v1.0/users/$($newUserUpn)" `
                -Headers $authHeader -Method Get
    $userId = $usr.id
  } catch {
    Write-Warning "Could not resolve user '$($newUserUpn)' to an ID: $($_)"
    return
  }
  # POST to users/$ref
  $uri  = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$deviceId/users/`$ref"
  $body = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$userId" } | ConvertTo-Json
  $hdrs = $authHeader + @{ "Content-Type" = "application/json" }
  try {
    Invoke-RestMethod -Uri $uri -Headers $hdrs -Method Post -Body $body
    Write-Output "ADD - Assigned primary user '$($newUserUpn)' to device $($deviceId)"
  } catch {
    Write-Warning "Failed to assign primary user on $($deviceId): $($_)"
  }
}

# =====================================================
# 3) Fetch all Intune-managed devices (with paging)
# =====================================================
$uri     = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
$devices = @()
do {
  try {
    $r       = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
    $devices += $r.value
    $uri      = $r.'@odata.nextLink'
  } catch {
    Write-Warning "Error listing devices: $($_)"
    break
  }
} while ($uri)

# =====================================================
# 4) Reconcile: always set primary if we know last
# =====================================================
foreach ($dev in $devices) {
  $intuneId    = $dev.id
  $aadDeviceId = $dev.azureADDeviceId

  $last    = Get-LastLoggedOnUser -aadDeviceId $aadDeviceId -intuneDeviceId $intuneId
  $primary = Get-PrimaryUser       -deviceId     $intuneId

  # Skip if we can’t determine last-logged-on
  if (-not $last) {
    Write-Warning "No last-logged-on user for $($intuneId); skipping."
    continue
  }

  if ($last -ne $primary) {
    if ($primary) {
      Write-Output "CHANGE - Changing primary for $($intuneId) from '$($primary)' to '$($last)'"
    } else {
      Write-Output "CHECK - No primary set on $($intuneId); setting to '$($last)'"
    }
    Update-PrimaryUser -deviceId $intuneId -newUserUpn $last
  } else {
    Write-Output "CHECK - $($intuneId) already correct ($($last))"
  }
}
