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

$batchSeparator = "`r`nGO`r`n"
$OutputScriptBuilder = [string](Get-Content -Path $TemplateHeaderFilePath -Raw)

$CheckHeaderTemplate = [string](Get-Content -Path $CheckTemplateHeaderFilePath -Raw)
$CheckFooterTemplate = [string](Get-Content -Path $CheckTemplateFooterFilePath -Raw)

[int]$CheckId = 0

Get-ChildItem -Path $CheckScriptsFolderPath -Include $CheckScriptsFilter | ForEach-Object {
    $CheckId += 1
    Write-Output "Check $CheckId : $($_.BaseName)"

    $OutputScriptBuilder += $batchSeparator
    $OutputScriptBuilder += $CheckHeaderTemplate.Replace('{CheckId}', $CheckId)
    $OutputScriptBuilder += [string](Get-Content -Path $_.FullName -Raw).Replace('{CheckId}', $CheckId)
    $OutputScriptBuilder += $CheckFooterTemplate.Replace('{CheckId}', $CheckId)
}

Write-Output "Finalizing output script: $OutputScriptFilePath"

$OutputScriptBuilder += $batchSeparator
$OutputScriptBuilder += [string](Get-Content -Path $TemplateFooterFilePath -Raw)

$OutputScriptBuilder | Out-File $OutputScriptFilePath -Force
