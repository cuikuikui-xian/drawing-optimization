param(
 [Parameter(Mandatory=$true)][string]$AssemblyPath,
 [Parameter(Mandatory=$true)][string]$OutputDir
)
$ErrorActionPreference='Stop'
$interop='D:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\api\redist\SolidWorks.Interop.sldworks.dll'
$swconst='D:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\api\redist\SolidWorks.Interop.swconst.dll'
Add-Type -Path $interop; Add-Type -Path $swconst
$source=@'
using System;
using System.IO;
using SolidWorks.Interop.sldworks;
using SolidWorks.Interop.swconst;
public static class SwSectionViews{
 public static string Run(string path,string outdir){
  ISldWorks sw=new SldWorksClass();sw.Visible=true;sw.UserControl=false;IModelDoc2 doc=null;
  try{int e=0,w=0;doc=sw.OpenDoc6(path,(int)swDocumentTypes_e.swDocASSEMBLY,(int)(swOpenDocOptions_e.swOpenDocOptions_ReadOnly|swOpenDocOptions_e.swOpenDocOptions_Silent),"",ref e,ref w);if(doc==null)throw new Exception("open "+e);
   ((IAssemblyDoc)doc).ResolveAllLightWeightComponents(false);((IAssemblyDoc)doc).ForceRebuild2(false);
   IModelViewManager mvm=doc.ModelViewManager; IMathUtility mu=(IMathUtility)sw.GetMathUtility();
   double[] xs={0.0888,0.1398}; string[] names={"left","right"};
   for(int i=0;i<2;i++){
    SectionViewData sd=(SectionViewData)mvm.CreateSectionViewData();
    sd.FirstPlane=new double[]{xs[i],0.025982843406600405,1.011,1.0,0.0,0.0}; sd.FirstOffset=0; sd.ShowSectionCap=true; sd.KeepCapColor=false; sd.GraphicsOnlySection=false; sd.Redraw=true;
    bool ok=mvm.CreateSectionView(sd);
    doc.ShowNamedView2("*Right",(int)swStandardViews_e.swRightView);doc.ViewZoomtofit2();
    string bmp=Path.Combine(outdir,"native_section_"+names[i]+".bmp");bool save=doc.SaveBMP(bmp,1800,1200);
    File.AppendAllText(Path.Combine(outdir,"section_log.txt"),names[i]+" Create="+ok+" Save="+save+" File="+bmp+System.Environment.NewLine);
    mvm.RemoveSectionView();
   }
   return "ok";
  }finally{if(doc!=null)sw.CloseDoc(doc.GetTitle());sw.ExitApp();}
 }
}
'@
Add-Type -TypeDefinition $source -ReferencedAssemblies $interop,$swconst
[SwSectionViews]::Run($AssemblyPath,$OutputDir)
