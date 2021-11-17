unit resampler;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  math,
  sndbase;

type
  TTapBank = array[0..31] of single;
  TBanks = array of TTapBank;

  TResampler = class
  private
    fNCO: double;
    fTaps: TBanks;
    fBanks: longint;
    fDelay: array[0..1] of array of single;
  public
    function Downsample(ABaseFactor, AFactor: double; var AOutSamples: TSamples; const AInSamples: TSamples; AInCount: longint; out AConsumed: longint): longint;
    function Downsample(AInterpolate: longint; ABaseFactor, AFactor: double; var AOutSamples: TSamples; const AInSamples: TSamples; AInCount: longint; out AConsumed: longint): longint;

    constructor Create(const ATapBanks: TBanks);
  end;

function Dot32(a,b: psingle): single;
function DotN(a,b: psingle; cnt: longint): single;

function TapsToBanks(const ATaps: TSingles; ABanks: longint): TBanks;

implementation

procedure Normalize(var ABank: TTapBank; AScale: double);
var
  i: Integer;
  x: double;
begin
  //x:=0;
  //for i:=0 to high(ABank) do
  //  x:=x+ABank[i];
  //x:=1/sqrt(x);
  x:=ascale;
  for i:=0 to high(ABank) do
    ABank[i]:=x*ABank[i];
end;

{$ifdef CPUX86_641}
{$define DOT32}
function Dot32(a,b: psingle): single; assembler;
asm
  movaps 16*0(%rsi), %xmm0
  movaps 16*1(%rsi), %xmm1
  movaps 16*2(%rsi), %xmm2
  movaps 16*3(%rsi), %xmm3
  movaps 16*4(%rsi), %xmm4
  movaps 16*5(%rsi), %xmm5
  movaps 16*6(%rsi), %xmm6
  movaps 16*7(%rsi), %xmm7

  mulps 16*0(%rdi), %xmm0
  mulps 16*1(%rdi), %xmm1
  mulps 16*2(%rdi), %xmm2
  mulps 16*3(%rdi), %xmm3
  mulps 16*4(%rdi), %xmm4
  mulps 16*5(%rdi), %xmm5
  mulps 16*6(%rdi), %xmm6
  mulps 16*7(%rdi), %xmm7

  addps %xmm4, %xmm0
  addps %xmm5, %xmm1
  addps %xmm6, %xmm2
  addps %xmm7, %xmm3

  addps %xmm1, %xmm0
  addps %xmm3, %xmm2

  addps %xmm2, %xmm0

  haddps %xmm0, %xmm0
  haddps %xmm0, %xmm0
end;
{$endif}

{$ifdef CPU3861}
{$define DOT32}
function Dot32(a,b: psingle): single; assembler;
asm
  mov a, %eax
  mov b, %edx

  movaps 16*0(%eax), %xmm0
  movaps 16*1(%eax), %xmm1
  movaps 16*2(%eax), %xmm2
  movaps 16*3(%eax), %xmm3
  movaps 16*4(%eax), %xmm4
  movaps 16*5(%eax), %xmm5
  movaps 16*6(%eax), %xmm6
  movaps 16*7(%eax), %xmm7

  mulps 16*0(%edx), %xmm0
  mulps 16*1(%edx), %xmm1
  mulps 16*2(%edx), %xmm2
  mulps 16*3(%edx), %xmm3
  mulps 16*4(%edx), %xmm4
  mulps 16*5(%edx), %xmm5
  mulps 16*6(%edx), %xmm6
  mulps 16*7(%edx), %xmm7

  addps %xmm4, %xmm0
  addps %xmm5, %xmm1
  addps %xmm6, %xmm2
  addps %xmm7, %xmm3

  addps %xmm1, %xmm0
  addps %xmm3, %xmm2

  addps %xmm2, %xmm0

  haddps %xmm0, %xmm0
  haddps %xmm0, %xmm0

  movss %xmm0, result
end;
{$endif}

{$ifndef DOT32}
function Dot32(a,b: psingle): single;
var
  i: Integer;
begin
  result:=0;
  for i:=0 to 31 do
    result:=result+a[i]*b[i];
end;
{$endif}

function DotN(a,b: psingle; cnt: longint): single;
var
  i: Integer;
begin
  result:=0;
  for i:=0 to cnt-1 do
    result:=result+a[i]*b[i];
end;

function TapsToBanks(const ATaps: TSingles; ABanks: longint): TBanks;
var
  i, i2: Integer;
begin
  setlength(result, ABanks);

  for i:=0 to ABanks-1 do
    for i2:=0 to 31 do
      result[i][i2]:=ATaps[i+32*i2];
end;

function TResampler.Downsample(ABaseFactor, AFactor: double; var AOutSamples: TSamples; const AInSamples: TSamples; AInCount: longint; out AConsumed: longint): longint;
var
  cnt, inCnt, len: SizeInt;
  bank: Int64;
  i, consumed: longint;
begin
  cnt:=length(AOutSamples[0]);
  inCnt:=AInCount;

  consumed:=0;
  result:=0;

  len:=length(fDelay[0]);
  assert(len=32, 'Taps should be 32');

  for i:=0 to incnt-1 do
  begin          
    inc(consumed);
    fNCO:=fNCO + AFactor;

    move(fDelay[0][0],fDelay[0][1],(len-1)*sizeof(single));
    move(fDelay[1][0],fDelay[1][1],(len-1)*sizeof(single));
    fDelay[0][0]:=AInSamples[0][i];
    fDelay[1][0]:=AInSamples[1][i];

    if fNCO>=1 then
    begin
      fNCO:=fNCO-1;

      bank:=round(fNCO * fBanks / ABaseFactor) mod fBanks;
      bank:=fBanks-1-bank;
      //bank:=0;

      AOutSamples[0][result]:=Dot32(@fDelay[0][0], @fTaps[bank][0]);
      AOutSamples[1][result]:=Dot32(@fDelay[1][0], @fTaps[bank][0]);
      inc(result);

      if result>=cnt then
        break;
    end;
  end;

  AConsumed:=consumed;
end;

function TResampler.Downsample(AInterpolate: longint; ABaseFactor, AFactor: double; var AOutSamples: TSamples; const AInSamples: TSamples; AInCount: longint; out AConsumed: longint): longint;
var
  cnt, inCnt, len: SizeInt;
  bank: Int64;
  i, i2, consumed: longint;
begin
  cnt:=length(AOutSamples[0]);
  inCnt:=AInCount;

  consumed:=0;
  result:=0;

  len:=length(fDelay[0]);
  assert(len=32, 'Taps should be 32');

  for i:=0 to incnt-1 do
  begin
    for i2:=0 to AInterpolate-1 do
    begin     
      inc(consumed);
      fNCO:=fNCO + AFactor;

      move(fDelay[0][0],fDelay[0][1],(len-1)*sizeof(single));
      move(fDelay[1][0],fDelay[1][1],(len-1)*sizeof(single));
      if i2=0 then
      begin
        fDelay[0][0]:=AInSamples[0][i];
        fDelay[1][0]:=AInSamples[1][i];
      end
      else
      begin
        fDelay[0][0]:=0;
        fDelay[1][0]:=0;
      end;

      if fNCO>=1 then
      begin
        fNCO:=fNCO-1;

        bank:=trunc(fNCO * fBanks / ABaseFactor) mod fBanks;
        bank:=fBanks-1-bank;

        AOutSamples[0][result]:=Dot32(@fDelay[0][0], @fTaps[bank][0]);
        AOutSamples[1][result]:=Dot32(@fDelay[1][0], @fTaps[bank][0]);
        inc(result);
      end;
    end;

    if (result+AInterpolate-1)>=cnt then
      break;
  end;

  AConsumed:=consumed;
end;

constructor TResampler.Create(const ATapBanks: TBanks);
var
  i: Integer;
begin
  inherited Create;
  fNCO:=0;
  fTaps:=Copy(ATapBanks);
  fBanks:=Length(ATapBanks);

  for i:=0 to high(fTaps) do
    Normalize(fTaps[i], length(fTaps[0])*2);

  setlength(fDelay[0], length(fTaps[0]));
  setlength(fDelay[1], length(fTaps[0]));
end;

end.

