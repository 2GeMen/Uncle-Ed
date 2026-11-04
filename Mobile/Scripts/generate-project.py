import os
from pathlib import Path
import plistlib,hashlib,json
root=Path(__file__).resolve().parent.parent;project=root/'UncleEd.xcodeproj';project.mkdir(exist_ok=True);objects={}
def add(identifier,**data):
 key=hashlib.sha1(identifier.encode()).hexdigest()[:24].upper();objects[key]=data;return key
fileRefs=[];sourceBuild=[]
for p in sorted((root/'Sources').rglob('*')):
 if p.suffix not in ['.swift','.c','.m']:continue
 rel=str(p.relative_to(root));ref=add(rel,isa='PBXFileReference',lastKnownFileType={'.swift':'sourcecode.swift','.c':'sourcecode.c.c','.m':'sourcecode.c.objc'}[p.suffix],path=rel,sourceTree='<group>');fileRefs.append(ref);sourceBuild.append(add('build'+rel,isa='PBXBuildFile',fileRef=ref))
resources=[]
for name,path,kind in [('Assets','../Assets','folder'),('Images','Resources/Images.xcassets','folder.assetcatalog')]:
 ref=add(name,isa='PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='<group>');fileRefs.append(ref);resources.append(add('build'+name,isa='PBXBuildFile',fileRef=ref))
frameworks=[]
for name in ['UIKit','AudioToolbox','AVFAudio','OpenGLES','QuartzCore','CryptoKit','SceneKit']:
 ref=add(name,isa='PBXFileReference',lastKnownFileType='wrapper.framework',name=name+'.framework',path='System/Library/Frameworks/'+name+'.framework',sourceTree='SDKROOT');fileRefs.append(ref);frameworks.append(add('build'+name,isa='PBXBuildFile',fileRef=ref))
product=add('product',isa='PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='Uncle Ed.app',sourceTree='BUILT_PRODUCTS_DIR')
products=add('products',isa='PBXGroup',children=[product],name='Products',sourceTree='<group>')
group=add('group',isa='PBXGroup',children=fileRefs+[products],sourceTree='<group>')
sources=add('sources',isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=sourceBuild,runOnlyForDeploymentPostprocessing=0)
resources=add('resources',isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)
package=add('zip-package',isa='XCRemoteSwiftPackageReference',repositoryURL='https://github.com/weichsel/ZIPFoundation.git',requirement={'kind':'upToNextMajorVersion','minimumVersion':'0.9.19'})
zipProduct=add('zip-product',isa='XCSwiftPackageProductDependency',package=package,productName='ZIPFoundation')
frameworks.append(add('build-zip',isa='PBXBuildFile',productRef=zipProduct))
frameworks=add('frameworks',isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=frameworks,runOnlyForDeploymentPostprocessing=0)
embed=add('embed',isa='PBXShellScriptBuildPhase',buildActionMask=2147483647,files=[],inputPaths=[],outputPaths=[],runOnlyForDeploymentPostprocessing=0,shellPath='/bin/sh',shellScript='"$SRCROOT/Scripts/embed-cores.sh"\n',alwaysOutOfDate=1,name='Embed and sign platform-specific cores')
projectSettings={'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','CLANG_ENABLE_OBJC_ARC':'YES','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES'}
targetSettings={'PRODUCT_BUNDLE_IDENTIFIER':'local.uncleed.mobile','PRODUCT_NAME':'Uncle Ed','INFOPLIST_FILE':'Resources/Info.plist','SWIFT_OBJC_BRIDGING_HEADER':'Sources/Runtime/Bridge.h','HEADER_SEARCH_PATHS':['$(inherited)','$(SRCROOT)/../Sources','$(SRCROOT)/Sources/Runtime'],'TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':os.environ.get('UNCLEED_APPLE_TEAM',''),'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'ENABLE_USER_SCRIPT_SANDBOXING':'NO','SUPPORTS_MACCATALYST':'NO','MARKETING_VERSION':'0.11.0','CURRENT_PROJECT_VERSION':'11','OTHER_CFLAGS':['$(inherited)','-Wno-deprecated-declarations'],'SWIFT_EMIT_LOC_STRINGS':'YES'}
def configs(prefix,settings):
 ids=[]
 for name in ['Debug','Release']:
  setting=settings.copy();setting['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if name=='Debug' else '-O'
  if name=='Debug': setting['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
  ids.append(add(prefix+name,isa='XCBuildConfiguration',name=name,buildSettings=setting))
 return add(prefix+'configs',isa='XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target=add('target',isa='PBXNativeTarget',name='UncleEd-iOS',productName='Uncle Ed',productReference=product,productType='com.apple.product-type.application',buildPhases=[sources,frameworks,resources,embed],buildRules=[],dependencies=[],buildConfigurationList=configs('target',targetSettings),packageProductDependencies=[zipProduct])
proj=add('project',isa='PBXProject',attributes={'LastUpgradeCheck':'1600','TargetAttributes':{target:{'CreatedOnToolsVersion':'16.0'}}},buildConfigurationList=configs('project',projectSettings),compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['en','zh-Hans','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target],packageReferences=[package])
def serialize(v,level=0):
 if isinstance(v,dict):return '{\n'+''.join('\t'*(level+1)+json.dumps(str(k))+ ' = '+serialize(x,level+1)+';\n' for k,x in v.items())+'\t'*level+'}'
 if isinstance(v,list):return '( '+', '.join(serialize(x,level+1) for x in v)+' )'
 if isinstance(v,int):return str(v)
 return json.dumps(v,ensure_ascii=False)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':proj})+'\n')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Uncle Ed.app" BlueprintName="UncleEd-iOS" ReferencedContainer="container:UncleEd.xcodeproj"/>'
(scheme/'UncleEd-iOS.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
info={'CFBundleDisplayName':'Uncle Ed','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName':'Uncle Ed','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UIRequiresFullScreen':True,'UIViewControllerBasedStatusBarAppearance':True,'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UISupportedInterfaceOrientations':['UIInterfaceOrientationLandscapeRight','UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft'],'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'UIFileSharingEnabled':True,'LSSupportsOpeningDocumentsInPlace':True}
(root/'Resources/Info.plist').write_bytes(plistlib.dumps(info))
images=root/'Resources/Images.xcassets';images.mkdir(parents=True,exist_ok=True);(images/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}));icon=images/'AppIcon.appiconset';icon.mkdir(exist_ok=True);import shutil;
# Icon is exported to 1024px by prepare-assets.swift; keep an existing prepared icon.
if not (icon/'Icon.png').exists(): shutil.copyfile(root/'../Assets/Branding/UncleED-Icon.png',icon/'Icon.png')
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'Icon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}))
