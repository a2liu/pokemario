Set-ExecutionPolicy AllSigned

iex ((New-Object System.Net.WebClient).DownloadString("https://chocolatey.org/install.ps1"))

choco install git.install --params "/GitAndUnixToolsOnPath /WindowsTerminal" -y
choco install ripgrep fd -y

# New-Item -ItemType SymbolicLink -Path ".\.gitconfig" -Target ".\code\config\programs\neovim"
# New-Item -ItemType SymbolicLink -Path ".\AppData\Local\nvim" -Target ".\code\config\programs\neovim"

# Install Windows Subsystem for Linux
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux

# Install Ubuntu
# Invoke-RestMethod -Uri "https://aka.ms/wsl-debian-gnulinux" -OutFile "~/Ubuntu.zip" -UseBasicParsing

# Making Windows Terminal behave correctly
rm "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\profiles.json"

# Use mklink in command prompt to make a hard link to the correct place


