Attribute VB_Name = "PIT_Survivorship_v2"
'=====================================================================
'  POINT-IN-TIME (SURVIVORSHIP-FREE) UNIVERSE + DATA PULLER  -- v2
'  SGX Multi-Factor FYP
'
'  CHANGES VS v1:
'    - MAX_WAIT 60 -> 120s  (BDH often hadn't finished loading at 60s,
'      which is why ~5 still-listed names came back empty)
'    - AUTO-RETRY: after the first pass, every ticker that returned no
'      price data is re-pulled (up to MAX_RETRY times) with double wait.
'      This recovers the timing failures with no manual work.
'    - DIAGNOSTICS sheet: per-ticker row counts + status, so you can
'      see exactly what resolved and document anything that didn't.
'
'  WHAT IT CANNOT DO:
'    Tickers that are genuinely dead (Bloomberg placeholder IDs like
'    2643373D, recycled/alt lines, long-privatized names) return no
'    BDH history under that string no matter how long you wait. Those
'    are listed as "NO DATA" in Diagnostics and need manual ISIN
'    resolution (see note at bottom of the chat).
'
'  ONE-CLICK:  Alt+F8 -> Run_PIT_All   (~8-20 min with retries)
'=====================================================================
Option Explicit

' ----------------------------- CONFIG --------------------------------
Private Const IDX As String = "FSSTI Index"   ' STI. Try "STI Index" if membership won't resolve.
Private Const START_YEAR As Integer = 2001
Private Const END_YEAR As Integer = 2026
Private Const MAX_WAIT As Long = 120          ' seconds to wait per Bloomberg request
Private Const MAX_RETRY As Integer = 2        ' cleanup passes over empty-price tickers

Private Const PX_FIELDS As String = "PX_LAST,TOT_RETURN_INDEX_GROSS_DVDS,CUR_MKT_CAP,PX_TO_BOOK_RATIO,EQY_DVD_YLD_IND,PX_VOLUME"
Private Const FN_FIELDS As String = "PE_RATIO,RETURN_COM_EQY,TOT_DEBT_TO_COM_EQY,PX_TO_BOOK_RATIO"
' ---------------------------------------------------------------------


Public Sub Run_PIT_All()
    Dim t0 As Double: t0 = Timer
    Application.ScreenUpdating = False
    Application.DisplayStatusBar = True
    On Error GoTo fail

    Dim roster As Collection
    Set roster = BuildPITUniverse()
    If roster.Count = 0 Then
        MsgBox "No members returned. Check the terminal is connected and that " & _
               IDX & " resolves with INDX_MWEIGHT_HIST (try 'STI Index').", vbExclamation
        GoTo done
    End If

    PullData roster

    Application.StatusBar = False
    MsgBox "Done in " & Format((Timer - t0) / 60, "0.0") & " min." & vbCrLf & _
           "Roster: " & roster.Count & " tickers." & vbCrLf & _
           "Check the Diagnostics sheet for any ticker still showing NO DATA.", vbInformation
    GoTo done
fail:
    Application.StatusBar = False
    MsgBox "Error " & Err.Number & ": " & Err.Description, vbCritical
done:
    Application.ScreenUpdating = True
End Sub


'--- 1) Build the point-in-time roster (union of all historical members) ---
Private Function BuildPITUniverse() As Collection
    Dim ws As Worksheet: Set ws = FreshSheet("Universe_PIT")
    Dim sc As Worksheet: Set sc = FreshSheet("_pit_scratch")
    Dim seen As Object: Set seen = CreateObject("Scripting.Dictionary")
    Dim yr As Integer, q As Integer, mEnd As Date, dts As String, r As Long, tk As String, a As Variant

    For yr = START_YEAR To END_YEAR
        For q = 1 To 4
            mEnd = QuarterEnd(yr, q)
            If mEnd <= Date Then
                dts = Format(mEnd, "yyyymmdd")
                sc.Cells.ClearContents
                sc.Cells(1, 1).Formula = "=BDS(""" & IDX & """,""INDX_MWEIGHT_HIST"",""END_DATE_OVERRIDE"",""" & dts & """)"
                RefreshCell sc.Cells(1, 1), MAX_WAIT
                r = 1
                Do While Len(Trim(SafeStr(sc.Cells(r, 1).Value))) > 0
                    tk = NormalizeTicker(SafeStr(sc.Cells(r, 1).Value))
                    If Len(tk) > 0 Then
                        If Not seen.Exists(tk) Then
                            seen.Add tk, Array(mEnd, mEnd)
                        Else
                            a = seen(tk): a(1) = mEnd: seen(tk) = a
                        End If
                    End If
                    r = r + 1
                    If r > 200 Then Exit Do
                Loop
                Application.StatusBar = "PIT membership " & yr & " Q" & q & "  |  unique so far: " & seen.Count
            End If
        Next q
    Next yr

    ws.Range("A1:C1").Value = Array("Ticker", "FirstSeen", "LastSeen")
    Dim keys As Variant: keys = seen.Keys
    Dim j As Long
    For j = 0 To seen.Count - 1
        tk = keys(j): a = seen(tk)
        ws.Cells(j + 2, 1).Value = tk
        ws.Cells(j + 2, 2).Value = a(0)
        ws.Cells(j + 2, 3).Value = a(1)
    Next j

    Dim col As New Collection
    For j = 2 To seen.Count + 1
        col.Add SafeStr(ws.Cells(j, 1).Value)
    Next j
    Set BuildPITUniverse = col
End Function


'--- 2) Pull data: pass 1, then auto-retry empty tickers, then diagnostics ---
Private Sub PullData(roster As Collection)
    Dim px As Worksheet: Set px = FreshSheet("PriceData_PIT")
    px.Range("A1:H1").Value = Array("Date", "Ticker", "PX_LAST", "TOT_RET_IDX", "MKT_CAP", "PX_TO_BOOK", "DIV_YIELD", "PX_VOLUME")
    Dim fn As Worksheet: Set fn = FreshSheet("Fundamentals_PIT")
    fn.Range("A1:F1").Value = Array("Date", "Ticker", "PE_RATIO", "ROE", "DEBT_TO_EQ", "PX_TO_BOOK_Q")
    Dim sc As Worksheet: Set sc = FreshSheet("_pit_scratch")

    Dim sD As String: sD = START_YEAR & "0101"
    Dim eD As String: eD = END_YEAR & "1231"
    Dim pxRow As Long: pxRow = 2
    Dim fnRow As Long: fnRow = 2
    Dim diag As Object: Set diag = CreateObject("Scripting.Dictionary")
    Dim i As Long, tk As String, np As Long, nf As Long, np2 As Long, d As Variant
    Dim pass As Integer, retried As Long, j As Long, keys As Variant

    ' PASS 1 ---------------------------------------------------------
    For i = 1 To roster.Count
        tk = roster(i)
        np = PullOne(tk, PX_FIELDS, "M", 6, px, pxRow, sc, sD, eD, MAX_WAIT)
        nf = PullOne(tk, FN_FIELDS, "Q", 4, fn, fnRow, sc, sD, eD, MAX_WAIT)
        diag(tk) = Array(np, nf)
        Application.StatusBar = "Pass 1  " & i & "/" & roster.Count & ":  " & tk & "   (" & np & " px rows)"
    Next i

    ' CLEANUP PASSES (retry tickers with zero price rows, longer wait) -
    For pass = 1 To MAX_RETRY
        retried = 0
        For i = 1 To roster.Count
            tk = roster(i): d = diag(tk)
            If d(0) = 0 Then
                np2 = PullOne(tk, PX_FIELDS, "M", 6, px, pxRow, sc, sD, eD, MAX_WAIT * 2)
                If np2 > 0 Then d(0) = np2: diag(tk) = d
                retried = retried + 1
                Application.StatusBar = "Cleanup " & pass & "  retrying " & tk & "   (" & np2 & " rows)"
            End If
        Next i
        If retried = 0 Then Exit For
    Next pass

    ' DIAGNOSTICS ----------------------------------------------------
    Dim dg As Worksheet: Set dg = FreshSheet("Diagnostics")
    dg.Range("A1:D1").Value = Array("Ticker", "PriceRows", "FundRows", "Status")
    keys = diag.Keys
    For j = 0 To diag.Count - 1
        tk = keys(j): d = diag(tk)
        dg.Cells(j + 2, 1).Value = tk
        dg.Cells(j + 2, 2).Value = d(0)
        dg.Cells(j + 2, 3).Value = d(1)
        dg.Cells(j + 2, 4).Value = IIf(d(0) > 0, "OK", IIf(d(1) > 0, "FUND ONLY - price unresolved", "NO DATA"))
    Next j

    Application.DisplayAlerts = False
    sc.Delete
    Application.DisplayAlerts = True
End Sub


'--- pull ONE BDH block to scratch, append to dst, return rows written (0 = failed) ---
Private Function PullOne(tk As String, fields As String, per As String, nFields As Integer, _
                         dst As Worksheet, ByRef writeRow As Long, sc As Worksheet, _
                         sD As String, eD As String, waitSecs As Long) As Long
    sc.Cells.ClearContents
    sc.Cells(1, 1).Formula = "=BDH(""" & tk & """,""" & fields & """,""" & sD & """,""" & eD & """,""Per=" & per & """,""Days=A"")"
    RefreshCell sc.Cells(1, 1), waitSecs

    Dim lastR As Long: lastR = sc.Cells(sc.Rows.Count, 1).End(xlUp).Row
    If lastR < 2 Then PullOne = 0: Exit Function
    Dim arr As Variant: arr = sc.Range(sc.Cells(1, 1), sc.Cells(lastR, nFields + 1)).Value

    Dim n As Long, r As Long, k As Integer, v As Variant
    For r = 1 To lastR
        If IsDate(arr(r, 1)) Then n = n + 1
    Next r
    If n = 0 Then PullOne = 0: Exit Function

    Dim o() As Variant: ReDim o(1 To n, 1 To nFields + 2)
    Dim idx As Long
    For r = 1 To lastR
        If IsDate(arr(r, 1)) Then
            idx = idx + 1
            o(idx, 1) = arr(r, 1)
            o(idx, 2) = tk
            For k = 1 To nFields
                v = arr(r, 1 + k)
                If IsError(v) Then v = vbNullString
                o(idx, 2 + k) = v
            Next k
        End If
    Next r
    dst.Range(dst.Cells(writeRow, 1), dst.Cells(writeRow + n - 1, nFields + 2)).Value = o
    writeRow = writeRow + n
    PullOne = n
End Function


'--- force Bloomberg refresh, poll until "Requesting Data" clears, then settle ---
Private Sub RefreshCell(c As Range, waitSecs As Long)
    On Error Resume Next
    Application.Run "RefreshAllStaticData"
    On Error GoTo 0
    Application.CalculateFull

    Dim t As Double: t = Timer
    Dim s As String
    Do
        DoEvents
        Application.Wait Now + TimeValue("0:00:01")
        s = SafeStr(c.Value)
    Loop Until (InStr(1, s, "Requesting", vbTextCompare) = 0) Or (Timer - t > waitSecs)
    Application.Wait Now + TimeValue("0:00:01")   ' extra settle so the full array finishes spilling
End Sub


'--- helpers ---
Private Function NormalizeTicker(s As String) As String
    Dim t As String: t = Trim(s)
    NormalizeTicker = ""
    If Len(t) = 0 Then Exit Function
    If t Like "#N/A*" Then Exit Function
    If InStr(1, t, " SP", vbTextCompare) = 0 Then Exit Function
    If InStr(1, t, "Equity", vbTextCompare) = 0 Then t = t & " Equity"
    NormalizeTicker = t
End Function

Private Function SafeStr(v As Variant) As String
    If IsError(v) Then SafeStr = "" Else SafeStr = CStr(v)
End Function

Private Function QuarterEnd(yr As Integer, q As Integer) As Date
    QuarterEnd = DateSerial(yr, q * 3 + 1, 0)
End Function

Private Function FreshSheet(nm As String) As Worksheet
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(nm)
    On Error GoTo 0
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        ws.Name = nm
    Else
        ws.Cells.Clear
    End If
    Set FreshSheet = ws
End Function
