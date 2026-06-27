Attribute VB_Name = "PublicationPulls"
'==============================================================================
' Publication-grade re-pulls for the survivorship-corrected SGX study.
' Run BOTH subs in this order, in your SGX2 workbook:
'   1) PullMembershipQuarterly   -> finer point-in-time membership (caveat 2/3)
'   2) PullPricePanelV2          -> adds BOOK_VAL_PER_SH so book-to-market exists
'                                   for ALL names, delisted included (caveat 1)
' Then send the workbook back.
'==============================================================================
Option Explicit

Private Const REFRESH_TIMEOUT_SEC As Long = 150
Private Const MAX_ROWS_PER_PULL   As Long = 150
Private Const USE_FIGI As Boolean = False

Private Function IndexTickers() As Variant
    IndexTickers = Array("FSSTI Index", "SGMCNL Index")   ' <-- your exact index tickers
End Function

'------------------------------------------------------------------------------
' 1) QUARTERLY membership (Mar/Jun/Sep/Dec ends), 2001..2025.
'    Writes "MembershipQ" and APPENDS any newly-seen tickers to "MasterUniverse"
'    (flagged), so step 2 will pull prices for them too.
'------------------------------------------------------------------------------
Public Sub PullMembershipQuarterly()
    Const START_YEAR As Long = 2001
    Const END_YEAR   As Long = 2025
    Dim idx As Variant: idx = IndexTickers()

    Dim wsOut As Worksheet: Set wsOut = EnsureSheet("MembershipQ")
    Dim wsU As Worksheet:   Set wsU = EnsureSheet("MasterUniverse")
    Dim wsTmp As Worksheet: Set wsTmp = EnsureSheet("_bbg_tmp")

    wsOut.Cells.Clear
    wsOut.Range("A1:D1").Value = Array("AsOfDate", "Index", "Ticker", "Weight")
    Dim outRow As Long: outRow = 2

    ' existing master set (so we can flag genuinely new names)
    Dim known As Object: Set known = CreateObject("Scripting.Dictionary")
    Dim lastU As Long: lastU = wsU.Cells(wsU.Rows.Count, 1).End(xlUp).Row
    Dim u As Long
    For u = 2 To lastU
        Dim t0 As String: t0 = Trim(CStr(wsU.Cells(u, 1).Value))
        If Len(t0) > 0 And Not known.Exists(t0) Then known.Add t0, True
    Next u
    If wsU.Cells(1, 1).Value = "" Then wsU.Range("A1:B1").Value = Array("Ticker", "FIGI")

    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False

    Dim qMonths As Variant: qMonths = Array(3, 6, 9, 12)
    Dim y As Long, qi As Long, k As Long, r As Long
    Dim asOf As String, f As String, tk As String, newCount As Long: newCount = 0

    For y = START_YEAR To END_YEAR
        For qi = 0 To 3
            ' last calendar day of the quarter-end month
            Dim mm As Long: mm = qMonths(qi)
            asOf = Format(DateSerial(y, mm + 1, 0), "yyyymmdd")
            For k = LBound(idx) To UBound(idx)
                wsTmp.Cells.Clear
                f = "=BDS(""" & idx(k) & """,""INDX_MWEIGHT_HIST""," & _
                    """END_DATE_OVERRIDE=" & asOf & """,""cols=2;rows=" & MAX_ROWS_PER_PULL & """)"
                wsTmp.Range("A1").Formula = f
                Application.Run "RefreshAllStaticData"
                WaitForBloomberg wsTmp, REFRESH_TIMEOUT_SEC

                r = 1
                Do While Len(Trim(CStr(wsTmp.Cells(r, 1).Value))) > 0
                    tk = CStr(wsTmp.Cells(r, 1).Value)
                    If InStr(1, tk, "#N/A", vbTextCompare) = 0 And _
                       InStr(1, tk, "requesting", vbTextCompare) = 0 Then
                        tk = NormalizeTicker(tk)
                        wsOut.Cells(outRow, 1).Value = DateSerial(y, mm + 1, 0)
                        wsOut.Cells(outRow, 2).Value = idx(k)
                        wsOut.Cells(outRow, 3).Value = tk
                        wsOut.Cells(outRow, 4).Value = wsTmp.Cells(r, 2).Value
                        outRow = outRow + 1
                        If Not known.Exists(tk) Then
                            known.Add tk, True
                            Dim nu As Long: nu = wsU.Cells(wsU.Rows.Count, 1).End(xlUp).Row + 1
                            wsU.Cells(nu, 1).Value = tk
                            wsU.Cells(nu, 1).Interior.Color = RGB(255, 235, 156)  ' flag NEW
                            newCount = newCount + 1
                        End If
                    End If
                    r = r + 1
                Loop
            Next k
        Next qi
    Next y
    wsTmp.Cells.Clear
    Application.DisplayAlerts = True
    Application.ScreenUpdating = True
    MsgBox "Quarterly membership done." & vbCrLf & _
           (outRow - 2) & " rows -> 'MembershipQ'" & vbCrLf & _
           newCount & " NEW ticker(s) appended to MasterUniverse (highlighted)." & vbCrLf & _
           IIf(newCount > 0, "Re-run step 2 so their prices are pulled.", ""), vbInformation
End Sub

'------------------------------------------------------------------------------
' 2) Price panel WITH BOOK_VAL_PER_SH (so book-to-market = BVPS / PX_LAST).
'    Same robust one-field-at-a-time pull as before.
'------------------------------------------------------------------------------
Public Sub PullPricePanelV2()
    Const START_DT As String = "1/1/2001"
    Const END_DT   As String = "6/30/2026"
    Dim bbgFields As Variant, outHdr As Variant
    bbgFields = Array("PX_LAST", "TOT_RETURN_INDEX_GROSS_DVDS", "CUR_MKT_CAP", _
                      "BOOK_VAL_PER_SH", "EQY_DVD_YLD_IND", "PX_VOLUME", _
                      "PE_RATIO", "RETURN_COM_EQY")
    outHdr = Array("PX_LAST", "TOT_RETURN", "MKT_CAP", "BVPS", _
                   "DIV_YIELD", "PX_VOLUME", "PE_RATIO", "ROE")
    Dim nF As Long: nF = UBound(bbgFields) - LBound(bbgFields) + 1

    Dim wsU As Worksheet:   Set wsU = ThisWorkbook.Worksheets("MasterUniverse")
    Dim lastT As Long:      lastT = wsU.Cells(wsU.Rows.Count, 1).End(xlUp).Row
    Dim wsTmp As Worksheet: Set wsTmp = EnsureSheet("_bbg_tmp")
    Dim wsOut As Worksheet: Set wsOut = EnsureSheet("PricePanel")
    Dim wsC As Worksheet:   Set wsC = EnsureSheet("Classification2")

    wsOut.Cells.Clear
    wsOut.Range("A1").Value = "Date": wsOut.Range("B1").Value = "Ticker"
    Dim j As Long
    For j = 0 To nF - 1: wsOut.Cells(1, 3 + j).Value = outHdr(j): Next j
    Dim outRow As Long: outRow = 2
    wsC.Cells.Clear
    wsC.Range("A1:C1").Value = Array("Ticker", "Sector", "Industry")
    Dim cRow As Long: cRow = 2

    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False

    Dim i As Long, k As Long, r As Long, tk As String, secId As String, f As String
    Dim dRowMap As Object
    For i = 2 To lastT
        tk = Trim(CStr(wsU.Cells(i, 1).Value))
        If Len(tk) = 0 Then GoTo NextI
        If USE_FIGI And Len(Trim(CStr(wsU.Cells(i, 2).Value))) > 0 Then
            secId = "/bbgid/" & Trim(CStr(wsU.Cells(i, 2).Value))
        Else
            secId = tk
        End If
        Set dRowMap = CreateObject("Scripting.Dictionary")
        For k = 0 To nF - 1
            wsTmp.Cells.Clear
            f = "=BDH(""" & secId & ""","""& bbgFields(k) & """,""" & START_DT & _
                """,""" & END_DT & """,""Per=M"",""Fill=P"",""Dts=S"")"
            wsTmp.Range("A1").Formula = f
            Application.Run "RefreshAllStaticData"
            WaitForBloomberg wsTmp, REFRESH_TIMEOUT_SEC
            r = 1
            Do While IsDate(wsTmp.Cells(r, 1).Value)
                Dim dk As Long: dk = CLng(CDate(wsTmp.Cells(r, 1).Value))
                If k = 0 Then
                    wsOut.Cells(outRow, 1).Value = wsTmp.Cells(r, 1).Value
                    wsOut.Cells(outRow, 2).Value = tk
                    wsOut.Cells(outRow, 3).Value = wsTmp.Cells(r, 2).Value
                    If Not dRowMap.Exists(dk) Then dRowMap.Add dk, outRow
                    outRow = outRow + 1
                Else
                    If dRowMap.Exists(dk) Then wsOut.Cells(dRowMap(dk), 3 + k).Value = wsTmp.Cells(r, 2).Value
                End If
                r = r + 1
            Loop
        Next k
        wsC.Cells(cRow, 1).Value = tk
        wsC.Cells(cRow, 2).Formula = "=BDP(""" & secId & """,""GICS_SECTOR_NAME"")"
        wsC.Cells(cRow, 3).Formula = "=BDP(""" & secId & """,""GICS_INDUSTRY_NAME"")"
        cRow = cRow + 1
NextI:
    Next i

    Application.Run "RefreshAllStaticData"
    WaitForBloomberg wsC, REFRESH_TIMEOUT_SEC
    With wsC.Range("A1:C" & (cRow - 1)): .Value = .Value: End With
    wsTmp.Cells.Clear
    Application.DisplayAlerts = True
    Application.ScreenUpdating = True
    MsgBox "PricePanel (with BVPS) done." & vbCrLf & (outRow - 2) & " rows.", vbInformation
End Sub

'--- shared helpers (Private) -------------------------------------------------
Private Sub WaitForBloomberg(ws As Worksheet, timeoutSec As Long)
    Dim t0 As Double: t0 = Timer
    Dim s As Double
    Do
        DoEvents
        If ws.UsedRange.Find("*Requesting Data*", LookIn:=xlValues) Is Nothing Then Exit Do
        If Timer - t0 > timeoutSec Then Exit Do
        s = Timer: Do While Timer - s < 0.3: DoEvents: Loop
    Loop
End Sub

Private Function NormalizeTicker(ByVal t As String) As String
    t = Trim(t)
    If InStr(1, t, " Equity", vbTextCompare) = 0 And InStr(1, t, " Index", vbTextCompare) = 0 Then t = t & " Equity"
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
