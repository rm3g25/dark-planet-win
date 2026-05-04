object Form1: TForm1
  Left = 0
  Top = 0
  Caption = #1058#1105#1084#1085#1072#1103' '#1055#1083#1072#1085#1077#1090#1072
  ClientHeight = 400
  ClientWidth = 640
  Color = clBlack
  DoubleBuffered = True
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  KeyPreview = True
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  OnKeyUp = FormKeyUp
  OnPaint = FormPaint
  TextHeight = 13
  object Timer1: TTimer
    Enabled = False
    Interval = 25
    OnTimer = Timer1Timer
    Left = 16
    Top = 16
  end
end
