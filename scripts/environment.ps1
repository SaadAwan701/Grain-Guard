$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root '.tooling'
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PUB_CACHE = Join-Path $tools 'pub-cache'
$env:GRADLE_USER_HOME = Join-Path $tools 'gradle'
$env:FIREBASE_EMULATORS_PATH = Join-Path $tools 'firebase-emulators'
$env:TEMP = Join-Path $tools 'tmp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force $env:TEMP | Out-Null
$env:Path = "$tools\flutter\bin;$env:PUB_CACHE\bin;$env:ANDROID_HOME\platform-tools;$env:JAVA_HOME\bin;$env:Path"
