# Runs the RaySAR ray-tracing engine (pvengine.exe) to the end without leaving
# any window on screen. Called by Render_POV.m.
#
# The engine is a Windows GUI program. Started plainly it opens its main window
# and a render window, takes the focus, and closes them itself when done. This
# starts it minimised and hides those windows the moment they appear, then
# waits for it to finish. Dialogs are never hidden: a hidden dialog would wait
# for an answer nobody can give.
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$WorkDir,
    [Parameter(Mandatory)][string]$PovFile,
    [Parameter(Mandatory)][int]$Wpx,
    [Parameter(Mandatory)][int]$Hpx,
    [Parameter(Mandatory)][string]$IncludeDir,
    [int]$TimeoutSec = 3600
)

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class EngineWindows {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    public static void Hide(uint pid) {
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) {
                var c = new StringBuilder(256); GetClassName(h, c, 256);
                if (c.ToString() != "#32770") ShowWindow(h, 0);
            }
            return true;
        }, IntPtr.Zero);
    }
}
'@

$p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -WindowStyle Minimized -PassThru `
    -ArgumentList '/EXIT', "+I`"$PovFile`"", "+W$Wpx", "+H$Hpx", "+L`"$IncludeDir`""

$clock = [Diagnostics.Stopwatch]::StartNew()
while (-not $p.HasExited) {
    [EngineWindows]::Hide($p.Id)
    if ($clock.Elapsed.TotalSeconds -gt $TimeoutSec) {
        $p.Kill()
        [Console]::Error.WriteLine("The engine did not finish within $TimeoutSec s and was stopped.")
        exit 2
    }
    Start-Sleep -Milliseconds 30
}
$p.WaitForExit()
exit $p.ExitCode
