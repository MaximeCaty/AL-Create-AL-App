# Package AL source to .App in AL

Using provided codeunit allow you to "compil" a Business Central extension with given source to an App file that can be published and installed.

## Usage

var
AppPackaging: codeunit "TOO Al App Packaging";

// Create App
AppPackaging.Initialize(CreateGuid(), 'ALProject1', 'Default Publisher', '1.0.0.0');
AppPackaging.SetExposurePolicy(true, true, true, true);
AppPackaging.AddDependency('96f3ba5e-7658-441e-8519-43f3eeee787c', 'MyOtherApp', 'Default Publisher', '1.0.0.0');
AppPackaging.AddALSourceFile(ALFileName, ALFileContent);

// Store App file
TempBlob.CreateOutStream(OutStream);
AppPackaging.PackageApp(OutStream);
// OutStream contains the packaged .app file

## Function Definition

Initialize(AppID: Guid; AppName: Text; AppPublisher: Text; AppVersion: Text)
AddDependency(AppID: Guid; AppName: Text; AppPublisher: Text; AppVersion: Text)
AddPreprocessorSymbol(Symbol: Text)
SetObjectIDRange(MinObjectID: Integer; MaxObjectID: Integer)
SetExposurePolicy(AllowDebugging: Boolean; AllowDownloadingSource: Boolean; IncludeSourceInSymbolFile: Boolean; ApplyToDevExtension: Boolean)
AddALSourceFile(ALSourceFileName: Text; ALSourceFileContent: Text)
PackageApp(var  AppPackageOutStream: OutStream)

## How it work



### .App file format

App file format are basically ZIP file with additionnal header.
The Zip contain metainformation such as as the project name, symboles, and AL source that are compiled in DotNet by Business Central Instance.
The header is composed of a **NAVX** keyword, followed by the **header length**, extension type (V**2** for AL), **package GUID**, the **zip length** and end with another **NAVX** keyword.

### Zip file

Minimum required files for the .app to be recognized by Business Central :
Source AL file (at least one)
SymbolReferences.Json -> contain list of object reference and the al file location inside the zip
NavxManifest.xml -> General app information such as name, publisher, version (transcode of app.json to xml)
MediaIdListing.xml -> External media such as the app logo information and location inside the zip
[Content_Types].xml -> file types informations

## Publish App from AL

Business Central SaaS allow direct publication of App file from AL. 
Use codeunit  "Extension Management";
Method : UploadExtension(InStream; languageID)

Therefore you can package source code and publish and install it directly like this :

// Store App file  
TempBlob.CreateOutStream(OutStream);  
AppPackaging.PackageApp(OutStream);
TempBlob.CreateInStream(InStream);  
// Deploy App 
ExtensionMgt.UploadExtension(InStream; languageID); // LCID i.e. 1033 for en-US
ExtensionMgt.DeployExtension(AppId: Guid; lcid: Integer; IsUIEnabled: Boolean)


