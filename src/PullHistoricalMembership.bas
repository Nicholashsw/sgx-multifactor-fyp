Attribute VB_Name = "PullHistoricalMembership"
'==============================================================================
' Point-in-time index membership puller  (SGX Multi-Factor FYP)
'
' WHAT IT DOES
'   For each as-of date, asks Bloomberg who was ACTUALLY in the index then
'   (using INDX_MWEIGHT_HIST + END_DATE_OVERRIDE), and writes a tidy
'   (AsOfDate | Index | Ticker | Weight) table to a "Membership" sheet, plus a
'   de-duplicated "MasterUniverse" list. The master list INCLUDES names that
'   later left or were delisted -> that is what removes survivorship bias.
'
' HOW TO USE
'   1. Open this in a Bloomberg-connected Excel (Alt+F11 > File > Import File).
'   2. Set INDEX_TICKERS and the year range below to your indices/period.
'   3. Run PullHistoricalMembership.
'   4. Feed "MasterUniverse" into your existing BDH price pull (the same
'      machinery that built bloombergapi4_fixed) to get PX_LAST /
'      TOT_RETURN_INDEX_GROSS_DVDS etc. for every name, delisted ones included.
'
' NOTES / THINGS TO VERIFY ON YOUR TERMINAL
'   * Index ticker: the Straits Times Index is usually "FSSTI Index" on
'     Bloomberg ("STI Index" may also resolve). Put the exact SGMCNL ticker too.
'   * INDX_MWEIGHT_HIST returns member ticker (col 1) + weight (col 2) as of the
'     override date. INDX_MEMBERS also accepts END_DATE_OVERRIDE on most setups.
'   * Returned tickers may be short form ("DBS SP"); NORMALIZE_TO_EQUITY below
'     appends " Equity" so they match your panel's "DBS SP Equity".
'   * Delisted names: BDH by ticker usually works, but tickers can be reused.
'     For a bulletproof pull, capture each member's FIGI (ID_BB_GLOBAL) at the
'     time and BDH by "/bbgid/<FIGI>". See GetFigisForMaster (optional) below.
'==============================================================================
Option Explicit

' ---- CONFIG -----------------------------------------------------------------
Private Const START_YEAR As Long = 2001
Private Const END_YEAR   As Long = 2025
Private Const SNAPSHOT_MONTH As Long = 12      ' year-end snapshots (12 = Dec)
Private Const SNAPSHOT_DAY   As Long = 31
Private Const MAX_ROWS_PER_PULL As Long = 150  ' generous cap on index size
Private Const REFRESH_TIMEOUT_SEC As Long = 90
Private Const NORMALIZE_TO_EQUITY As Boolean = True

Private Function IndexTickers() As Variant
    ' <-- EDIT THESE to your exact Bloomberg index tickers
    IndexTickers = Array("FSSTI Index", "SGMCNL Index")
End Function
' -----------------------------------------------------------------------------

Public Sub PullHistoricalMembership()
    Dim idx As Variant: idx = IndexTickers()
    Dim wsOut As Worksheet, wsTmp As Worksheet
    Set wsOut = EnsureSheet("Membership")
    Set wsTmp = EnsureSheet("_bbg_tmp")

    wsOut.Cells.Clear
    wsOut.Range("A1:D1").Value = Array("AsOfDate", "Index", "Ticker", "Weight")

    Dim master As Object: Set master = CreateObject("Scripting.Dictionary")
    Dim outRow As Long: outRow = 2
    Dim y As Long, k As Long, r As Long
    Dim asOf As String, f As String, tk As String

    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False

    For y = START_YEAR To END_YEAR
        asOf = Format(DateSerial(y, SNAPSHOT_MONTH, SNAPSHOT_DAY), "yyyymmdd")
        For k = LBound(idx) To UBound(idx)
            wsTmp.Cells.Clear
            ' Historical members + weights as of the override date
            f = "=BDS(""" & idx(k) & """,""INDX_MWEIGHT_HIST""," & _
                """END_DATE_OVERRIDE=" & asOf & """," & _
                """cols=2;rows=" & MAX_ROWS_PER_PULL & """)"
            wsTmp.Range("A1").Formula = f

            Application.Run "RefreshAllStaticData"
            WaitForBloomberg wsTmp, REFRESH_TIMEOUT_SEC

            r = 1
            Do While Len(Trim(CStr(wsTmp.Cells(r, 1).Value))) > 0
                tk = CStr(wsTmp.Cells(r, 1).Value)
                If InStr(1, tk, "#N/A", vbTextCompare) = 0 And _
                   InStr(1, tk, "requesting", vbTextCompare) = 0 Then
                    tk = NormalizeTicker(tk)
                    wsOut.Cells(outRow, 1).Value = DateSerial(y, SNAPSHOT_MONTH, SNAPSHOT_DAY)
                    wsOut.Cells(outRow, 2).Value = idx(k)
                    wsOut.Cells(outRow, 3).Value = tk
                    wsOut.Cells(outRow, 4).Value = wsTmp.Cells(r, 2).Value   ' weight
                    outRow = outRow + 1
                    If Not master.Exists(tk) Then master.Add tk, 1
                End If
                r = r + 1
            Loop
        Next k
    Next y

    ' Write the de-duplicated master universe (survivorship-free)
    Dim wsM As Worksheet: Set wsM = EnsureSheet("MasterUniverse")
    wsM.Cells.Clear
    wsM.Range("A1").Value = "Ticker"
    Dim i As Long: i = 2
    Dim key As Variant
    For Each key In master.Keys
        wsM.Cells(i, 1).Value = key
        i = i + 1
    Next key

    wsTmp.Cells.Clear
    Application.DisplayAlerts = True
    Application.ScreenUpdating = True
    MsgBox "Done." & vbCrLf & _
           (outRow - 2) & " membership rows -> 'Membership'" & vbCrLf & _
           (i - 2) & " unique tickers -> 'MasterUniverse'", vbInformation
End Sub

' Block until no cell on ws shows "Requesting Data" (or timeout elapses).
Private Sub WaitForBloomberg(ws As Worksheet, timeoutSec As Long)
    Dim t0 As Double: t0 = Timer
    Dim s As Double
    Do
        DoEvents
        If ws.UsedRange.Find("*Requesting Data*", LookIn:=xlValues) Is Nothing Then Exit Do
        If Timer - t0 > timeoutSec Then Exit Do            ' give up, move on
        s = Timer: Do While Timer - s < 0.3: DoEvents: Loop ' ~0.3s pause
    Loop
End Sub

Private Function NormalizeTicker(ByVal t As String) As String
    t = Trim(t)
    If NORMALIZE_TO_EQUITY Then
        If InStr(1, t, " Equity", vbTextCompare) = 0 And InStr(1, t, " Index", vbTextCompare) = 0 Then
            t = t & " Equity"
        End If
    End If
    NormalizeTicker = t
End Function

Private Function EnsureSheet(nm As String) As Worksheet
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(nm)
    On Error GoTo 0
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        ws.Name = nm
    End If
    Set EnsureSheet = ws
End Function

'------------------------------------------------------------------------------
' OPTIONAL: capture FIGIs for the master list, so you can BDH delisted names
' robustly by "/bbgid/<FIGI>" instead of by ticker (which can be reused).
' Run AFTER PullHistoricalMembership.
'------------------------------------------------------------------------------
Public Sub GetFigisForMaster()
    Dim wsM As Worksheet: Set wsM = EnsureSheet("MasterUniverse")
    Dim lastRow As Long: lastRow = wsM.Cells(wsM.Rows.Count, 1).End(xlUp).Row
    If lastRow < 2 Then Exit Sub
    wsM.Range("B1").Value = "FIGI"
    Dim i As Long
    Application.Calculation = xlCalculationAutomatic
    For i = 2 To lastRow
        wsM.Cells(i, 2).Formula = "=BDP(""" & wsM.Cells(i, 1).Value & """,""ID_BB_GLOBAL"")"
    Next i
    Application.Run "RefreshAllStaticData"
    WaitForBloomberg wsM, REFRESH_TIMEOUT_SEC
    wsM.Range("B2:B" & lastRow).Value = wsM.Range("B2:B" & lastRow).Value  ' hardcode
    MsgBox "FIGIs pulled for " & (lastRow - 1) & " tickers.", vbInformation
End Sub
