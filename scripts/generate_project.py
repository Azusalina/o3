"""Generate the checked-in Xcode project without third-party project generators."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def ident(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


def add(key, content):
    objects[ident(key)] = content
    return ident(key)


def array(values):
    return "(" + ", ".join(values) + ")"


def file(path, kind):
    return add(path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{path}"; sourceTree = SOURCE_ROOT;')


def phase(key, kind, files):
    builds = [add("build:" + key + f, f"isa = PBXBuildFile; fileRef = {f};") for f in files]
    return add(key, f"isa = {kind}; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;")


def configs(key, settings):
    refs = []
    for name in ["Debug", "Release"]:
        options = dict(settings)
        options["SWIFT_OPTIMIZATION_LEVEL"] = '"-Onone"' if name == "Debug" else '"-O"'
        if name == "Debug":
            options["ENABLE_TESTABILITY"] = "YES"
            options["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = '"DEBUG $(inherited)"'
        text = " ".join(f"{k} = {v};" for k, v in options.items())
        refs.append(add(key + name, f"isa = XCBuildConfiguration; buildSettings = {{ {text} }}; name = {name};"))
    return add(key + "configs", f"isa = XCConfigurationList; buildConfigurations = {array(refs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")


swift = [file(str(p.relative_to(ROOT)), "sourcecode.swift") for p in sorted((ROOT / "RawDenoise").glob("*.swift"))]
model = file("RawDenoise/Models/RawForgeSuperLight.mlpackage", "folder.mlpackage")
license_ref = file("RawDenoise/RawForge-LICENSE.txt", "text")
info_ref = file("RawDenoise/Info.plist", "text.plist.xml")
test = file("Tests/RawDenoiseTests.swift", "sourcecode.swift")
fixture = file("Tests/Fixtures/rawforge-reference.f32", "file")
app_product = add("appproduct", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = RawDenoise.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add("testproduct", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = RawDenoiseTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f"isa = PBXGroup; children = {array([app_product, test_product])}; name = Products; sourceTree = \"<group>\";")
group = add("main", f"isa = PBXGroup; children = {array(swift + [model, license_ref, info_ref, test, fixture, products])}; sourceTree = \"<group>\";")
common = {"IPHONEOS_DEPLOYMENT_TARGET": "18.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
          "TARGETED_DEVICE_FAMILY": '"1,2"', "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES"}
project_config = configs("project", common)
app_config = configs("app", {"PRODUCT_BUNDLE_IDENTIFIER": "com.example.RawDenoise", "PRODUCT_NAME": '"$(TARGET_NAME)"',
                             "INFOPLIST_FILE": "RawDenoise/Info.plist", "CODE_SIGN_STYLE": "Automatic",
                             "SWIFT_EMIT_LOC_STRINGS": "YES", "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"'})
test_config = configs("test", {"PRODUCT_BUNDLE_IDENTIFIER": "com.example.RawDenoiseTests", "PRODUCT_NAME": '"$(TARGET_NAME)"',
                               "GENERATE_INFOPLIST_FILE": "YES", "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/RawDenoise.app/RawDenoise"',
                               "BUNDLE_LOADER": '"$(TEST_HOST)"', "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @loader_path/Frameworks"'})
app_phases = [phase("appsource", "PBXSourcesBuildPhase", swift + [model]), phase("appresource", "PBXResourcesBuildPhase", [license_ref]), phase("appframeworks", "PBXFrameworksBuildPhase", [])]
test_phases = [phase("testsource", "PBXSourcesBuildPhase", [test]), phase("testframeworks", "PBXFrameworksBuildPhase", []), phase("testresources", "PBXResourcesBuildPhase", [fixture])]
app_target = add("apptarget", f'isa = PBXNativeTarget; buildConfigurationList = {app_config}; buildPhases = {array(app_phases)}; buildRules = (); dependencies = (); name = RawDenoise; productName = RawDenoise; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy = add("proxy", f"isa = PBXContainerItemProxy; containerPortal = {ident('project')}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = RawDenoise;")
dependency = add("dependency", f"isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};")
test_target = add("testtarget", f'isa = PBXNativeTarget; buildConfigurationList = {test_config}; buildPhases = {array(test_phases)}; buildRules = (); dependencies = ({dependency}); name = RawDenoiseTests; productName = RawDenoiseTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
project = add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {test_target} = {{ TestTargetID = {app_target}; }}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({app_target}, {test_target});')
destination = ROOT / "RawDenoise.xcodeproj"
destination.mkdir(exist_ok=True)
lines = ["// !$*UTF8*$!", "{", "archiveVersion = 1;", "classes = {};", "objectVersion = 56;", "objects = {"]
lines += [f"{key} = {{ {value} }};" for key, value in objects.items()]
lines += ["};", f"rootObject = {project};", "}"]
(destination / "project.pbxproj").write_text("\n".join(lines) + "\n")
schemes = destination / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)


def reference(target, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:RawDenoise.xcodeproj"/>'


app_ref = reference(app_target, "RawDenoise", "RawDenoise.app")
test_ref = reference(test_target, "RawDenoiseTests", "RawDenoiseTests.xctest")
(schemes / "RawDenoise.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(destination)
