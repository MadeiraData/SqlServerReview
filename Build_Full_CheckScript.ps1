Param
(
 [string]$OutputScriptFilePath = "Full_Check_Script.sql"
,[string]$TemplateHeaderFilePath = "Template/Template_Header.sql"
,[string]$TemplateFooterFilePath = "Template/Template_Footer.sql"
,[string]$CheckTemplateHeaderFilePath = "Template/Check_Header.sql"
,[string]$CheckTemplateFooterFilePath = "Template/Check_Footer.sql"
,[string]$CheckScriptsFolderPath = "SQLChecks\*"
,[string]$CheckScriptsFilter = "*.sql"
)
cls
Set-ExecutionPolicy bypass -Scope Process -force

# Execute SQL_Server_Build_Check_Script_Creation.ps1 and wait for it to finish
Write-Host "Execute SQL_Server_Build_Check_Script_Creation.ps1 and wait for it to finish"
& .\SQL_Server_Build_Check_Script_Creation.ps1
Start-Sleep -Seconds 2
Write-Host "SQL_Server_Build_Check_Script_Creation script has finished
"

# Execute SQL_Server_Major_Version_Out_of_Support_Script_Creation.ps1 and wait for it to finish
Write-Host "Execute SQL_Server_Major_Version_Out_of_Support_Script_Creation.ps1 and wait for it to finish"
& .\SQL_Server_Major_Version_Out_of_Support_Script_Creation.ps1
Start-Sleep -Seconds 2
Write-Host "SQL_Server_Major_Version_Out_of_Support_Script_Creation.ps1
"

$batchSeparator = "`r`nGO`r`n"
$OutputScriptBuilder = [string](Get-Content -Path $TemplateHeaderFilePath -Raw)

$CheckHeaderTemplate = [string](Get-Content -Path $CheckTemplateHeaderFilePath -Raw)
$CheckFooterTemplate = [string](Get-Content -Path $CheckTemplateFooterFilePath -Raw)

[int]$CheckId = 0

Get-ChildItem -Path $CheckScriptsFolderPath -Include $CheckScriptsFilter | ForEach-Object {
    $CheckId += 1
    $CheckTitle = $($_.BaseName)
    Write-Output "Check $CheckId : $CheckTitle"

    $OutputScriptBuilder += $batchSeparator
    $OutputScriptBuilder += $CheckHeaderTemplate.Replace('{CheckId}', $CheckId).Replace('{CheckTitle}', $CheckTitle)
    $OutputScriptBuilder += [string](Get-Content -Path $_.FullName -Raw).Replace('{CheckId}', $CheckId).Replace('{CheckTitle}', $CheckTitle)
    $OutputScriptBuilder += $CheckFooterTemplate.Replace('{CheckId}', $CheckId).Replace('{CheckTitle}', $CheckTitle)
}

Write-Output "Finalizing output script: $OutputScriptFilePath"

$OutputScriptBuilder += $batchSeparator
$OutputScriptBuilder += [string](Get-Content -Path $TemplateFooterFilePath -Raw)

$OutputScriptBuilder | Out-File $OutputScriptFilePath -Force
