# TL;DR
    
    Install-Module ServerEye.Powershell.Helper, ImportExcel -Scope CurrentUser

Für alle Kunden:
    
    .\servereye_win11_upgradeauswertung.ps1 -ApiKey "<DEIN_API_KEY>"

Für einen speziellen Kunden:

    .\servereye_win11_upgradeauswertung.ps1 -ApiKey "<DEIN_API_KEY>" -CustomerID "<CID>"

---

# ServerEye Windows 11 Upgradeauswertung

Dieses PowerShell-Skript dient der systematischen Auswertung von Sensorhubs eines ServerEye-Kunden im Hinblick auf ihre Windows 11-Kompatibilität. Es aggregiert die folgenden Informationen in einer Excel-Datei pro Kunde:

- Hostname & Gerätetyp
- Windows 11 Status (kompatibel / inkompatibel)
- CPU-Modell
- Gesamter Arbeitsspeicher (MB)
- Gesamtspeicher (MB)
- Informationen zu installierten Office-Produkten
- Weitere nützliche Systeminfos wie OS, VM-Status, letzter Reboot-Benutzer etc.

Die Ergebnisse werden kompakt im Excel-Format unter dem Unterordner `.\inventory\` gespeichert, getrennt nach Kundenname.

## Voraussetzungen

Dieses Skript benötigt folgende PowerShell-Module:

- ServerEye.Powershell.Helper
- ImportExcel

Installieren mit:

    Install-Module ServerEye.Powershell.Helper, ImportExcel -Scope CurrentUser

## Ausführung

    .\servereye_win11_upgradeauswertung.ps1 -ApiKey "<DEIN_API_KEY>"

Die Auswertung erfolgt automatisch für alle dir zugewiesenen Kunden. Standardmäßig wird die Excel-Ausgabe im aktuellen Verzeichnis gespeichert.

---

## Code-Signing (optional, empfohlen)

Du kannst das Skript mit einem selbstsignierten Zertifikat signieren, z. B. zur Nutzung auf Systemen mit aktiviertem Execution Policy Enforcement (nicht vergessen den Pfad anzupassen!):

    New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Matze" -CertStoreLocation "cert:\CurrentUser\My"

    $cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -eq "CN=Matze" }
    Export-Certificate -Cert $cert -FilePath "$env:TEMP\codesign.cer"
    Import-Certificate -FilePath "$env:TEMP\codesign.cer" -CertStoreLocation Cert:\CurrentUser\Root
    Remove-Item "$env:TEMP\codesign.cer"

    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -eq "CN=Matze" }
    Set-AuthenticodeSignature -FilePath "C:\Pfad\zu\servereye_win11_upgradeauswertung.ps1" -Certificate $cert

---

## Autor

Dieses Skript wurde für den internen Einsatz erstellt und kann bei Bedarf erweitert oder angepasst werden.
