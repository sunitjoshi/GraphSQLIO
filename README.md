GraphSQLIO PowerShell Script

*** Disclaimer ***
This script is provided "as is" and with all faults and the usage of such is not warranted to be uninterrupted or error free. Please use it at your own risk.

GraphSQLIO is a PowerShell script to automate SQLIO (from Microsoft) runs. It uses the files, param.txt and TestSQLIO.cmd, as options for SQLIO run. Param.txt contain location and size of the test dat file, and TestSQLIO.cmd, has cmds for each individual SQLIO run. Edit these files as suitable for your environment. 

It also display a charts for each run in a tabbed interface to quickly analyze the results. The results are stored locally, in SQLIOResults.xml, and can be viewed later by using the -OnlyCharts option
