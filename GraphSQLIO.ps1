<#
    Author:      Sunit Joshi
    Description: Script to invoke SQLIO from options specified in a cmd file. The output data is 
                 then serialized and displayed as charts 
    Site:        www.sunitjoshi.wordpress.com                 
    Date:        12/04/2013
#>
param
(
    [string]$OptionsFile= "TestSQLIO.cmd",
    [string]$ResultsFile= "SQLIOResults.xml",
    [switch]$OnlyCharts
)

Add-Type -AssemblyName System.Windows.Forms

#Currently the script is set to work on a .NET 3.5, Windows 7, PowerShell 2.0 machine

#On PowerShell 3.0 machines like Windows 8+, uncomment the line below
Add-Type -AssemblyName System.Windows.Forms.DataVisualization

#Comment this line below using prefix # on a PowerShell 3.0, like Windows 8.0, machine
#Add-Type -AssemblyName ('System.Windows.Forms.DataVisualization, Version=3.5.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35')

#Script level variable to store Run entries
$Script:entries = @()

function ParseRunEntries
{
    $folder = Split-Path (Resolve-Path $OptionsFile) -Parent
    $lines = (Get-Content $OptionsFile) -split [Environment]::NewLine | Where {$_.Trim().Length -gt 0 -and $_.StartsWith("sqlio")} | foreach {$_.Trim()}    
	
    try
    {
        foreach($line in $lines)
        {
            $options = $line -split "-"  | foreach {$_.Trim()}
            $filename = [String]::Empty
            if($options.Length -eq 9)
            {                
                $sqlObj = New-Object psobject
                Add-Member -InputObject $sqlObj -m NoteProperty -Name "Options" -Value @()
                foreach($option in $options[1..$options.Length])
                {
                    $sqlObj.Options += "'-$option'"         #Create parameter array of string type
                    $value = $option.Substring(1).Trim()
                    if($option -match "^k(w|W|R|r)"){  
                        $filename += $value.ToUpper()
                        Add-Member -InputObject $sqlObj -m NoteProperty -Name "Operation" -Value $value
                    }
                    elseif($option -match "^s\d+" ) {
                        $filename += $option
                        Add-Member -InputObject $sqlObj -m NoteProperty -Name "Duration" -Value ([int]$value)
                    }
                    elseif($option -match "^f(random|sequential)") {
                        $filename += $option
                        Add-Member -InputObject $sqlObj -m NoteProperty -Name "Mode" -Value $value
                    }
                    elseif($option -match "^o\d+") {
                        Add-Member -InputObject $sqlObj -m NoteProperty -Name "Outstanding" -Value ([int]$value)
                    }
                    elseif($option -match "^b\d+") {
                        $filename += $option
                        Add-Member -InputObject $sqlObj -m NoteProperty -Name "Size" -Value ([int]$value)
                    }                    
                    elseif($option -match "-F.*\.txt")
                    {
                        Add-Member -InputObject $sqlObj -m NoteProperty -Name "ParamFile" -Value $value
                    }                                 
                }
                $filename += ".txt"
                Add-Member -InputObject $sqlObj -m NoteProperty -Name "OutputFile" -Value $filename
                Add-Member -InputObject $sqlObj -m NoteProperty -Name "CaptureLatency" -Value "'-LS'"
                Add-Member -InputObject $sqlObj -m NoteProperty -Name "Buffering" -Value "'-BN'"
                $Script:entries += $sqlObj
				$sqlObj = $null
            }
        }
    }
    catch{
        write "Error executing script: $Error"
    }    
}

function RunEntries
{
    $validRuns = @()
    if($Matches) { $Matches.Clear()}
	foreach($obj in $Script:entries)
	{        
        $sqlioPath = Resolve-Path sqlio.exe
        $results = Invoke-Expression -Command "$sqlioPath $($obj.Options)" | Out-String
        $results | Set-Content $obj.OutputFile

        #Add the results to each run object
        Add-Member -InputObject $obj -m NoteProperty -Name "Results" -Value $results

        if($results.Contains("histogram:"))
        {
            $lines = $obj.Results -split [Environment]::NewLine | Where {$_.Trim().Length -gt 0} | foreach {$_.Trim()}
            foreach($line in $lines)
            {
                $outputValue = ParseOutputValue $line
                if($outputValue -is [double])
                {
                    if($line -match "IOs/sec.*")
                    {
                        Add-Member -InputObject $obj -MemberType NoteProperty -Name "IOsPerSec" -Value $outputValue 
                    }
                    elseif($line -match "MBs.*")
                    {
                        Add-Member -InputObject $obj -MemberType NoteProperty -Name "MBsPerSec" -Value $outputValue
                    }
                    elseif($line -match "Avg_Latency.*")
                    {
                        Add-Member -InputObject $obj -MemberType NoteProperty -Name "AvgLatencyMs" -Value $outputValue
                    }                    
                    elseif($line -match "using (specified|current) size:")
                    {
                         Add-Member -InputObject $obj -MemberType NoteProperty -Name "TestFilesize" -Value $outputValue
                    }
                }
                elseif($line -match "(?<th>\d+)\s+thread[s]?\s+(reading|writing).*file\s+(?<TestFile>[a-zA-Z]?[:\\]?.*)")
                {
                    Add-Member -InputObject $obj -MemberType NoteProperty -Name "Threads" -Value ([int]$Matches.th)
                    Add-Member -InputObject $obj -MemberType NoteProperty -Name "TestFile" -Value $Matches.TestFile.Trim() 
                }
                elseif($line -match "^ms:\s+\d+")
                {
                    #ms: 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24+
                    $lineWithValues = $line -split {$_ -eq "m" -or $_ -eq "s" -or $_ -eq ":" -or $_ -eq "+"} | where {$_.Trim().Length -gt 0} | foreach {$_.Trim()}
                    $values = $lineWithValues -split "\s+" | foreach {[int]$_}
                    Add-Member -InputObject $obj -MemberType NoteProperty -Name "LatencyValues" -Value $values
                }
                elseif($line -match "^%:\s+\d+")
                {
                    #%:  0  0  0  0  3  4  5  2  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0 85
                    $lineLatency = $line -split {$_ -eq "%" -or $_ -eq ":"} | where{$_.Trim().Length -gt 0} | foreach{$_.Trim()} 
                    $percentValues = $lineLatency -split "\s+" | foreach {[int]$_}
                    Add-Member -InputObject $obj -MemberType NoteProperty -Name "LatencyPercent" -Value $percentValues
                }
            }
            $validRuns += $obj        
        }
	}
    $validRuns | Export-Clixml -Path $ResultsFile
}


function ParseOutputValue($linevalue)
{
    $value = [String]::Empty
    if($linevalue -match "([^(ms:|%:\d+)].*:\s+)(?<no>\d+)")
    {
        $value = [double] $Matches.no 
    }
    $value
}

function GetChartArea($chart)
{
    $chartArea = $null
    $chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
    $chartArea.AxisY.MajorGrid.LineColor = "Blue"
    #$chartArea.Area3DStyle = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea3DStyle `
    #                        -Property @{Enable3D=$true; IsRightAngleAxes=$false; Rotation=20; Inclination=20; PointDepth=100; PointGapDepth=200}
    
    Start-Sleep -Milliseconds 20    #To handle issues on WindowsServer 2008R2
    $curTicks = (Get-Date).Ticks
    $chartAreaName = "CA-$curTicks"
    $chartArea.Name = $chartAreaName
    $chartArea.BackSecondaryColor = [System.Drawing.Color]::LightSteelBlue
    $chartArea.BackGradientStyle = [System.Windows.Forms.DataVisualization.Charting.GradientStyle]::DiagonalRight    
    $chartArea.AxisX.Title = "Block Size" 
    $chartArea.Area3DStyle.Enable3D = $false
    $chart.ChartAreas.Add($chartArea) | Out-Null
    $chartArea
}

function SetSeries($chart, $chartArea, $chartType="Column", $seriesType="Cylinder")
{

    Start-Sleep -Milliseconds 20    #To handle issues on WindowsServer 2008R2
    $curTicks = (Get-Date).Ticks
    $seriesName = "SE-$curTicks"
    $chart.Series.Add($seriesName) | Out-Null

    $chart.Series[$seriesName].ChartArea =$chartArea.Name
    $chart.Series[$seriesName].BorderWidth = 2
    $chart.Series[$seriesName].ChartType = $chartType
    $chart.Series[$seriesName].LabelForeColor = [System.Drawing.Color]::DarkGreen
    $chart.Series[$seriesName].LabelBackColor = [System.Drawing.Color]::LightGreen
    $chart.Series[$seriesName]["DrawingStyle"] = $seriesType
    $chart.Series[$seriesName]["PointWidth"] = "0.5"        
    $chart.Series[$seriesName].IsValueShownAsLabel = $true
    $chart.Series[$seriesName].IsXValueIndexed = $true

    $seriesName
}

function GenerateCharts
{
    if(-not (Test-Path $ResultsFile))
    {
        throw "Invalid file specified"
    }       

    $Script:entries = Import-Clixml $ResultsFile    
    $groupEntries = $Script:entries | Group-Object -Property Operation, Mode -AsHashTable -AsString

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "SQLIO CHARTS"
    $form.Width = 700
    $form.Height = 700

    $tabHost = New-Object System.Windows.Forms.TabControl    
    $tabHost.Dock = "Fill"  
    $form.Controls.Add($tabHost)
    $runThreads = ($Script:entries | select -First 1).Threads
    $runOutstanding = ($Script:entries | select -First 1).Outstanding
    $runDuration = ($Script:entries | select -First 1).Duration
    $runFileSize = ($Script:entries | select -First 1).TestFilesize
    $runFilePath = ($Script:entries | select -First 1).TestFile
    $form.Text = "SQLIO-$runDuration sec run with $runThreads threads, $runOutstanding pending IOs & $runFileSize(MB) $runFilePath file"

    foreach($grpKey in $groupEntries.Keys)
    {   
        #Create tab page to host group Chart       
        $chartName = ($grpKey -replace ",", "-") -replace " " , ""
        $tabPage = New-Object System.Windows.Forms.TabPage -ArgumentList "Run-$($chartName)"        

        #create chart host
        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart 
        $chart.BackColor = [System.Drawing.Color]::Transparent
        $chart.Dock = "fill"
        
        if($grpKey -match "random")
        {
            $chart.Titles.Add("Note: IOPS & Avg.Latency") | Out-Null
        }
        else
        {
            $chart.Titles.Add("Note: MBs/sec & Avg.Latency") | Out-Null
        }        

        $chart.Titles[0].Font = New-Object System.Drawing.Font("Arial",11, [System.Drawing.FontStyle]::Bold)

        #Create chart areas
        $grpEntry = $groupEntries[$grpKey]
        AddChartAreas $chart $grpEntry 
        
        #Add chart to tab page
        $tabPage.Controls.Add($chart)

        #Add tab page to tab control
        $tabHost.TabPages.Add($tabPage)
    }

    $form.Add_Shown({$form.Activate()})
    $form.ShowDialog() | Out-Null
}

function AddChartAreas($chart, $currentGroup)
{    
    for($i=0; $i -lt 3; $i++)
    {
        #Get a chartarea and add it to chart
        $chartArea = GetChartArea $chart

        if($i -lt 3)
        {
            $seriesName = SetSeries $chart $chartArea
     
            #Add series data
            if($i -eq 0)
            {
                $chartarea.AxisY.Title = "Avg. Latency(ms)"
                $currentGroup | ForEach-Object{$chart.Series[$seriesName].Points.AddXY($_.Size, $_.AvgLatencyMs)} | Out-Null
            }
            elseif($i -eq 1)
            {
              $chartarea.AxisY.Title = "MBs/sec"         
              $currentGroup | ForEach-Object{$chart.Series[$seriesName].Points.AddXY($_.Size, $_.MBsPerSec)} | Out-Null
            }
            elseif($i -eq 2)
            {
                $chartarea.AxisY.Title = "IOPS"
                $currentGroup | ForEach-Object{$chart.Series[$seriesName].Points.AddXY($_.Size, $_.IOsPerSec)}| Out-Null
            }        
        }
        <#
        else
        {                        
            $chartArea.AxisY.Title = "Percentage"
            $chartArea.AxisX.Title = "Latency (ms)"
            $chartArea.AxisY.IsMarginVisible = $true
            #Add series data
            foreach($grpEntry in $currentGroup)
            {
                $seriesName = SetSeries $chart $chartArea -seriesType "Default"
                
                for($i=0; $i -lt $grpEntry.LatencyPercent.Count; $i++)
                {
                    $chart.Series[$seriesName].Points.AddY($grpEntry.LatencyPercent[$i]) | Out-Null
                }
            }            
        }
    #>
    }    
}


Clear-Host
if($OnlyCharts)
{
    GenerateCharts
}
else
{
    ParseRunEntries
    RunEntries
    GenerateCharts             
}
#$Script:entries
