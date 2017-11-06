using namespace Microsoft.PowerShell.SHiPS

$script:PuppetMasterURI = $null
$script:PuppetRequestSession = $null

class PuppetConsole : SHiPSDirectory
{
  PuppetConsole() : base($this.GetType())
  {
  }

  PuppetConsole([string]$name): base($name)
  {
  }

  [object[]] GetChildItem()
  {
    $obj =  @()

    $obj += [PuppetConsoleServiceStatus]::new();
    $obj += [PuppetConsoleClassification]::new();
    
    return $obj;
  }
}

# Classification and Node Groups
[SHiPSProvider(UseCache=$true)]
class PuppetConsoleNodeGroup : SHiPSDirectory
{
  [String]$Description;
  [String]$DisplayName;
  [String]$Environment;
  [String]$Id;

  Hidden [object]$data = $null

  PuppetConsoleNodeGroup ([String]$Name, [String]$Description, [Object]$data): base($name)
  {
    $this.data = $data
    
    $this.DisplayName = $data.displayname
    $this.Description = $data.description
    $this.Environment = $data.environment
    $this.Id = $data.Id
  }

  [object[]] GetChildItem()
  {
    $findRoot = ($this.data -eq $null) -or ($this.data.id -eq $null)
    
    $uriModifier = ''
    if (!$findRoot) {
      $uriModifier = '/' + $this.data.id
    }

    $result = (Invoke-PuppetRequest -URI "/api/classifier/group-tree$($uriModifier)?depth=1" | ConvertFrom-JSON)
    $obj = @()
    $result.'group-tree' | % {
      if ($findRoot) {
        if ($_.id -eq $_.parent) { $obj += ([PuppetConsoleNodeGroup]::new($_.DisplayName, $_.Description, $_)) }
      } else {
        if ($_.id -ne $this.data.id) { $obj += ([PuppetConsoleNodeGroup]::new($_.DisplayName, $_.Description, $_)) }
      }
    }

    return $obj;
  }
}

class PuppetConsoleClassification : PuppetConsoleNodeGroup
{
  PuppetConsoleClassification () : base ('Classification', $null, $null)
  {
  }
}

# Service Status Classes
class PuppetConsoleServiceStatus : SHiPSDirectory
{
  PuppetConsoleServiceStatus () : base ('ServiceStatus')
  {
  }

  PuppetConsoleServiceStatus ([String]$name): base($name)
  {
  }

  [object[]] GetChildItem()
  {
    $obj =  @()

    $obj += [PuppetConsoleServiceStatusCollection]::new('All');
    $obj += [PuppetConsoleServiceStatusCollection]::new('Running');
    $obj += [PuppetConsoleServiceStatusCollection]::new('Error');
    $obj += [PuppetConsoleServiceStatusCollection]::new('Unknown');

    return $obj;
  }
}

class PuppetConsoleServiceStatusCollection : SHiPSDirectory
{
  PuppetConsoleServiceStatusCollection () : base ('ServiceStatusCollection')
  {
  }

  PuppetConsoleServiceStatusCollection ([string]$name): base($name)
  {
  }

  [object[]] GetChildItem()
  {
    $collectionName = $this.Name

    $result = (Invoke-PuppetRequest -URI '/api/cm/service-alerts' | ConvertFrom-JSON)
    $obj = ($result.'cm/service-alerts' | ? { ($_.state -like $collectionName) -or ($collectionName -eq 'All') } | % {
      Write-Output ([PuppetConsoleServiceStatusItem]::new($_.id, $_))
    })
    
    return $obj;
  }
}

class PuppetConsoleServiceStatusItem : SHiPSLeaf
{
  [String]$DisplayName;
  [String]$Name;
  [String]$Url;
  [String]$Status;
  [String]$ServiceVersion;
  [String]$State;
  [String]$Replication;
  [String]$Timestamp;
  Hidden [object]$data = $null

  PuppetConsoleServiceStatusItem ([string]$name): base($name)
  {
  }

  PuppetConsoleServiceStatusItem ([string]$name, [Object]$data): base($name)
  {
    $this.data = $data

    $this.DisplayName = $data.name
    $this.Name = $name
    $this.Url = $data.url
    $this.Status = $data.status
    $this.ServiceVersion  = $data.serviceVersion
    $this.State  = $data.state
    $this.Replication  = $data.replication
    $this.Timestamp  = $data.timestamp
  }
}

#----- Helper functions
Function Script:Get-PuppetLoginToken() {
  $password = $ENV:PuppetConsolePassword
  if ($ENV:PuppetConsoleSecurePassword -ne $null) {
    # Decrypt a Secure String
    $SecureStr = ConvertTo-SecureString -String $ENV:PuppetConsoleSecurePassword
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureStr)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
  }
  $body = @{
    'username' = $ENV:PuppetConsoleUsername;
    'password' = $password;
    'redirect' = '/'
  }
  $sv = $null

  $contentType = 'application/x-www-form-urlencoded'
  $result = Invoke-WebRequest -Uri "$($ENV:PuppetConsoleURI)/auth/login" -ContentType $contentType `
    -Method Post -Body $body -SessionVariable sv

  $body = $null
  $password = $null

  $token = $null
  $result.Headers.'Set-Cookie' | % {
    if ($_.SubString(0,8) -eq 'pl_ssti=') { $token = ($_.SubString(8) -split ';',2)[0]}
  }
  $sv.Headers.Add('X-Authentication', $Token + '|no_keepalive')
  $script:PuppetRequestSession = $sv
  $script:PuppetMasterURI = $ENV:PuppetConsoleURI
}

Function Script:Invoke-PuppetRequest($URI, $Method = 'GET', $Body = $null) {
  if ($script:PuppetRequestSession -eq $null) {
    Get-PuppetLoginToken | Out-Null
  }

  $iwrArgs = @{
    'URI' = "$($script:PuppetMasterURI)$URI";
    'Method' = $Method;
    'WebSession' = $script:PuppetRequestSession;
    'UseBasicParsing' = $true;
  }
  $oldPreference = $progressPreference
  $progressPreference = 'SilentlyContinue'
  $result = Invoke-WebRequest @iwrArgs
  $progressPreference = $oldPreference

  Return $result.Content
}
