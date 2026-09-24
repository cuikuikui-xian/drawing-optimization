param(
    [Parameter(Mandatory = $true)] [string]$AssemblyPath,
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

public static class SwNativeInspector
{
    static string F(double x) { return x.ToString("G17", System.Globalization.CultureInfo.InvariantCulture); }
    static string A(double[] x) { return x == null ? "null" : String.Join(",", Array.ConvertAll(x, F)); }

    public static string Run(string assemblyPath, string outputPath)
    {
        ISldWorks sw = new SldWorksClass();
        sw.Visible = true;
        sw.UserControl = false;
        var lines = new List<string>();
        IModelDoc2 doc = null;
        try
        {
            object[] deps = sw.GetDocumentDependencies2(assemblyPath, true, true, true) as object[];
            lines.Add("DependenciesCount=" + (deps == null ? 0 : deps.Length));
            if (deps != null) for (int i=0; i<deps.Length; i++) lines.Add("Dependency["+i+"]="+deps[i]);

            int errors = 0, warnings = 0;
            doc = sw.OpenDoc6(assemblyPath, (int)swDocumentTypes_e.swDocASSEMBLY,
                (int)(swOpenDocOptions_e.swOpenDocOptions_ReadOnly | swOpenDocOptions_e.swOpenDocOptions_Silent),
                "", ref errors, ref warnings);
            lines.Add("Open errors=" + errors + " warnings=" + warnings + " null=" + (doc == null));
            if (doc == null) throw new Exception("OpenDoc6 failed.");
            lines.Add("Title=" + doc.GetTitle());
            lines.Add("Path=" + doc.GetPathName());
            lines.Add("DocType=" + doc.GetType());
            lines.Add("Config=" + doc.ConfigurationManager.ActiveConfiguration.Name);

            IAssemblyDoc assy = (IAssemblyDoc)doc;
            int resolve = assy.ResolveAllLightWeightComponents(false);
            lines.Add("ResolveAll=" + resolve);
            assy.ForceRebuild2(false);
            object[] components = assy.GetComponents(false) as object[];
            lines.Add("ComponentCount=" + (components == null ? 0 : components.Length));
            if (components != null)
            {
                for (int ci=0; ci<components.Length; ci++)
                {
                    IComponent2 comp = (IComponent2)components[ci];
                    double[] cbox = comp.GetBox(false, false) as double[];
                    IMathTransform xf = comp.Transform2;
                    double[] xfa = xf == null ? null : xf.ArrayData as double[];
                    lines.Add("Component["+ci+"] Name="+comp.Name2+" Path="+comp.GetPathName()+
                        " Suppressed="+comp.IsSuppressed()+" Visible="+comp.Visible+
                        " Box_m="+A(cbox)+" Transform="+A(xfa));
                    object[] bodies = comp.GetBodies2((int)swBodyType_e.swAllBodies) as object[];
                    lines.Add("Component["+ci+"] BodyCount="+(bodies==null?0:bodies.Length));
                    if (bodies != null)
                    {
                        for(int bi=0; bi<bodies.Length; bi++)
                        {
                            IBody2 body=(IBody2)bodies[bi];
                            double[] box=body.GetBodyBox() as double[];
                            object[] mass=body.GetMassProperties(1.0) as object[];
                            double volume=mass!=null && mass.Length>3?Convert.ToDouble(mass[3]):Double.NaN;
                            lines.Add("Component["+ci+"].Body["+bi+"] Name="+body.Name+" Type="+body.GetType()+
                                " Faces="+body.GetFaceCount()+" Volume_m3="+F(volume)+" Box_m="+A(box));
                        }
                    }
                    IModelDoc2 cdoc = comp.GetModelDoc2() as IModelDoc2;
                    if (cdoc != null)
                    {
                        lines.Add("Component["+ci+"] ModelTitle="+cdoc.GetTitle()+" ModelType="+cdoc.GetType()+
                            " FeatureCount="+cdoc.GetFeatureCount());
                        IFeature feat=cdoc.FirstFeature() as IFeature; int fi=0;
                        while(feat!=null && fi<500)
                        {
                            lines.Add("Component["+ci+"].Feature["+fi+"] Name="+feat.Name+" Type="+feat.GetTypeName2()+
                                " Suppressed="+feat.IsSuppressed());
                            feat=feat.GetNextFeature() as IFeature; fi++;
                        }
                    }
                }
            }

            doc.ShowNamedView2("*Isometric", (int)swStandardViews_e.swIsometricView);
            doc.ViewZoomtofit2();
            string iso=Path.Combine(Path.GetDirectoryName(outputPath),"native_isometric.bmp");
            lines.Add("Iso="+iso+" Ok="+doc.SaveBMP(iso,1800,1200));
            doc.ShowNamedView2("*Front", (int)swStandardViews_e.swFrontView);
            doc.ViewZoomtofit2();
            string front=Path.Combine(Path.GetDirectoryName(outputPath),"native_front.bmp");
            lines.Add("Front="+front+" Ok="+doc.SaveBMP(front,1800,1200));
            doc.ShowNamedView2("*Bottom", (int)swStandardViews_e.swBottomView);
            doc.ViewZoomtofit2();
            string bottom=Path.Combine(Path.GetDirectoryName(outputPath),"native_bottom.bmp");
            lines.Add("Bottom="+bottom+" Ok="+doc.SaveBMP(bottom,1800,1200));

            File.WriteAllLines(outputPath, lines.ToArray(), System.Text.Encoding.UTF8);
            return String.Join(System.Environment.NewLine,lines.ToArray());
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
[SwNativeInspector]::Run($AssemblyPath,$OutputPath)
