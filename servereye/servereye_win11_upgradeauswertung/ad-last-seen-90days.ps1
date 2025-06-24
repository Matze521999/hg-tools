$cutoffDate = (Get-Date).AddDays(-90)

Get-ADComputer -Filter 'name -like "*"' -Properties Name,OperatingSystem,IPv4Address,LastLogonDate |
Where-Object { $_.LastLogonDate -gt $cutoffDate } |
Select-Object Name, OperatingSystem, IPv4Address, LastLogonDate |
Sort-Object LastLogonDate |
Export-Csv -Path "C:\computer_last_seen.csv" -NoTypeInformation -Encoding UTF8
