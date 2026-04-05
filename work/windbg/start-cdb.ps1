Set-Location 'D:\repos\reverse\littlebigreversing'
& 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2603.20001.0_x64__8wekyb3d8bbwe\amd64\cdb.exe' -server 'tcp:port=5012,password=test' -logo 'D:\repos\reverse\littlebigreversing\work\windbg\file-host-cdb.log' -p 24552 -noio
