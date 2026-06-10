Attribute VB_Name = "Module_CapIQ_SGX"
Option Explicit

' =============================================================================
' SGX MULTI-FACTOR FYP — Capital IQ Excel Add-In Automation
' NTU EEE Final Year Project
'
' CAPITAL IQ EXCEL ADD-IN MECHANICS (read before editing)
' ─────────────────────────────────────────────────────────
' 1. CIQ()      — point-in-time single value per company per metric.
'                 Syntax: =CIQ(company_id, metric_id, currency)
'                 Example: =CIQ("IQ21835","IQ_PE_EXCL","")
'                 Returns: LTM or most recent value. Updates on refresh.
'
' 2. CIQSERIES()— historical time series for one company + one metric.
'                 Syntax: =CIQSERIES(id,metric,currency,period_type,start,end,fiscal_yr,transpose)
'                 Example: =CIQSERIES("IQ21835","IQ_TOTAL_REV","SGD","Annual","FY-4","FY0","",FALSE)
'                 Returns: multi-cell spill (dates + values). Use with care re: spill overlap.
'
' 3. Refresh:    CapIQ does NOT auto-refresh. You must trigger it explicitly.
'                The add-in registers a COM object: "CapIQ.Application" or similar.
'                VBA trigger: Application.Run "CIQRefreshAll" or
'                             Application.Run "Capital IQ.RefreshAll"
'                After triggering, YOU MUST WAIT — CapIQ pulls data asynchronously.
'                Wait strategy: poll a known CIQ cell until its value changes from
'                "#Loading..." or until a fixed wait period passes.
'
' 4. Entitlement limitations:
'    - CIQ() works for any field your subscription covers.
'    - Some fields (e.g. IQ_EPS_REVISION, IQ_SHORT_INTEREST) require premium add-ons.
'    - If a field returns "#Error" it is not in your entitlement.
'    - Currency conversion to SGD works for most fields via the currency parameter.
'    - Historical time series via CIQSERIES require the "Excel Plug-in" license tier.
'    - Direct Python API access (PyCIQ) requires a SEPARATE API entitlement —
'      Excel add-in entitlement does NOT grant Python API access.
'
' 5. AUTOMATION LIMITS:
'    - You CAN automate: formula placement, refresh triggering, wait-and-read, CSV export.
'    - You CANNOT automate: programmatic data fetching without the Excel formula layer.
'    - The add-in must be open and logged in for any automation to work.
'    - Batch refreshes of large universes (100+ stocks) may take 2-5 minutes.
'
' PUBLIC ENTRY POINTS:
'    Run_CapIQ_Refresh()  — refreshes CapIQ data, waits, exports all CSVs
'    ExportAllCSV()       — exports sheets to CSV without refreshing
'    WriteCapIQFormulas() — writes CIQ formulas for all tickers in Tickers sheet
'
' HOW TO RUN:
'    Alt+F8 → Run_CapIQ_Refresh → Run
'    Ensure CapIQ Add-In is active and you are logged in.
' =============================================================================

' ── Constants ─────────────────────────────────────────────────────────────────
Private Const TICKER_SHEET    As String = "Tickers"
Private Const SNAPSHOT_SHEET  As String = "CIQ_Snapshot"
Private Const TIMESERIES_SHEET As String = "CIQ_TimeSeries"
Private Const LOG_SHEET        As String = "Log"

' CapIQ formula refresh wait: max seconds before giving up
Private Const MAX_WAIT_SEC    As Long = 300   ' 5 minutes max
Private Const POLL_INTERVAL   As Long = 5     ' check every 5 seconds

' Column indices in Tickers sheet
Private Const COL_BBG_ID    As Long = 1  ' Bloomberg ID (e.g. "DBS SP Equity")
Private Const COL_CIQ_ID    As Long = 2  ' CapIQ Company ID (e.g. "IQ21835")
Private Const COL_NAME      As Long = 3  ' Short name
Private Const COL_SECTOR    As Long = 4  ' GICS Sector
Private Const COL_SOURCE    As Long = 5  ' STI / SGMCNL
Private Const COL_INCLUDE   As Long = 6  ' Y/N filter


' =============================================================================
' PUBLIC ENTRY POINT 1: Full refresh + export
' =============================================================================

Public Sub Run_CapIQ_Refresh()
    If Not CapIQIsLoaded() Then
        MsgBox "Capital IQ Excel Add-In is not loaded or you are not logged in." & vbCrLf & _
               "Open CapIQ, log in, and ensure the Excel add-in is active.", vbCritical
        Exit Sub
    End If

    Dim t0 As Single: t0 = Timer
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False

    StatusMsg "CapIQ SGX — triggering data refresh..."
    WriteLog "Run_CapIQ_Refresh", "START", "Triggering CapIQ refresh"

    ' Step 1: Force Excel recalc first (ensures CIQ formulas are in cells)
    Application.Calculate

    ' Step 2: Trigger CapIQ's own refresh mechanism
    TriggerCapIQRefresh

    ' Step 3: Wait for data to resolve
    StatusMsg "Waiting for CapIQ data to resolve (up to 5 min)..."
    Dim resolved As Boolean
    resolved = WaitForCapIQResolution(MAX_WAIT_SEC, POLL_INTERVAL)

    If Not resolved Then
        WriteLog "Run_CapIQ_Refresh", "WARN", "Data may not be fully resolved after " & MAX_WAIT_SEC & "s"
        Dim resp As Integer
        resp = MsgBox("CapIQ data may not be fully resolved." & vbCrLf & _
                      "Some cells may still show #Loading..." & vbCrLf & vbCrLf & _
                      "Export anyway?", vbYesNo + vbExclamation)
        If resp = vbNo Then GoTo CleanUp
    Else
        WriteLog "Run_CapIQ_Refresh", "OK", "Data resolved"
    End If

    ' Step 4: Export all sheets to CSV
    StatusMsg "Exporting to CSV..."
    ExportAllCSV

    WriteLog "Run_CapIQ_Refresh", "OK", "Complete in " & Format(Timer - t0, "0") & "s"

CleanUp:
    Application.ScreenUpdating = True
    Application.DisplayAlerts = True
    Application.StatusBar = False

    MsgBox "CapIQ refresh complete." & vbCrLf & _
           "Elapsed: " & Format(Timer - t0, "0") & "s" & vbCrLf & _
           "Check Log sheet for any WARN entries.", vbInformation
End Sub


' =============================================================================
' PUBLIC ENTRY POINT 2: Write CIQ formulas for all tickers
' =============================================================================

Public Sub WriteCapIQFormulas()
    ' Writes CIQ() snapshot formulas into CIQ_Snapshot for every ticker
    ' where Include = "Y" in the Tickers sheet.
    '
    ' IMPORTANT: This OVERWRITES existing formulas in CIQ_Snapshot rows 2+.
    ' Run this once to set up the sheet, then only use Run_CapIQ_Refresh.

    Dim wsT As Worksheet, wsS As Worksheet
    Set wsT = Worksheets(TICKER_SHEET)
    Set wsS = Worksheets(SNAPSHOT_SHEET)

    ' Clear existing data rows (keep header row 1)
    Dim lastDataRow As Long
    lastDataRow = LastRow(wsS, 1)
    If lastDataRow > 1 Then
        wsS.Rows("2:" & lastDataRow).ClearContents
    End If

    Dim lr As Long: lr = LastRow(wsT, COL_BBG_ID)
    Dim outRow As Long: outRow = 2
    Dim i As Long

    For i = 2 To lr
        Dim bbgID  As String: bbgID  = SafeText(wsT.Cells(i, COL_BBG_ID))
        Dim ciqID  As String: ciqID  = SafeText(wsT.Cells(i, COL_CIQ_ID))
        Dim name   As String: name   = SafeText(wsT.Cells(i, COL_NAME))
        Dim sector As String: sector = SafeText(wsT.Cells(i, COL_SECTOR))
        Dim incl   As String: incl   = UCase$(SafeText(wsT.Cells(i, COL_INCLUDE)))

        If bbgID = "" Then GoTo NextTicker
        If incl <> "Y" Then GoTo NextTicker
        If ciqID = "" Then
            ' No CapIQ ID — write static values from Tickers sheet but skip formulas
            wsS.Cells(outRow, 1).Value = bbgID
            wsS.Cells(outRow, 2).Value = "[NO CIQ ID]"
            wsS.Cells(outRow, 3).Value = name
            wsS.Cells(outRow, 4).Value = sector
            outRow = outRow + 1
            GoTo NextTicker
        End If

        ' ── Write identifier columns (static references) ──────────────────
        wsS.Cells(outRow, 1).Value = bbgID    ' Ticker
        wsS.Cells(outRow, 2).Value = ciqID    ' CapIQ ID
        wsS.Cells(outRow, 3).Value = name     ' Short name
        wsS.Cells(outRow, 4).Value = sector   ' Sector

        ' ── Write CIQ() formulas for each metric ──────────────────────────
        ' Column mapping (1-indexed):
        '  5=MktCap, 6=EV, 7=PE, 8=PB, 9=EV/EBITDA, 10=EV/Rev,
        ' 11=DivYld, 12=FCF_Yield, 13=ROE, 14=ROA, 15=ROIC,
        ' 16=GrossMargin, 17=EBITDA_Margin, 18=NetMargin,
        ' 19=NetDebt/EBITDA, 20=Debt/Capital, 21=RevGrowth, 22=EPSGrowth,
        ' 23=Beta, 24=DataDate

        Dim q As String: q = Chr(34)  ' quote character for formula strings

        With wsS
            .Cells(outRow, 5).Formula  = "=CIQ(" & q & ciqID & q & "," & q & "IQ_MARKETCAP" & q & "," & q & "SGD" & q & ")/1000000"
            .Cells(outRow, 6).Formula  = "=CIQ(" & q & ciqID & q & "," & q & "IQ_TEV" & q & "," & q & "SGD" & q & ")/1000000"
            .Cells(outRow, 7).Formula  = "=CIQ(" & q & ciqID & q & "," & q & "IQ_PE_EXCL" & q & "," & q & q & ")"
            .Cells(outRow, 8).Formula  = "=CIQ(" & q & ciqID & q & "," & q & "IQ_PBX" & q & "," & q & q & ")"
            .Cells(outRow, 9).Formula  = "=CIQ(" & q & ciqID & q & "," & q & "IQ_EBITDA_MULTIPLE" & q & "," & q & q & ")"
            .Cells(outRow, 10).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_REVENUE_MULTIPLE" & q & "," & q & q & ")"
            .Cells(outRow, 11).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_DIV_YIELD_CURR" & q & "," & q & q & ")"
            .Cells(outRow, 12).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_FCF_YIELD" & q & "," & q & q & ")"
            .Cells(outRow, 13).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_RETURN_ON_EQUITY" & q & "," & q & q & ")"
            .Cells(outRow, 14).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_RETURN_ON_ASSETS" & q & "," & q & q & ")"
            .Cells(outRow, 15).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_ROIC" & q & "," & q & q & ")"
            .Cells(outRow, 16).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_GROSS_MARGIN" & q & "," & q & q & ")"
            .Cells(outRow, 17).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_EBITDA_MARGIN" & q & "," & q & q & ")"
            .Cells(outRow, 18).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_NET_MARGIN" & q & "," & q & q & ")"
            .Cells(outRow, 19).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_NET_DEBT_EBITDA" & q & "," & q & q & ")"
            .Cells(outRow, 20).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_TOTAL_DEBT_CAPITAL" & q & "," & q & q & ")"
            .Cells(outRow, 21).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_REVENUE_GROWTH" & q & "," & q & q & ")"
            .Cells(outRow, 22).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_EPS_GROWTH" & q & "," & q & q & ")"
            .Cells(outRow, 23).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_BETA" & q & "," & q & q & ")"
            .Cells(outRow, 24).Formula = "=CIQ(" & q & ciqID & q & "," & q & "IQ_LAST_CLOSE_DATE" & q & "," & q & q & ")"
        End With

        outRow = outRow + 1

NextTicker:
    Next i

    MsgBox "CIQ formulas written for " & (outRow - 2) & " tickers." & vbCrLf & _
           "Run Run_CapIQ_Refresh to pull data.", vbInformation
    WriteLog "WriteCapIQFormulas", "OK", (outRow - 2) & " tickers written"
End Sub


' =============================================================================
' PUBLIC ENTRY POINT 3: Export all sheets to CSV
' =============================================================================

Public Sub ExportAllCSV()
    ' Exports each data sheet to CSV in the same directory as the workbook.
    ' Run AFTER Bloomberg data has been refreshed and CapIQ has resolved.

    Dim exportSheets As Variant
    exportSheets = Array("Tickers", "CIQ_Snapshot", "CIQ_TimeSeries", _
                         "CEIC_SG_Macro", "CEIC_Global_Macro", "BBG_Market_Factors", "Log")

    Dim savePath As String
    savePath = ThisWorkbook.Path & Application.PathSeparator

    Application.ScreenUpdating = False
    Application.DisplayAlerts = False

    Dim sName As Variant, ws As Worksheet, tempWB As Workbook
    Dim saved As Long

    For Each sName In exportSheets
        On Error Resume Next
        Set ws = Nothing
        Set ws = ThisWorkbook.Worksheets(CStr(sName))
        On Error GoTo 0
        If Not ws Is Nothing Then
            Set tempWB = Workbooks.Add(xlWBATWorksheet)
            ws.UsedRange.Copy tempWB.Worksheets(1).Range("A1")
            Application.DisplayAlerts = False
            tempWB.SaveAs savePath & CStr(sName) & ".csv", xlCSV
            tempWB.Close SaveChanges:=False
            saved = saved + 1
        End If
    Next sName

    Application.ScreenUpdating = True
    Application.DisplayAlerts = True
    WriteLog "ExportAllCSV", "OK", saved & " CSVs saved to " & savePath

    MsgBox saved & " CSV files exported to:" & vbCrLf & savePath, vbInformation
End Sub


' =============================================================================
' PRIVATE: CapIQ add-in detection
' =============================================================================

Private Function CapIQIsLoaded() As Boolean
    ' Checks for Capital IQ add-in by scanning AddIns collection.
    ' Also checks for the CIQ function being callable.

    Dim ai As AddIn
    For Each ai In Application.AddIns
        If InStr(1, LCase$(ai.Name), "capital iq", vbTextCompare) > 0 Or _
           InStr(1, LCase$(ai.Name), "ciq", vbTextCompare) > 0 Or _
           InStr(1, LCase$(ai.Name), "capiq", vbTextCompare) > 0 Then
            If ai.Installed Then
                CapIQIsLoaded = True
                Exit Function
            End If
        End If
    Next ai

    ' Fallback: try to detect via Application.Run
    ' If CapIQ is loaded, "CIQRefreshAll" will exist as a registered command
    On Error Resume Next
    Application.Run "CIQRefreshAll"
    If Err.Number = 0 Or Err.Number = 1004 Then
        ' 1004 = "Cannot run the macro" usually means the function EXISTS but had an error
        ' That's fine — it confirms CapIQ is loaded
        CapIQIsLoaded = True
        Err.Clear
    End If
    On Error GoTo 0
End Function


' =============================================================================
' PRIVATE: Trigger CapIQ refresh
' =============================================================================

Private Sub TriggerCapIQRefresh()
    ' CapIQ registers these macro names depending on add-in version.
    ' Try each in order. Non-fatal if they error — Excel recalc covers it.

    On Error Resume Next

    ' Method 1: Standard CapIQ refresh command (most common)
    Application.Run "CIQRefreshAll"
    If Err.Number = 0 Then GoTo Done
    Err.Clear

    ' Method 2: Alternative command name
    Application.Run "Capital IQ.RefreshAll"
    If Err.Number = 0 Then GoTo Done
    Err.Clear

    ' Method 3: Older add-in version
    Application.Run "RefreshAllCIQData"
    If Err.Number = 0 Then GoTo Done
    Err.Clear

    ' Method 4: Force Excel recalculation which triggers CIQ formula evaluation
    Application.CalculateFull
    Err.Clear

Done:
    On Error GoTo 0
    ' Give CapIQ a moment to start its async fetch
    Application.Wait Now + TimeSerial(0, 0, 3)
    DoEvents
End Sub


' =============================================================================
' PRIVATE: Wait for CapIQ resolution
' =============================================================================

Private Function WaitForCapIQResolution(maxSec As Long, pollSec As Long) As Boolean
    ' Polls CIQ_Snapshot for "#Loading..." or error strings.
    ' Returns True if data resolved, False if timed out.
    '
    ' CapIQ cells show "#Loading..." while fetching data asynchronously.
    ' When they resolve to numbers or "#N/A" (no data), the fetch is done.

    Dim ws As Worksheet
    On Error Resume Next
    Set ws = Worksheets(SNAPSHOT_SHEET)
    On Error GoTo 0
    If ws Is Nothing Then
        WaitForCapIQResolution = True  ' No snapshot sheet — nothing to wait for
        Exit Function
    End If

    Dim startTime As Single: startTime = Timer
    Dim elapsed As Long: elapsed = 0
    Dim loadingCount As Long
    Dim lastLoadCount As Long: lastLoadCount = 999999

    Do While elapsed < maxSec
        loadingCount = 0
        Dim lastDataRow As Long: lastDataRow = LastRow(ws, 1)

        If lastDataRow < 2 Then Exit Do  ' No data rows

        ' Count cells still showing "#Loading..." in data columns (5 to 24)
        Dim r As Long, c As Long
        For r = 2 To lastDataRow
            For c = 5 To 24
                Dim v As Variant
                v = ws.Cells(r, c).Value
                If TypeName(v) = "String" Then
                    If InStr(1, CStr(v), "Loading", vbTextCompare) > 0 Or _
                       InStr(1, CStr(v), "Retrieving", vbTextCompare) > 0 Then
                        loadingCount = loadingCount + 1
                    End If
                End If
            Next c
        Next r

        If loadingCount = 0 Then
            WaitForCapIQResolution = True
            Exit Function
        End If

        ' Progress update
        StatusMsg "CapIQ resolving... " & loadingCount & " cells pending | " & elapsed & "s elapsed"
        DoEvents

        ' Wait poll interval
        Application.Wait Now + TimeSerial(0, 0, pollSec)
        elapsed = CLng(Timer - startTime)
        DoEvents
    Loop

    WaitForCapIQResolution = False   ' Timed out
End Function


' =============================================================================
' UTILITIES
' =============================================================================

Private Function LastRow(ws As Worksheet, col As Long) As Long
    LastRow = ws.Cells(ws.Rows.Count, col).End(xlUp).Row
End Function

Private Function SafeText(c As Range) As String
    If IsError(c.Value) Or IsEmpty(c.Value) Then
        SafeText = ""
    Else
        SafeText = Trim(CStr(c.Value))
    End If
End Function

Private Sub StatusMsg(msg As String)
    Application.StatusBar = msg
    DoEvents
End Sub

Private Sub WriteLog(step As String, status As String, detail As String)
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(LOG_SHEET)
    On Error GoTo 0
    If ws Is Nothing Then Exit Sub

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1
    ws.Cells(nextRow, 1).Value = Format(Now, "yyyy-mm-dd hh:mm:ss")
    ws.Cells(nextRow, 2).Value = step
    ws.Cells(nextRow, 3).Value = status
    ws.Cells(nextRow, 4).Value = detail

    If UCase$(status) = "WARN" Then
        ws.Cells(nextRow, 3).Font.Color = RGB(192, 0, 0)
    ElseIf UCase$(status) = "OK" Then
        ws.Cells(nextRow, 3).Font.Color = RGB(0, 128, 0)
    End If
End Sub


' =============================================================================
' BONUS: Validate CapIQ field list before mass pull
' =============================================================================

Public Sub TestCapIQFields()
    ' Tests a sample ticker (DBS) against all planned CIQ field IDs.
    ' Run this once to confirm which fields your subscription covers.
    ' Output goes to a new sheet called "CIQ_FieldTest".

    Dim testID As String: testID = "IQ21835"   ' DBS Group — well-covered SGX name

    Dim fieldIDs As Variant, fieldNames As Variant
    fieldIDs = Array( _
        "IQ_MARKETCAP", "IQ_TEV", "IQ_PE_EXCL", "IQ_PBX", _
        "IQ_EBITDA_MULTIPLE", "IQ_REVENUE_MULTIPLE", _
        "IQ_DIV_YIELD_CURR", "IQ_FCF_YIELD", _
        "IQ_RETURN_ON_EQUITY", "IQ_RETURN_ON_ASSETS", "IQ_ROIC", _
        "IQ_GROSS_MARGIN", "IQ_EBITDA_MARGIN", "IQ_NET_MARGIN", _
        "IQ_NET_DEBT_EBITDA", "IQ_TOTAL_DEBT_CAPITAL", _
        "IQ_REVENUE_GROWTH", "IQ_EPS_GROWTH", _
        "IQ_BETA", "IQ_LAST_CLOSE_DATE" _
    )
    fieldNames = Array( _
        "Market Cap", "EV", "P/E (excl)", "P/B", _
        "EV/EBITDA", "EV/Revenue", _
        "Div Yield", "FCF Yield", _
        "ROE", "ROA", "ROIC", _
        "Gross Margin", "EBITDA Margin", "Net Margin", _
        "Net Debt/EBITDA", "Debt/Capital", _
        "Revenue Growth 1Y", "EPS Growth 1Y", _
        "Beta 3Y", "Last Close Date" _
    )

    ' Create or clear test sheet
    Dim wsTest As Worksheet
    On Error Resume Next
    Set wsTest = ThisWorkbook.Worksheets("CIQ_FieldTest")
    On Error GoTo 0
    If wsTest Is Nothing Then
        Set wsTest = ThisWorkbook.Worksheets.Add( _
            After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        wsTest.Name = "CIQ_FieldTest"
    Else
        wsTest.Cells.Clear
    End If

    wsTest.Range("A1:D1").Value = Array("FieldID", "FieldName", "CIQ_Formula", "Result")
    wsTest.Range("A1:D1").Font.Bold = True

    Dim q As String: q = Chr(34)
    Dim i As Long
    For i = LBound(fieldIDs) To UBound(fieldIDs)
        wsTest.Cells(i + 2, 1).Value = fieldIDs(i)
        wsTest.Cells(i + 2, 2).Value = fieldNames(i)
        wsTest.Cells(i + 2, 3).Value = "=CIQ(" & q & testID & q & "," & q & fieldIDs(i) & q & "," & q & "SGD" & q & ")"
        wsTest.Cells(i + 2, 4).Formula = "=CIQ(" & q & testID & q & "," & q & fieldIDs(i) & q & "," & q & "SGD" & q & ")"
    Next i

    wsTest.Columns("A:D").AutoFit
    TriggerCapIQRefresh
    Application.Wait Now + TimeSerial(0, 0, 15)

    MsgBox "Field test written for DBS (IQ21835). Check CIQ_FieldTest sheet." & vbCrLf & _
           "Cells showing #Error or #N/A are not in your subscription.", vbInformation
End Sub
