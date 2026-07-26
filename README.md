SCRIPT 1.
(1) checks if Ollama is running and restarts if stopped,
  (2) checks if Ollama is bound to 127.0.0.1 (not 0.0.0.0) — warns if insecure,
  (3) checks disk usage of ~/.ollama/models — warns if above 80%,
  (4) outputs last 5 failed SSH login attempts.

SCRIPT 2.
System Info Summary
•    Hostname, IP, OS version, kernel, uptime
•    Disk usage — flag any filesystem above 80%
•    Memory and CPU model
•    Output to ~/sysinfo_[date].txt

SCRIPT 3. 
Bash script that checks each of the following and outputs PASS/FAIL for each:
•    Is the Ollama service running? (systemctl is-active ollama)
•    Is Ollama bound to 127.0.0.1 not 0.0.0.0? (ss -tuln | grep 11434)
•    Is the Ollama API responding? (curl -s http://localhost:11434/api/tags)
•    How many models are installed? (ollama list | tail -n +2 | wc -l)
•    Is model disk usage below 80% of the partition?
•    Any ERROR entries in Ollama journal in the last hour?
•    Output a final summary: HEALTHY / WARNING / CRITICAL

SCRIPT 4.
•    List all users with login shells (not /sbin/nologin)
•    Check which have sudo rights
•    Flag any user with UID 0 other than root
