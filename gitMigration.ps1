$BBusername = "juzernejm"
$BBplainPwd = Read-Host "heslo"
Set-Variable BBRestUri -Option Constant -Value ([string]"https://bb-qa.onsemi.com/rest/api/1.0") -Scope Global -Force -ErrorAction Ignore

function Set-BBProject {
    Param
    (
        [parameter(Mandatory = $true, Position = 0, HelpMessage = "Bitbucket Project Name")]
        [String]
        $BBProjectName,
        [parameter(Mandatory = $true, Position = 1, HelpMessage = "Bitbucket Project Key")]
        [String]
        $BBProjectKey

    )

    $projectExists = $false
    $statusCode = 0
    $responseCheck = $null
    $projectWasJustCreated = $false

    try {
        Write-host "Getting info about project [$BBProjectKey]"

        $BBUri = "$BBRestUri/projects/$BBProjectKey"
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $BBusername, $BBplainPwd)))
        $header = @{accept = "application/json"; Authorization = ("Basic {0}" -f $base64AuthInfo) }
        $bodyHash = @{name = $BBProjectName; key = $BBProjectKey; is_private = $false }
        $body = $bodyHash | ConvertTo-Json


        #Checks if BB project exists if not creates it
        $responseCheck = Invoke-WebRequest -Method Get -Uri $BBUri -ContentType "application/json" -Headers $header -ErrorAction SilentlyContinue
    }
    catch {
        Write-host "Getting info about project [$BBProjectKey]: [$($_.Exception.Message)]"
    }


    if ($($responseCheck.StatusCode) -eq 200) {
        $statusCode = 200
        Write-host "Project [$BBProjectName,$BBProjectKey] already exists"
        $projectExists = $true
    }
    else {
        # try to create project
        try {
            $BBUri = "$BBRestUri/projects"
            $response = Invoke-WebRequest -Method Post -Uri $BBUri -Body $body -ContentType "application/json" -Headers $header
            if ($($response.StatusCode) -eq 201) {
                $statusCode = 201
                $projectExists = $true
                $projectWasJustCreated = $true
            }
        }
        catch {
            Write-host "Creating project: [$($_.Exception.Message)]"

            if ($($_.Exception.Message) -match "(409) Conflict") {
                Write-host "Trying with different project name"
                $statusCode = 409
            }
            else {
                $statusCode = 999
            }

            Write-host "$($_.Exception.Message). Trying with different project name"

            # write-log
            # stop
        }
    }

    return $statusCode
}

function Set-BBRepo {

    Param
    (
        [parameter(Mandatory = $true, Position = 0, HelpMessage = "Bitbucket Project Name")]
        [String]
        $BBProjectKey,
        [parameter(Mandatory = $true, Position = 1, HelpMessage = "Bitbucket Repository URL")]
        [String]
        $BBRepoSlug,
        [parameter(Position = 2, HelpMessage = "Set Repository to public")]
        [switch]
        $PublicRepo,
        [parameter(Position = 3, HelpMessage = "Delete Repo")]
        [switch]
        $DeleteBBRepo


    )

    $BBUri = "$BBRestUri/projects/$BBProjectKey/repos/$BBRepoSlug/commits"
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $BBusername, $BBplainPwd)))
    $header = @{accept = "application/json"; Authorization = ("Basic {0}" -f $base64AuthInfo) }
    $responseN = $null
    $responseCreate = $null


    if ($DeleteBBRepo) {
        $BBUri = "$BBRestUri/projects/$BBProjectKey/repos/$BBRepoSlug"
        $del = Invoke-WebRequest -Method DELETE -Uri $BBUri -ContentType "application/json" -Headers $header -ErrorAction Ignore
        if (($del.StatusCode -eq 202) -or ($del.StatusCode -eq 204)) {
            return $true
        }
        else {
            Write-host "Unable to delete BB Repo [$BBUri]"
            Throw "Unable to delete BB Repo"
        }

    }
    else {
        try {
            $responseN = Invoke-WebRequest -Method Get -Uri $BBUri -ContentType "application/json" -Headers $header -ErrorAction Ignore
        }
        catch {
            Write-host "Repo [$BBUri] does not exists. Thought so... Will attempt to create. Hang on..."
        }

        switch ($responseN.StatusCode) {
            200 {

                $payload = $responseN.Content | ConvertFrom-Json
                if ($payload.size -eq 0) {
                    Write-host "Empty BB Repo already exists [$BBUri]"
                    return $true
                }
                else {
                    Write-host "NONEmpty BB Repo already exists [$BBUri] !!! Resolve"
                    Throw "BB Repo exists and is not empty !!!"
                }

            }
            default {
                Write-host "Creating repository"

                $BBUri = "$BBRestUri/projects/$BBProjectKey/repos"
                $bodyHash = @{name = $BBRepoSlug; scmId = 'git'; public = $PublicRepo.IsPresent }
                $body = $bodyHash | ConvertTo-Json

                try {
                    $responseCreate = Invoke-WebRequest -Method Post -Uri $BBUri -Body $body -ContentType "application/json" -Headers $header
                    return $($responseCreate.StatusCode)
                }
                catch {                    
                    Write-host "Creating new repo: [$($_.Exception.Message)]"
                    return $false
                }
            }
        }
    }


}
function Start-GitMigrate {

    Param
    (
        [parameter(Mandatory = $true, Position = 0, HelpMessage = "SCM Repository URL")]
        [String]
        $sourceRepositoryURL,
        [parameter(Mandatory = $true, Position = 1, HelpMessage = "BB Repository URL")]
        [String]
        $DestinationGitRepositoryURL,
        [parameter(Mandatory = $true, Position = 2, HelpMessage = "SCM ID")]
        [String]
        $RepoID
    )

    [string]$repoName = $RepoID + "_" + $(Split-Path $SourceRepositoryURL -Leaf)
    #fix reponame for git
    $repoName = $repoName.Replace(".git", "")
    $mainTempRepoFolder = "C:\Temp\BB\M"

    [string]$fullPath = $mainTempRepoFolder + "\" + $repoName

    If (!(Test-Path $mainTempRepoFolder)) {
        $null = New-Item -ItemType Directory -Force -Path $mainTempRepoFolder
    }
    Set-Location $mainTempRepoFolder

    if (Get-Item $repoName -ErrorAction:SilentlyContinue) {
        Remove-Item -path $fullPath -Recurse -Force
        $null = mkdir $fullPath

    }
    else {
        $null = mkdir $fullPath
    }

    #based on https://www.atlassian.com/git/tutorials/git-move-repository    
    git.exe clone $SourceRepositoryURL --mirror $fullPath
    Set-Location $fullPath
    git.exe remote rm origin
    git.exe push $DestinationGitRepositoryURL --all --verbose
    git.exe push $DestinationGitRepositoryURL --tags

}

# $repos = @("spyglass",
# "platform-apps",
# "cloud-services",
# "cloud-microservices",
# "embedded-strata-core",
# "training",
# "computer-vision",
# "cadence_library")
$BBProjectKey = "test2"
$BBProjectName = "test2"

$repos = @(
"AccessManagement",
"Autosys",
"Confluence",
"ScriptTools"
)

foreach($repo in $repos){
# https://code.onsemi.com/scm/cdtapp/bitbucket.git
    $sourceRepositoryURL = "ssh://git@code.onsemi.com/$BBProjectName/$repo.git"
    $DestinationGitRepositoryURL= "ssh://git@bb-qa.onsemi.com:7999/scm/$BBProjectName/$repo.git"
    $RepositoryID = "MigrationToQa"

    Set-BBProject -BBProjectName $BBProjectName -BBProjectKey $BBProjectKey
    Set-BBRepo -BBProjectKey $BBProjectKey -BBRepoSlug $repo -PublicRepo:$false
    Start-GitMigrate -SourceRepositoryURL $sourceRepositoryURL -DestinationGitRepositoryURL $DestinationGitRepositoryURL -RepoID $RepositoryID
}