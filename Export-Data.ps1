<#
.PARAMETER IncludeEmptyVertices
    Export Allow vertices, even if there is no parent or no child

.PARAMETER IncludeDisabled
    Export as well
    - Disabled roles
    - Disabled Access Profile
    - Application not available in the request center
.PARAMETER IncludeEntitlements
    Export entitlements
#>
param(
    
    [switch] $IncludeEmptyVertices,
    [switch] $IncludeDisabled,
    [switch] $IncludeEntitlements
)
$vertices = @()
$edges = @()

$VERTICE_COLLECTION = 'idnVertices'
$EDGE_COLLECTION = 'idnEdges'

$ROLE_COLOR = '1'
$DISABLED_ROLE_COLOR = '2'
$ACCESS_PROFILE_COLOR = '3'
$DISABLED_ACCESS_PROFILE_COLOR = '4'
$APP_COLOR = '5'
$DISABLED_APP_COLOR = '6'
$SOURCE_COLOR = '7'


############################################
#region Role
#

$roles = Get-IdentityNowRole
$roleCount = ($roles | Measure-Object ).Count
Write-Host "Found $roleCount role(s)"
$roles = $roles | Where-Object {$IncludeDisabled -or ($_.enabled) }

$vertices += $roles | Select-Object name, description, enabled, requestable, `
    @{Name = 'color'; Expression = { if ($_.enabled) { $ROLE_COLOR }else { $DISABLED_ROLE_COLOR } } }, `
    @{Name = 'type'; Expression = { "role" } }, `
    @{Name = '_key'; Expression = { $_.id } }

    
foreach ($role in $roles) {
    $accessProfiles = $role | Select-Object -ExpandProperty accessProfiles
    $edges += $accessProfiles | Select-Object @{Name = '_from'; Expression = { "{0}/{1}" -f $VERTICE_COLLECTION, $role.id } }, `
        @{Name = '_to'; Expression = { "{0}/{1}" -f $VERTICE_COLLECTION, $_.id } }

}  
    

if (-not $IncludeEmptyVertices) {
    $accessProfileIds = $roles | Select-Object -ExpandProperty accessProfiles | select-Object -Unique id | Select-Object -ExpandProperty id
    Write-Host "Need to export $(($accessProfileIds | Measure-Object ).Count) Access Profile(s)"
}

#
#endregion Role
############################################

############################################
#region Application
#

$applications = Get-IdentityNowApplication
$applicationCount = ($applications | Measure-Object ).Count
Write-Host "Found $applicationCount application(s)"
$applications = $applications | Where-Object {$IncludeDisabled -or ($_.appCenterEnabled) }

$vertices += $applications | Select-Object name, description, appCenterEnabled, `
    @{Name = 'color'; Expression = { if ($_.appCenterEnabled) { $APP_COLOR } else { $DISABLED_APP_COLOR } } }, `
    @{Name = 'type'; Expression = { "application" } }, `
    @{Name = '_key'; Expression = { $_.id } }

$accessProfilesForApplication =@()
foreach ($application in $applications) {
    $accessProfiles = Get-IdentityNowApplicationAccessProfile -appID $application.id
    $accessProfilesForApplication += $accessProfiles | Select-Object -ExpandProperty id
    $edges += $accessProfiles | Select-Object @{Name = '_from'; Expression = { "{0}/{1}" -f $VERTICE_COLLECTION, $application.id } }, `
        @{Name = '_to'; Expression = { "{0}/{1}" -f $VERTICE_COLLECTION, $_.id } }
}

if (-not $IncludeEmptyVertices) {
    $accessProfileIds += $accessProfilesForApplication
    $accessProfileIds = $accessProfileIds | select -Unique
    Write-Host "Need to export $(($accessProfileIds | Measure-Object ).Count) Access Profile(s)"
}

#
#endregion Application
############################################

############################################
#region Access Profile
#


$accessProfiles = Get-IdentityNowAccessProfile
$accessProfileCount = ($accessProfiles | Measure-Object ).Count
Write-Host "Found $accessProfileCount Access Profile(s)"
$accessProfiles = $accessProfiles | Where-Object {$IncludeEmptyVertices -or ($accessProfileIds -contains $_.id) }

# Add vertices for access profiles
$vertices += $accessProfiles | Select-Object name, description, disabled, requestable, `
        @{Name = 'color'; Expression = { if (!$_.disabled) { $ACCESS_PROFILE_COLOR }else { $DISABLED_ACCESS_PROFILE_COLOR } } }, `
        @{Name = '_key'; Expression = { $_.id } }, `
        @{Name = 'type'; Expression = { "accessProfile" } }

# Add edges for sources
$edges += $accessProfiles | Select-Object @{Name = '_from'; Expression = { "{0}/{1}" -f $VERTICE_COLLECTION, $_.id } }, `
        @{Name = '_to'; Expression = { "{0}/{1}" -f $VERTICE_COLLECTION, $_.sourceId } }

if (-not $IncludeEmptyVertices) {
    $sourceIds = $accessProfiles  | select-Object -Unique sourceId | Select-Object -ExpandProperty sourceId
    Write-Host "Need to export $(($sourceIds | Measure-Object ).Count) Source(s)"
}

# Add edges for entitlements
# XXX TODO

#
#endregion Access Profile
############################################

############################################
#region Source
#

$sources = Get-IdentityNowSource
$sourceCount = ($sources | Measure-Object ).Count
Write-Host "Found $sourceCount Source(s)"
$sources = $sources | Where-Object {$IncludeEmptyVertices -or ($sourceIds -contains $_.id) }

$vertices += $sources | Select-Object name, description, sourceConnected, sourceConnectorName, `
        @{Name = 'color'; Expression = { $SOURCE_COLOR } }, `
        @{Name = '_key'; Expression = { $_.id } }, `
        @{Name = 'type'; Expression = { "source" } }

#
#endregion Source
############################################

    

# Force UTF8 without BOM. See https://stackoverflow.com/a/5596984/3214451
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
$targetFile = Join-Path $PSScriptRoot "$VERTICE_COLLECTION.json"
[System.IO.File]::WriteAllLines($targetFile, ($vertices | ConvertTo-Json), $Utf8NoBomEncoding)


$edges | ConvertTo-Json  | Set-Content "$EDGE_COLLECTION.json"