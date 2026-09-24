param(
    [Parameter(Mandatory = $true)] [string]$StepPath,
    [Parameter(Mandatory = $true)] [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$interop = 'D:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\api\redist\SolidWorks.Interop.sldworks.dll'
$swconst = 'D:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\api\redist\SolidWorks.Interop.swconst.dll'
Add-Type -Path $interop
Add-Type -Path $swconst

$source = @'
using System;
using System.Collections.Generic;
using System.IO;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;

public static class SwImportInspector
{
    static string F(double x) { return x.ToString("G17", System.Globalization.CultureInfo.InvariantCulture); }

    public static string Run(string stepPath, string outputPath)
    {
        ISldWorks sw = new SldWorksClass();
        sw.Visible = true;
        sw.UserControl = false;
        IModelDoc2 doc = null;
        var lines = new List<string>();
        try
        {
            int errors = 0, warnings = 0;
            doc = sw.OpenDoc6(stepPath, (int)swDocumentTypes_e.swDocPART,
                (int)(swOpenDocOptions_e.swOpenDocOptions_ReadOnly | swOpenDocOptions_e.swOpenDocOptions_Silent),
                "", ref errors, ref warnings);
            lines.Add("OpenDoc6 errors=" + errors + " warnings=" + warnings + " null=" + (doc == null));
            if (doc == null)
            {
                object importData = sw.GetImportFileData(stepPath);
                int loadErrors = 0;
                doc = sw.LoadFile4(stepPath, "r", importData, ref loadErrors);
                lines.Add("LoadFile4 errors=" + loadErrors + " null=" + (doc == null));
            }
            if (doc == null) throw new Exception("Both OpenDoc6 and LoadFile4 failed.");

            lines.Add("Title=" + doc.GetTitle());
            lines.Add("Path=" + doc.GetPathName());
            lines.Add("DocType=" + doc.GetType());
            lines.Add("Visible=" + doc.Visible);

            IPartDoc part = doc as IPartDoc;
            IAssemblyDoc assy = doc as IAssemblyDoc;
            object[] bodies = part == null ? null : part.GetBodies2((int)swBodyType_e.swAllBodies, false) as object[];
            if (assy != null)
            {
                lines.Add("ResolveAll=" + assy.ResolveAllLightWeightComponents(false));
                assy.ForceRebuild2(false);
                object[] components = assy.GetComponents(true) as object[];
                lines.Add("ComponentCount=" + (components == null ? 0 : components.Length));
                if (components != null)
                {
                    for (int ci = 0; ci < components.Length; ci++)
                    {
                        IComponent2 comp = (IComponent2)components[ci];
                        double[] cbox = comp.GetBox(false, false) as double[];
                        IMathTransform xf = comp.Transform2;
                        double[] xfa = xf == null ? null : xf.ArrayData as double[];
                        lines.Add("Component[" + ci + "] Name=" + comp.Name2 + " Path=" + comp.GetPathName() +
                            " Suppressed=" + comp.IsSuppressed() + " Visible=" + comp.Visible +
                            " Box_m=" + (cbox == null ? "null" : String.Join(",", Array.ConvertAll(cbox, F))) +
                            " Transform=" + (xfa == null ? "null" : String.Join(",", Array.ConvertAll(xfa, F))));
                        object[] cbodies = comp.GetBodies2((int)swBodyType_e.swAllBodies) as object[];
                        lines.Add("Component[" + ci + "] BodyCount=" + (cbodies == null ? 0 : cbodies.Length));
                        if (cbodies != null)
                        {
                            for (int bi = 0; bi < cbodies.Length; bi++)
                            {
                                IBody2 body = (IBody2)cbodies[bi];
                                double[] box = body.GetBodyBox() as double[];
                                lines.Add("Component[" + ci + "].Body[" + bi + "] Name=" + body.Name +
                                    " Type=" + body.GetType() + " Faces=" + body.GetFaceCount() +
                                    " Box_m=" + String.Join(",", Array.ConvertAll(box, F)));
                            }
                        }
                    }
                }
            }
            lines.Add("PartBodyCount=" + (bodies == null ? 0 : bodies.Length));
            if (bodies != null)
            {
                for (int i = 0; i < bodies.Length; i++)
                {
                    IBody2 body = (IBody2)bodies[i];
                    double[] box = body.GetBodyBox() as double[];
                    object[] mass = body.GetMassProperties(1.0) as object[];
                    double volume = mass != null && mass.Length > 3 ? Convert.ToDouble(mass[3]) : Double.NaN;
                    lines.Add("Body[" + i + "] Name=" + body.Name + " Type=" + body.GetType() +
                        " Faces=" + body.GetFaceCount() + " Volume_m3=" + F(volume) +
                        " Box_m=" + String.Join(",", Array.ConvertAll(box, F)));
                }
            }

            doc.ShowNamedView2("*Isometric", (int)swStandardViews_e.swIsometricView);
            doc.ViewZoomtofit2();
            string bmp = Path.ChangeExtension(outputPath, ".bmp");
            bool bmpOk = doc.SaveBMP(bmp, 1800, 1200);
            lines.Add("Bitmap=" + bmp + " Ok=" + bmpOk);
            File.WriteAllLines(outputPath, lines.ToArray(), System.Text.Encoding.UTF8);
            return String.Join(System.Environment.NewLine, lines.ToArray());
        }
        finally
        {
            if (doc != null) sw.CloseDoc(doc.GetTitle());
            sw.ExitApp();
        }
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies $interop,$swconst
[SwImportInspector]::Run($StepPath, $OutputPath)
