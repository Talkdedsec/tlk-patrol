# Renders text lines to 22.05 kHz mono WAV with the Windows SAPI voice (System.Speech).
# Input: UTF-8 TSV "<id><TAB><text>" per line. Output: <OutDir>\<id>.wav (existing files are skipped).
# Used by araclar/ses/telsiz_uret.py; the voice (Microsoft Zira, en-US) is the only English voice installed.
param(
	[Parameter(Mandatory = $true)][string]$InFile,
	[Parameter(Mandatory = $true)][string]$OutDir,
	[int]$Rate = 1
)
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.Rate = $Rate
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$count = 0
foreach ($line in [System.IO.File]::ReadAllLines($InFile, [System.Text.Encoding]::UTF8)) {
	$parts = $line.Split([char]9)
	if ($parts.Length -lt 2) { continue }
	$path = Join-Path $OutDir ($parts[0] + ".wav")
	if (Test-Path $path) { continue }
	$synth.SetOutputToWaveFile($path, $format)
	$synth.Speak($parts[1])
	$synth.SetOutputToNull()
	$count++
}
Write-Output "rendered $count clips"
