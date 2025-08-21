
# Package AL source to .App in AL

Provided codeunit allow you to "compile" a Business Central extension App file, within given AL source code. 
The app can then be published and installed in Business Central (also in AL if you are on SaaS).

Note that this code does not "compile" in a sense that it does NOT verify the source code or validate any information you provide. 
Missing dependency or malformed AL code are not detected and will create an .app file that fail publication.
If you want a proper compilation of AL source with symbol and code verification outside of visual Studio Code, you may use alc.exe command line.
[Check out alc.exe commands](https://dankinsella.blog/business-central-al-compiler/)

## Usage

    var
    AppPackaging: codeunit "TOO Al App Packaging";
    
    // Define App source and infos
    AppPackaging.Initialize(CreateGuid(), 'ALProject1', 'Default Publisher', '1.0.0.0');
    AppPackaging.SetExposurePolicy(true, true, true, true);
    AppPackaging.AddDependency('96f3ba5e-7658-441e-8519-43f3eeee787c', 'MyOtherApp', 'Default Publisher', '1.0.0.0');
    AppPackaging.AddALSourceFile(ALFileName, ALFileContent);
    
    // "Compile" and write the App into an OutStream
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
The Zip contain source code and meta informations such as as the project name, symboles, and file location inside the Zip.
The AL source are compiled to DotNet by Business Central instance when the App file is published.
The header is composed of a **NAVX** keyword, followed by the **header length**, extension type (V**2** for AL), **package GUID**, the **zip length** and end with another **NAVX** keyword.

### Zip file

Minimum required files for the .app to be recognized by Business Central :
- Source AL file (at least one)
- SymbolReferences.Json -> contain list of object reference and the al file location inside the zip
- NavxManifest.xml -> General app information such as name, publisher, version (transcode of app.json to xml)
- MediaIdListing.xml -> External media such as the app logo information and location inside the zip
- [Content_Types].xml -> file types informations

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


