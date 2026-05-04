unit GameMain;

{ ============================================================
  Dark Planet - port from Turbo Pascal / DOS to Delphi VCL
  Original: (C) Computer Dragon, 1998
  ============================================================
  .IMG file format (BGI256 PutImage):
    Word  - (width  - 1)
    Word  - (height - 1)
    Bytes - pixels (palette index, row by row)

  Rendering:
    Instead of DOS-era XOR trick we use double buffering:
    FBack - level background (tiles), redrawn on screen change
    FBuf  - work buffer: background copy + all sprites on top
    Index 0 is treated as transparent (like black background in original)
  ============================================================ }

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Math,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.Dialogs;

const
  GW         = 320;   { game field width in pixels }
  GH         = 200;   { height }
  SC         = 2;     { display scale (320x200 -> 640x400) }
  MaxEnemys  = 5;
  HSprCount  = 28;

  DIR_FW = 'F';  { forward  (original: 'Vpered')  }
  DIR_BW = 'B';  { backward (original: 'Nazad')   }
  DIR_UP = 'U';  { up       (jump)                }
  DIR_DN = 'D';  { down     (fall)                }

  HSprFiles: array[1..HSprCount] of string = (
    'hero01.IMG', 'hero02.IMG', 'hero03.IMG', 'hero04.IMG',
    'hero05.IMG', 'hero06.IMG', 'hero07.IMG', 'hero08.IMG',
    'heroS1.IMG', 'heroS2.IMG',
    'hero01M.IMG','hero02M.IMG','hero03M.IMG','hero04M.IMG',
    'hero05M.IMG','hero06M.IMG','hero07M.IMG','hero08M.IMG',
    'heroS1M.IMG','heroS2M.IMG',
    'heroJP.IMG', 'heroJPM.IMG',
    'hero01k.IMG','hero02k.IMG','hero03k.IMG',
    'hero01kM.IMG','hero02kM.IMG','hero03kM.IMG'
  );

type
  TGameField = array[1..80] of Byte;
  PGameField = ^TGameField;

  TGameState = (gsTitle, gsPlaying);

  TEnemy = record
    EX, EY:     Integer;
    EDirection: ShortInt;
    EType:      Byte;
    EImageNum:  Byte;  { 1-8 = forward walk, 9-16 = mirror walk }
    EDead:      Boolean;
    ECnt:       Byte;  { death animation countdown }
    EAnimTick:  Byte;  { animation throttle counter }
  end;
  PEnemy = ^TEnemy;

  { Sprite in BGI256 format (already decoded) }
  TSprite = record
    W, H:   Word;
    Pixels: TBytes;  { W * H bytes, palette indices }
  end;

  TForm1 = class(TForm)
    Timer1: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormPaint(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    { --- rendering --- }
    FBack: TBitmap;  { background (level tiles), 24bpp }
    FBuf:  TBitmap;  { work buffer, redrawn every frame }
    FPal:  array[0..255] of COLORREF;  { VGA palette }

    { --- keys --- }
    FKeys: array[0..255] of Boolean;

    { --- game state machine --- }
    FState:          TGameState;
    FTitleSpr:       TSprite;
    FFadeStep:       Integer;   { 0..63 palette fade for title text }

    { --- fullscreen --- }
    FFullscreen:     Boolean;
    FWindowedBounds: TRect;
    { --- game state --- }
    FX, FY:       Integer;
    FLastX, FLastY: Integer;
    FQuit:        Boolean;
    FCurImg:      Byte;
    FLastImg:     Byte;
    FHeroShoot:   Boolean;
    FShootY:      Integer;   { Y at moment of shooting -- used for hit detection }
    FHeroJump:    Boolean;
    FHeroDead:    Boolean;
    FVelY:        Double;   { vertical velocity, pixels/tick, negative = up }
    FShootDelay:  Byte;
    FDir:         Char;   { DIR_FW / DIR_BW }

    FActiveEnemys: Byte;
    FCnt:         Double;
    FAKill:       Boolean;
    FNEnemys:     Byte;
    FSceNum:      Byte;
    FHeroSpeed:   Byte;
    FEnemySpeed:  Byte;
    FLoaded:      Boolean;

    { --- sprites --- }
    FHeroSpr:   array[1..HSprCount] of TSprite;
    FEnemySpr:  array[1..255] of TSprite;
    FBgSpr:     array[1..50] of TSprite;
    FESprFiles: array[1..320] of string;
    FESprCount: Byte;
    FSprCount:  Byte;
    FBgFiles:   array[1..50] of string;

    { --- level --- }
    FGameField: PGameField;
    FObjEnemy:  array[1..MaxEnemys] of PEnemy;
    FScenario:  TFileStream;

    procedure RenderTitle;
    procedure TitleTick;
    procedure BuildVGAPalette;
    function  LoadSprite(const AFile: string; out S: TSprite): Boolean;
    procedure BlitSprite(ABmp: TBitmap; AX, AY: Integer; const S: TSprite);
    function  FieldItem(AX, AY: Integer): Byte;
    procedure LoadHeroSprites;
    procedure LoadBgSprites;
    procedure LoadEnemySprites;
    procedure LoadStuffList(const AFile: string;
                            var AArr: array of string;
                            out ACount: Byte);
    procedure LoadStuffs(const AName: string);
    procedure RenderBackground;
    procedure LoadScreen;
    procedure RenderFrame;
    procedure GameInit;
    procedure ProcessKeys;
    procedure DrawHeroSprites;
    procedure DrawEnemySprites;
    procedure CheckKill;
    procedure MoveForward;
    procedure MoveBackward;
    procedure DoJump;
    procedure DoShoot;
    procedure DoGameOver;
    procedure ToggleFullscreen;
    procedure GetRenderRect(out R: TRect);
    procedure FreeEnemies;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

{ ============================================================
  Standard VGA palette (BIOS default, 256 colors)
  First 16 - standard EGA colors.
  Source: RBIL / VGA BIOS specs
  ============================================================ }
const
  VGA_PAL_RGB: array[0..767] of Byte = (
    { 0..15 - standard 16 EGA colors }
    $00,$00,$00, $00,$00,$AA, $00,$AA,$00, $00,$AA,$AA,
    $AA,$00,$00, $AA,$00,$AA, $AA,$55,$00, $AA,$AA,$AA,
    $55,$55,$55, $55,$55,$FF, $55,$FF,$55, $55,$FF,$FF,
    $FF,$55,$55, $FF,$55,$FF, $FF,$FF,$55, $FF,$FF,$FF,
    { 16..31 }
    $00,$00,$00, $10,$10,$10, $20,$20,$20, $35,$35,$35,
    $45,$45,$45, $55,$55,$55, $65,$65,$65, $75,$75,$75,
    $8A,$8A,$8A, $9A,$9A,$9A, $AA,$AA,$AA, $BA,$BA,$BA,
    $CA,$CA,$CA, $DB,$DB,$DB, $EB,$EB,$EB, $FF,$FF,$FF,
    { 32..47 }
    $00,$00,$FF, $41,$00,$FF, $82,$00,$FF, $BE,$00,$FF,
    $FF,$00,$FF, $FF,$00,$BE, $FF,$00,$82, $FF,$00,$41,
    $FF,$00,$00, $FF,$41,$00, $FF,$82,$00, $FF,$BE,$00,
    $FF,$FF,$00, $BE,$FF,$00, $82,$FF,$00, $41,$FF,$00,
    { 48..63 }
    $00,$FF,$00, $00,$FF,$41, $00,$FF,$82, $00,$FF,$BE,
    $00,$FF,$FF, $00,$BE,$FF, $00,$82,$FF, $00,$41,$FF,
    $82,$82,$FF, $9E,$82,$FF, $BE,$82,$FF, $DB,$82,$FF,
    $FF,$82,$FF, $FF,$82,$DB, $FF,$82,$BE, $FF,$82,$9E,
    { 64..79 }
    $FF,$82,$82, $FF,$9E,$82, $FF,$BE,$82, $FF,$DB,$82,
    $FF,$FF,$82, $DB,$FF,$82, $BE,$FF,$82, $9E,$FF,$82,
    $82,$FF,$82, $82,$FF,$9E, $82,$FF,$BE, $82,$FF,$DB,
    $82,$FF,$FF, $82,$DB,$FF, $82,$BE,$FF, $82,$9E,$FF,
    { 80..95 }
    $BA,$BA,$FF, $CA,$BA,$FF, $DB,$BA,$FF, $EB,$BA,$FF,
    $FF,$BA,$FF, $FF,$BA,$EB, $FF,$BA,$DB, $FF,$BA,$CA,
    $FF,$BA,$BA, $FF,$CA,$BA, $FF,$DB,$BA, $FF,$EB,$BA,
    $FF,$FF,$BA, $EB,$FF,$BA, $DB,$FF,$BA, $CA,$FF,$BA,
    { 96..111 }
    $BA,$FF,$BA, $BA,$FF,$CA, $BA,$FF,$DB, $BA,$FF,$EB,
    $BA,$FF,$FF, $BA,$EB,$FF, $BA,$DB,$FF, $BA,$CA,$FF,
    $00,$00,$71, $1C,$00,$71, $38,$00,$71, $55,$00,$71,
    $71,$00,$71, $71,$00,$55, $71,$00,$38, $71,$00,$1C,
    { 112..127 }
    $71,$00,$00, $71,$1C,$00, $71,$38,$00, $71,$55,$00,
    $71,$71,$00, $55,$71,$00, $38,$71,$00, $1C,$71,$00,
    $00,$71,$00, $00,$71,$1C, $00,$71,$38, $00,$71,$55,
    $00,$71,$71, $00,$55,$71, $00,$38,$71, $00,$1C,$71,
    { 128..143 }
    $38,$38,$71, $45,$38,$71, $55,$38,$71, $61,$38,$71,
    $71,$38,$71, $71,$38,$61, $71,$38,$55, $71,$38,$45,
    $71,$38,$38, $71,$45,$38, $71,$55,$38, $71,$61,$38,
    $71,$71,$38, $61,$71,$38, $55,$71,$38, $45,$71,$38,
    { 144..159 }
    $38,$71,$38, $38,$71,$45, $38,$71,$55, $38,$71,$61,
    $38,$71,$71, $38,$61,$71, $38,$55,$71, $38,$45,$71,
    $51,$51,$71, $59,$51,$71, $61,$51,$71, $69,$51,$71,
    $71,$51,$71, $71,$51,$69, $71,$51,$61, $71,$51,$59,
    { 160..175 }
    $71,$51,$51, $71,$59,$51, $71,$61,$51, $71,$69,$51,
    $71,$71,$51, $69,$71,$51, $61,$71,$51, $59,$71,$51,
    $51,$71,$51, $51,$71,$59, $51,$71,$61, $51,$71,$69,
    $51,$71,$71, $51,$69,$71, $51,$61,$71, $51,$59,$71,
    { 176..191 }
    $00,$00,$41, $10,$00,$41, $20,$00,$41, $30,$00,$41,
    $41,$00,$41, $41,$00,$30, $41,$00,$20, $41,$00,$10,
    $41,$00,$00, $41,$10,$00, $41,$20,$00, $41,$30,$00,
    $41,$41,$00, $30,$41,$00, $20,$41,$00, $10,$41,$00,
    { 192..207 }
    $00,$41,$00, $00,$41,$10, $00,$41,$20, $00,$41,$30,
    $00,$41,$41, $00,$30,$41, $00,$20,$41, $00,$10,$41,
    $20,$20,$41, $28,$20,$41, $30,$20,$41, $38,$20,$41,
    $41,$20,$41, $41,$20,$38, $41,$20,$30, $41,$20,$28,
    { 208..223 }
    $41,$20,$20, $41,$28,$20, $41,$30,$20, $41,$38,$20,
    $41,$41,$20, $38,$41,$20, $30,$41,$20, $28,$41,$20,
    $20,$41,$20, $20,$41,$28, $20,$41,$30, $20,$41,$38,
    $20,$41,$41, $20,$38,$41, $20,$30,$41, $20,$28,$41,
    { 224..239 }
    $2C,$2C,$41, $30,$2C,$41, $35,$2C,$41, $3A,$2C,$41,
    $41,$2C,$41, $41,$2C,$3A, $41,$2C,$35, $41,$2C,$30,
    $41,$2C,$2C, $41,$30,$2C, $41,$35,$2C, $41,$3A,$2C,
    $41,$41,$2C, $3A,$41,$2C, $35,$41,$2C, $30,$41,$2C,
    { 240..255 }
    $2C,$41,$2C, $2C,$41,$30, $2C,$41,$35, $2C,$41,$3A,
    $2C,$41,$41, $2C,$3A,$41, $2C,$35,$41, $2C,$30,$41,
    $00,$00,$00, $00,$00,$00, $00,$00,$00, $00,$00,$00,
    $00,$00,$00, $00,$00,$00, $00,$00,$00, $00,$00,$00
  );

{ ============================================================ }

procedure TForm1.RenderTitle;
var
  DC:  HDC;
  R:   TRect;
  SX, SY: Integer;
  Alpha: Byte;
  TxtW: Integer;
  OldBk, OldFg: COLORREF;
  OldMode: Integer;
begin
  { Black background }
  FBuf.Canvas.Brush.Color := clBlack;
  FBuf.Canvas.FillRect(Rect(0, 0, GW, GH));

  { Center the logo sprite }
  if (FTitleSpr.W > 0) and (FTitleSpr.H > 0) then
  begin
    SX := (GW - FTitleSpr.W) div 2;
    SY := 40;
    BlitSprite(FBuf, SX, SY, FTitleSpr);
  end;

  { Fade-in text: FFadeStep 0..63 drives brightness 0..255 }
  Alpha := Byte(Min(FFadeStep * 4, 255));
  if Alpha > 0 then
  begin
    FBuf.Canvas.Font.Name  := 'Arial';
    FBuf.Canvas.Font.Size  := 10;
    FBuf.Canvas.Font.Style := [fsBold];
    FBuf.Canvas.Font.Color := RGB(Alpha, Alpha div 4, 0);
    FBuf.Canvas.Brush.Style := bsClear;
    TxtW := FBuf.Canvas.TextWidth('Computer Dragon');
    FBuf.Canvas.TextOut((GW - TxtW) div 2, 120, 'Computer Dragon');
    FBuf.Canvas.Font.Size  := 7;
    FBuf.Canvas.Font.Color := RGB(Alpha div 2, Alpha div 2, Alpha div 2);
    TxtW := FBuf.Canvas.TextWidth('Press any key to start');
    FBuf.Canvas.TextOut((GW - TxtW) div 2, 145, 'Press any key to start');
    FBuf.Canvas.Brush.Style := bsSolid;
  end;

  GetRenderRect(R);
  DC := Canvas.Handle;
  if FFullscreen then
  begin
    Canvas.Brush.Color := clBlack;
    Canvas.FillRect(Rect(0, 0, R.Left, ClientHeight));
    Canvas.FillRect(Rect(R.Right, 0, ClientWidth, ClientHeight));
    Canvas.FillRect(Rect(0, 0, ClientWidth, R.Top));
    Canvas.FillRect(Rect(0, R.Bottom, ClientWidth, ClientHeight));
  end;
  StretchBlt(DC, R.Left, R.Top, R.Width, R.Height,
             FBuf.Canvas.Handle, 0, 0, GW, GH, SRCCOPY);
end;

procedure TForm1.TitleTick;
begin
  if FFadeStep < 64 then
    Inc(FFadeStep);
  RenderTitle;

  { Any key except Alt+Enter starts the game }
  if FKeys[VK_SPACE] or FKeys[VK_RETURN] or
     FKeys[Ord('Z')] or FKeys[VK_LEFT] or FKeys[VK_RIGHT] then
  begin
    FState := gsPlaying;
    FillChar(FKeys, SizeOf(FKeys), 0);
    GameInit;
  end;
end;

procedure TForm1.BuildVGAPalette;
var
  I: Integer;
begin
  for I := 0 to 255 do
    FPal[I] := RGB(
      VGA_PAL_RGB[I * 3],
      VGA_PAL_RGB[I * 3 + 1],
      VGA_PAL_RGB[I * 3 + 2]
    );
end;

{ --- Load sprite from .IMG (BGI256 PutImage format) ---
  Header: Word(W-1), Word(H-1) -- this is how Borland stored sizes.
  Data:      W * H bytes, each = palette index.                  }
function TForm1.LoadSprite(const AFile: string; out S: TSprite): Boolean;
var
  F:    TFileStream;
  RW, RH: Word;
begin
  Result := False;
  S.W := 0;
  S.H := 0;
  if not FileExists(AFile) then
    Exit;
  F := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
  try
    F.ReadBuffer(RW, 2);
    F.ReadBuffer(RH, 2);
    S.W := RW + 1;
    S.H := RH + 1;
    SetLength(S.Pixels, S.W * S.H);
    F.ReadBuffer(S.Pixels[0], S.W * S.H);
    Result := True;
  finally
    F.Free;
  end;
end;

{ --- Draw sprite on TBitmap, skipping pixels with index 0 (transparent) --- }
procedure TForm1.BlitSprite(ABmp: TBitmap; AX, AY: Integer; const S: TSprite);
var
  Row, Col:  Integer;
  PRow:      PByte;
  Px, Py:    Integer;
  PixIdx:    Byte;
  C:         COLORREF;
begin
  if (S.W = 0) or (S.H = 0) or (Length(S.Pixels) = 0) then
    Exit;
  for Row := 0 to S.H - 1 do
  begin
    Py := AY + Row;
    if (Py < 0) or (Py >= GH) then
      Continue;
    PRow := ABmp.ScanLine[Py];
    for Col := 0 to S.W - 1 do
    begin
      Px := AX + Col;
      if (Px < 0) or (Px >= GW) then
        Continue;
      PixIdx := S.Pixels[Row * S.W + Col];
      if PixIdx = 0 then
        Continue;  { transparent }
      C := FPal[PixIdx];
      { TBitmap 24bpp: BGR byte order }
      PRow[Px * 3]     := GetBValue(C);
      PRow[Px * 3 + 1] := GetGValue(C);
      PRow[Px * 3 + 2] := GetRValue(C);
    end;
  end;
end;

{ --- Field element (collisions) ---
  Original: Round((CurX+31)/31) and Round((CurY+12)/24)          }
function TForm1.FieldItem(AX, AY: Integer): Byte;
var
  tX, tY, Idx: Integer;
begin
  Result := 0;
  if not Assigned(FGameField) then
    Exit;
  { Turbo Pascal Round(2.5)=3, Delphi Round(2.5)=2 (bankers rounding).
    Use Trunc(x+0.5) to match original half-up behavior. }
  tX := Trunc((AX + 31) / 31 + 0.5);
  tY := Trunc((AY + 12) / 24 + 0.5);
  Idx := tY * 10 + tX;
  if (Idx >= 1) and (Idx <= 80) then
    Result := FGameField^[Idx];
end;

{ --- Load file list from text file (space = separator) --- }
procedure TForm1.LoadStuffList(const AFile: string;
                               var AArr: array of string;
                               out ACount: Byte);
var
  F:    TFileStream;
  Raw:  TBytes;
  I, N: Integer;
  S:    string;
begin
  ACount := 0;
  if not FileExists(AFile) then
    Exit;
  F := TFileStream.Create(AFile, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Raw, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Raw[0], F.Size);
  finally
    F.Free;
  end;
  { IMPORTANT: open array parameter is always 0-indexed in Delphi.
    AArr[0] maps to the first element of the caller's array (e.g. FBgFiles[1]).
    So we start writing from index 0, not 1. }
  S := '';
  N := 0;
  for I := 0 to Length(Raw) - 1 do
  begin
    if (Raw[I] = Ord(' ')) or (Raw[I] = 13) or (Raw[I] = 10) then
    begin
      if S <> '' then
      begin
        AArr[N] := S;
        Inc(N);
      end;
      S := '';
    end
    else
      S := S + Chr(Raw[I]);
  end;
  if S <> '' then
  begin
    AArr[N] := S;
    Inc(N);
  end;
  ACount := N;
end;

procedure TForm1.LoadHeroSprites;
var
  I: Integer;
begin
  for I := 1 to HSprCount do
    LoadSprite(HSprFiles[I], FHeroSpr[I]);
end;

procedure TForm1.LoadBgSprites;
var
  I: Integer;
begin
  for I := 1 to FSprCount do
    LoadSprite(FBgFiles[I], FBgSpr[I]);
end;

procedure TForm1.LoadEnemySprites;
var
  I: Integer;
begin
  for I := 1 to FESprCount do
    LoadSprite(FESprFiles[I], FEnemySpr[I]);
end;

procedure TForm1.LoadStuffs(const AName: string);
var
  OldDir: string;
begin
  OldDir := GetCurrentDir;
  { .STF and .ITM files are in root dir }
  LoadStuffList(OldDir + '\\' + AName + '.STF', FESprFiles, FESprCount);
  LoadStuffList(OldDir + '\\' + AName + '.ITM', FBgFiles, FSprCount);
  { All sprites (enemies, tiles, hero) live in SPRITES.NEW }
  SetCurrentDir(OldDir + '\\SPRITES.NEW');
  LoadEnemySprites;
  LoadBgSprites;
  if not FLoaded then
    LoadHeroSprites;  { load hero sprites once, also from SPRITES.NEW }
  SetCurrentDir(OldDir);
end;

{ --- Draw background (tiles) to FBack --- }
procedure TForm1.RenderBackground;
var
  Xm, Ym, N: Integer;
  SprIdx:    Byte;
begin
  FBack.Canvas.Brush.Color := clBlack;
  FBack.Canvas.FillRect(Rect(0, 0, GW, GH));
  if not Assigned(FGameField) then
    Exit;
  N := 1;
  for Ym := 0 to 7 do
    for Xm := 0 to 9 do
    begin
      SprIdx := FGameField^[N];
      if (SprIdx >= 1) and (SprIdx <= 50) then
        BlitSprite(FBack, Xm * 31, Ym * 24, FBgSpr[SprIdx]);
      Inc(N);
    end;
end;

{ --- Load one screen (scene) from scenario file --- }
procedure TForm1.LoadScreen;
var
  N, Xm, Ym: Integer;
  SprIdx:    Byte;
  EX, EY:    Word;
  EType:     Byte;
  SName:     string;
begin
  if FScenario.Position >= FScenario.Size then
  begin
    { Advance to next level }
    FreeAndNil(FScenario);
    Inc(FSceNum);
    SName := 'LEVEL' + IntToStr(FSceNum) + '.SF!';
    if not FileExists(SName) then
    begin
      ShowMessage('You completed all levels!');
      FQuit := True;
      Exit;
    end;
    FScenario := TFileStream.Create(SName, fmOpenRead or fmShareDenyNone);
    FX := 20;
    FY := 144;
    FLastX := FX;
    FLastY := FY;
    
    FActiveEnemys := 0;
    FHeroDead := False;
    FAKill := False;
    FCurImg := 1;
    FVelY := 0;
    FShootDelay := 100;
    FDir := DIR_FW;
    FHeroJump := False;
    FreeEnemies;
    LoadStuffs('LEVEL' + IntToStr(FSceNum));
    if Assigned(FGameField) then
    begin
      Dispose(FGameField);
      FGameField := nil;
    end;
  end;

  New(FGameField);
  FScenario.ReadBuffer(FGameField^, SizeOf(TGameField));

  RenderBackground;

  { Read enemies }
  FScenario.ReadBuffer(FActiveEnemys, 1);
  FNEnemys := FActiveEnemys;
  for N := 1 to FNEnemys do
  begin
    New(FObjEnemy[N]);
    FScenario.ReadBuffer(EX, 2);
    FScenario.ReadBuffer(EY, 2);
    FScenario.ReadBuffer(EType, 1);
    FObjEnemy[N]^.EX := EX;
    FObjEnemy[N]^.EY := EY;
    FObjEnemy[N]^.EType := EType;
    FObjEnemy[N]^.EDirection := 1;
    FObjEnemy[N]^.EImageNum := (EType - 1) * 32 + 1;
    FObjEnemy[N]^.EDead     := False;
    FObjEnemy[N]^.ECnt      := 0;
    FObjEnemy[N]^.EAnimTick := 0;
  end;
end;

{ --- Compose frame: background + hero + enemies -> FBuf -> screen --- }
procedure TForm1.GetRenderRect(out R: TRect);
var
  ScaleX, ScaleY, Scale: Double;
  W, H: Integer;
begin
  if FFullscreen then
  begin
    ScaleX := ClientWidth  / GW;
    ScaleY := ClientHeight / GH;
    Scale  := Min(ScaleX, ScaleY);
    W := Trunc(GW * Scale);
    H := Trunc(GH * Scale);
    R := Rect(
      (ClientWidth  - W) div 2,
      (ClientHeight - H) div 2,
      (ClientWidth  - W) div 2 + W,
      (ClientHeight - H) div 2 + H
    );
  end
  else
    R := Rect(0, 0, GW * SC, GH * SC);
end;

procedure TForm1.ToggleFullscreen;
begin
  FFullscreen := not FFullscreen;
  if FFullscreen then
  begin
    FWindowedBounds := BoundsRect;
    BorderStyle  := bsNone;
    WindowState  := wsMaximized;
  end
  else
  begin
    WindowState  := wsNormal;
    BorderStyle  := bsSingle;
    BoundsRect   := FWindowedBounds;
  end;
  Canvas.Brush.Color := clBlack;
  Canvas.FillRect(ClientRect);
end;

procedure TForm1.RenderFrame;
var
  DC: HDC;
  R:  TRect;
begin
  FBuf.Canvas.Draw(0, 0, FBack);

  DrawEnemySprites;
  DrawHeroSprites;

  GetRenderRect(R);
  DC := Canvas.Handle;
  { Fill letterbox bars with black }
  if FFullscreen then
  begin
    Canvas.Brush.Color := clBlack;
    Canvas.FillRect(Rect(0, 0, R.Left, ClientHeight));
    Canvas.FillRect(Rect(R.Right, 0, ClientWidth, ClientHeight));
    Canvas.FillRect(Rect(0, 0, ClientWidth, R.Top));
    Canvas.FillRect(Rect(0, R.Bottom, ClientWidth, ClientHeight));
  end;
  StretchBlt(
    DC,    R.Left, R.Top, R.Width, R.Height,
    FBuf.Canvas.Handle, 0, 0, GW, GH,
    SRCCOPY
  );
end;

procedure TForm1.DrawEnemySprites;
var
  N:    Integer;
  EOfs: Integer;
begin
  for N := 1 to FActiveEnemys do
    if Assigned(FObjEnemy[N]) then
      with FObjEnemy[N]^ do
      begin
        if EDirection = -1 then EOfs := 8 else EOfs := 0;

        if EDead then
        begin
          if ECnt > 0 then
          begin
            { Death animation: ECnt counts down 16..1
              Kill-forward frames: base+17..base+24
              Kill-mirror frames:  base+25..base+32 }
            if EDirection = 1 then
              EImageNum := (24 - (ECnt div 2)) + (EType - 1) * 32
            else
              EImageNum := (32 - (ECnt div 2)) + (EType - 1) * 32;
            if EImageNum < 1 then EImageNum := 1;
            if EImageNum > FESprCount then EImageNum := FESprCount;
            BlitSprite(FBuf, EX, EY, FEnemySpr[EImageNum]);
            Dec(ECnt);
          end
          else
          begin
            { ECnt = 0: animation done -- keep drawing last frame (corpse stays) }
            if EDirection = 1 then
              EImageNum := (EType - 1) * 32 + 24
            else
              EImageNum := (EType - 1) * 32 + 32;
            if EImageNum < 1 then EImageNum := 1;
            if EImageNum > FESprCount then EImageNum := FESprCount;
            BlitSprite(FBuf, EX, EY, FEnemySpr[EImageNum]);
          end;
        end
        else
        begin
          if (EImageNum + EOfs >= 1) and (EImageNum + EOfs <= FESprCount) then
            BlitSprite(FBuf, EX, EY, FEnemySpr[EImageNum + EOfs]);

          EX := EX + EDirection * FEnemySpeed;

          if (EImageNum = 8 + (EType - 1) * 32) or
             (EImageNum = 16 + (EType - 1) * 32) then
            EImageNum := EImageNum - 7
          else
            Inc(EImageNum);

          if (EDirection = -1) and
             ((FieldItem(EX - 5, EY) = 0) or (EX < 10) or
              (FieldItem(EX - 20, EY - 24) <> 0)) then
            EDirection := 1;

          if (EDirection = 1) and
             ((FieldItem(EX + 20, EY) = 0) or (EX > 290) or
              (FieldItem(EX + 20, EY - 24) <> 0)) then
            EDirection := -1;
        end;
      end;
end;

procedure TForm1.CheckKill;
var
  N:          Integer;
  FirstEnNum: Integer;
  FirstEnX:   Integer;
begin
  for N := 1 to FActiveEnemys do
    if Assigned(FObjEnemy[N]) and not FObjEnemy[N]^.EDead then
      with FObjEnemy[N]^ do
        if (FX > EX) and (FX < EX + 20) then
          if (FY + 12 > EY) and (FY + 12 < EY + 24) then
          begin
            if FHeroJump then FVelY := Abs(FVelY);  { start falling on death }
            FHeroDead := True;
          end;

  FirstEnNum := 0;
  FirstEnX   := 0;

  if (not FHeroDead) and FHeroShoot and (not FAKill) then
  begin
    for N := 1 to FActiveEnemys do
      if Assigned(FObjEnemy[N]) and not FObjEnemy[N]^.EDead then
        with FObjEnemy[N]^ do
        begin
          if FDir = DIR_FW then
          begin
            if (Abs(FShootY - EY) <= 12) and (EX > FX) then
            begin
              if FirstEnX = 0 then
              begin
                FirstEnX := EX;
                FirstEnNum := N;
              end;
              if EX < FirstEnX then
              begin
                FirstEnNum := N;
                FirstEnX := EX;
              end;
            end;
          end;
          if FDir = DIR_BW then
          begin
            if (Abs(FShootY - EY) <= 12) and (EX < FX) then
            begin
              if FirstEnX = 0 then
              begin
                FirstEnX := EX;
                FirstEnNum := N;
              end;
              if EX > FirstEnX then
              begin
                FirstEnNum := N;
                FirstEnX := EX;
              end;
            end;
          end;
        end;
    if FirstEnNum > 0 then
    begin
      FObjEnemy[FirstEnNum]^.EDead := True;
      FObjEnemy[FirstEnNum]^.ECnt  := 16;
      FAKill := True;
      Dec(FNEnemys);
    end;
  end;
end;

procedure TForm1.DoShoot;
begin
  if FHeroShoot then Exit;
  FHeroShoot  := True;
  FShootDelay := 50;
  FAKill      := False;
  FShootY     := FY;  { freeze Y for hit detection }
end;

procedure TForm1.DoJump;
begin
  if FHeroJump then Exit;
  FHeroJump := True;
  FVelY     := -10;  { initial upward velocity, pixels/tick }
end;

procedure TForm1.MoveForward;
begin
  FLastX := FX;
  FLastY := FY;
  if not FHeroJump then
  begin
    if FieldItem(FX + 10, FY - 12) <> 0 then Exit;
    if FieldItem(FX, FY + 12) = 0 then
    begin
      Inc(FX, 5);
      FHeroJump := True;
      FVelY     := 0;  { start falling, gravity will take over }
      Exit;
    end;
    if FDir = DIR_BW then
    begin
      FDir := DIR_FW;
      FCurImg := FCurImg - 10;
    end;
    if FCurImg = 8 then
      FCurImg := 1
    else
      Inc(FCurImg);
    Inc(FX, FHeroSpeed);
  end
  else
  begin
    if FieldItem(FX + 10, FY) <> 0 then Exit;
    Inc(FX, FHeroSpeed);
    FLastX := FX;
    FLastY := FY;
  end;
  if FX > 280 then
  begin
    FX := 20;
    FLastX := FX;
    FLastY := FY;
    LoadScreen;
  end;
end;

procedure TForm1.MoveBackward;
begin
  FLastX := FX;
  FLastY := FY;
  if not FHeroJump then
  begin
    if FX < 2 then Exit;
    if FieldItem(FX - 10, FY - 12) <> 0 then Exit;
    if FieldItem(FX, FY + 12) = 0 then
    begin
      Dec(FX, 5);
      FHeroJump := True;
      FVelY     := 0;
      Exit;
    end;
    if FDir = DIR_FW then
    begin
      FDir := DIR_BW;
      FCurImg := FCurImg + 10;
    end;
    if FCurImg = 18 then
      FCurImg := 11
    else
      Inc(FCurImg);
    Dec(FX, FHeroSpeed);
  end
  else
  begin
    if FieldItem(FX - 10, FY) <> 0 then Exit;
    Dec(FX, FHeroSpeed);
    FLastX := FX;
    FLastY := FY;
  end;
end;

procedure TForm1.DoGameOver;
begin
  FQuit := True;
  Timer1.Enabled := False;
  ShowMessage('Game Over');
end;

{ --- DrawSprites from original (hero movement logic) --- }
procedure TForm1.DrawHeroSprites;
var
  SprIdx: Integer;
  SDirect, DD: Integer;
begin
  { Check death on falling off screen }
  if FY > 167 then
    FHeroDead := True;

  if FHeroDead and not FHeroShoot then
  begin
    if FDir = DIR_FW then DD := 0 else DD := 3;
    if FCurImg < 22 + DD then
    begin
      FCnt := 0;
      FCurImg := 23 + DD;
    end
    else if FCurImg < 25 + DD then
    begin
      FCnt := FCnt + 0.03;
      FCurImg := FCurImg + Round(FCnt);
    end;
    if FCurImg - DD = 25 then
      DoGameOver;
  end;

  { Shooting }
  if FHeroShoot then
  begin
    if FDir = DIR_FW then SDirect := 0 else SDirect := 10;
    if FShootDelay > 25 then
    begin
      if FShootDelay = 50 then
        FCurImg := 9 + SDirect;
      Dec(FShootDelay);
    end
    else
    begin
      if FShootDelay = 25 then
        FCurImg := 10 + SDirect;
      Dec(FShootDelay);
    end;
    if FShootDelay = 0 then
    begin
      FHeroShoot := False;
      FCurImg := 1 + SDirect;
      FLastImg := FCurImg;
    end;
  end;

  { Jump - parabolic physics }
  if FHeroJump then
  begin
    const GRAVITY = 0.55;
    if FDir = DIR_FW then FCurImg := 21 else FCurImg := 22;
    { Hit ceiling going up }
    if (FVelY < 0) and (FieldItem(FX, FY - 24) <> 0) then
      FVelY := 0;
    FVelY := FVelY + GRAVITY;
    FY    := FY + Round(FVelY);
    { Landed on floor }
    if (FVelY > 0) and (FieldItem(FX, FY) <> 0) then
    begin
      { Snap to tile }
      while FieldItem(FX, FY) <> 0 do Dec(FY);
      FHeroJump := False;
      FVelY     := 0;
      if FDir = DIR_FW then FCurImg := 1 else FCurImg := 11;
    end;
  end;

  { Standing - update sprite by position }
  if not FHeroJump and ((FLastX <> FX) or (FLastY <> FY)) then
  begin
    FLastX := FX;
    FLastY := FY;
  end;

  SprIdx := FCurImg;
  if (SprIdx >= 1) and (SprIdx <= HSprCount) then
    BlitSprite(FBuf, FX, FY, FHeroSpr[SprIdx]);
end;

{ --- Key processing --- }
procedure TForm1.ProcessKeys;
begin
  if FQuit then Exit;

  { ESC -> quit }
  if FKeys[VK_ESCAPE] then
  begin
    FQuit := True;
    Exit;
  end;

  if not FHeroDead then
  begin
    if FKeys[VK_LEFT]  and not FHeroShoot then MoveBackward;
    if FKeys[VK_RIGHT] and not FHeroShoot then MoveForward;
    if FKeys[VK_UP]    and not FHeroShoot then DoJump;
    if FKeys[VK_SPACE] then DoShoot;
  end;
end;

{ ============================================================
  Initialization and game loop
  ============================================================ }

procedure TForm1.FreeEnemies;
var
  I: Integer;
begin
  for I := 1 to MaxEnemys do
    if Assigned(FObjEnemy[I]) then
    begin
      Dispose(FObjEnemy[I]);
      FObjEnemy[I] := nil;
    end;
end;

procedure TForm1.GameInit;
var
  I: Integer;
begin
  SetCurrentDir(ExtractFilePath(Application.ExeName));

  FHeroSpeed  := 1;
  FEnemySpeed := 1;
  FSceNum     := 1;
  FLoaded     := False;

  for I := 1 to MaxEnemys do
    FObjEnemy[I] := nil;
  FGameField := nil;

  { Initial coordinates }
  FX      := 20;
  FY      := 144;
  FLastX  := FX;
  FLastY  := FY;
  FQuit   := False;
  FCurImg := 1;
  FLastImg := 1;
  FHeroShoot := False;
  FHeroJump  := False;
  FHeroDead  := False;
  FVelY := 0;
  FShootDelay := 0;
  FDir    := DIR_FW;
  
  FActiveEnemys := 0;
  FAKill := False;
  FCnt   := 0;

  LoadStuffs('LEVEL1');

  { Open scenario file }
  if not FileExists('LEVEL1.SF!') then
  begin
    ShowMessage('File LEVEL1.SF! not found');
    Application.Terminate;
    Exit;
  end;
  FScenario := TFileStream.Create('LEVEL1.SF!', fmOpenRead or fmShareDenyNone);

  LoadScreen;

  FLoaded := True;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption := 'Dark Planet';
  ClientWidth  := GW * SC;
  ClientHeight := GH * SC;
  BorderStyle  := bsSingle;
  Position     := poScreenCenter;

  FBack := TBitmap.Create;
  FBack.PixelFormat := pf24bit;
  FBack.Width  := GW;
  FBack.Height := GH;

  FBuf := TBitmap.Create;
  FBuf.PixelFormat := pf24bit;
  FBuf.Width  := GW;
  FBuf.Height := GH;

  Timer1.Interval := 25;
  Timer1.Enabled  := False;

  FFullscreen := False;
  FState := gsTitle;
  FFadeStep := 0;
  FillChar(FKeys, SizeOf(FKeys), 0);
  FillChar(FHeroSpr,  SizeOf(FHeroSpr),  0);
  FillChar(FEnemySpr, SizeOf(FEnemySpr), 0);
  FillChar(FBgSpr,    SizeOf(FBgSpr),    0);

  BuildVGAPalette;
  LoadSprite('CDRAGON.PIC', FTitleSpr);

  Timer1.Interval := 30;
  Timer1.Enabled  := True;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  Timer1.Enabled := False;
  FreeEnemies;
  if Assigned(FGameField) then Dispose(FGameField);
  FreeAndNil(FScenario);
  FreeAndNil(FBack);
  FreeAndNil(FBuf);
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (ssAlt in Shift) then
  begin
    ToggleFullscreen;
    Key := 0;
    Exit;
  end;
  if Key <= 255 then
    FKeys[Key] := True;
end;

procedure TForm1.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key <= 255 then
    FKeys[Key] := False;
end;

procedure TForm1.FormPaint(Sender: TObject);
begin
  case FState of
    gsTitle:   RenderTitle;
    gsPlaying: if FLoaded then RenderFrame;
  end;
end;

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  if FQuit then
  begin
    Timer1.Enabled := False;
    Application.Terminate;
    Exit;
  end;
  case FState of
    gsTitle:   TitleTick;
    gsPlaying:
    begin
      ProcessKeys;
      CheckKill;
      RenderFrame;
    end;
  end;
end;

end.
