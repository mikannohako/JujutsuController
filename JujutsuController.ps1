[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

$script:DefaultRepositoryUrl = "https://github.com/mikannohako/JujutsuController.git"
$script:ConfigPath = Join-Path $PSScriptRoot "config.ini"
$script:SetupMarkerPath = Join-Path $PSScriptRoot ".setup-completed"
$script:ControllerVersion = "4.1.1"
$Host.UI.RawUI.WindowTitle = "JujutsuController"

function Get-LatestRelease {
    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/mikannohako/JujutsuController/releases/latest" `
        -Headers @{ "User-Agent" = "JujutsuController" }

    if ($null -eq $release) {
        throw "GitHub APIからリリース惁E��を取得できませんでした、E
    }

    if ([string]::IsNullOrWhiteSpace([string]$release.tag_name)) {
        throw "最新リリースのバ�Eジョン惁E��が取得できませんでした、E
    }

    return $release
}

function Test-Update {
    try {
        $release = Get-LatestRelease

        $latestVersion = ([string]$release.tag_name).TrimStart("v")
        $latestUrl = [string]$release.html_url

        if ([version]$latestVersion -gt [version]$script:ControllerVersion) {
            Write-Host ""
            Write-Host "新しいJujutsuControllerがあります、E -ForegroundColor Yellow
            Write-Host "  現在: $script:ControllerVersion" -ForegroundColor Gray
            Write-Host "  最新: $latestVersion" -ForegroundColor Green
            Write-Host ""

            if (
                Read-YesNo -Prompt "最新版�Eペ�Eジを開きますか�E�E -DefaultYes $true
            ) {
                Start-Process $latestUrl
            }
        }
    }
    catch {
        Write-Host "JujutsuControllerの更新確認中にエラーが発生しました: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  Jujutsu Controller" -ForegroundColor Cyan
    Write-Host "  Git / Jujutsu project toolkit" -ForegroundColor DarkCyan
    Write-Host "  Version $script:ControllerVersion" -ForegroundColor DarkGray
    Write-Host "  Repository: $($script:DefaultRepositoryUrl)" -ForegroundColor DarkGray
    Write-Host "  $('-' * 42)" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-StageProgress {
    param(
        [Parameter(Mandatory)] [int] $Current,
        [Parameter(Mandatory)] [int] $Total,
        [Parameter(Mandatory)] [string] $Activity,
        [Parameter(Mandatory)] [string] $Status
    )

    Write-Host "  $Activity - $Status" -ForegroundColor DarkCyan
}

function Invoke-RequiredCommand {
    param(
        [Parameter(Mandatory)] [string] $Command,
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "コマンドに失敗しました: $Command $($Arguments -join ' ')"
    }
}

function Test-CommandAvailable {
    param([Parameter(Mandatory)] [string] $Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Read-Config {
    $config = @{}
    if (-not (Test-Path $script:ConfigPath)) {
        return $config
    }

    foreach ($line in [System.IO.File]::ReadAllLines($script:ConfigPath)) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith("#") -or $trimmedLine.StartsWith("[")) {
            continue
        }

        $separator = $trimmedLine.IndexOf('=')
        if ($separator -gt 0) {
            $key = $trimmedLine.Substring(0, $separator).Trim()
            $value = $trimmedLine.Substring($separator + 1).Trim()
            $config[$key] = $value
        }
    }

    return $config
}

function Save-Config {
    param(
        [Parameter(Mandatory)] [string] $UserName,
        [Parameter(Mandatory)] [string] $UserEmail,
        [string] $RepositoryUrl = $script:DefaultRepositoryUrl,
        [AllowEmptyString()] [string] $SshSigningKey = $null
    )

    $existingConfig = Read-Config
    $projectDirectory = [string] $existingConfig["project_directory"]
    if ($null -eq $SshSigningKey) {
        $SshSigningKey = [string] $existingConfig["ssh_signing_key"]
    }
    $lines = @(
        "[user]",
        "name=$UserName",
        "email=$UserEmail",
        "repository_url=$RepositoryUrl",
        "project_directory=$projectDirectory",
        "ssh_signing_key=$SshSigningKey",
        ""
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($script:ConfigPath, $lines, $utf8NoBom)
}

function Save-ProjectDirectory {
    param([Parameter(Mandatory)] [string] $ProjectDirectory)

    $lines = @()
    if (Test-Path -LiteralPath $script:ConfigPath) {
        $lines = [System.IO.File]::ReadAllLines($script:ConfigPath)
    }

    $projectLineIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*project_directory\s*=') {
            $projectLineIndex = $index
            break
        }
    }

    $projectLine = "project_directory=$ProjectDirectory"
    if ($projectLineIndex -ge 0) {
        $lines[$projectLineIndex] = $projectLine
    }
    else {
        $lines += $projectLine
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($script:ConfigPath, $lines, $utf8NoBom)
}

function Get-ProjectDirectory {
    $config = Read-Config
    $projectDirectory = [string] $config["project_directory"]
    if ([string]::IsNullOrWhiteSpace($projectDirectory)) {
        throw "セチE��アチE�E先�Eプロジェクトフォルダが設定されてぁE��せん。セチE��アチE�Eを�E実行してください、E
    }
    if (-not (Test-Path -LiteralPath $projectDirectory -PathType Container)) {
        throw "保存済みのプロジェクトフォルダが見つかりません: $projectDirectory"
    }

    $resolvedProjectDirectory = (Resolve-Path -LiteralPath $projectDirectory).Path
    $hasRepository = Test-Path -LiteralPath (Join-Path $resolvedProjectDirectory ".jj")
    $hasGitRepository = Test-Path -LiteralPath (Join-Path $resolvedProjectDirectory ".git")
    if (-not ($hasRepository -or $hasGitRepository)) {
        throw "保存済みのフォルダは Git/Jujutsu リポジトリではありません: $resolvedProjectDirectory"
    }

    return $resolvedProjectDirectory
}

function Set-ProjectLocation {
    $projectDirectory = Get-ProjectDirectory
    Set-Location -LiteralPath $projectDirectory
}

function Get-RepositoryUrl {
    $config = Read-Config
    $repositoryUrl = [string] $config["repository_url"]
    if ([string]::IsNullOrWhiteSpace($repositoryUrl)) {
        return $script:DefaultRepositoryUrl
    }
    return $repositoryUrl
}

function Get-SshSigningKey {
    $config = Read-Config
    return [string] $config["ssh_signing_key"]
}

function Test-SshSigningKey {
    param([Parameter(Mandatory)] [string] $PublicKey)

    $normalizedKey = ($PublicKey -replace "`r`n", "`n").Trim()
    $keyLines = @($normalizedKey -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($keyLines.Count -ne 1) {
        throw "SSH公開鍵は1行で入力してください。秘寁E��の冁E��は持E��しなぁE��ください、E
    }
    if ($keyLines[0] -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\s+\S+(?:\s+.*)?$') {
        throw "SSH公開鍵の形式を確認できません。ssh-ed25519、ssh-rsa、また�EECDSA公開鍵を指定してください、E
    }
    return $keyLines[0].Trim()
}

function Remove-OptionalConfigValue {
    param(
        [Parameter(Mandatory)] [string] $Command,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [int[]] $AllowedExitCodes
    )

    & $Command @Arguments
    if ($LASTEXITCODE -notin $AllowedExitCodes) {
        throw "コマンドに失敗しました: $Command $($Arguments -join ' ')"
    }
}

function Set-SshSigningConfiguration {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $PublicKey
    )

    if ([string]::IsNullOrWhiteSpace($PublicKey)) {
        Remove-OptionalConfigValue "git" @("config", "--global", "--unset", "gpg.format") @(0, 5)
        Remove-OptionalConfigValue "git" @("config", "--global", "--unset", "user.signingkey") @(0, 5)
        Remove-OptionalConfigValue "git" @("config", "--global", "--unset", "commit.gpgsign") @(0, 5)
        Remove-OptionalConfigValue "jj" @("config", "unset", "--user", "signing.backend") @(0, 1)
        Remove-OptionalConfigValue "jj" @("config", "unset", "--user", "signing.key") @(0, 1)
        return
    }

    $normalizedKey = Test-SshSigningKey -PublicKey $PublicKey
    Invoke-RequiredCommand "git" @("config", "--global", "gpg.format", "ssh")
    Invoke-RequiredCommand "git" @("config", "--global", "user.signingkey", $normalizedKey)
    Invoke-RequiredCommand "git" @("config", "--global", "commit.gpgsign", "true")
    Invoke-RequiredCommand "jj" @("config", "set", "--user", "signing.backend", "ssh")
    Invoke-RequiredCommand "jj" @("config", "set", "--user", "signing.key", $normalizedKey)

    try {
        Set-Clipboard -Value $normalizedKey
        Write-Host "公開鍵をクリチE�Eボ�Eドへコピ�Eしました、E -ForegroundColor Green
    }
    catch {
        Write-Host "公開鍵のクリチE�Eボ�Eドへのコピ�Eに失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host "GitHubの SSH signing key 登録画面で公開鍵を登録してください、E -ForegroundColor Yellow
    if (Read-YesNo -Prompt "GitHubの登録画面を開きますか�E�E -DefaultYes $true) {
        Start-Process "https://github.com/settings/keys"
    }
}

function Read-SshSigningSettings {
    param([Parameter(Mandatory)] [string] $UserEmail)

    $currentKey = Get-SshSigningKey
    if (-not [string]::IsNullOrWhiteSpace($currentKey) -and
        (Test-Path -LiteralPath $currentKey -PathType Leaf)) {
        $currentKey = [System.IO.File]::ReadAllText($currentKey).Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($currentKey)) {
        Write-Host ""
        Write-Host "保存済みのSSH署名鍵: $currentKey" -ForegroundColor Cyan
        $decision = Read-Host "こ�ESSH署名鍵を利用しますか�E�E[Y/n/D(解除)]"
        if ([string]::IsNullOrWhiteSpace($decision) -or $decision -match '^(?i)y(es)?$') {
            $normalizedKey = Test-SshSigningKey -PublicKey $currentKey
            Set-SshSigningConfiguration -PublicKey $normalizedKey
            return $normalizedKey
        }
        if ($decision -match '^(?i)d(elete)?$') {
            Set-SshSigningConfiguration -PublicKey ""
            return ""
        }
    }

    if (Read-YesNo -Prompt "SSH署名鍵を設定�E変更しますか�E�E -DefaultYes $False) {
        return $currentKey
    } else {
        return ""
        Write-Host "設定�E行いませんでした、E -ForegroundColor Green
    }

    Write-Host "公開鍵の持E��方法を選択してください、E -ForegroundColor Cyan
    Write-Host "  F: 公開鍵ファイルを読み込む"
    Write-Host "  T: 公開鍵を文章で入力すめE
    $inputMethod = Read-Host "持E��方況E[F/T]"
    if ($inputMethod -match '^(?i)f(ile)?$') {
        $keyPath = Read-Host "SSH公開鍵ファイルのパス"
        if ([string]::IsNullOrWhiteSpace($keyPath)) {
            throw "SSH公開鍵ファイルのパスが�E力されてぁE��せん、E
        }
        $resolvedPath = [System.IO.Path]::GetFullPath($keyPath.Trim().Trim('"'))
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "SSH公開鍵ファイルが見つかりません: $resolvedPath"
        }
        $inputKey = [System.IO.File]::ReadAllText($resolvedPath)
    }
    elseif ($inputMethod -match '^(?i)t(ext)?$') {
        $inputKey = Read-Host "SSH公開鍵めE行で入力してください"
    }
    else {
        throw "公開鍵の持E��方法�E F また�E T です、E
    }

    $normalizedKey = Test-SshSigningKey -PublicKey $inputKey
    Set-SshSigningConfiguration -PublicKey $normalizedKey
    return $normalizedKey
}

function Read-RepositorySettings {
    param([Parameter(Mandatory)] [hashtable] $UserSettings)

    $currentRepositoryUrl = Get-RepositoryUrl
    Write-Host ""
    Write-Host "cloneするリポジトリを選択してください、E -ForegroundColor Cyan
    $repositoryUrl = Read-Host "リポジトリURL [$currentRepositoryUrl]"
    if ([string]::IsNullOrWhiteSpace($repositoryUrl)) {
        $repositoryUrl = $currentRepositoryUrl
    }
    Test-RepositoryUrl -RepositoryUrl $repositoryUrl

    if (Read-YesNo -Prompt "こ�EリポジトリURLを設定に保存しますか�E�E -DefaultYes $true) {
        Save-Config -UserName $UserSettings.Name -UserEmail $UserSettings.Email -RepositoryUrl $repositoryUrl
        Write-Host "設定を保存しました: $script:ConfigPath" -ForegroundColor Green
    }
    else {
        Write-Host "リポジトリURLは保存せず、今回のセチE��アチE�Eだけで利用します、E -ForegroundColor Yellow
    }

    return $repositoryUrl
}

function Test-RepositoryUrl {
    param([Parameter(Mandatory)] [string] $RepositoryUrl)

    if ($RepositoryUrl -match '^git@[^:]+:.+$') {
        return
    }

    $uri = $null
    if (-not [Uri]::TryCreate($RepositoryUrl, [UriKind]::Absolute, [ref] $uri) -or $uri.Scheme -notin @("http", "https", "ssh", "git")) {
        throw "リポジトリURLが正しくありません、E
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter()] [bool] $DefaultYes = $true
    )

    $defaultOption = if ($DefaultYes) { "Y/n" } else { "y/N" }
    while ($true) {
        $response = Read-Host "$Prompt [$defaultOption]"
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultYes
        }
        if ($response -match '^(?i)y(es)?$') {
            return $true
        }
        if ($response -match '^(?i)n(o)?$') {
            return $false
        }
        Write-Host "有効な入力ではありません、E また�E N を�E力してください、E -ForegroundColor Yellow
    }
}

function Read-UserSettings {
    $config = Read-Config
    $savedName = [string] $config["name"]
    $savedEmail = [string] $config["email"]
    $hasSavedSettings = -not [string]::IsNullOrWhiteSpace($savedName) -and -not [string]::IsNullOrWhiteSpace($savedEmail)

    if ($hasSavedSettings) {
        Write-Host "保存済みの設定が見つかりました、E -ForegroundColor Cyan
        Write-Host "  名前: $savedName" -ForegroundColor DarkGray
        Write-Host "  メール: $savedEmail" -ForegroundColor DarkGray
        if (Read-YesNo "こ�E設定を利用しますか�E�E $true) {
            return @{ Name = $savedName; Email = $savedEmail }
        }
    }
    
    $userName = Read-Host "Git ユーザー吁E
    $userEmail = Read-Host "Git メールアドレス"
    if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($userEmail)) {
        throw "名前とメールアドレスは忁E��です、E
    }

    if (Read-YesNo "設定を保存しますか�E�E $true) {
        Save-Config -UserName $userName -UserEmail $userEmail -RepositoryUrl (Get-RepositoryUrl)
        Write-Host "設定を保存しました: $script:ConfigPath" -ForegroundColor Green
    }
    else {
        Write-Host "設定�E保存せず、この処琁E��のみ利用します、E -ForegroundColor Yellow
    }
    return @{ Name = $userName; Email = $userEmail }
}

function Invoke-ConfigChange {
    Write-Header
    try {
        $config = Read-Config
        $currentName = [string] $config["name"]
        $currentEmail = [string] $config["email"]
        $currentRepositoryUrl = Get-RepositoryUrl
        $currentSshSigningKey = [string] $config["ssh_signing_key"]
        $sshSigningLabel = if ([string]::IsNullOrWhiteSpace($currentSshSigningKey)) { "未設宁E } else { $currentSshSigningKey }

        $settings = @(
            [PSCustomObject]@{ Label = "Git ユーザー吁E; Key = "name"; Value = $currentName },
            [PSCustomObject]@{ Label = "Git メールアドレス"; Key = "email"; Value = $currentEmail },
            [PSCustomObject]@{ Label = "リポジトリURL"; Key = "repository_url"; Value = $currentRepositoryUrl },
            [PSCustomObject]@{ Label = "SSH署名鍵"; Key = "ssh_signing_key"; Value = $sshSigningLabel }
        )
        $selected = 0
        $itemCount = $settings.Count + 1
        while ($true) {
            Write-Header
            Write-Host "  変更する設定を選択してください、E -ForegroundColor Cyan
            Write-Host "  上丁E選抁E Enter:決宁E Esc:キャンセル" -ForegroundColor DarkCyan
            Write-Host ""
            for ($index = 0; $index -lt $settings.Count; $index++) {
                $line = "$($settings[$index].Label): $($settings[$index].Value)"
                if ($index -eq $selected) {
                    Write-Host "  > $line" -ForegroundColor White -BackgroundColor DarkGray
                }
                else {
                    Write-Host "    $line" -ForegroundColor Gray
                }
            }

            if ($selected -eq $settings.Count) {
                Write-Host "  > キャンセル" -ForegroundColor Yellow -BackgroundColor DarkGray
            }
            else {
                Write-Host "    キャンセル" -ForegroundColor Yellow
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" { $selected = ($selected - 1 + $settings.Count + 1) % ($settings.Count + 1) }
                "DownArrow" { $selected = ($selected + 1) % ($settings.Count + 1) }
                "Escape" { return }
                "Enter" { break }
            }
            if ($key.Key -eq "Enter") {
                break
            }
        }

        if ($selected -eq $settings.Count) {
            Write-Host "設定変更をキャンセルしました、E -ForegroundColor Yellow
            return
        }

        $setting = $settings[$selected]
        if ($setting.Key -eq "ssh_signing_key") {
            $newSshSigningKey = Read-SshSigningSettings -UserEmail $currentEmail
            Save-Config `
                -UserName $currentName `
                -UserEmail $currentEmail `
                -RepositoryUrl $currentRepositoryUrl `
                -SshSigningKey $newSshSigningKey
            Write-Host "SSH署名鍵の設定を更新しました、E -ForegroundColor Green
            return
        }

        $newValue = Read-Host "$($setting.Label) [$($setting.Value)]"
        if ([string]::IsNullOrWhiteSpace($newValue)) {
            Write-Host "設定変更をキャンセルしました、E -ForegroundColor Yellow
            return
        }

        $newName = $currentName
        $newEmail = $currentEmail
        $newRepositoryUrl = $currentRepositoryUrl
        switch ($setting.Key) {
            "name" { $newName = $newValue }
            "email" { $newEmail = $newValue }
            "repository_url" { $newRepositoryUrl = $newValue }
        }
        if ([string]::IsNullOrWhiteSpace($newName) -or [string]::IsNullOrWhiteSpace($newEmail)) {
            throw "名前とメールアドレスは忁E��です、E
        }
        Test-RepositoryUrl -RepositoryUrl $newRepositoryUrl
        Save-Config -UserName $newName -UserEmail $newEmail -RepositoryUrl $newRepositoryUrl
        Write-Host "設定を保存しました: $script:ConfigPath" -ForegroundColor Green
    }
    catch {
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = @($machinePath, $userPath) | Where-Object { $_ } | ForEach-Object {
        $_ -split ';' | Where-Object { $_ }
    }

    $env:Path = ($pathEntries | Select-Object -Unique) -join ';'
    Write-Host "PATH を�E読み込みしました、E -ForegroundColor Green
}

function Install-RequiredTools {
    if (-not (Test-CommandAvailable "winget")) {
        throw "winget が見つかりません。Windows App Installer をインスト�Eルしてください、E
    }

    Write-Host "winget を確認しました、E -ForegroundColor Green

    if (-not (Test-CommandAvailable "git")) {
        Write-Host "Git をインスト�EルしてぁE��ぁE.." -ForegroundColor Yellow
        Invoke-RequiredCommand "winget" @("install", "--id", "Git.Git", "--exact", "--source", "winget")
        Write-Host "Git のインスト�Eルが完亁E��ました、E -ForegroundColor Green
    }
    else {
        Write-Host "Git はインスト�Eル済みです、E -ForegroundColor DarkGray
    }

    if (-not (Test-CommandAvailable "jj")) {
        Write-Host "Jujutsu (jj) をインスト�EルしてぁE��ぁE.." -ForegroundColor Yellow
        Invoke-RequiredCommand "winget" @("install", "--id", "jj-vcs.jj", "--exact", "--source", "winget")
        Write-Host "jj のインスト�Eルが完亁E��ました、E -ForegroundColor Green
    }
    else {
        Write-Host "jj はインスト�Eル済みです、E -ForegroundColor DarkGray
    }

    Update-ProcessPath
}

function Select-ProjectDirectory {
    $projectName = Read-Host "プロジェクトフォルダ吁E
    if ([string]::IsNullOrWhiteSpace($projectName)) {
        throw "プロジェクトフォルダ名が入力されてぁE��せん、E
    }

    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()
    if ($projectName.IndexOfAny($invalidCharacters) -ge 0 -or $projectName -in @('.', '..')) {
        throw "プロジェクトフォルダ名に使用できなぁE��字が含まれてぁE��す、E
    }

    $defaultParentDirectory = [Environment]::GetFolderPath("Desktop")
    $parentDirectory = Read-Host "プロジェクトを置く親フォルダのパス [$defaultParentDirectory]"
    if ([string]::IsNullOrWhiteSpace($parentDirectory)) {
        $parentDirectory = $defaultParentDirectory
    }
    $parentDirectory = $parentDirectory.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
        throw "親フォルダが見つかりません: $parentDirectory"
    }

    $projectDirectory = Join-Path (Resolve-Path -LiteralPath $parentDirectory).Path $projectName
    if (Test-Path $projectDirectory) {
        if (-not (Test-Path $projectDirectory -PathType Container)) {
            throw "同名のファイルが既に存在しまぁE $projectDirectory"
        }
        $hasRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".jj")
        $hasGitRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".git")
        $hasExistingFiles = @(Get-ChildItem -LiteralPath $projectDirectory -Force).Count -gt 0
        if ($hasExistingFiles -and -not ($hasRepository -or $hasGitRepository)) {
            throw "選択した場所に既存�EファイルがありまぁE $projectDirectory"
        }
    }

    return $projectDirectory
}

function Initialize-Repository {
    $projectDirectory = Select-ProjectDirectory

    New-Item -ItemType Directory -Path $projectDirectory -Force | Out-Null
    Set-Location $projectDirectory

    $userSettings = Read-UserSettings
    $repositoryUrl = Read-RepositorySettings -UserSettings $userSettings
    $sshSigningKey = Read-SshSigningSettings -UserEmail $userSettings.Email
    Save-Config `
        -UserName $userSettings.Name `
        -UserEmail $userSettings.Email `
        -RepositoryUrl $repositoryUrl `
        -SshSigningKey $sshSigningKey

    Invoke-RequiredCommand "jj" @("config", "set", "--user", "user.name", $userSettings.Name)
    Invoke-RequiredCommand "jj" @("config", "set", "--user", "user.email", $userSettings.Email)

    $hasRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".jj")
    $hasGitRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".git")
    if ($hasRepository -or $hasGitRepository) {
        Write-Host "既存�Eリポジトリを使用しまぁE.." -ForegroundColor Yellow
    }
    else {
        Write-Host "リポジトリを取得してぁE��ぁE.." -ForegroundColor Yellow
        Invoke-RequiredCommand "jj" @("git", "clone", $repositoryUrl, ".")
    }
    Save-ProjectDirectory -ProjectDirectory $projectDirectory
    explorer.exe $projectDirectory

    Write-Host "セチE��アチE�E允E $projectDirectory" -ForegroundColor Green
}

function Invoke-Setup {
    Write-Header
    $total = 3
    try {
        Write-StageProgress 1 $total "JC セチE��アチE�E" "忁E��なチE�Eルを確認してぁE��ぁE.."
        Install-RequiredTools

        Write-StageProgress 2 $total "JC セチE��アチE�E" "リポジトリ設定を準備してぁE��ぁE.."
        if (-not (Test-CommandAvailable "jj")) {
            throw "PATH 再読み込み後も jj が見つかりません。新しい PowerShell で再実行してください、E
        }

        Write-StageProgress 3 $total "JC セチE��アチE�E" "ユーザー設定とリポジトリを準備してぁE��ぁE.."
        Initialize-Repository
        
        Set-Content -LiteralPath $script:SetupMarkerPath -Value "completed" -Encoding utf8
        Write-Host "`nセチE��アチE�Eが完亁E��ました、E -ForegroundColor Green
        Write-Host ""
        Read-Host "Enter キーを押して続行してください..."
        return $true
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-Update {
    Write-Header
    try {
        Write-StageProgress 1 2 "JC 更新" "サーバ�Eから最新惁E��を取得してぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("git", "fetch")

        Write-StageProgress 2 2 "JC 更新" "最新の main に合わせてぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("rebase", "-d", "main@origin")
        
        Write-Host "`n更新が完亁E��ました。`n" -ForegroundColor Green
        Write-Host "現在の状慁E" -ForegroundColor Cyan
        & jj status
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "コンフリクトなどが発生してぁE��可能性があります。コンフリクトを解決してください、E -ForegroundColor Yellow
    }
}

function Get-Branches {
    $branchLines = @(& jj bookmark list)
    if ($LASTEXITCODE -ne 0) {
        throw "コマンドに失敗しました: jj bookmark list"
    }

    $branches = @()
    foreach ($line in $branchLines) {
        if ([string]$line -match '^\s*([^:\s]+)\s*:') {
            $branches += $Matches[1]
        }
    }

    return @($branches | Select-Object -Unique)
}

function Invoke-BranchSwitch {
    Write-Header
    try {
        $branches = @(Get-Branches)
        if ($branches.Count -eq 0) {
            Write-Host "刁E��替え可能なブランチがありません、E -ForegroundColor Yellow
            return
        }

        $itemCount = $branches.Count + 1
        $selected = 0
        while ($true) {
            Write-Header
            Write-Host "  刁E��替えるブランチを選択してください、E -ForegroundColor Cyan
            Write-Host "  上丁E選抁E Enter:決宁E Esc:キャンセル" -ForegroundColor DarkCyan
            Write-Host ""
            for ($index = 0; $index -lt $branches.Count; $index++) {
                if ($index -eq $selected) {
                    Write-Host "  > $($branches[$index])" -ForegroundColor White -BackgroundColor DarkGray
                }
                else {
                    Write-Host "    $($branches[$index])" -ForegroundColor Gray
                }
            }

            if ($selected -eq $branches.Count) {
                Write-Host "  > キャンセル" -ForegroundColor Yellow -BackgroundColor DarkGray
            }
            else {
                Write-Host "    キャンセル" -ForegroundColor Yellow
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" { $selected = ($selected - 1 + $itemCount) % $itemCount }
                "DownArrow" { $selected = ($selected + 1) % $itemCount }
                "Escape" { return }
                "Enter" { break }
            }
            if ($key.Key -eq "Enter") {
                break
            }
        }

        if ($selected -eq $branches.Count) {
            return
        }

        $branch = $branches[$selected]
        Write-Host ""
        Write-Host "選択したブランチE $branch" -ForegroundColor Cyan
        Write-Host "現在の作業変更をこのブランチ上�E新しい変更へ刁E��替えます、E -ForegroundColor Yellow
        
        if (Read-YesNo -Prompt "続行しますか�E�E -DefaultYes $False) {
            Write-Host "ブランチ�Eり替えをキャンセルしました、E -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "ブランチ�Eり替ぁE "$branch に刁E��替えてぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("new", $branch)
        
        Write-Host "`nブランチを刁E��替えました: $branch" -ForegroundColor Green
        Write-Host "新しい作業変更で作業を開始できます、E -ForegroundColor DarkGray
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-BranchCreate {
    Write-Header
    try {
        $branch = Read-Host "作�Eするブランチ名�E�空白でキャンセル�E�E
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "ブランチ作�Eをキャンセルしました、E -ForegroundColor Yellow
            return
        }
        if ($branch -notmatch '^[A-Za-z0-9._/-]+$') {
            throw "ブランチ名に使用できなぁE��字が含まれてぁE��す、E
        }

        Write-StageProgress 1 1 "ブランチ作�E" "$branch を作�EしてぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("bookmark", "create", $branch, "-r", "@")
        
        Write-Host "`nブランチを作�Eしました: $branch" -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-BranchDelete {
    Write-Header
    try {
        $branches = @(Get-Branches)
        if ($branches.Count -eq 0) {
            Write-Host "削除できるブランチがありません、E -ForegroundColor Yellow
            return
        }

        Write-Host "削除するブランチ名を�E力してください、E -ForegroundColor Cyan
        $branch = Read-Host "ブランチ名�E�空白でキャンセル�E�E
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "ブランチ削除をキャンセルしました、E -ForegroundColor Yellow
            return
        }
        if ($branches -notcontains $branch) {
            throw "持E��したブランチが見つかりません: $branch"
        }

        Write-Host "削除対象: $branch" -ForegroundColor Yellow
        if (Read-YesNo -Prompt "こ�Eブランチを削除しますか�E�E -DefaultYes $False) {
            Write-Host "ブランチ削除をキャンセルしました、E -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "ブランチ削除" "$branch を削除してぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("bookmark", "delete", $branch)
        
        Write-Host "`nブランチを削除しました: $branch" -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-BranchMerge {
    Write-Header
    try {
        $branches = @(Get-Branches)
        if ($branches.Count -lt 2) {
            Write-Host "マ�Eジには2つ以上�Eブランチが忁E��です、E -ForegroundColor Yellow
            return
        }

        Write-Host "マ�Eジ先（変更を取り込む側�E�を入力してください、E -ForegroundColor Cyan
        $target = Read-Host "マ�Eジ先ブランチ名�E�空白でキャンセル�E�E
        if ([string]::IsNullOrWhiteSpace($target)) {
            Write-Host "ブランチ�Eージをキャンセルしました、E -ForegroundColor Yellow
            return
        }
        if ($branches -notcontains $target) {
            throw "マ�Eジ先ブランチが見つかりません: $target"
        }

        Write-Host "マ�Eジ允E��取り込む側�E�を入力してください、E -ForegroundColor Cyan
        $source = Read-Host "マ�Eジ允E��ランチ名�E�空白でキャンセル�E�E
        if ([string]::IsNullOrWhiteSpace($source)) {
            Write-Host "ブランチ�Eージをキャンセルしました、E -ForegroundColor Yellow
            return
        }
        if ($branches -notcontains $source) {
            throw "マ�Eジ允E��ランチが見つかりません: $source"
        }
        if ($target -eq $source) {
            throw "マ�Eジ先とマ�Eジ允E��は別のブランチを持E��してください、E
        }

        Write-Host "$source めE$target にマ�Eジします、E -ForegroundColor Yellow
        if (Read-YesNo -Prompt "実行しますか�E�E -DefaultYes $False) {
            Write-Host "ブランチ�Eージをキャンセルしました、E -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 2 "ブランチ�Eージ" "マ�Eジ変更を作�EしてぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("new", $target, $source)
        Write-StageProgress 2 2 "ブランチ�Eージ" "$target を�Eージ結果へ更新してぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("bookmark", "set", $target, "-r", "@")
        
        Write-Host "`nブランチをマ�Eジしました: $source -> $target" -ForegroundColor Green
        Write-Host "忁E��に応じて「変更を保存」かめEpush してください、E -ForegroundColor DarkGray
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-BranchManagement {
    $items = @(
        @{ Label = "ブランチを刁E��替ぁE; Color = "Magenta"; Action = { Invoke-BranchSwitch } },
        @{ Label = "ブランチを作�E"; Color = "Green"; Action = { Invoke-BranchCreate } },
        @{ Label = "ブランチをマ�Eジ"; Color = "Blue"; Action = { Invoke-BranchMerge } },
        @{ Label = "ブランチを削除"; Color = "Red"; Action = { Invoke-BranchDelete } },
        @{ Label = "戻めE; Color = "Gray"; Action = { return } }
    )
    $selected = 0

    while ($true) {
        Write-Header
        Write-Host "  ブランチ操作を選択してください" -ForegroundColor White
        Write-Host ""
        for ($index = 0; $index -lt $items.Count; $index++) {
            if ($index -eq $selected) {
                Write-Host "  > $($items[$index].Label)" -ForegroundColor $items[$index].Color -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $($items[$index].Label)" -ForegroundColor $items[$index].Color
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $items.Count) % $items.Count }
            "DownArrow" { $selected = ($selected + 1) % $items.Count }
            "Escape" { return }
            "Enter" {
                if ($selected -eq ($items.Count - 1)) { return }
                & $items[$selected].Action
                Write-Host ""
                Read-Host "Enter でブランチ操作メニューに戻りまぁE
            }
        }
    }
}

function Invoke-Publish {
    Write-Header
    try {

        Invoke-Update

        Write-StageProgress 1 4 "JC 保孁E "変更を確認してぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("status")
        
        Write-Host ""
        $existingComment = @(& jj log -r "@" --no-graph -T "description") -join [Environment]::NewLine
        if ($LASTEXITCODE -ne 0) {
            throw "コマンドに失敗しました: jj log -r @ --no-graph -T description"
        }
        $existingComment = $existingComment.Trim()

        if (-not [string]::IsNullOrWhiteSpace($existingComment)) {
            Write-Host "現在のコメンチE" -ForegroundColor Cyan
            Write-Host $existingComment -ForegroundColor DarkGray

            if ( Read-YesNo -Prompt "こ�Eコメントを利用しますか�E�E -DefaultYes $true) {
                $comment = $existingComment
            }
            else {
                Write-Host "変更を保存するにはコメントが忁E��です。（空白でキャンセル�E�E -ForegroundColor Cyan
                $comment = Read-Host "変更コメンチE
            }
        }
        else {
            Write-Host "変更を保存するにはコメントが忁E��です。（空白でキャンセル�E�E -ForegroundColor Cyan
            $comment = Read-Host "変更コメンチE
        }

        if ([string]::IsNullOrWhiteSpace($comment)) {
            
            Write-Host "`n保存をキャンセルしました、E -ForegroundColor Yellow
            return
        }

        Write-StageProgress 2 4 "JC 保孁E "変更にコメントを設定してぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("desc", "-m", $comment)

        Write-StageProgress 3 4 "JC 保孁E "main を更新してぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("bookmark", "set", "main", "-r", "@")

        Write-StageProgress 4 4 "JC 保孁E "サーバ�EへアチE�EロードしてぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("git", "push")
        
        Write-Host "`nアチE�Eロードが完亁E��ました、E -ForegroundColor Green
        Write-Host "コメンチE $comment" -ForegroundColor DarkGray
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-NewChange {
    Write-Header
    try {
        Write-Host "新しい変更のコメントを入力してください。（空白でキャンセル�E�E -ForegroundColor Cyan
        $comment = Read-Host "変更コメンチE
        if ([string]::IsNullOrWhiteSpace($comment)) {
            
            Write-Host "`n変更をキャンセルしました、E -ForegroundColor Yellow
            return
        }
        Write-StageProgress 1 1 "JC 区刁E��" "新しい変更を作�EしてぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("new", "-m", $comment)
        
        Write-Host "`n新しい変更を作�Eしました、E -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ChangeDescriptionMenu {
    $items = @(
        @{ Label = "新しい変更で区刁E��"; Color = "DarkCyan"; Action = { Invoke-NewChange } },
        @{ Label = "既存�E変更にコメントを付けめE; Color = "White"; Action = { Invoke-AddDescription } },
        @{ Label = "変更履歴を閲覧"; Color = "DarkCyan"; Action = { Invoke-ViewHistory } },
        @{ Label = "戻めE; Color = "Gray"; Action = { return } }
    )
    $selected = 0

    while ($true) {
        Write-Header
        Write-Host "  変更の区刁E��・コメント設宁E -ForegroundColor White
        Write-Host ""
        for ($index = 0; $index -lt $items.Count; $index++) {
            if ($index -eq $selected) {
                Write-Host "  > $($items[$index].Label)" -ForegroundColor $items[$index].Color -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $($items[$index].Label)" -ForegroundColor $items[$index].Color
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $items.Count) % $items.Count }
            "DownArrow" { $selected = ($selected + 1) % $items.Count }
            "Escape" { return }
            "Enter" {
                if ($selected -eq ($items.Count - 1)) { return }
                & $items[$selected].Action
                Write-Host ""
                Read-Host "Enter でメニューに戻りまぁE
            }
        }
    }
}

function Invoke-AddDescription {
    Write-Header
    try {
        while ($true) {
            $logLines = @(& jj log -r "mutable() ~ root()" --no-graph -T 'change_id ++ "\t" ++ committer.timestamp() ++ "\t" ++ description.first_line() ++ "\n"')
            if ($LASTEXITCODE -ne 0) {
                throw "コマンドに失敗しました: jj log -r mutable() ~ root()"
            }

            $candidates = @()
            foreach ($line in $logLines) {
                $parts = $line -split "`t", 3
                if ($parts.Count -eq 3) {
                    $description = $parts[2].Trim()
                    if ([string]::IsNullOrWhiteSpace($description)) {
                        $description = "(コメントなぁE"
                    }
                    $candidates += [PSCustomObject]@{
                        ChangeId    = $parts[0].Trim()
                        Timestamp   = $parts[1].Trim()
                        Description = $description
                    }
                }
            }

            if ($candidates.Count -eq 0) {
                Write-Host "コメントを設定�E変更できる未pushの変更はありません、E -ForegroundColor Green
                return
            }

            $selectedIndex = 0
            while ($true) {
                Write-Header
                Write-Host "  コメントを設定�E変更する変更を選択してください、E -ForegroundColor Cyan
                Write-Host "  上丁E選抁E Enter:決宁E Esc:キャンセル" -ForegroundColor DarkCyan
                Write-Host ""
                for ($index = 0; $index -lt $candidates.Count; $index++) {
                    $line = "$($candidates[$index].ChangeId)  $($candidates[$index].Timestamp)  $($candidates[$index].Description)"

                    if ($index -eq $selectedIndex) {
                        Write-Host "  > $line" -ForegroundColor White -BackgroundColor DarkGray
                    }
                    else {
                        Write-Host "    $line" -ForegroundColor Gray
                    }
                }

                if ($selectedIndex -eq $candidates.Count) {
                    Write-Host "  > キャンセル" -ForegroundColor Yellow -BackgroundColor DarkGray
                }
                else {
                    Write-Host "    キャンセル" -ForegroundColor Yellow
                }

                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    "UpArrow" { $selectedIndex = ($selectedIndex - 1 + $candidates.Count + 1) % ($candidates.Count + 1) }
                    "DownArrow" { $selectedIndex = ($selectedIndex + 1) % ($candidates.Count + 1) }
                    "Escape" { return }
                    "Enter" { if ($selectedIndex -eq $candidates.Count) { return } break }
                }
                if ($key.Key -eq "Enter") {
                    break
                }
            }

            $comment = Read-Host "変更コメント（上書き可・空白でキャンセル�E�E
            if ([string]::IsNullOrWhiteSpace($comment)) {
                Write-Host "コメントが空のためキャンセルしました、E -ForegroundColor Yellow
                return
            }

            Write-StageProgress 1 1 "コメント設宁E "変更コメントを設定してぁE��ぁE.."
            Invoke-RequiredCommand "jj" @("desc", "-r", $candidates[$selectedIndex].ChangeId, "-m", $comment)
            
            Write-Host "`nコメントを設定しました、E -ForegroundColor Green
            Write-Host "続けて別の変更にもコメントを設定できます、E -ForegroundColor DarkCyan
        }
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Undo {
    Write-Header
    try {
        Write-Host "直前�E操作を取り消します、E -ForegroundColor Yellow
        
        if (Read-YesNo -Prompt "取り消しますか�E�E -DefaultYes $False) {
            Write-Host "取り消しをキャンセルしました、E -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "JC Undo" "直前�E操作を取り消してぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("undo")
        
        Write-Host "`n直前�E操作を取り消しました、E -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-ConflictFiles {
    $conflictLines = @(& jj resolve --list 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $errorText = ($conflictLines | ForEach-Object { [string] $_ }) -join [Environment]::NewLine
        if ($errorText -match "(?i)No conflicts found at this revision") {
            return @()
        }
        throw "コマンドに失敗しました: jj resolve --list"
    }

    $conflictFiles = @()
    foreach ($line in $conflictLines) {
        $path = ([string] $line).Trim()
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $conflictFiles += [PSCustomObject]@{
                Status = "C"
                Path   = $path
            }
        }
    }
    return $conflictFiles
}

function Invoke-ResolveConflicts {
    try {
        $conflictFiles = @(Get-ConflictFiles)
        if ($conflictFiles.Count -eq 0) {
            Write-Header
            Write-Host "  コンフリクトがありません、E -ForegroundColor Green
            return
        }

        $selected = 0
        while ($true) {
            Write-Header
            Write-Host "  解決するコンフリクトを選択してください、E -ForegroundColor Cyan
            Write-Host "  上丁E選抁E Enter:決宁E Esc:キャンセル" -ForegroundColor DarkCyan
            Write-Host ""
            for ($index = 0; $index -lt $conflictFiles.Count; $index++) {
                $line = "[C] $($conflictFiles[$index].Path)"
                if ($index -eq $selected) {
                    Write-Host "  > $line" -ForegroundColor Red -BackgroundColor DarkGray
                }
                else {
                    Write-Host "    $line" -ForegroundColor Red
                }
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" { $selected = ($selected - 1 + $conflictFiles.Count) % $conflictFiles.Count }
                "DownArrow" { $selected = ($selected + 1) % $conflictFiles.Count }
                "Escape" { return }
                "Enter" { break }
            }
            if ($key.Key -eq "Enter") {
                break
            }
        }

        $conflictPath = $conflictFiles[$selected].Path
        Write-Host ""
        Write-Host "対象: $conflictPath" -ForegroundColor Cyan
        Write-Host "  L: ローカルを優允E
        Write-Host "  R: リモートを優允E
        Write-Host "  C: キャンセル"
        $decision = Read-Host "解決方況E
        if ($decision -match '^(?i)l(ocal)?$') {
            $tool = ":ours"
            $side = "ローカル"
        }
        elseif ($decision -match '^(?i)r(emote)?$') {
            $tool = ":theirs"
            $side = "リモーチE
        }
        else {
            Write-Host "コンフリクト解決をキャンセルしました、E -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "コンフリクト解決" "$side を優先してぁE��ぁE.."
        Invoke-RequiredCommand "jj" @("resolve", "--tool", $tool, "--", $conflictPath)
        
        Write-Host "`nコンフリクトを解決しました: $conflictPath" -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ReviewChanges {
    $changedFiles = @()
    try {
        Write-StageProgress 1 2 "変更を確誁E "変更状態を確認してぁE��ぁE.."
        $statusOutput = @(& jj status)
        if ($LASTEXITCODE -ne 0) {
            throw "コマンドに失敗しました: jj status"
        }

        foreach ($line in $statusOutput) {
            if ($line -match '^\s*([MADRC?])\s+(.+?)\s*$') {
                $changedFiles += [PSCustomObject]@{
                    Status = $Matches[1]
                    Path   = $Matches[2]
                }
            }
        }

        
        if ($changedFiles.Count -eq 0) {
            Write-Header
            Write-Host "  変更されたファイルはありません、E -ForegroundColor Green
            return
        }

        Read-ChangedFileChoice -ChangedFiles $changedFiles
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ViewHistory {
    Write-Header
    try {
        Write-Host "  変更履歴�E�最迁E0件�E�E -ForegroundColor Cyan
        Write-Host ""
        & jj log -r "all()" -n 10 --no-pager
        if ($LASTEXITCODE -ne 0) {
            throw "コマンドに失敗しました: jj log -r all() --no-pager"
        }
    }
    catch {
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

function Get-StatusColor {
    param([Parameter(Mandatory)] [string] $Status)

    switch ($Status) {
        "M" { return "Yellow" }
        "A" { return "Green" }
        "D" { return "Red" }
        "R" { return "Cyan" }
        default { return "Gray" }
    }
}

function Read-ChangedFileChoice {
    param([Parameter(Mandatory)] [array] $ChangedFiles)

    $selected = 0
    while ($true) {
        Write-Header
        Write-Host "  変更されたファイル" -ForegroundColor White
        Write-Host "  M:変更  A:追加  D:削除  R:名前変更" -ForegroundColor DarkGray
        Write-Host ""

        for ($index = 0; $index -lt $ChangedFiles.Count; $index++) {
            $file = $ChangedFiles[$index]
            $color = Get-StatusColor -Status $file.Status
            $line = "[$($file.Status)] $($file.Path)"
            if ($index -eq $selected) {
                Write-Host "  > $line" -ForegroundColor $color -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $line" -ForegroundColor $color
            }
        }

        Write-Host ""
        Write-Host "  Enter:差刁E��表示  Esc:戻めE -ForegroundColor DarkCyan
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $ChangedFiles.Count) % $ChangedFiles.Count }
            "DownArrow" { $selected = ($selected + 1) % $ChangedFiles.Count }
            "Escape" { return }
            "Enter" {
                Show-FileDiff -Path $ChangedFiles[$selected].Path
            }
        }
    }
}

function Show-FileDiff {
    param([Parameter(Mandatory)] [string] $Path)

    Write-Header
    Write-Host "  [$Path]" -ForegroundColor Cyan
    Write-Host ""
    & jj diff -- $Path
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n差刁E�E表示に失敗しました、E -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Enter でファイル一覧に戻りまぁE
}

function Read-MenuChoice {
    $items = @(
        @{ Label = "最新の惁E��を取征E; Color = "Blue"; Action = { Invoke-Update } },
        @{ Label = "変更を保孁E; Color = "Green"; Action = { Invoke-Publish } },
        @{ Label = "変更を確誁E; Color = "Cyan"; Action = { Invoke-ReviewChanges } },
        @{ Label = "変更を区刁E�� / コメントを付け / 変更履歴"; Color = "DarkCyan"; Action = { Invoke-ChangeDescriptionMenu } },
        @{ Label = "ブランチ操作（�Eり替ぁE/ 作�E / マ�Eジ / 削除�E�E; Color = "Magenta"; Action = { Invoke-BranchManagement } },
        @{ Label = "直前�E操作を取り消す"; Color = "Yellow"; Action = { Invoke-Undo } },
        @{ Label = "コンフリクトを解決"; Color = "Red"; Action = { Invoke-ResolveConflicts } },
        @{ Label = "保存済み設定を変更"; Color = "Yellow"; Action = { Invoke-ConfigChange } },
        @{ Label = "終亁E; Color = "Gray"; Action = { return } }
    )
    $selected = 0

    while ($true) {
        Write-Header
        Write-Host "  操作を選択してください" -ForegroundColor White
        Write-Host ""
        for ($index = 0; $index -lt $items.Count; $index++) {
            if ($index -eq $selected) {
                Write-Host "  > $($items[$index].Label)" -ForegroundColor $items[$index].Color -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $($items[$index].Label)" -ForegroundColor $items[$index].Color
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $items.Count) % $items.Count }
            "DownArrow" { $selected = ($selected + 1) % $items.Count }
            "Enter" {
                if ($selected -eq ($items.Count - 1)) { return }
                & $items[$selected].Action
                Write-Host ""
                Read-Host "Enter でメニューに戻りまぁE
            }
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $script:SetupMarkerPath)) {
        if (-not (Invoke-Setup)) {
            exit 1
        }

        Invoke-Update

        Write-Host ""
        Read-Host "Enter でメニューに進みまぁE
    }
    else {
        try {
            Set-ProjectLocation
        }
        catch {
            Write-Host "`n保存済みプロジェクトを利用できません: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "セチE��アチE�E惁E��を削除して、セチE��アチE�Eをやり直します、E -ForegroundColor Yellow

            Remove-Item -LiteralPath $script:SetupMarkerPath -Force

            if (-not (Invoke-Setup)) {
                exit 1
            }

            Write-Host ""
            Read-Host "Enter でメニューに進みまぁE
        }
    }

    # JujutsuControllerの更新確誁E
    Test-Update

    Read-MenuChoice
}
catch {
    Write-Host "`n致命皁E��エラー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}