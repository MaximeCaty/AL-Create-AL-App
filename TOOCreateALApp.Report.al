report 51002 "TOO Create AL App"
{
    UsageCategory = Tasks;
    ApplicationArea = All;
    ProcessingOnly = true;

    requestpage
    {
        AboutTitle = 'Teaching tip title';
        AboutText = 'Teaching tip content';
        layout
        {
            area(Content)
            {
                group(App)
                {
                    field(ALFile; ALFileName)
                    {
                        ApplicationArea = All;
                        caption = 'AL Source File';

                        trigger OnDrillDown()
                        var
                            InStr: InStream;
                            OutStr: OutStream;
                        begin
                            UploadIntoStream('AL File', '', '', ALFileName, InStr);

                            if InStr.Length = 0 then
                                Error('No file was uploaded.');

                            ALFileContent.CreateOutStream(OutStr);
                            CopyStream(OutStr, InStr)

                        end;
                    }
                }
            }
        }
    }

    trigger OnPreReport()
    var
        AppBlob: Codeunit "Temp Blob";
        OutStr: OutStream;
        InStr: InStream;
        AppPackaging: Codeunit "TOO Al App Packaging";
        DownloadfileName: Text;
    begin
        // Package App
        AppPackaging.Initialize(CreateGuid(), 'ALProject1', 'Default Publisher', '4.0.0.0');
        AppPackaging.SetExposurePolicy(true, true, true, true);
        AppPackaging.AddDependency('96f3ba5e-7658-441e-8519-43f3eeee787c', 'ECA Base', 'ECA', '25.0.0.0');
        AppPackaging.AddALSourceFile(ALFileName, BlobToText(ALFileContent));
        AppBlob.CreateOutStream(OutStr);
        AppPackaging.PackageApp(OutStr);

        // Download stream
        AppBlob.CreateInStream(InStr);
        DownloadfileName := 'ALProject1.app';
        DownloadFromStream(InStr, '', '', '', DownloadfileName);
    end;

    local procedure BlobToText(var TempBlob: Codeunit "Temp Blob") Cont: Text
    var
        Line: Text;
        InStr: InStream;
        CRLF: Text[2];
    begin
        CRLF[1] := 13;
        CRLF[2] := 10;
        TempBlob.CreateInStream(InStr);
        while not InStr.EOS do begin
            InStr.ReadText(Line);
            Cont += Line;
            if not InStr.EOS then
                Cont += CRLF;
        end;
    end;

    var
        ALFileName: Text;
        ALFileContent: Codeunit "Temp Blob";
}