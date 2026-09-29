# gen-speech.ps1 - synthesize test audio with Windows SAPI.
#
# WHY: lets us regression-test transcription accuracy (especially the domain
# vocab prompt) without needing a human at the mic. Uses System.Speech, which
# ships with Windows - no third-party install, nothing leaves the machine.
#
# usage: powershell -NoProfile -File gen-speech.ps1 -Text "..." -Out C:\path\out.wav
#        powershell -NoProfile -File gen-speech.ps1 -ListVoices

param(
    [string]$Text,
    [string]$Out,
    [string]$Voice = "",
    [int]$Rate = 0,              # -10..10, 0 = normal
    [switch]$ListVoices
)

Add-Type -AssemblyName System.Speech

if ($ListVoices) {
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $s.GetInstalledVoices() | ForEach-Object {
        $i = $_.VoiceInfo
        "{0}  [{1}, {2}]" -f $i.Name, $i.Gender, $i.Culture
    }
    $s.Dispose()
    exit 0
}

if (-not $Text -or -not $Out) { Write-Error "need -Text and -Out"; exit 2 }

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
if ($Voice) {
    try { $synth.SelectVoice($Voice) } catch { Write-Error "no such voice: $Voice"; exit 3 }
}
$synth.Rate = $Rate

# 16 kHz mono 16-bit PCM - exactly what whisper.cpp wants, avoids a resample.
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, `
        [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, `
        [System.Speech.AudioFormat.AudioChannel]::Mono)

$synth.SetOutputToWaveFile($Out, $fmt)
$synth.Speak($Text)
$synth.SetOutputToNull()
$synth.Dispose()

if (Test-Path $Out) {
    "OK {0} ({1:N0} bytes)" -f $Out, (Get-Item $Out).Length
} else {
    Write-Error "failed to write $Out"; exit 4
}
