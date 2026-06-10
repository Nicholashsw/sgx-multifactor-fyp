Attribute VB_Name = "Module1_SGX_Bloomberg"
Option Explicit

' =============================================================================
' SGX MULTI-FACTOR FYP — Bloomberg Excel Add-In Data Collection
' NTU EEE Final Year Project
'
' ARCHITECTURE DECISIONS (read before editing)
' ─────────────────────────────────────────────
' 1. BDS universe pull  → RawUniverse sheet, columns A (STI) and C (SGMCNL)
'    BDS returns short tickers like "DBS SP". NormalizeSGXTicker() appends
'    " Equity" and filters out non-SP names. Result stored in Universe sheet.
'
' 2. BDP static fields  → Classification sheet (GICS sector/industry per ticker)
'    BDP is single-cell, one formula per cell, no spill risk.
'
' 3. BDH time-series    → HORIZONTAL layout. Each ticker in PriceData and
'    Fundamentals is placed in a column pair (Date | Value). Tickers advance
'    rightward by COL_STRIDE columns. This ELIMINATES vertical spill overlap
'    which was the root cause of the original "Invalid Security" cascade.
'
' 4. Benchmark          → STI starts at A2, SGMCNL starts at D2.
'    Column C is left blank as a deliberate spill guard.
'
' 5. Risk-free ticker   → ResolveRiskFreeTicker() tests a candidate list with
'    BDP, waits for refresh, reads back results, picks first valid. Never
'    hard-codes a ticker that may or may not be licensed.
'
' 6. One public entry point: Run_All_Bloomberg_SGX()
'    All other routines are Private.
'
' HOW TO RUN
' ──────────
'   Alt+F8 → Run_All_Bloomberg_SGX → OK
'   Bloomberg must be connected and you must be logged in.
'   Full pull (universe ~100 stocks, 2001-present) takes 5-15 minutes.
'
' BLOOMBERG MNEMONICS USED
' ────────────────────────
'   BDS  : INDX_MEMBERS
'   BDP  : GICS_SECTOR_NAME, GICS_INDUSTRY_NAME, PX_LAST (test only)
'   BDH  : PX_LAST, TOT_RETURN_INDEX_GROSS_DVDS, CUR_MKT_CAP,
'           PX_TO_BOOK_RATIO, PE_RATIO, RETURN_COM_EQY,
'           EQY_DVD_YLD_IND, PX_VOLUME
'
' NOTE ON EQY_DVD_YLD_IND vs EQY_DVD_YLD_12M:
'   EQY_DVD_YLD_IND = indicated yield (forward-looking, always live)
'   EQY_DVD_YLD_12M = trailing 12-month yield
'   Both are valid. IND is used here because it is more consistently
'   available in Bloomberg for SGX names.
' =============================================================================

' ── Global constants ─────────────────────────────────────────────────────────
Private Const START_DATE    As String = "01/01/2001"   ' Adjust if needed
Private Const END_DATE      As String = "04/02/2026"   ' Update for re-runs

Private Const INDEX_STI     As String = "STI Index"
Private Const INDEX_SGMC    As String = "SGMCNL Index"

' BDH layout: each (Date|Value) pair occupies 2 columns.
' COL_STRIDE = 2 means tickers are placed at columns 1, 3, 5, 7, ...
' Add 1 blank column between fields for readability: stride = 3
Private Const COL_STRIDE    As Long = 3  ' 2 data cols + 1 gap col per ticker

' Max rows a single BDH series can produce (years * 12 months, with headroom)
' 2001-2026 = 25 years * 12 = 300. Use 350 for safety.
Private Const BDH_MAX_ROWS  As Long = 350

' Module-level: resolved risk-free ticker (set by ResolveRiskFreeTicker)
Private m_rfTicker As String


' =============================================================================
' PUBLIC ENTRY POINT
' =============================================================================

Public Sub Run_All_Bloomberg_SGX()
    ' Safety: confirm Bloomberg Add-In is loaded before proceeding
    If Not BloombergIsLoaded() Then
        MsgBox "Bloomberg Excel Add-In is not loaded." & vbCrLf & _
               "Open Bloomberg Terminal, log in, and ensure the Add-In is active.", _
               vbCritical, "Bloomberg Not Found"
        Exit Sub
    End If

    Dim t0 As Single: t0 = Timer

    Application.ScreenUpdating = False
    Application.DisplayAlerts = False
    Application.Calculation = xlCalculationManual

    ' ── Step 1: Ensure all sheets exist ──────────────────────────────────────
    StatusMsg "Step 1/9 — Creating sheets..."
    SetupSheets
    ClearDataSheets
    WriteLog "SetupSheets", "OK", "All sheets created/cleared"

    ' ── Step 2: Pull raw index members via BDS ───────────────────────────────
    StatusMsg "Step 2/9 — Pulling universe (BDS)..."
    WriteUniverseRaw
    BBRefresh 12
    WriteLog "WriteUniverseRaw", "OK", "BDS formulas placed; refresh waited 12s"

    ' ── Step 3: Normalize tickers → Universe sheet ───────────────────────────
    StatusMsg "Step 3/9 — Normalizing tickers..."
    BuildCleanUniverse
    Dim nTickers As Long
    nTickers = LastRow(Worksheets("Universe"), 1) - 1
    WriteLog "BuildCleanUniverse", "OK", nTickers & " tickers after dedup + filter"

    If nTickers = 0 Then
        MsgBox "No tickers found after normalization." & vbCrLf & _
               "Check RawUniverse sheet — BDS may not have refreshed yet." & vbCrLf & _
               "Wait 30 seconds and re-run.", vbExclamation
        GoTo CleanUp
    End If

    ' ── Step 4: Resolve risk-free ticker ─────────────────────────────────────
    StatusMsg "Step 4/9 — Resolving risk-free ticker..."
    ResolveRiskFreeTicker
    WriteLog "ResolveRiskFreeTicker", IIf(m_rfTicker = "", "WARN", "OK"), _
             IIf(m_rfTicker = "", "No candidate resolved", "Using: " & m_rfTicker)

    ' ── Step 5: Classification (BDP — sector/industry) ───────────────────────
    StatusMsg "Step 5/9 — Writing classification formulas (BDP)..."
    WriteClassificationFormulas
    WriteLog "Classification", "OK", nTickers & " BDP rows written"

    ' ── Step 6: Price + market data (BDH monthly) ────────────────────────────
    StatusMsg "Step 6/9 — Writing price data formulas (BDH monthly)..."
    WritePriceDataFormulas
    WriteLog "PriceData", "OK", "6 metrics * " & nTickers & " tickers"

    ' ── Step 7: Fundamentals (BDH quarterly) ─────────────────────────────────
    StatusMsg "Step 7/9 — Writing fundamentals formulas (BDH quarterly)..."
    WriteFundamentalsFormulas
    WriteLog "Fundamentals", "OK", "3 metrics * " & nTickers & " tickers"

    ' ── Step 8: Benchmark ────────────────────────────────────────────────────
    StatusMsg "Step 8/9 — Writing benchmark formulas..."
    WriteBenchmarkFormulas
    WriteLog "Benchmark", "OK", "STI + SGMCNL"

    ' ── Step 9: Risk-free series ──────────────────────────────────────────────
    StatusMsg "Step 9/9 — Writing risk-free series..."
    WriteRiskFreeFormulas
    WriteLog "RiskFree", IIf(m_rfTicker = "", "WARN", "OK"), m_rfTicker

    ' ── Final Bloomberg refresh ───────────────────────────────────────────────
    StatusMsg "Final Bloomberg refresh (please wait)..."
    Application.Calculation = xlCalculationAutomatic
    BBRefresh 30
    Application.Calculation = xlCalculationManual

CleanUp:
    Application.ScreenUpdating = True
    Application.DisplayAlerts = True
    Application.StatusBar = False
    Application.Calculation = xlCalculationAutomatic

    Dim elapsed As Long: elapsed = CLng(Timer - t0)
    MsgBox "Run complete in " & elapsed & "s." & vbCrLf & vbCrLf & _
           "Tickers found:  " & nTickers & vbCrLf & _
           "Risk-free used: " & IIf(m_rfTicker = "", "NOT RESOLVED — check RiskFree sheet", m_rfTicker) & vbCrLf & vbCrLf & _
           "Next steps:" & vbCrLf & _
           "  1. Wait for Bloomberg to finish pulling data (watch status bar)." & vbCrLf & _
           "  2. Check Log sheet for any WARN entries." & vbCrLf & _
           "  3. Run ExportAllCSV macro to export for Python.", _
           vbInformation, "SGX Bloomberg Pull"
End Sub


' =============================================================================
' HELPER: Bloomberg loaded check
' =============================================================================

Private Function BloombergIsLoaded() As Boolean
    ' Tests whether the Bloomberg Excel Add-In is present by checking
    ' for a known Bloomberg function name in the Application.AddIns collection
    Dim ai As AddIn
    For Each ai In Application.AddIns
        If InStr(1, LCase$(ai.Name), "bloomberg", vbTextCompare) > 0 Then
            If ai.Installed Then
                BloombergIsLoaded = True
                Exit Function
            End If
        End If
    Next ai
    ' Fallback: try calling a Bloomberg function; if it errors Bloomberg is absent
    On Error Resume Next
    Dim testVal As Variant
    testVal = Application.Run("BDP", "DBS SP Equity", "PX_LAST")
    BloombergIsLoaded = (Err.Number = 0)
    Err.Clear
    On Error GoTo 0
End Function


' =============================================================================
' STEP 1: Sheet scaffolding
' =============================================================================

Private Sub SetupSheets()
    Dim names As Variant
    names = Array("RawUniverse", "Universe", "Classification", _
                  "PriceData", "Fundamentals", "Benchmark", "RiskFree", "Log")
    Dim n As Variant
    For Each n In names
        EnsureSheet CStr(n)
    Next n
End Sub

Private Sub EnsureSheet(ByVal sName As String)
    ' Creates sheet if it does not exist; does not touch it if it does
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(sName)
    On Error GoTo 0
    If ws Is Nothing Then
        ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets( _
            ThisWorkbook.Worksheets.Count)).Name = sName
    End If
End Sub

Private Sub ClearDataSheets()
    ' Clears all data sheets but preserves the Log sheet header row
    Dim toClr As Variant
    toClr = Array("RawUniverse", "Universe", "Classification", _
                  "PriceData", "Fundamentals", "Benchmark", "RiskFree")
    Dim n As Variant
    For Each n In toClr
        Worksheets(CStr(n)).Cells.Clear
    Next n
    ' Log: only clear data rows, keep header (row 1)
    With Worksheets("Log")
        If .Cells(2, 1).Value <> "" Then
            Dim lastLogRow As Long
            lastLogRow = .Cells(.Rows.Count, 1).End(xlUp).Row
            If lastLogRow > 1 Then .Rows("2:" & lastLogRow).ClearContents
        End If
    End With
End Sub


' =============================================================================
' STEP 2: Write raw BDS universe formulas
' =============================================================================

Private Sub WriteUniverseRaw()
    ' BDS("STI Index","INDX_MEMBERS") returns a vertical list of short tickers
    ' like "DBS SP", "OCBC SP", etc. — no " Equity" suffix.
    ' We place each index in a separate column so their spill ranges never clash.
    '
    ' CRITICAL: BDS spills DOWNWARD from the formula cell. Column A and column C
    ' are used, with column B left empty as a buffer.

    Dim ws As Worksheet
    Set ws = Worksheets("RawUniverse")

    ' Row 1: labels
    ws.Range("A1").Value = "STI_Raw"
    ws.Range("A1").Font.Bold = True
    ws.Range("C1").Value = "SGMCNL_Raw"
    ws.Range("C1").Font.Bold = True
    ws.Range("B1").Value = "← gap →"

    ' Row 2: BDS formulas
    ' BDS returns only the member names; Bloomberg fills cells below automatically
    ws.Range("A2").Formula = "=BDS(""" & INDEX_STI & """,""INDX_MEMBERS"")"
    ws.Range("C2").Formula = "=BDS(""" & INDEX_SGMC & """,""INDX_MEMBERS"")"
End Sub


' =============================================================================
' STEP 3: Normalize tickers and build clean Universe
' =============================================================================

Private Sub BuildCleanUniverse()
    ' Reads RawUniverse cols A and C, normalises each entry to full Bloomberg ID
    ' format ("DBS SP" → "DBS SP Equity"), deduplicates, filters non-SGX names,
    ' and writes the clean list to Universe sheet.

    Dim wsRaw As Worksheet, wsU As Worksheet
    Set wsRaw = Worksheets("RawUniverse")
    Set wsU   = Worksheets("Universe")

    Dim dict As Object
    Set dict = CreateObject("Scripting.Dictionary")
    dict.CompareMode = vbTextCompare   ' Case-insensitive dedup

    ' Write headers
    wsU.Range("A1").Value = "Ticker"
    wsU.Range("B1").Value = "SourceIndex"
    wsU.Range("A1:B1").Font.Bold = True

    Dim outRow As Long: outRow = 2
    Dim i As Long, raw As String, clean As String

    ' ── Pull STI members (column A) ──────────────────────────────────────────
    For i = 2 To 500   ' BDS for STI will not exceed 50 rows; 500 is safe ceiling
        raw = SafeText(wsRaw.Cells(i, 1))
        If raw = "" Then Exit For
        clean = NormalizeSGXTicker(raw)
        If clean <> "" And Not dict.Exists(clean) Then
            dict.Add clean, "STI"
            wsU.Cells(outRow, 1).Value = clean
            wsU.Cells(outRow, 2).Value = "STI"
            outRow = outRow + 1
        End If
    Next i

    ' ── Pull SGMCNL members (column C) ──────────────────────────────────────
    ' SGMCNL Index (SGX Mid-Cap) contains non-SGX names; filter to " SP " only
    For i = 2 To 1000  ' Mid-cap index can have ~300 names
        raw = SafeText(wsRaw.Cells(i, 3))
        If raw = "" Then Exit For
        clean = NormalizeSGXTicker(raw)
        If clean <> "" And Not dict.Exists(clean) Then
            dict.Add clean, "SGMCNL"
            wsU.Cells(outRow, 1).Value = clean
            wsU.Cells(outRow, 2).Value = "SGMCNL"
            outRow = outRow + 1
        End If
    Next i

    wsU.Columns("A:B").AutoFit
End Sub

Private Function NormalizeSGXTicker(ByVal s As String) As String
    ' Converts raw BDS output to full Bloomberg equity ID.
    '
    ' Rules:
    '   "DBS SP"        → "DBS SP Equity"   (append suffix)
    '   "DBS SP Equity" → "DBS SP Equity"   (already correct)
    '   "D05 SP"        → "D05 SP Equity"   (numeric tickers are valid)
    '   "N2IU SP"       → "N2IU SP Equity"  (REITs have alphanumeric codes)
    '   ""              → ""                (skip blanks)
    '   "STI Index"     → ""                (skip index names)
    '   "DBS HK"        → ""                (non-SGX exchange, skip)
    '   #N/A or errors  → ""                (skip Bloomberg error strings)
    '
    ' SGX equities always contain " SP " in their Bloomberg ID.
    ' Any name without " SP" is not an SGX primary listing and is dropped.

    Dim x As String
    x = Trim(s)

    ' Drop blanks and error strings
    If x = "" Then GoTo ReturnEmpty
    If Left$(x, 1) = "#" Then GoTo ReturnEmpty           ' e.g. #N/A #VALUE!
    If InStr(1, x, "N.A.", vbTextCompare) > 0 Then GoTo ReturnEmpty

    ' Drop index/meta entries Bloomberg sometimes injects
    If InStr(1, UCase$(x), " INDEX", vbTextCompare) > 0 Then GoTo ReturnEmpty
    If InStr(1, UCase$(x), "MEMBER", vbTextCompare) > 0 Then GoTo ReturnEmpty
    If InStr(1, UCase$(x), "CONSTITUENT", vbTextCompare) > 0 Then GoTo ReturnEmpty

    ' ── Already has " Equity" suffix ─────────────────────────────────────────
    If InStr(1, UCase$(x), " EQUITY", vbTextCompare) > 0 Then
        ' Only keep if it's an SGX name (contains " SP ")
        If InStr(1, UCase$(x), " SP ", vbTextCompare) > 0 Then
            NormalizeSGXTicker = x
        End If
        Exit Function
    End If

    ' ── Short form: must contain " SP" to be an SGX name ────────────────────
    '   Reject names like "DBS HK", "SIA SJ" etc.
    If InStr(1, UCase$(x), " SP", vbTextCompare) > 0 Then
        ' Append " Equity"
        NormalizeSGXTicker = x & " Equity"
        Exit Function
    End If

ReturnEmpty:
    NormalizeSGXTicker = ""
End Function


' =============================================================================
' STEP 4: Resolve risk-free ticker
' =============================================================================

Private Sub ResolveRiskFreeTicker()
    ' Tests a list of Singapore short-rate tickers using BDP("ticker","PX_LAST").
    ' Waits for Bloomberg to refresh, then reads back the values.
    ' Uses the first ticker that returns a non-error, non-empty numeric value.
    '
    ' Candidate list (ordered by preference):
    '   SGS3M Index  — MAS 3-month Singapore Government Securities yield
    '   SIBOR3M Index— 3-month SGD SIBOR (legacy, may be discontinued post-2024)
    '   SOR3M Index  — 3-month SGD Swap Offer Rate
    '   MASB3M Index — MAS Bill 3-month
    '   SGDOIS Index — SGD overnight indexed swap (alternative short rate)
    '   MASG3M Index — alternative MAS 3-month field name

    Dim ws As Worksheet
    Set ws = Worksheets("RiskFree")

    Dim candidates As Variant
    candidates = Array( _
        "SGS3M Index", _
        "SIBOR3M Index", _
        "SOR3M Index", _
        "MASB3M Index", _
        "SGDOIS Index", _
        "MASG3M Index" _
    )

    ' Write test block in columns E:F of RiskFree sheet (out of the way)
    Dim testCol As Long: testCol = 5  ' Column E
    ws.Cells(1, testCol).Value = "Candidate"
    ws.Cells(1, testCol + 1).Value = "BDP_Test"
    ws.Cells(1, testCol).Font.Bold = True
    ws.Cells(1, testCol + 1).Font.Bold = True

    Dim i As Long
    For i = LBound(candidates) To UBound(candidates)
        ws.Cells(i + 2, testCol).Value = candidates(i)
        ' BDP returns current last price; non-zero means ticker is valid
        ws.Cells(i + 2, testCol + 1).Formula = _
            "=BDP(""" & candidates(i) & """,""PX_LAST"")"
    Next i

    ' Wait for Bloomberg to resolve
    BBRefresh 10

    ' Read back results and pick first valid ticker
    m_rfTicker = ""
    Dim cellVal As Variant
    For i = LBound(candidates) To UBound(candidates)
        cellVal = ws.Cells(i + 2, testCol + 1).Value
        If Not IsError(cellVal) Then
            If IsNumeric(cellVal) Then
                If CDbl(cellVal) > 0 Then
                    m_rfTicker = CStr(candidates(i))
                    Exit For
                End If
            ElseIf Trim(CStr(cellVal)) <> "" And _
                   Trim(CStr(cellVal)) <> "0" And _
                   Left$(Trim(CStr(cellVal)), 1) <> "#" Then
                m_rfTicker = CStr(candidates(i))
                Exit For
            End If
        End If
    Next i

    ' Log result in column G
    ws.Cells(2, testCol + 2).Value = IIf(m_rfTicker = "", "NONE RESOLVED", "RESOLVED: " & m_rfTicker)
    ws.Cells(2, testCol + 2).Font.Color = IIf(m_rfTicker = "", RGB(192, 0, 0), RGB(0, 128, 0))
End Sub


' =============================================================================
' STEP 5: Classification (BDP — one formula per cell, no spill risk)
' =============================================================================

Private Sub WriteClassificationFormulas()
    Dim wsU As Worksheet, wsC As Worksheet
    Set wsU = Worksheets("Universe")
    Set wsC = Worksheets("Classification")

    ' Headers
    wsC.Range("A1:D1").Value = Array("Ticker", "SourceIndex", "GICS_Sector", "GICS_Industry")
    wsC.Range("A1:D1").Font.Bold = True

    Dim lr As Long: lr = LastRow(wsU, 1)
    Dim i As Long, t As String

    For i = 2 To lr
        t = SafeText(wsU.Cells(i, 1))
        If t = "" Then GoTo NextTicker

        wsC.Cells(i, 1).Value = t
        wsC.Cells(i, 2).Value = SafeText(wsU.Cells(i, 2))

        ' BDP returns a single cell value — no spill, completely safe
        wsC.Cells(i, 3).Formula = "=BDP(""" & t & """,""GICS_SECTOR_NAME"")"
        wsC.Cells(i, 4).Formula = "=BDP(""" & t & """,""GICS_INDUSTRY_NAME"")"

NextTicker:
    Next i

    wsC.Columns("A:D").AutoFit
End Sub


' =============================================================================
' STEP 6: Price data (BDH monthly, HORIZONTAL layout)
' =============================================================================

Private Sub WritePriceDataFormulas()
    ' ── Why horizontal layout? ────────────────────────────────────────────────
    ' The original code placed each BDH formula in the SAME ROW for each metric
    ' (cols B, D, E, F, G, H) with `outRow + 330` vertical stride per ticker.
    ' Problem: BDH returns Date in col N and Value in col N+1. When you place
    ' the formula at B2 and D2 in the same row, both spill downward into the
    ' same rows → Bloomberg reports "Invalid Security" or shows #N/A because
    ' the spill ranges collide.
    '
    ' FIX: Each ticker occupies ONE column group: col 1+offset (Date) and
    ' col 2+offset (Value). Tickers advance rightward. BDH spills downward
    ' within their own two-column territory. No overlaps possible.
    '
    ' Layout:
    '   Row 1 = metric name header
    '   Row 2 = ticker names
    '   Row 3 = "Date" / "Value" sub-headers
    '   Row 4+ = BDH spill (Date | Value)
    '
    ' PriceData sheet: 6 metrics, each in its own column group of 3 (D|V|gap)
    ' Metrics: PX_LAST | TOT_RETURN_INDEX_GROSS_DVDS | CUR_MKT_CAP |
    '          PX_TO_BOOK_RATIO | EQY_DVD_YLD_IND | PX_VOLUME

    Dim wsU As Worksheet, wsP As Worksheet
    Set wsU = Worksheets("Universe")
    Set wsP = Worksheets("PriceData")

    Dim metrics As Variant, mLabels As Variant, mFreq As Variant
    metrics = Array("PX_LAST", "TOT_RETURN_INDEX_GROSS_DVDS", "CUR_MKT_CAP", _
                    "PX_TO_BOOK_RATIO", "EQY_DVD_YLD_IND", "PX_VOLUME")
    mLabels = Array("Price (Last)", "Total Return Index (Gross Dvds)", "Mkt Cap (USD mn)", _
                    "P/B Ratio", "Div Yield Indicated (%)", "Volume")
    ' All monthly
    mFreq = Array("CM", "CM", "CM", "CM", "CM", "CM")

    Dim nMetrics As Long: nMetrics = UBound(metrics) + 1
    Dim lr As Long: lr = LastRow(wsU, 1)
    Dim nTickers As Long: nTickers = lr - 1

    ' ── Each metric gets its own horizontal block ────────────────────────────
    '    Block start column = 1 + m * (nTickers * COL_STRIDE + 2)
    '    Within a block: ticker k starts at col blockStart + k * COL_STRIDE

    Dim m As Long, k As Long
    Dim blockStartCol As Long
    Dim tickerCol As Long, t As String

    ' Row 1: metric section headers (spanning cols for each metric block)
    ' Row 2: "Ticker" labels
    ' Row 3: "Date" / "Value" sub-headers  ← BDH formula goes in row 4

    Const DATA_START_ROW As Long = 4

    For m = 0 To nMetrics - 1
        blockStartCol = 1 + m * (nTickers * COL_STRIDE + 2)

        ' Metric name label in row 1
        wsP.Cells(1, blockStartCol).Value = "◆ " & mLabels(m)
        wsP.Cells(1, blockStartCol).Font.Bold = True
        wsP.Cells(1, blockStartCol).Font.Color = RGB(31, 78, 121)

        ' Separator note
        wsP.Cells(1, blockStartCol + nTickers * COL_STRIDE + 1).Value = "|"

        For k = 0 To nTickers - 1
            t = SafeText(wsU.Cells(k + 2, 1))
            If t = "" Then GoTo NextTickerP

            tickerCol = blockStartCol + k * COL_STRIDE

            ' Row 2: ticker name
            wsP.Cells(2, tickerCol).Value = t
            wsP.Cells(2, tickerCol).Font.Bold = True

            ' Row 3: column sub-headers
            wsP.Cells(3, tickerCol).Value = "Date"
            wsP.Cells(3, tickerCol + 1).Value = metrics(m)
            wsP.Cells(3, tickerCol).Font.Color = RGB(89, 89, 89)
            wsP.Cells(3, tickerCol + 1).Font.Color = RGB(89, 89, 89)

            ' Row 4: BDH formula — spills downward safely
            ' Dir=V  → dates in LEFT column, values in RIGHT column (2-col spill)
            ' Per=CM → calendar month end
            ' Fill=P → carry forward last known value for missing months
            ' Dts=S  → dates returned as serial numbers (avoids text date issues)
            wsP.Cells(DATA_START_ROW, tickerCol).Formula = _
                "=BDH(""" & t & """,""" & metrics(m) & """," & _
                """" & START_DATE & """,""" & END_DATE & """," & _
                """Dir=V"",""Per=" & mFreq(m) & """,""Fill=P"",""Dts=S"")"

NextTickerP:
        Next k
    Next m
End Sub


' =============================================================================
' STEP 7: Fundamentals (BDH quarterly, same horizontal layout)
' =============================================================================

Private Sub WriteFundamentalsFormulas()
    ' Quarterly fields: PE_RATIO, RETURN_COM_EQY, PX_TO_BOOK_RATIO
    ' RETURN_COM_EQY = Bloomberg mnemonic for Return on Common Equity (ROE)
    ' PX_TO_BOOK_RATIO included here at quarterly freq for point-in-time accuracy

    Dim wsU As Worksheet, wsF As Worksheet
    Set wsU = Worksheets("Universe")
    Set wsF = Worksheets("Fundamentals")

    Dim metrics  As Variant: metrics  = Array("PE_RATIO", "RETURN_COM_EQY", "PX_TO_BOOK_RATIO")
    Dim mLabels  As Variant: mLabels  = Array("P/E Ratio", "ROE (Return on Common Equity)", "P/B Ratio (Quarterly)")

    Dim nMetrics As Long: nMetrics = UBound(metrics) + 1
    Dim lr As Long: lr = LastRow(wsU, 1)
    Dim nTickers As Long: nTickers = lr - 1

    Const DATA_START_ROW As Long = 4

    Dim m As Long, k As Long
    Dim blockStartCol As Long, tickerCol As Long, t As String

    For m = 0 To nMetrics - 1
        blockStartCol = 1 + m * (nTickers * COL_STRIDE + 2)

        wsF.Cells(1, blockStartCol).Value = "◆ " & mLabels(m)
        wsF.Cells(1, blockStartCol).Font.Bold = True
        wsF.Cells(1, blockStartCol).Font.Color = RGB(112, 48, 160)

        For k = 0 To nTickers - 1
            t = SafeText(wsU.Cells(k + 2, 1))
            If t = "" Then GoTo NextTickerF

            tickerCol = blockStartCol + k * COL_STRIDE

            wsF.Cells(2, tickerCol).Value = t
            wsF.Cells(2, tickerCol).Font.Bold = True
            wsF.Cells(3, tickerCol).Value = "Date"
            wsF.Cells(3, tickerCol + 1).Value = metrics(m)
            wsF.Cells(3, tickerCol).Font.Color = RGB(89, 89, 89)
            wsF.Cells(3, tickerCol + 1).Font.Color = RGB(89, 89, 89)

            ' Per=CQ → calendar quarter end
            wsF.Cells(DATA_START_ROW, tickerCol).Formula = _
                "=BDH(""" & t & """,""" & metrics(m) & """," & _
                """" & START_DATE & """,""" & END_DATE & """," & _
                """Dir=V"",""Per=CQ"",""Fill=P"",""Dts=S"")"

NextTickerF:
        Next k
    Next m
End Sub


' =============================================================================
' STEP 8: Benchmark (BDH monthly — two series with explicit spill gap)
' =============================================================================

Private Sub WriteBenchmarkFormulas()
    ' STI PX_LAST  → spills from A2 downward (cols A:B)
    ' Gap column C → deliberately left empty (prevents spill collision)
    ' SGMCNL PX_LAST → spills from D2 downward (cols D:E)
    '
    ' Using PX_LAST for index levels (compute returns in Python).
    ' TOT_RETURN_INDEX_GROSS_DVDS also available for total return comparison.

    Dim ws As Worksheet
    Set ws = Worksheets("Benchmark")

    ' Row 1: labels
    ws.Range("A1").Value = "Date_STI"
    ws.Range("B1").Value = "STI_PX_LAST"
    ws.Range("C1").Value = "← SPILL GUARD — DO NOT USE"
    ws.Range("D1").Value = "Date_SGMCNL"
    ws.Range("E1").Value = "SGMCNL_PX_LAST"
    ws.Range("A1:E1").Font.Bold = True
    ws.Range("C1").Font.Color = RGB(192, 0, 0)
    ws.Range("C1").Font.Italic = True

    ' STI — A2 is formula anchor, spills to A:B
    ws.Range("A2").Formula = _
        "=BDH(""" & INDEX_STI & """,""PX_LAST""," & _
        """" & START_DATE & """,""" & END_DATE & """," & _
        """Dir=V"",""Per=CM"",""Fill=P"",""Dts=S"")"

    ' SGMCNL — D2 is formula anchor, spills to D:E
    ' Column C is the gap. BDH for STI ends at col B. Col C empty. Safe.
    ws.Range("D2").Formula = _
        "=BDH(""" & INDEX_SGMC & """,""PX_LAST""," & _
        """" & START_DATE & """,""" & END_DATE & """," & _
        """Dir=V"",""Per=CM"",""Fill=P"",""Dts=S"")"

    ' Note for Python user
    ws.Range("G1").Value = "NOTE: Compute monthly returns in Python as pct_change() on PX_LAST column."
    ws.Range("G1").Font.Color = RGB(89, 89, 89)
    ws.Range("G1").Font.Italic = True
End Sub


' =============================================================================
' STEP 9: Risk-free series (BDH monthly)
' =============================================================================

Private Sub WriteRiskFreeFormulas()
    Dim ws As Worksheet
    Set ws = Worksheets("RiskFree")

    ' Main data headers in cols A:C
    ws.Range("A1").Value = "Date"
    ws.Range("B1").Value = "RiskFree_Rate"
    ws.Range("C1").Value = "Resolved_Ticker"
    ws.Range("A1:C1").Font.Bold = True

    If m_rfTicker <> "" Then
        ' BDH spills from A2 into A:B (Date | Rate)
        ws.Range("A2").Formula = _
            "=BDH(""" & m_rfTicker & """,""PX_LAST""," & _
            """" & START_DATE & """,""" & END_DATE & """," & _
            """Dir=V"",""Per=CM"",""Fill=P"",""Dts=S"")"
        ' Write resolved ticker as a static note in C2
        ws.Range("C2").Value = m_rfTicker
        ws.Range("C2").Font.Color = RGB(0, 128, 0)
    Else
        ws.Range("A2").Value = "NO RISK-FREE TICKER RESOLVED"
        ws.Range("A2").Font.Color = RGB(192, 0, 0)
        ws.Range("C2").Value = "Try: SGS3M Index / SIBOR3M Index manually in Bloomberg"
    End If
End Sub


' =============================================================================
' UTILITY: Export all sheets to CSV for Python
' =============================================================================

Public Sub ExportAllCSV()
    ' Saves each data sheet as a CSV in the same folder as the workbook.
    ' Run this AFTER Bloomberg has fully refreshed all data.
    ' Python reads these CSVs directly.

    Dim exportSheets As Variant
    exportSheets = Array("Universe", "Classification", "PriceData", _
                         "Fundamentals", "Benchmark", "RiskFree")

    Dim savePath As String
    savePath = ThisWorkbook.Path & Application.PathSeparator

    Application.ScreenUpdating = False
    Application.DisplayAlerts = False

    Dim sName As Variant, ws As Worksheet
    Dim tempWB As Workbook
    Dim savedCount As Long

    For Each sName In exportSheets
        On Error Resume Next
        Set ws = Nothing
        Set ws = Worksheets(CStr(sName))
        On Error GoTo 0

        If Not ws Is Nothing Then
            Set tempWB = Workbooks.Add(xlWBATWorksheet)
            ws.UsedRange.Copy tempWB.Worksheets(1).Range("A1")
            tempWB.SaveAs savePath & CStr(sName) & ".csv", xlCSV
            tempWB.Close SaveChanges:=False
            savedCount = savedCount + 1
        End If
    Next sName

    Application.ScreenUpdating = True
    Application.DisplayAlerts = True

    MsgBox savedCount & " CSV files saved to:" & vbCrLf & savePath, _
           vbInformation, "Export Complete"
End Sub


' =============================================================================
' PRIVATE UTILITIES
' =============================================================================

Private Function LastRow(ws As Worksheet, col As Long) As Long
    LastRow = ws.Cells(ws.Rows.Count, col).End(xlUp).Row
End Function

Private Function SafeText(c As Range) As String
    ' Returns trimmed string from cell, or "" if cell contains an error
    If IsError(c.Value) Then
        SafeText = ""
    ElseIf IsEmpty(c.Value) Then
        SafeText = ""
    Else
        SafeText = Trim(CStr(c.Value))
    End If
End Function

Private Sub StatusMsg(ByVal msg As String)
    Application.StatusBar = msg
    DoEvents
End Sub

Private Sub BBRefresh(ByVal waitSec As Long)
    ' Triggers Bloomberg refresh then waits.
    ' Bloomberg exposes these entry points depending on Add-In version:
    '   "RefreshEntireWorkbook"   — refreshes all BBG formulas in workbook
    '   "RefreshCurrentWorksheet" — refreshes active sheet only
    '   "BloombergUI.RefreshWorkbook" — older API name
    ' We try each in sequence; errors are non-fatal.

    On Error Resume Next
    Application.Run "RefreshEntireWorkbook"
    If Err.Number <> 0 Then
        Err.Clear
        Application.Run "BloombergUI.RefreshWorkbook"
    End If
    If Err.Number <> 0 Then
        Err.Clear
        ' Last fallback: force Excel recalc which triggers Bloomberg add-in
        Application.CalculateFull
    End If
    Err.Clear
    On Error GoTo 0

    Application.Wait Now + TimeSerial(0, 0, waitSec)
    DoEvents
End Sub

Private Sub WriteLog(ByVal step As String, ByVal status As String, ByVal detail As String)
    Dim ws As Worksheet
    Set ws = Worksheets("Log")

    Dim nextRow As Long
    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1
    If nextRow = 2 And ws.Cells(1, 1).Value = "" Then
        ' Write header if log is empty
        ws.Range("A1:D1").Value = Array("Timestamp", "Step", "Status", "Detail")
        ws.Range("A1:D1").Font.Bold = True
    End If

    ws.Cells(nextRow, 1).Value = Format(Now, "yyyy-mm-dd hh:mm:ss")
    ws.Cells(nextRow, 2).Value = step
    ws.Cells(nextRow, 3).Value = status
    ws.Cells(nextRow, 4).Value = detail

    If UCase$(status) = "WARN" Or UCase$(status) = "ERROR" Then
        ws.Cells(nextRow, 3).Font.Color = RGB(192, 0, 0)
    Else
        ws.Cells(nextRow, 3).Font.Color = RGB(0, 128, 0)
    End If
End Sub
