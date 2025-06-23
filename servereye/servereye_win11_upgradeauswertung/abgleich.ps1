# Hole das aktuelle Verzeichnis
$folder = Get-Location

# Suche nach .csv-Dateien
$csvFiles = Get-ChildItem -Path $folder -Filter *.csv
if ($csvFiles.Count -ne 1) {
    Write-Host "Es muss genau eine CSV-Datei im Verzeichnis sein." -ForegroundColor Red
    exit 1
}
$csvPath = $csvFiles[0].FullName
Write-Host "CSV-Datei gefunden: $($csvFiles[0].Name)"

# Suche nach .xlsx-Dateien
$xlsxFiles = Get-ChildItem -Path $folder -Filter *.xlsx
if ($xlsxFiles.Count -ne 1) {
    Write-Host "Es muss genau eine Excel-Datei (.xlsx) im Verzeichnis sein." -ForegroundColor Red
    exit 1
}
$xlsxPath = $xlsxFiles[0].FullName
Write-Host "Excel-Datei gefunden: $($xlsxFiles[0].Name)"

# CSV einlesen (Spalte A, ab Zeile 2)
$csvRaw = Get-Content -Path $csvPath | Select-Object -Skip 1
$csvNames = $csvRaw | ForEach-Object {
    ($_.Split(',')[0]).Trim().Trim('"')  # ← Entfernt führende & nachgestellte "
} | Where-Object { $_ -ne "" } | Sort-Object -Unique


# Excel öffnen
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$workbook = $excel.Workbooks.Open($xlsxPath)
$worksheet = $workbook.Worksheets.Item(1)

# Excel-Spalte A einlesen (ab Zeile 2)
$row = 2
$xlsxNames = @()
while ($true) {
    $cellValue = $worksheet.Cells.Item($row, 1).Text
    if ([string]::IsNullOrWhiteSpace($cellValue)) { break }
    $xlsxNames += $cellValue.Trim()
    $row++
}

# Excel schließen
$workbook.Close($false)
$excel.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($worksheet) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

# Vergleich
$nurInCsv = $csvNames | Where-Object { $_ -notin $xlsxNames }
$nurInXlsx = $xlsxNames | Where-Object { $_ -notin $csvNames }
$inBeiden = $csvNames | Where-Object { $_ -in $xlsxNames }

# Ergebnis vorbereiten
$result = @()

$inBeiden | ForEach-Object {
    $result += [PSCustomObject]@{ Name = $_; Quelle = "Beide" }
}
$nurInCsv | ForEach-Object {
    $result += [PSCustomObject]@{ Name = $_; Quelle = "Nur in CSV" }
}
$nurInXlsx | ForEach-Object {
    $result += [PSCustomObject]@{ Name = $_; Quelle = "Nur in Excel" }
}

# Ergebnis speichern
$outFile = Join-Path $folder "vergleich_ergebnis.csv"
$result | Sort-Object Name | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

Write-Host "`n Vergleich abgeschlossen. Ergebnis gespeichert in: $outFile" -ForegroundColor Green
