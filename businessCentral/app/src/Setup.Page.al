// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License. See LICENSE in the project root for license information.
page 82560 "ADLSE Setup"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    SourceTable = "ADLSE Setup";
    InsertAllowed = false;
    DeleteAllowed = false;
    Caption = 'Export to Azure Data Lake Storage';

    layout
    {
        area(Content)
        {
            group(Setup)
            {
                Caption = 'Setup';
                group(General)
                {
                    Caption = 'Account';
                    field(StorageType; Rec."Storage Type")
                    {
                        Tooltip = 'Specifies the type of storage type to use.';

                        trigger OnValidate()
                        begin
                            CurrPage.Update(true);
                        end;
                    }
                    field("Tenant ID"; StorageTenantID)
                    {
                        Caption = 'Tenant ID';
                        Tooltip = 'Specifies the tenant ID which holds the app registration as well as the storage account. Note that they have to be on the same tenant.';

                        trigger OnValidate()
                        begin
                            ADLSECredentials.SetTenantID(StorageTenantID);
                        end;
                    }
                }

                group(Account)
                {
                    Caption = 'Azure Data Lake';
                    Editable = AzureDataLake;
                    field(Container; Rec.Container)
                    {
                        Tooltip = 'Specifies the name of the container where the data is going to be uploaded. Please refer to constraints on container names at https://docs.microsoft.com/en-us/rest/api/storageservices/naming-and-referencing-containers--blobs--and-metadata.';
                    }
                    field(AccountName; Rec."Account Name")
                    {
                        Tooltip = 'Specifies the name of the storage account.';
                    }
                }
                group(MSFabric)
                {
                    Caption = 'Microsoft Fabric';
                    Editable = not AzureDataLake;
                    field(Workspace; Rec.Workspace)
                    {
                        Tooltip = 'Specifies the name of the Workspace where the data is going to be uploaded. This can be a name or a GUID.';
                    }
                    field(Lakehouse; Rec.Lakehouse)
                    {
                        Tooltip = 'Specifies the name of the Lakehouse where the data is going to be uploaded. This can be a name or a GUID.';
                    }
                }
                group(Access)
                {
                    Caption = 'App registration';
                    field("Client ID"; ClientID)
                    {
                        Caption = 'Client ID';
                        ExtendedDatatype = Masked;
                        Tooltip = 'Specifies the application client ID for the Azure App Registration that accesses the storage account.';

                        trigger OnValidate()
                        begin
                            ADLSECredentials.SetClientID(ClientID);
                        end;
                    }
                    field("Client secret"; ClientSecret)
                    {
                        Caption = 'Client secret';
                        ExtendedDatatype = Masked;
                        Tooltip = 'Specifies the client secret for the Azure App Registration that accesses the storage account.';

                        trigger OnValidate()
                        begin
                            ADLSECredentials.SetClientSecret(ClientSecret);
                        end;
                    }
                }
                group(Execution)
                {
                    Caption = 'Execution';
                    field(MaxPayloadSize; Rec.MaxPayloadSizeMiB)
                    {
                        Editable = not AzureDataLake;
                        Tooltip = 'Specifies the maximum size of the upload for each block of data in MiBs. A large value will reduce the number of iterations to upload the data but may interfear with the performance of other processes running on this environment.';
                    }

                    field("CDM data format"; Rec.DataFormat)
                    {
                        ToolTip = 'Specifies the format in which to store the exported data in the ''data'' CDM folder. The Parquet format is recommended for storing the data with the best fidelity.';
                    }

                    field("Skip Timestamp Sorting On Recs"; Rec."Skip Timestamp Sorting On Recs")
                    {
                        Enabled = not ExportInProgress;
                        ToolTip = 'Specifies that the records are not sorted as per their row version before exporting them to the lake. Enabling this may interfear with how incremental data is pushed to the lake in subsequent export runs- please refer to the documentation.';
                    }

                    field("Emit telemetry"; Rec."Emit telemetry")
                    {
                        Tooltip = 'Specifies if operational telemetry will be emitted to this extension publisher''s telemetry pipeline. You will have to configure a telemetry account for this extension first.';
                    }
                    field("Translations"; Rec.Translations)
                    {
                        ToolTip = 'Specifies the translations for the enums used in the selected tables.';

                        trigger OnAssistEdit()
                        var
                            Language: Record Language;
                            Languages: Page "Languages";
                            RecRef: RecordRef;
                        begin
                            Languages.LookupMode(true);
                            if Languages.RunModal() = Action::LookupOK then begin
                                Rec.Translations := '';
                                Languages.SetSelectionFilter(Language);
                                RecRef.GetTable(Language);

                                if Language.FindSet() then
                                    repeat
                                        if Language.Code <> '' then
                                            Rec.Translations += Language.Code + ';';
                                    until Language.Next() = 0;
                                //Remove last semicolon
                                Rec.Translations := CopyStr(Rec.Translations, 1, StrLen(Rec.Translations) - 1);
                                CurrPage.Update();
                            end;
                        end;
                    }
                    field("Export Enum as Integer"; Rec."Export Enum as Integer")
                    {
                        ToolTip = 'Specifies if the enums will be exported as integers instead of strings. This is useful if you want to use the enums in Power BI.';
                    }
                    field("Delete Table"; Rec."Delete Table")
                    {
                        ToolTip = 'Specifies if the table will be deleted if a reset of the table is done.';
                        Editable = not AzureDataLake;
                    }
                    field("Check no Deltas exist"; Rec."Check no Deltas exist")
                    {
                        ToolTip = 'Checks when reset export of schedule if there are any deltas on the AzureDataLake still pending';
                    }
                    field("Delivered DateTime"; Rec."Delivered DateTime")
                    {
                        ToolTip = 'Specifies if the column DeliveredDateTime will be added to the CSV export file.';
                    }
                    field("Export Company Database Tables"; Rec."Export Company Database Tables")
                    {
                        ToolTip = 'Specifies the company for the export of the database tables.';
                        Lookup = true;
                    }
                }
            }
            part(Tables; "ADLSE Setup Tables")
            {
                UpdatePropagation = Both;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ExportNow)
            {
                ApplicationArea = All;
                Caption = 'Export';
                Tooltip = 'Starts the export process by spawning different sessions for each table. The action is disabled in case there are export processes currently running, also in other companies.';
                Image = Start;
                Enabled = not ExportInProgress;

                trigger OnAction()
                var
                    ADLSEExecution: Codeunit "ADLSE Execution";
                begin
                    ADLSEExecution.StartExport();
                    CurrPage.Update();
                end;
            }

            action(StopExport)
            {
                ApplicationArea = All;
                Caption = 'Stop export';
                Tooltip = 'Tries to stop all sessions that are exporting data, including those that are running in other companies.';
                Image = Stop;

                trigger OnAction()
                var
                    ADLSEExecution: Codeunit "ADLSE Execution";
                begin
                    ADLSEExecution.StopExport();
                    CurrPage.Update();
                end;
            }
            action(SchemaExport)
            {
                ApplicationArea = All;
                Caption = 'Schema export';
                Tooltip = 'This will export the schema of the tables selected in the setup to the lake. This is a one-time operation and should be done before the first export of data.';
                Image = Start;

                trigger OnAction()
                var
                    ADLSEExecution: Codeunit "ADLSE Execution";
                begin
                    ADLSEExecution.SchemaExport();
                    CurrPage.Update();
                end;
            }
            action(ClearSchemaExported)
            {
                ApplicationArea = All;
                Caption = 'Clear schema export date';
                Tooltip = 'This will clear the schema exported on field. If this is cleared you can change the schema and export it again.';
                Image = ClearLog;

                trigger OnAction()
                var
                    ADLSEExecution: Codeunit "ADLSE Execution";
                begin
                    ADLSEExecution.ClearSchemaExportedOn();
                    CurrPage.Update();
                end;
            }

            action(Schedule)
            {
                ApplicationArea = All;
                Caption = 'Schedule export';
                Tooltip = 'Schedules the export process as a job queue entry.';
                Image = Timesheet;

                trigger OnAction()
                var
                    ADLSEExecution: Codeunit "ADLSE Execution";
                begin
                    ADLSEExecution.ScheduleExport();
                end;
            }

            action(ClearDeletedRecordsList)
            {
                ApplicationArea = All;
                Caption = 'Clear tracked deleted records';
                Tooltip = 'Removes the entries in the deleted record list that have already been exported. This should be done periodically to free up storage space. The codeunit ADLSE Clear Tracked Deletions may be invoked using a job queue entry for the same end.';
                Image = ClearLog;
                Enabled = TrackedDeletedRecordsExist;

                trigger OnAction()
                begin
                    Codeunit.Run(Codeunit::"ADLSE Clear Tracked Deletions");
                    CurrPage.Update();
                end;
            }

            action(DeleteOldRuns)
            {
                ApplicationArea = All;
                Caption = 'Clear execution log';
                Tooltip = 'Removes the history of the export executions. This should be done periodically to free up storage space.';
                Image = History;
                Enabled = OldLogsExist;

                trigger OnAction()
                var
                    ADLSERun: Record "ADLSE Run";
                begin
                    ADLSERun.DeleteOldRuns();
                    CurrPage.Update();
                end;
            }

            action(FixIncorrectData)
            {
                ApplicationArea = All;
                Caption = 'Fix incorrect data';
                Tooltip = 'Fixes incorrect tables and fields in the setup. This should be done if you have deleted some tables and fields and you cannot disable them.';
                Image = Error;

                trigger OnAction()
                var
                    ADLSESetup: Codeunit "ADLSE Setup";
                begin
                    ADLSESetup.FixIncorrectData();
                end;
            }
        }
        area(Navigation)
        {
            action(EnumTranslations)
            {
                ApplicationArea = All;
                Caption = 'Enum translations';
                Tooltip = 'Show the translations for the enums used in the selected tables.';
                Image = Translations;
                RunObject = page "ADLSE Enum Translations";
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                group(Export)
                {
                    ShowAs = SplitButton;
                    actionref(ExportNow_Promoted; ExportNow) { }
                    actionref(StopExport_Promoted; StopExport) { }
                    actionref(SchemaExport_Promoted; SchemaExport) { }
                    actionref(Schedule_Promoted; Schedule) { }
                    actionref(ClearSchemaExported_Promoted; ClearSchemaExported) { }
                }
                actionref(ClearDeletedRecordsList_Promoted; ClearDeletedRecordsList) { }
                actionref(DeleteOldRuns_Promoted; DeleteOldRuns) { }
            }
        }
    }

    var
        AzureDataLake: Boolean;
        ClientSecretLbl: Label 'Secret not shown';
        ClientIdLbl: Label 'ID not shown';

    trigger OnInit()
    begin
        Rec.GetOrCreate();
        ADLSECredentials.Init();
        StorageTenantID := ADLSECredentials.GetTenantID();
        if ADLSECredentials.IsClientIDSet() then
            ClientID := ClientIdLbl;
        if ADLSECredentials.IsClientSecretSet() then
            ClientSecret := ClientSecretLbl;
    end;

    trigger OnAfterGetRecord()
    var
        ADLSEDeletedRecord: Record "ADLSE Deleted Record";
        ADLSECurrentSession: Record "ADLSE Current Session";
        ADLSERun: Record "ADLSE Run";
    begin
        ExportInProgress := ADLSECurrentSession.AreAnySessionsActive();
        TrackedDeletedRecordsExist := not ADLSEDeletedRecord.IsEmpty();
        OldLogsExist := ADLSERun.OldRunsExist();
        UpdateNotificationIfAnyTableExportFailed();
        AzureDataLake := Rec."Storage Type" = Rec."Storage Type"::"Azure Data Lake";
    end;

    var
        ADLSECredentials: Codeunit "ADLSE Credentials";
        TrackedDeletedRecordsExist: Boolean;
        ExportInProgress: Boolean;
        [NonDebuggable]
        StorageTenantID: Text;
        [NonDebuggable]
        ClientID: Text;
        [NonDebuggable]
        ClientSecret: Text;
        OldLogsExist: Boolean;
        FailureNotificationID: Guid;
        ExportFailureNotificationMsg: Label 'Data from one or more tables failed to export on the last run. Please check the tables below to see the error(s).';

    local procedure UpdateNotificationIfAnyTableExportFailed()
    var
        ADLSETable: Record "ADLSE Table";
        ADLSERun: Record "ADLSE Run";
        FailureNotification: Notification;
        Status: enum "ADLSE Run State";
        LastStarted: DateTime;
        ErrorIfAny: Text[2048];
    begin
        if ADLSETable.FindSet() then
            repeat
                ADLSERun.GetLastRunDetails(ADLSETable."Table ID", Status, LastStarted, ErrorIfAny);
                if Status = "ADLSE Run State"::Failed then begin
                    FailureNotification.Message := ExportFailureNotificationMsg;
                    FailureNotification.Scope := NotificationScope::LocalScope;

                    if IsNullGuid(FailureNotificationID) then
                        FailureNotificationID := CreateGuid();
                    FailureNotification.Id := FailureNotificationID;

                    FailureNotification.Send();
                    exit;
                end;
            until ADLSETable.Next() = 0;

        // no failures- recall notification
        if not IsNullGuid(FailureNotificationID) then begin
            FailureNotification.Id := FailureNotificationID;
            FailureNotification.Recall();
            Clear(FailureNotificationID);
        end;
    end;
}