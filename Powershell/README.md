Script 1 — System Health Check
•    Disk space on all drives — warn if below 20%
•    CPU usage — warn if average above 80% for 30 seconds
•    Memory — warn if less than 500MB free
•    Top 5 processes by CPU
•    Output: formatted report to C:\Temp\healthcheck_[date].txt


Script 2 — User Account Report
•    List all local users with: name, enabled status, last logon, whether in Administrators group
•    Flag any accounts never logged in that are enabled
•    Output: save to a .csv file

Script 3 — Event Log Parser
•    Query System log for Error events in last 24 hours
•    Query Security log for Event ID 4625 (failed logon) in last 24 hours
•    Output both to a single text report with timestamps

