<#
.SYNOPSIS
Presents a GUI menu to select and run PowerShell (.ps1) or Batch (.bat) scripts
from the same directory with Administrator privileges. Displays the current folder path.
Allows engine selection (powershell.exe vs pwsh.exe) for .ps1 files.
The menu remains open after launching a script.

.DESCRIPTION
This script must be run as Administrator. It finds all .ps1 and .bat files in its
own directory (excluding itself), displays the folder path at the top, and lists the
scripts below.
- For .ps1 files, the user can choose to run with Windows PowerShell (powershell.exe)
  or PowerShell Core (pwsh.exe, if available).
- For .bat files, they are run using the command prompt (cmd.exe).
Selecting a script and clicking 'Run Selected' will execute that script using the
appropriate engine via Start-Process -Verb RunAs.
The selection window stays open until explicitly closed.

.NOTES
Author: Gemini AI
Date:   2025-05-01 (Updated)
Requires: PowerShell 3.0 or higher, .NET Framework (usually included with Windows)
          Must be run with Administrator privileges.
          Checks for pwsh.exe in PATH for PowerShell Core option.
#>

#Requires -RunAsAdministrator # Ensures script exits if not run as admin (PSv4+)

# --- Configuration ---
$windowTitle = "Admin Script Launcher (.ps1 / .bat)"
# Label instruction is now slightly less important as path is shown above
$labelInstruction = "Select script below to run as Administrator:"

# --- Pre-Checks ---

# Verify running as Administrator
$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run with Administrator privileges. Please right-click and 'Run as administrator'."
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("This script must be run with Administrator privileges.`nPlease right-click the script and select 'Run as administrator'.", "Admin Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop)
    Exit 1
}

# Check if pwsh.exe (PowerShell Core/7+) is available
$pwshExists = $null -ne (Get-Command pwsh.exe -ErrorAction SilentlyContinue)
Write-Verbose "pwsh.exe found: $pwshExists"

# --- Core Logic ---

# Get the directory where this script resides
if ($PSVersionTable.PSVersion.Major -ge 3) {
    $scriptPath = $PSScriptRoot
} else {
    # Fallback for PSv2
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
Write-Verbose "Script execution path identified as: $scriptPath"

# Find other PowerShell (.ps1) and Batch (.bat) scripts in the same directory
try {
    Write-Verbose "Searching for *.ps1, *.bat files in '$scriptPath', excluding '$($MyInvocation.MyCommand.Name)'"
    $allScripts = Get-ChildItem -Path $scriptPath -ErrorAction Stop | Where-Object { ($_.Extension -eq '.ps1' -or $_.Extension -eq '.bat') -and $_.Name -ne $MyInvocation.MyCommand.Name }
    Write-Verbose "Found $($allScripts.Count) other script(s)."
}
catch {
    Write-Error "Error finding scripts in '$scriptPath': $($_.Exception.Message)"
    Add-Type -AssemblyName System.Windows.Forms # Ensure loaded for error box
    [System.Windows.Forms.MessageBox]::Show("Error finding scripts in '$scriptPath':`n$($_.Exception.Message)", "File Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Exit 1
}

# Check if any other scripts were found
if ($allScripts.Count -eq 0) {
    Add-Type -AssemblyName System.Windows.Forms # Ensure loaded for info box
    [System.Windows.Forms.MessageBox]::Show("No other PowerShell (.ps1) or Batch (.bat) scripts found in this directory:`n$scriptPath", $windowTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Exit
}

# Extract just the names for the list box
$scriptNames = $allScripts | Select-Object -ExpandProperty Name

# --- Build GUI ---

# Load necessary .NET assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = $windowTitle
$form.Size = New-Object System.Drawing.Size(450, 440) # Slightly increased height for path box
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false

# --- NEW: Create Textbox for Folder Path ---
$folderPathTextBox = New-Object System.Windows.Forms.TextBox
$folderPathTextBox.Location = New-Object System.Drawing.Point(10, 10)
$folderPathTextBox.Size = New-Object System.Drawing.Size(410, 20)
$folderPathTextBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$folderPathTextBox.ReadOnly = $true
$folderPathTextBox.Text = $scriptPath # Display the path
$form.Controls.Add($folderPathTextBox)

# Create instruction label (position adjusted down)
$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(10, 35) # MOVED DOWN
$label.Size = New-Object System.Drawing.Size(410, 20)
$label.Text = $labelInstruction
$form.Controls.Add($label)

# Create a list box (position adjusted down)
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(10, 60) # MOVED DOWN
$listBox.Size = New-Object System.Drawing.Size(410, 190) # Adjusted height slightly
$listBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$listBox.Items.AddRange($scriptNames)
$form.Controls.Add($listBox)

# Create GroupBox for engine selection (Position relative to ListBox)
$groupBox = New-Object System.Windows.Forms.GroupBox
$groupBox.Location = New-Object System.Drawing.Point(10, 260) # MOVED DOWN (below listbox)
$groupBox.Size = New-Object System.Drawing.Size(410, 75)
$groupBox.Text = "Run PowerShell with Engine:"
$groupBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$groupBox.Enabled = $false # START DISABLED
$form.Controls.Add($groupBox)

# Create Radio button for Windows PowerShell
$radioPowerShell = New-Object System.Windows.Forms.RadioButton
$radioPowerShell.Location = New-Object System.Drawing.Point(15, 25)
$radioPowerShell.Size = New-Object System.Drawing.Size(380, 20)
$radioPowerShell.Text = "Windows PowerShell (powershell.exe)"
$radioPowerShell.Checked = $true
$radioPowerShell.TabIndex = 0
$groupBox.Controls.Add($radioPowerShell)

# Create Radio button for PowerShell Core/7+
$radioPwsh = New-Object System.Windows.Forms.RadioButton
$radioPwsh.Location = New-Object System.Drawing.Point(15, 45)
$radioPwsh.Size = New-Object System.Drawing.Size(380, 20)
$radioPwsh.Text = "PowerShell Core (pwsh.exe)"
$radioPwsh.Checked = $false
$radioPwsh.TabIndex = 1
if (-not $pwshExists) {
    $radioPwsh.Text += "  (Not Found in PATH)"
}
$groupBox.Controls.Add($radioPwsh)

# --- Add event handler for ListBox selection change ---
$listBox.Add_SelectedIndexChanged({
    if ($listBox.SelectedItem -ne $null) {
        $selectedName = $listBox.SelectedItem.ToString()
        $extension = [System.IO.Path]::GetExtension($selectedName).ToLower()
        if ($extension -eq '.ps1') {
            $groupBox.Enabled = $true
            $radioPwsh.Enabled = $pwshExists
        } else {
            $groupBox.Enabled = $false
        }
    } else {
        $groupBox.Enabled = $false
    }
})

# Create the 'Run Selected' button (Position relative to GroupBox)
$runButton = New-Object System.Windows.Forms.Button
$runButton.Location = New-Object System.Drawing.Point(160, 350) # MOVED DOWN
$runButton.Size = New-Object System.Drawing.Size(100, 30)
$runButton.Text = "Run Selected"
$runButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom
$form.Controls.Add($runButton)

# Add event handler for the 'Run Selected' button click
$runButton.Add_Click({
    if ($listBox.SelectedItem -ne $null) {
        $selectedScriptName = $listBox.SelectedItem.ToString()
        $selectedScriptFullPath = Join-Path -Path $scriptPath -ChildPath $selectedScriptName
        $extension = [System.IO.Path]::GetExtension($selectedScriptName).ToLower()

        # --- Execute based on file type ---
        if ($extension -eq '.ps1') {
            # --- PowerShell Execution ---
            if (-not $groupBox.Enabled) {
                 [System.Windows.Forms.MessageBox]::Show("Please re-select the .ps1 script to ensure engine options are enabled.", "State Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                 return
            }
            $selectedExecutable = "powershell.exe"
            if ($radioPwsh.Checked) {
                if ($pwshExists) {
                    $selectedExecutable = "pwsh.exe"
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Cannot run with pwsh.exe as it was not found or is not enabled.", "Engine Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
            }
            Write-Host "Attempting to launch PS script '$selectedScriptFullPath' as Admin using '$selectedExecutable'..."
            try {
                Start-Process -FilePath $selectedExecutable -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$selectedScriptFullPath`"" -Verb RunAs -ErrorAction Stop
                Write-Host "'$selectedScriptName' launched successfully using '$selectedExecutable'. Launcher window remains open."
            } catch {
                $errorMessage = "Failed to launch '$selectedScriptName' using '$selectedExecutable'. Error: $($_.Exception.Message)"
                Write-Error $errorMessage
                [System.Windows.Forms.MessageBox]::Show($errorMessage, "Launch Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }

        } elseif ($extension -eq '.bat') {
            # --- Batch Execution ---
            Write-Host "Attempting to launch Batch script '$selectedScriptFullPath' as Admin using 'cmd.exe'..."
            try {
                Start-Process -FilePath "cmd.exe" -ArgumentList "/S /K `"$selectedScriptFullPath`"" -Verb RunAs -ErrorAction Stop
                Write-Host "'$selectedScriptName' launched successfully using 'cmd.exe'. Launcher window remains open."
            } catch {
                $errorMessage = "Failed to launch '$selectedScriptName' using 'cmd.exe'. Error: $($_.Exception.Message)"
                Write-Error $errorMessage
                [System.Windows.Forms.MessageBox]::Show($errorMessage, "Launch Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }

        } else {
             [System.Windows.Forms.MessageBox]::Show("Unsupported file type selected: '$selectedScriptName'", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }

    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select a script from the list first.", "No Selection", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

# Create the 'Close' button (Position relative to GroupBox)
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(270, 350) # MOVED DOWN
$cancelButton.Size = New-Object System.Drawing.Size(100, 30)
$cancelButton.Text = "Close"
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$cancelButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

# Add event handler for the 'Close' button click
$cancelButton.Add_Click({
    Write-Host "Close button clicked. Closing launcher."
    $form.Close()
})

# --- Display the Form ---
$form.TopMost = $true
$form.Add_Shown({$form.Activate()})
Write-Host "Displaying script selection window..."
[void]$form.ShowDialog()

# --- Cleanup ---
Write-Host "Script Launcher window closed."
$form.Dispose()
Write-Host "Script Launcher finished."