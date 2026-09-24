param(
    [Parameter(Mandatory = $true)] [string]$PartPath,
    [Parameter(Mandatory = $true)] [string]$OutputPath
)

$ErrorActionPreference='Stop'
$interop='D:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\api\redist\SolidWorks.Interop.sldworks.dll'
$swconst='D:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\api\redist\SolidWorks.Interop.swconst.dll'
Add-Type -Path $interop
Add-Type -Path $swconst

$source=@'
using System;
using System.Collections.Generic;
using System.IO;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;

public static class SwFeatureDetails
{
 static string F(double x){return x.ToString("G17",System.Globalization.CultureInfo.InvariantCulture);}
 static string A(double[] a){return a==null?"null":String.Join(",",Array.ConvertAll(a,F));}
 public static string Run(string partPath,string outputPath)
 {
  ISldWorks sw=new SldWorksClass(); sw.Visible=true; sw.UserControl=false; IModelDoc2 doc=null;
  var lines=new List<string>();
  try{
   int errors=0,warnings=0;
   doc=sw.OpenDoc6(partPath,(int)swDocumentTypes_e.swDocPART,(int)(swOpenDocOptions_e.swOpenDocOptions_ReadOnly|swOpenDocOptions_e.swOpenDocOptions_Silent),"",ref errors,ref warnings);
   lines.Add("Open errors="+errors+" warnings="+warnings+" null="+(doc==null)); if(doc==null)throw new Exception("open failed");
   lines.Add("Title="+doc.GetTitle()+" Path="+doc.GetPathName());
   IFeature feat=doc.FirstFeature() as IFeature; int fi=0;
   while(feat!=null && fi<500){
    string type=feat.GetTypeName2();
    lines.Add("Index="+fi+" Name="+feat.Name+" Type="+type);
    bool target=type=="RevCut"||type=="ProfileFeature";
    if(target){
     object bb=null; bool bok=feat.GetBox(ref bb); lines.Add("Feature Name="+feat.Name+" Type="+type+" BoxOk="+bok+" Box="+A(bb as double[]));
     IDisplayDimension dd=feat.GetFirstDisplayDimension() as IDisplayDimension; int di=0;
     while(dd!=null && di<100){IDimension d=dd.GetDimension2(0); lines.Add(" FeatureDim["+di+"] FullName="+d.FullName+" Name="+d.Name+" System_m_or_rad="+F(d.SystemValue)); dd=feat.GetNextDisplayDimension(dd) as IDisplayDimension;di++;}
     object[] faces=feat.GetFaces() as object[]; lines.Add(" FeatureFaces="+(faces==null?0:faces.Length));
     if(faces!=null)for(int k=0;k<faces.Length;k++){IFace2 face=(IFace2)faces[k]; double[] fbox=face.GetBox() as double[]; ISurface surf=face.GetSurface() as ISurface; string st="other"; double[] pars=null;
       if(surf.IsPlane()){st="plane";pars=surf.PlaneParams as double[];} else if(surf.IsCylinder()){st="cylinder";pars=surf.CylinderParams as double[];} else if(surf.IsCone()){st="cone";pars=surf.ConeParams as double[];} else if(surf.IsTorus()){st="torus";pars=surf.TorusParams as double[];}
       lines.Add("  Face["+k+"] Type="+st+" Box="+A(fbox)+" Params="+A(pars));}
     object def=feat.GetDefinition(); IRevolveFeatureData2 rev=def as IRevolveFeatureData2;
     if(rev!=null){bool access=rev.AccessSelections(doc,null);lines.Add(" Revolve Access="+access+" Type="+rev.Type+" AxisType="+rev.GetAxisType()+" FwdAngle="+F(rev.GetRevolutionAngle(true))+" RevAngle="+F(rev.GetRevolutionAngle(false))+" Reverse="+rev.ReverseDirection);rev.ReleaseSelectionAccess();}
     object specific=feat.GetSpecificFeature2(); ISketch sk=specific as ISketch;
     if(sk!=null){double[] xf=sk.ModelToSketchTransform.ArrayData as double[];lines.Add(" Sketch Transform="+A(xf)+" Points="+sk.GetSketchPointsCount2());object[] segs=sk.GetSketchSegments() as object[];lines.Add(" Sketch Segments="+(segs==null?0:segs.Length));if(segs!=null)for(int si=0;si<segs.Length;si++){ISketchSegment ss=(ISketchSegment)segs[si];ICurve c=ss.GetCurve() as ICurve;double[] cp=null;string ct="other";if(c!=null){if(c.IsLine()){ct="line";cp=c.LineParams as double[];}else if(c.IsCircle()){ct="circle";cp=c.CircleParams as double[];}}lines.Add("  Segment["+si+"] Type="+ct+" Construction="+ss.ConstructionGeometry+" Params="+A(cp));}}
    }
    feat=feat.GetNextFeature() as IFeature;fi++;
   }
   File.WriteAllLines(outputPath,lines.ToArray(),System.Text.Encoding.UTF8);return String.Join(System.Environment.NewLine,lines.ToArray());
  }finally{if(doc!=null)sw.CloseDoc(doc.GetTitle());sw.ExitApp();}
 }
}
'@
Add-Type -TypeDefinition $source -ReferencedAssemblies $interop,$swconst
[SwFeatureDetails]::Run($PartPath,$OutputPath)
