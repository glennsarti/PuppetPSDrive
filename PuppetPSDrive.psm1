using namespace Microsoft.PowerShell.SHiPS

$script:PuppetMasterURI = $null
$script:PuppetRequestSession = $null

[SHiPSProvider(UseCache=$true)]
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

    $obj += [PuppetConsoleClassification]::new();
    $obj += [PuppetConsoleServiceStatus]::new();
    $obj += [PuppetConsoleTaskCollection]::new();
    $obj += [PuppetConsoleNodeOverview]::new('Nodes') ;
      
    return $obj;
  }
}

# Nodes
class PuppetConsoleNodeSearcher
{
  Hidden [Hashtable]$Filter = @{}
  Hidden [Int]$OffsetBlock = 100
  Hidden [Int]$MaxResults = 2000

  PuppetConsoleNodeSearcher ([Hashtable]$filter)
  {
    $this.Filter = $filter
  }

  [object[]] GetChildNodes()
  {
    $obj = New-Object -TypeName System.Collections.ArrayList
    $Maximum = $this.MaxResults

    $offset = 0
    $returnedObjects = 0
    Write-Progress -Activity 'Loading Nodes' -PercentComplete 0

    $body = @{
      'filter' = ($this.Filter | ConvertTo-Json -Depth 5);
      'limit' = $this.OffsetBlock;
      'offset' = $offset;
    }

    # Filters are currently broken
    # $queryString = $this.ProviderContext.Filter
    # if ($queryString -ne $null) { $body.filter = $queryString }

    do {
      $body.offset = $offset;

      $result = (Invoke-PuppetRequest -URI '/api/cm/nodes' -Body $body | ConvertFrom-JSON)
      $totalNodes = $result.meta.total
      if ($totalNodes -le 1) { $totalNodes = $Maximum }
      Write-Progress -Activity 'Loading Nodes' -PercentComplete ($offset/$totalNodes * 100)
      $returnedObjects = 0
      $result.'cm/nodes' | % {
        $obj.Add([PuppetConsoleNode]::new($_.id, $_))
        $returnedObjects = $returnedObjects + 1
      }
      $offset = $offset + $this.OffsetBlock
    } while (($returnedObjects -eq $this.OffsetBlock) -and ($obj.Count -le $Maximum))
    Write-Progress -Activity 'Loading Nodes' -Completed

    if ($obj.Count -gt $Maximum) { THrow "Too many results returned" }

    return $obj;
  }
}

[SHiPSProvider(BuiltinProgress=$false)]
[SHiPSProvider(UseCache=$true)]
class PuppetConsoleNodeOverviewCollection : SHiPSDirectory
{
  [Int]$NodeCount
  Hidden [Object]$data
  Hidden [Object]$CollectionID

  PuppetConsoleNodeOverviewCollection ($name) : base ($name)
  {
    $this.InitObject($name, $null, 0)
  }
  PuppetConsoleNodeOverviewCollection ($name, $data, $collectionId) : base ($name)
  {
    $this.InitObject($name, $data, $collectionId)
  }

  [void] InitObject($name, $data, $collectionId) {
    $this.data = $data
    $this.collectionId = $collectionId
    if ($data -eq $null) {
      # We just want the metadata
      $body = @{
        'filter' = (@{ 'status' = 'all'} | ConvertTo-Json -Depth 5);
        'limit' = 1;
        'offset' = 0;
      }
      $result = (Invoke-PuppetRequest -URI '/api/cm/nodes' -Body $body | ConvertFrom-JSON)
      $this.data = $result.meta
    }

    switch ($this.collectionId) {
      0 { $this.NodeCount = $this.data.total; break; }
      1 {
        $total = 0
        $this.data.enforcement | ? { $_.type -ne 'cached' } | % {
          $total = $total + $_.count
        }
        $this.NodeCount = $total
        break;
      }
      2 {
        $total = 0
        $this.data.noop | ? { $_.type -ne 'cached' } | % {
          $total = $total + $_.count
        }
        $this.NodeCount = $total
        break;
      }
      3 {
        $total = 0
        $this.data.notReporting | ? { $_.type -ne 'cached' } | % {
          $total = $total + $_.count
        }
        $this.NodeCount = $total
        break;
      }
      4 { $this.NodeCount = $this.data.total; break; }
      # Enforcement
      5 {
        $total = 0
        $this.data.enforcement | ? { $_.type -ne 'cached' } | % {
          $total = $total + $_.count
        }
        $this.NodeCount = $total
        break;
      }
      6 { $this.data.enforcement | ? { $_.type -eq 'failed'} | % { $this.NodeCount = $_.count}}
      7 { $this.data.enforcement | ? { $_.type -eq 'remediated'} | % { $this.NodeCount = $_.count}}
      8 { $this.data.enforcement | ? { $_.type -eq 'changed'} | % { $this.NodeCount = $_.count}}
      9 { $this.data.enforcement | ? { $_.type -eq 'unchanged'} | % { $this.NodeCount = $_.count}}
      10 { $this.data.enforcement | ? { $_.type -eq 'cached'} | % { $this.NodeCount = $_.count}}
      # NoOp
      11 {
        $total = 0
        $this.data.noop | ? { $_.type -ne 'cached' } | % {
          $total = $total + $_.count
        }
        $this.NodeCount = $total
        break;
      }
      12 { $this.data.noop | ? { $_.type -eq 'failed'} | % { $this.NodeCount = $_.count}}
      13 { $this.data.noop | ? { $_.type -eq 'remediated'} | % { $this.NodeCount = $_.count}}
      14 { $this.data.noop | ? { $_.type -eq 'changed'} | % { $this.NodeCount = $_.count}}
      15 { $this.data.noop | ? { $_.type -eq 'unchanged'} | % { $this.NodeCount = $_.count}}
      # Not Reporting
      17 { $this.data.notReporting | ? { $_.type -eq 'unresponsive'} | % { $this.NodeCount = $_.count}}
      18 { $this.data.notReporting | ? { $_.type -eq 'unreported'} | % { $this.NodeCount = $_.count}}
    }
  }

  [object[]] GetChildItem() {
    $obj = @()

    # TODO: There's probably a better way of doing this than a static list and ID numbers
    switch ($this.collectionId) {
      # Root Overview
      0 {
        $obj += [PuppetConsoleNodeOverviewCollection]::new('All', $this.data, 4)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('In Enforcement', $this.data, 1)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('In Noop', $this.data, 2)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('Not Reporting', $this.data, 3)
        break;
      }
      # Nodes in enforcement
      1 {
        $obj += [PuppetConsoleNodeOverviewCollection]::new('All', $this.data, 5)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('With Failures', $this.data, 6)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('With Corrective Changes', $this.data, 7)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('With Intentional Changes', $this.data, 8)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('Unchanged', $this.data, 9)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('With Intended Catalog Failure', $this.data, 10)
        break;
      }
      # Nodes in NoOp
      2 {
        $obj += [PuppetConsoleNodeOverviewCollection]::new('All', $this.data, 11)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('With Failures', $this.data, 12)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('With Corrective Changes', $this.data, 13)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('With Intentional Changes', $this.data, 14)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('Unchanged', $this.data, 15)
        break;
      }
      # Nodes not reporting
      3 {
        $obj += [PuppetConsoleNodeOverviewCollection]::new('Unresponsive', $this.data, 17)
        $obj += [PuppetConsoleNodeOverviewCollection]::new('Have Not Reported', $this.data, 18)
        break;
      }
      # All Nodes
      4 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'all'}).GetChildNodes(); }
      # Nodes in enforcement
      5 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'all'; 'noop' = $false }).GetChildNodes(); }
      6 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'failed'; 'noop' = $false }).GetChildNodes(); }
      7 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'remediated'; 'noop' = $false }).GetChildNodes(); }
      8 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'changed'; 'noop' = $false }).GetChildNodes(); }
      9 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'unchanged'; 'noop' = $false }).GetChildNodes(); }
      10 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'cached'; 'noop' = $false }).GetChildNodes(); }
      # Nodes in enforcement
      11 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'all'; 'noop' = $true }).GetChildNodes(); }
      12 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'failed'; 'noop' = $true }).GetChildNodes(); }
      13 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'remediated'; 'noop' = $true }).GetChildNodes(); }
      14 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'changed'; 'noop' = $true }).GetChildNodes(); }
      15 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'unchanged'; 'noop' = $true }).GetChildNodes(); }
      # Nodes not reporting
      17 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'unresponsive'}).GetChildNodes(); }
      18 { $obj = [PuppetConsoleNodeSearcher]::new(@{ 'status' = 'unreported'}).GetChildNodes(); }
    }
    return $obj;
  }
}

[SHiPSProvider(BuiltinProgress=$false)]
[SHiPSProvider(UseCache=$true)]
class PuppetConsoleNodeOverview : PuppetConsoleNodeOverviewCollection
{

  PuppetConsoleNodeOverview ($name) : base ($name) { }
  PuppetConsoleNodeOverview ($name, $data, $collectionId) : base ($name, $data, $collectionId) { }
}

class PuppetConsoleNode : SHiPSLeaf
{
  [String]$Name;
  [String]$Id;
  [String]$Environment;
  [Boolean]$NoOp;
  [String]$ReportId;
  [String]$ReportedAt;
  [String]$Status;
  Hidden [object]$data = $null

  PuppetConsoleNode () : base ('Node')
  {
  }

  PuppetConsoleNode ([String]$name, [Object]$data): base($name)
  {
    $this.data = $data

    $this.Name = $data.nodeName
    $this.Id = $data.Id
    $this.Environment = $data.environment
    $this.NoOp = $data.noop
    $this.ReportId = $data.reportId
    $this.ReportedAt = $data.reportedAt
    $this.Status = $data.status
  }
}

# Tasks
[SHiPSProvider(UseCache=$true)]
class PuppetConsoleTaskCollection : SHiPSDirectory
{
  PuppetConsoleTaskCollection () : base ('Tasks')
  {
  }

  PuppetConsoleTaskCollection ([String]$name): base($name)
  {
  }

  [object[]] GetChildItem()
  {
    $result = $null
    try {
      $result = (Invoke-PuppetRequest -URI '/api/tasks' | ConvertFrom-JSON)
    } catch {
      if ($_.ToString() -ne 'Resource not found.') { Throw $_ }
    }
    if ($result -eq $null) { return @() }
    $obj = ($result.'tasks' | % {
      Write-Output ([PuppetConsoleTask]::new($_.name, $_))
    })
    
    return $obj;
  }
}

[SHiPSProvider(UseCache=$true)]
class PuppetConsoleTask : SHiPSDirectory
{
  [String]$Name;
  [String]$Description;
  [String]$Id;
  [String]$Metadatum;
  [String[]]$Parameters;
  [String[]]$RequiredParameters;
  [Object[]]$ParameterDefinition;
  
  Hidden [object]$data = $null
  Hidden [object]$metadata = $null
  
  PuppetConsoleTask ([string]$name): base($name)
  {
  }

  PuppetConsoleTask ([string]$name, [Object]$data): base($name)
  {
    $this.data = $data

    $this.Name = $name
    $this.Id = $data.Id
    $this.Metadatum = $data.metadatum

    $this.metadata = (Invoke-PuppetRequest -URI ('/api/tasks/' + $this.Metadatum + '/meta') | ConvertFrom-JSON)

    $this.ParameterDefinition = $this.metadata.metadatum.params
    $this.Description = $this.metadata.metadatum.description
    $this.Parameters = @()
    $this.RequiredParameters = @()
    $this.ParameterDefinition | % {
      $this.Parameters += $_.name
      if ($_.required) { $this.RequiredParameters += $_.name }
    }
  }

  [object[]] GetChildItem()
  {
    return @()
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
  if ($Body -ne $null) { $iwrArgs.Add('Body', $Body) }
  $oldPreference = $progressPreference
  $progressPreference = 'SilentlyContinue'
  $result = Invoke-WebRequest @iwrArgs
  $progressPreference = $oldPreference

  Return $result.Content
}

# Fake Function
Function Start-PuppetTask {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory=$true, Position=0)]
    [PuppetConsoleTask] $Task,

    [Parameter(Mandatory=$true, ParameterSetName="ByNodeName")]
    [String[]] $Nodes = $null,

    [Parameter(Mandatory=$true, ParameterSetName="ByNodeObject", ValueFromPipeline=$true)]
    [Object[]] $InputObject = $null,

    [Alias('Params','Param')]
    [hashtable]$Parameters = @{},

    [Switch]$Wait
  )

  Begin {
    $MissingParams = @()
    $Task.RequiredParameters | % {
      if (-Not ($Parameters.ContainsKey($_))) {
        $MissingParams += $_
      }
    }

    if ($MissingParams -ne @()) { Throw "Missing required parameters $($MissingParams -join ', ')"; return }

    $NodeNames = New-Object -TypeName System.Collections.ArrayList
  }

  Process {
    if ($_ -ne $null) {
      $thisNode = $_
    } else {
      $thisNode = $Nodes[0]
    }
    if ($thisNode.GetType().ToString() -eq 'PuppetConsoleNode') { $thisNode = $thisNode.Name }

    # Fake the job
    if ($Wait) {
      $obj = New-Object -TypeName PSObject -Property @{'Node Name' = $thisNode; 'Status' = 'completed' }
      Write-Output $obj
    } else {
      $obj = New-Object -TypeName PSObject -Property @{'Node Name' = $thisNode; 'Status' = 'submitted' }
      Write-Output $obj
    }
  }

  End {
  }
}
