param(
    [Parameter(Mandatory = $true)]
    [string]$StepPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$swExe = 'D:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\SLDWORKS.exe'
$interop = 'D:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\api\redist\SolidWorks.Interop.sldworks.dll'

if (-not (Test-Path -LiteralPath $StepPath)) { throw "STEP not found: $StepPath" }
if (-not (Test-Path -LiteralPath $swExe)) { throw "SolidWorks not found: $swExe" }

# Close only headless SolidWorks processes started by this review (no visible window).
Get-Process SLDWORKS -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -eq 0 } |
    Stop-Process -Force -ErrorAction SilentlyContinue

$proc = Start-Process -FilePath $swExe -ArgumentList @('/r', ('"{0}"' -f $StepPath)) -PassThru

$deadline = (Get-Date).AddMinutes(3)
$swRaw = $null
do {
    Start-Sleep -Milliseconds 1000
    try { $swRaw = [Runtime.InteropServices.Marshal]::GetActiveObject('SldWorks.Application') } catch { }
} while (($null -eq $swRaw) -and ((Get-Date) -lt $deadline))

if ($null -eq $swRaw) { throw 'SolidWorks did not publish an active automation object.' }

Add-Type -Path $interop

$source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using SolidWorks.Interop.sldworks;

public static class SwInspector
{
    public static string Inspect(object raw, string outputPath)
    {
        ISldWorks sw = (ISldWorks)raw;
        DateTime deadline = DateTime.Now.AddMinutes(3);
        IModelDoc2 doc = null;
        while (DateTime.Now < deadline)
        {
            doc = sw.IActiveDoc2;
            if (doc != null) break;
            System.Threading.Thread.Sleep(1000);
        }
        if (doc == null) throw new Exception("No active document after STEP import.");

        var lines = new List<string>();
        lines.Add("Title=" + doc.GetTitle());
        lines.Add("Path=" + doc.GetPathName());
        lines.Add("DocType=" + doc.GetType());

        int bodyCount = 0;
        IPartDoc part = doc as IPartDoc;
        object[] bodies = part == null ? null : part.GetBodies2(0, true) as object[];
        if (bodies != null)
        {
            bodyCount = bodies.Length;
            for (int i = 0; i < bodies.Length; i++)
            {
                IBody2 body = (IBody2)bodies[i];
                double[] box = body.GetBodyBox() as double[];
                double volume = Double.NaN;
                object[] mass = body.GetMassProperties(1.0) as object[];
                if (mass != null && mass.Length > 3) volume = Convert.ToDouble(mass[3]);
                lines.Add(String.Format(System.Globalization.CultureInfo.InvariantCulture,
                    "Body[{0}] Name={1} Solid={2} Faces={3} Volume_m3={4:G17} Box_m={5:G17},{6:G17},{7:G17},{8:G17},{9:G17},{10:G17}",
                    i, body.Name, (body.GetType() == 0), body.GetFaceCount(), volume,
                    box[0], box[1], box[2], box[3], box[4], box[5]));
            }
        }
        lines.Add("BodyCount=" + bodyCount);

        doc.ShowNamedView2("*Isometric", 7);
        doc.ViewZoomtofit2();
        string imagePath = Path.ChangeExtension(outputPath, ".png");
        int errors = 0, warnings = 0;
        bool imageOk = doc.Extension.SaveAs(imagePath, 0, 1, null, ref errors, ref warnings);
        lines.Add("Image=" + imagePath + " Ok=" + imageOk + " Errors=" + errors + " Warnings=" + warnings);

        File.WriteAllLines(outputPath, lines.ToArray(), System.Text.Encoding.UTF8);
        return String.Join(System.Environment.NewLine, lines.ToArray());
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies $interop
[SwInspector]::Inspect($swRaw, $OutputPath)
