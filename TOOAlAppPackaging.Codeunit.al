codeunit 51005 "TOO Al App Packaging"
{
    /*
        This codeunit offer packaging of .app file given AL source code

        Usage :

        // Package App
        AppPackaging.Initialize(CreateGuid(), 'ALProject1', 'Default Publisher', '1.0.0.0');
        AppPackaging.SetExposurePolicy(true, true, true, true);
        AppPackaging.AddDependency('96f3ba5e-7658-441e-8519-43f3eeee787c', 'MyOtherApp', 'Default Publisher', '1.0.0.0');
        AppPackaging.AddALSourceFile(ALFileName, ALFileContent);
        TempBlob.CreateOutStream(OutStream);
        AppPackaging.PackageApp(OutStream);
        // OutStream contains the packaged .app file

    */
    procedure Initialize(AppID: Guid; AppName: Text; AppPublisher: Text; AppVersion: Text)
    begin
        ClearAll();
        this.AppID := AppID;
        this.AppName := AppName;
        this.AppPublisher := AppPublisher;
        this.AppVersion := AppVersion;
        AllowDebugging := true;
        AllowDownloadingSource := true;
        IncludeSourceInSymbolFile := true;
        ApplyToDevExtension := false;
    end;

    #region Dependency
    procedure AddDependency(AppID: Guid; AppName: Text; AppPublisher: Text; AppVersion: Text)
    begin
        if IsNullGuid(AppID) or (AppName = '') or (AppPublisher = '') or (AppVersion = '') then
            Error('AppId, AppName, AppPublisher and AppVersion must be set before adding a dependency.');

        DependenciesID.Add(AppID);
        DependenciesName.Add(AppName);
        DependenciesPublisher.Add(AppPublisher);
        DependenciesVersion.Add(AppVersion);
    end;
    #endregion

    procedure AddPreprocessorSymbol(Symbol: Text)
    begin
        if Symbol = '' then
            Error('Preprocessor symbol must not be empty.');
        PreprocessorSymbols.Add(Symbol);
    end;

    procedure SetExposurePolicy(AllowDebugging: Boolean; AllowDownloadingSource: Boolean; IncludeSourceInSymbolFile: Boolean; ApplyToDevExtension: Boolean)
    begin
        this.AllowDebugging := AllowDebugging;
        this.AllowDownloadingSource := AllowDownloadingSource;
        this.IncludeSourceInSymbolFile := IncludeSourceInSymbolFile;
        this.ApplyToDevExtension := ApplyToDevExtension;
    end;

    procedure SetObjectIDRange(MinObjectID: Integer; MaxObjectID: Integer)
    begin
        // Optional - automatically determined from AL source files
        if MinObjectID <= 0 then
            Error('MinObjectID must be greater than 0.');
        if MaxObjectID <= 0 then
            Error('MaxObjectID must be greater than 0.');
        if MinObjectID > MaxObjectID then
            Error('MinObjectID must be less than or equal to MaxObjectID.');
        this.MinObjectID := MinObjectID;
        this.MaxObjectID := MaxObjectID;
    end;

    #region AL File
    procedure AddALSourceFile(ALSourceFileName: Text; ALSourceFileContent: Text)
    var
        ALObjectName: Text;
        ALObjectID: Integer;
        Regex: Codeunit Regex;
        RegexOption: Record "Regex Options";
        RegexMatch: List of [Text];
        TypeStr: Text;
        Pattern: Text;
        StartAt: Integer;
    begin
        ALSourceFilesName.Add(ALSourceFileName);
        ALSourceFilesContent.Add(ALSourceFileContent);
        // Retrieve object type, id and name from source content
        // Pattern to match the object definition, skipping potential leading whitespace/comments roughly
        RegexOption.IgnoreCase := true;
        RegexOption.Multiline := true;
        Pattern := '\s*(table|report|codeunit|xmlport|menusuite|page|query|pageextension|tableextension|enum|enumextension|permissionset|permissionsetextension|reportextension|interface|controladdin)\s+(\d+)\s+(?:"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))';
        Regex.Split(ALSourceFileContent, Pattern, RegexOption, RegexMatch);
        // Shall return 1 match with 3 groups:
        // 1: Type (table, report, etc.)
        // 2: Object ID (integer)
        // 3: Object Name (quoted or unquoted)
        if RegexMatch.Count() > 4 then
            StartAt := 2
        else
            StartAt := 1; // No leading content, start at first match

        if RegexMatch.Count() > 3 then begin
            TypeStr := LowerCase(RegexMatch.Get(StartAt)); // Normalize to lowercase
            case TypeStr of
                'table':
                    ALObjectType := ALObjectType::"Table";
                'report':
                    ALObjectType := ALObjectType::Report;
                'codeunit':
                    ALObjectType := ALObjectType::Codeunit;
                'xmlport':
                    ALObjectType := ALObjectType::XMLport;
                'menusuite':
                    ALObjectType := ALObjectType::MenuSuite;
                'page':
                    ALObjectType := ALObjectType::Page;
                'query':
                    ALObjectType := ALObjectType::Query;
                'pageextension':
                    ALObjectType := ALObjectType::PageExtension;
                'tableextension':
                    ALObjectType := ALObjectType::TableExtension;
                'enum':
                    ALObjectType := ALObjectType::Enum;
                'enumextension':
                    ALObjectType := ALObjectType::EnumExtension;
                'permissionset':
                    ALObjectType := ALObjectType::PermissionSet;
                'permissionsetextension':
                    ALObjectType := ALObjectType::PermissionSetExtension;
                'reportextension':
                    ALObjectType := ALObjectType::ReportExtension;
                'controladdin':
                    ALObjectType := ALObjectType::ControlAddin;
                'interface':
                    ALObjectType := ALObjectType::Interface;
                else
                    Error('Unknown AL object type: %1', TypeStr);
            end;
            Evaluate(ALObjectID, RegexMatch.Get(StartAt + 1).Trim());
            ALObjectName := RegexMatch.Get(StartAt + 2).TrimStart('"').TrimEnd('"'); // Remove quotes around name
        end else
            Error('Could not parse AL object from content. Object type, id or name were not found.');

        ALSourceObjectType.Add(ALObjectType);
        ALSourceObjectName.Add(ALObjectName);
        ALSourceObjectID.Add(ALObjectID);

        // Update object ID range
        if MinObjectID = 0 then
            MinObjectID := ALObjectID
        else
            if MinObjectID > ALObjectID then
                MinObjectID := ALObjectID;
        if MaxObjectID = 0 then
            MaxObjectID := ALObjectID
        else
            if MaxObjectID < ALObjectID then
                MaxObjectID := ALObjectID;
    end;
    #endregion

    #region Package
    procedure PackageApp(var AppPackageOutStream: OutStream)
    var
        ZipMgt: Codeunit "Data Compression";
        InStr: InStream;
        Window: Dialog;
        ZipFile: Codeunit "Temp Blob";
        ZipFileOutStr: OutStream;
        ZipFileInStr: InStream;
        AppPackageGuid: Guid;
        GuidBytes: Array[16] of Byte;
        BinaryWriter: codeunit DotNet_BinaryWriter;
        DotNetStream: Codeunit DotNet_Stream;
        DotNetStream2: Codeunit DotNet_Stream;
        MemoryStream: Codeunit DotNet_MemoryStream;
        DotNetArrayByte: Codeunit DotNet_Array;
        i, LowPart, HighPart : Integer;
        ChunkSize, ZipLength : Integer;
        Offset: Integer;
    begin
        // Verify requirements
        if ALSourceFilesName.Count() = 0 then
            Error('There is no AL source file to package.');
        if IsNullGuid(AppID) then
            Error('AppId must be set before creating the .app file.');
        if AppName = '' then
            Error('AppName must be set before creating the .app file.');
        if AppPublisher = '' then
            Error('AppPublisher must be set before creating the .app file.');
        if AppVersion = '' then
            Error('AppVersion must be set before creating the .app file.');
        if GuiAllowed then
            Window.Open('Packaging App file... \ #1############');

        // Create Zip archive
        ZipMgt.CreateZipArchive();

        // [Content_Types].xml
        if GuiAllowed then
            Window.Update(1, 'Creating [Content_Types].xml');
        GetContentTypesXmlFile(InStr);
        ZipMgt.AddEntry(InStr, '[Content_Types].xml');

        // MediaIdListing.xml 
        if GuiAllowed then
            Window.Update(1, 'Creating MediaIdListing.xml');
        GetMediaIdListingXmlFile(InStr);
        ZipMgt.AddEntry(InStr, 'MediaIdListing.xml');

        // NavxManifest.xml
        if GuiAllowed then
            Window.Update(1, 'Creating NavxManifest.xml');
        GetNavxManifestFile(InStr);
        ZipMgt.AddEntry(InStr, 'NavxManifest.xml');

        // AL Files
        for i := 1 to ALSourceFilesName.Count() do begin
            Window.Update(1, 'Writting AL files : ' + ALSourceFilesName.Get(i));
            TextToInStream(ALSourceFilesContent.Get(i), InStr);
            ZipMgt.AddEntry(InStr, 'src/' + ALSourceFilesName.Get(i));
        end;

        // SymbolReference.json
        if GuiAllowed then
            Window.Update(1, 'Creating SymbolReference.json');
        GetSymbolReferenceJsonFile(InStr);
        ZipMgt.AddEntry(InStr, 'SymbolReference.json');

        // Create the ZIP file
        if GuiAllowed then
            Window.Update(1, 'Creating ZIP file');
        ZipFile.CreateOutStream(ZipFileOutStr);
        ZipMgt.SaveZipArchive(ZipFileOutStr);
        ZipFile.CreateInStream(ZipFileInStr);

        // Create NAVX header
        if GuiAllowed then
            Window.Update(1, 'Creating NAVX header');
        AppPackageGuid := CreateGuid();

        MemoryStream.MemoryStream(); // Initialiser
        MemoryStream.GetDotNetStream(DotNetStream);
        BinaryWriter.BinaryWriter(DotNetStream);

        // Write first "NAVX" (4 bytes, UInt32 : 1482047822U)
        BinaryWriter.WriteUInt32(1482047822); // "NAVX" en little-endian

        // Write MetadataSize (UInt32) : Usually fixed 40 bytes
        BinaryWriter.WriteUInt32(40);

        // Write MetadataVersion (UInt32) : 1 for C/AL delta, 2 for AL Extension
        BinaryWriter.WriteUInt32(2);

        // Write the package GUID (16 bytes)
        GuidToByteArray(AppPackageGuid, GuidBytes);
        for i := 1 to 16 do
            BinaryWriter.WriteByte(GuidBytes[i]);

        // Write content length of the zip expressed in bytes (Int64) - split in two Int32 because Int64 is not supported
        SplitBigIntegerToTwoInt32(ZipFileInStr.Length, LowPart, HighPart);
        BinaryWriter.WriteInt32(LowPart);
        BinaryWriter.WriteInt32(HighPart);

        // Write second "NAVX" (4 bytes,UInt32 : 1482047822U)
        BinaryWriter.WriteUInt32(1482047822);
        BinaryWriter.Flush(); // Write into the dotnetstream

        // Paste ZIP content by chunk of 1024
        if GuiAllowed then
            Window.Update(1, 'Merging ZIP file');
        DotNetStream2.FromInStream(ZipFileInStr);
        ChunkSize := 1024; // Taille chunk
        ZipLength := ZipFileInStr.Length();
        Offset := 0;
        while Offset < ZipLength do begin
            DotNetArrayByte.ByteArray(ChunkSize);
            // limit the size of the last chunk
            if Offset + ChunkSize > ZipLength then
                ChunkSize := ZipLength - Offset;
            // Read chunk
            DotNetStream2.Read(DotNetArrayByte, 0, ChunkSize);
            // Write it to the dotnet stream
            DotNetStream.Write(DotNetArrayByte, 0, ChunkSize);
            Offset += ChunkSize;
        end;

        // Write the whole binary result to AL outstream
        BinaryWriter.Flush();
        MemoryStream.WriteTo(AppPackageOutStream);
        BinaryWriter.Close();
        if GuiAllowed then
            Window.Close();
    end;
    #endregion

    #region Create Misc Files

    local procedure GetContentTypesXmlFile(var Result: InStream)
    var
        OutStr: OutStream;
    begin
        Clear(TempBlob);
        TempBlob.CreateOutStream(OutStr);
        OutStr.WriteText('<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="" /><Default Extension="al" ContentType="" /><Default Extension="json" ContentType="" /></Types>');
        TempBlob.CreateInStream(Result);
    end;

    local procedure GetMediaIdListingXmlFile(var Result: InStream)
    var
        OutStr: OutStream;
    begin
        Clear(TempBlob);
        TempBlob.CreateOutStream(OutStr);
        OutStr.WriteText('<MediaIdListing LogoFileName="" LogoId="" xmlns="http://schemas.microsoft.com/navx/2016/mediaidlisting"><MediaSetIds /></MediaIdListing>');
        TempBlob.CreateInStream(Result);
    end;
    #endregion

    #region Manifest File
    local procedure GetNavxManifestFile(var Result: InStream)
    var
        NavxManifestXml: Text;
        OutStr: OutStream;
        i: Integer;
    begin
        NavxManifestXml := '<Package xmlns="http://schemas.microsoft.com/navx/2015/manifest">';
        NavxManifestXml += '<App Id="' + format(AppID).TrimStart('{').TrimEnd('}') + '" Name="' + format(AppName) + '" Publisher="' + format(AppPublisher) + '" Brief="" Description="" Version="' + format(AppVersion) + '" CompatibilityId="0.0.0.0" PrivacyStatement="" EULA="" Help="" HelpBaseUrl="" Url="" Logo="" Platform="25.0.0.0" Application="25.0.0.0" Runtime="14.0" Target="Cloud" ShowMyCode="False" />';
        NavxManifestXml += '<IdRanges>';
        NavxManifestXml += '<IdRange MinObjectId="' + format(MinObjectID) + '" MaxObjectId="' + Format(MaxObjectID) + '" />';
        NavxManifestXml += '</IdRanges>';
        NavxManifestXml += '<Dependencies>';
        if DependenciesID.Count() > 0 then
            for i := 1 to DependenciesID.Count() do
                NavxManifestXml += '<Dependency Id="' + Format(DependenciesID.Get(i)).TrimStart('{').TrimEnd('}') + '" Name="' + DependenciesName.Get(i) + '" Publisher="' + DependenciesPublisher.Get(i) + '" MinVersion="' + DependenciesVersion.Get(i) + '" CompatibilityId="0.0.0.0"/>';
        NavxManifestXml += '</Dependencies>';
        NavxManifestXml += '<InternalsVisibleTo />';
        NavxManifestXml += '<ScreenShots />';
        NavxManifestXml += '<SupportedLocales />';
        NavxManifestXml += '<Features>';
        NavxManifestXml += '<Feature>NOIMPLICITWITH</Feature>';
        NavxManifestXml += '</Features>';
        NavxManifestXml += '<PreprocessorSymbols>';
        if PreprocessorSymbols.Count() > 0 then
            for i := 1 to PreprocessorSymbols.Count() do
                NavxManifestXml += '<PreprocessorSymbol>' + PreprocessorSymbols.Get(i) + '</PreprocessorSymbol>';
        NavxManifestXml += '</PreprocessorSymbols>';
        NavxManifestXml += '<SuppressWarnings />';
        NavxManifestXml += '<ResourceExposurePolicy AllowDebugging="' + formatTrueFalse(allowDebugging) + '" AllowDownloadingSource="' + formatTrueFalse(AllowDownloadingSource) + '" IncludeSourceInSymbolFile="' + formatTrueFalse(IncludeSourceInSymbolFile) + '" ApplyToDevExtension="' + formatTrueFalse(ApplyToDevExtension) + '" />';
        NavxManifestXml += '<KeyVaultUrls />';
        NavxManifestXml += '<Source />';
        NavxManifestXml += '<Build By="AL Language Extension,15.0.1433841" Timestamp="' + Format(CurrentDateTime, 0, 9) + '" CompilerVersion="15.0.21.57627" />';
        NavxManifestXml += '<AlternateIds />';
        NavxManifestXml += '</Package>';
        Clear(TempBlob);
        Tempblob.CreateOutStream(OutStr);
        OutStr.WriteText(NavxManifestXml);
        Tempblob.CreateInStream(Result);
    end;
    #endregion

    #region SymbolRef json
    local procedure GetSymbolReferenceJsonFile(var Result: InStream)
    var
        JsonBaseText: Text;
        JsonCodeunitText: Text;
        JsonReportText: Text;
        JsonReportExtensionText: Text;
        JsonXmlPortText: Text;
        JsonQueryText: Text;
        JsonPageText: Text;
        JsonPageExtensionText: Text;
        JsonTableText: Text;
        JsonTableExtensionText: Text;
        JsonEnumText: Text;
        JsonEnumExtensionText: Text;
        JsonPermissionSetText: Text;
        JsonPermissionSetExtensionText: Text;
        JsonControlAddInText: Text;
        JsonInterfaceText: Text;
        i: Integer;
        Outstr: OutStream;
    begin
        // {"RuntimeVersion":"14.0","Namespaces":[{"Namespaces":[{"Codeunits":[{"ReferenceSourceFileName":"HelloWorld.al","Id":50654,"Name":"CustomerListExtt"},{"ReferenceSourceFileName":"src/HelloWorld.al","Id":50100,"Name":"CustomerListExt"}],"Reports":[],"XmlPorts":[],"Queries":[],"ControlAddIns":[],"EnumTypes":[],"DotNetPackages":[],"Interfaces":[],"PermissionSets":[],"PermissionSetExtensions":[],"ReportExtensions":[],"Name":"ALProject1"}],"Codeunits":[],"Reports":[],"XmlPorts":[],"Queries":[],"ControlAddIns":[],"EnumTypes":[],"DotNetPackages":[],"Interfaces":[],"PermissionSets":[],"PermissionSetExtensions":[],"ReportExtensions":[],"Name":"DefaultPublisher"}],"Codeunits":[],"Reports":[],"XmlPorts":[],"Queries":[],"ControlAddIns":[],"EnumTypes":[],"DotNetPackages":[],"Interfaces":[],"PermissionSets":[],"PermissionSetExtensions":[],"ReportExtensions":[],"InternalsVisibleToModules":[],"AppId":"0b0de19d-f18d-4c1e-82e3-dfd8f7aa59f0","Name":"ALProject1","Publisher":"Default Publisher","Version":"1.0.0.0"}
        JsonBaseText := '{"RuntimeVersion":"14.0","Namespaces":[{"Namespaces":[{"Codeunits":[%5],"Reports":[%6],"XmlPorts":[%7],"Queries":[%8],"ControlAddIns":[%9],"EnumTypes":[%10],"DotNetPackages":[%11],"Interfaces":[%12],"PermissionSets":[%13],"PermissionSetExtensions":[%14],"ReportExtensions":[%15],"Name":"%02"}],"Codeunits":[],"Reports":[],"XmlPorts":[],"Queries":[],"ControlAddIns":[],"EnumTypes":[],"DotNetPackages":[],"Interfaces":[],"PermissionSets":[],"PermissionSetExtensions":[],"ReportExtensions":[],"Name":"DefaultPublisher"}],"Codeunits":[],"Reports":[],"XmlPorts":[],"Queries":[],"ControlAddIns":[],"EnumTypes":[],"DotNetPackages":[],"Interfaces":[],"PermissionSets":[],"PermissionSetExtensions":[],"ReportExtensions":[],"InternalsVisibleToModules":[],"AppId":"%01","Name":"%02","Publisher":"%03","Version":"%04"}';
        for i := 1 to ALSourceFilesName.Count do
            case ALSourceObjectType.Get(i) of
                ALObjectType::Codeunit:
                    JsonCodeunitText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::Report:
                    JsonReportText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::Page:
                    JsonPageText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::PageExtension:
                    JsonPageExtensionText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::Table:
                    JsonTableText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::TableExtension:
                    JsonTableExtensionText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::Enum:
                    JsonEnumText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::EnumExtension:
                    JsonEnumExtensionText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::PermissionSet:
                    JsonPermissionSetText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::PermissionSetExtension:
                    JsonPermissionSetExtensionText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::ReportExtension:
                    JsonReportExtensionText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::XMLport:
                    JsonXmlPortText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::Query:
                    JsonQueryText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::ControlAddin:
                    JsonControlAddInText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                ALObjectType::Interface:
                    JsonInterfaceText += '{"ReferenceSourceFileName": "src/' + ALSourceFilesName.Get(i) + '", "Id": ' + Format(ALSourceObjectID.Get(i)) + ', "Name": "' + ALSourceObjectName.Get(i) + '"},';
                else
                    Error('Object type %1 is not yet supported.', ALSourceObjectType.Get(i));
            end;

        if IsNullGuid(AppID) or (AppName = '') or (AppPublisher = '') or (AppVersion = '') then
            Error('AppId, AppName, AppPublisher and AppVersion must be set before creating the SymbolReference.json file.');

        JsonBaseText := JsonBaseText.Replace('%5', JsonCodeunitText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%6', JsonReportText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%7', JsonXmlPortText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%8', JsonQueryText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%9', JsonControlAddInText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%10', JsonEnumText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%11', ''); // DotNetPackages not supported yet
        JsonBaseText := JsonBaseText.Replace('%12', JsonInterfaceText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%13', JsonPermissionSetText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%14', JsonPermissionSetExtensionText.TrimEnd(','));
        JsonBaseText := JsonBaseText.Replace('%15', JsonReportExtensionText.TrimEnd(','));

        JsonBaseText := JsonBaseText.Replace('%01', Format(AppID).TrimStart('{').TrimEnd('}')); // AppId
        JsonBaseText := JsonBaseText.Replace('%02', AppName); // AppName
        JsonBaseText := JsonBaseText.Replace('%03', AppPublisher); // AppPublisher
        JsonBaseText := JsonBaseText.Replace('%04', AppVersion); // AppVersion

        Clear(TempBlob);
        TempBlob.CreateOutStream(Outstr);
        Outstr.WriteText(JsonBaseText);
        TempBlob.CreateInStream(Result);
    end;
    #endregion


    #region Internal
    local procedure TextToInStream(TextValue: Text; var Result: InStream)
    var
        OutStream: OutStream;
    begin
        clear(TempBlob);
        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(TextValue);
        TempBlob.CreateInStream(Result);
    end;

    local procedure GuidToByteArray(G: Guid; var Bytes: Array[16] of Byte)
    var
        HexStr: Text[32];
        i: Integer;
    begin
        HexStr := DelChr(Format(G, 0, 9), '=', '-{} '); // Obtient '00000000000000000000000000000000' en lowercase
        HexStr := UpperCase(HexStr); // Pour simplifier
        if StrLen(HexStr) <> 32 then
            Error('Invalid GUID format');

        // Ordre .NET ToByteArray : reverse pour Data1 (4 bytes), Data2 (2), Data3 (2), Data4 as is (8)
        // Bytes[1..4] = reverse hex[1..8]
        Bytes[4] := HexToByte(CopyStr(HexStr, 1, 2));
        Bytes[3] := HexToByte(CopyStr(HexStr, 3, 2));
        Bytes[2] := HexToByte(CopyStr(HexStr, 5, 2));
        Bytes[1] := HexToByte(CopyStr(HexStr, 7, 2));

        // Bytes[5..6] = reverse hex[9..12]
        Bytes[6] := HexToByte(CopyStr(HexStr, 9, 2));
        Bytes[5] := HexToByte(CopyStr(HexStr, 11, 2));

        // Bytes[7..8] = reverse hex[13..16]
        Bytes[8] := HexToByte(CopyStr(HexStr, 13, 2));
        Bytes[7] := HexToByte(CopyStr(HexStr, 15, 2));

        // Bytes[9..16] = hex[17..32] as is
        for i := 0 to 7 do
            Bytes[9 + i] := HexToByte(CopyStr(HexStr, 17 + i * 2, 2));
    end;

    local procedure HexToByte(HexPair: Text[2]): Byte
    var
        HighNib: Integer;
        LowNib: Integer;
    begin
        HighNib := GetHexDigitValue(HexPair[1]);
        LowNib := GetHexDigitValue(HexPair[2]);
        exit(HighNib * 16 + LowNib);
    end;

    local procedure GetHexDigitValue(C: Char): Integer
    begin
        if (C >= '0') and (C <= '9') then
            exit(C - '0');
        if (C >= 'A') and (C <= 'F') then
            exit(10 + C - 'A');
        Error('Invalid hex character: %1', C);
    end;

    local procedure SplitBigIntegerToTwoInt32(Value: BigInteger; var Low: Integer; var High: Integer)
    var
        Two32: BigInteger;
        Two31: BigInteger;
        LowBig: BigInteger;
        HighBig: BigInteger;
    begin
        Two32 := 4294967296L;
        Two31 := 2147483648L;

        // Low part (unsigned 32 bits, interpreted as signed Int32)
        LowBig := Value MOD Two32;
        if LowBig >= Two31 then
            Low := LowBig - Two32
        else
            Low := LowBig;

        // High part (next 32 bits)
        HighBig := Value DIV Two32;
        if HighBig >= Two31 then
            High := HighBig - Two32
        else
            High := HighBig;
    end;

    procedure FormatTrueFalse(Value: Boolean): Text
    begin
        if Value then
            exit('true')
        else
            exit('false');
    end;
    #endregion


    var
        AppID: Guid;
        AppName: Text;
        AppPublisher: Text;
        AppVersion: Text;
        ALSourceFilesName: List of [Text];
        ALSourceFilesContent: List of [Text];
        ALSourceObjectType: List of [Integer];
        ALSourceObjectName: List of [Text];
        ALSourceObjectID: List of [Integer];
        DependenciesID: List of [Guid];
        DependenciesName: List of [Text];
        DependenciesPublisher: List of [Text];
        DependenciesVersion: List of [Text];
        PreprocessorSymbols: List of [Text];
        ALObjectType: Option "Table","Report","Codeunit","XMLport",MenuSuite,"Page","Query","PageExtension","TableExtension","Enum","EnumExtension","PermissionSet","PermissionSetExtension","ReportExtension","ControlAddin","Interface";
        MinObjectID: Integer;
        MaxObjectID: Integer;
        AllowDebugging: Boolean;
        AllowDownloadingSource: Boolean;
        IncludeSourceInSymbolFile: Boolean;
        ApplyToDevExtension: Boolean;
        TempBlob: Codeunit "Temp Blob";

}
