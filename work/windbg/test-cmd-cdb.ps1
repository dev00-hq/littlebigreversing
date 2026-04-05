Set-Location 'D:\repos\reverse\littlebigreversing'
& 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2603.20001.0_x64__8wekyb3d8bbwe\amd64\cdb.exe' -server 'tcp:port=5017,password=smoketest' -logo 'D:\repos\reverse\littlebigreversing\work\windbg\test-cmd-cdb.log' -p 20872 -noio
