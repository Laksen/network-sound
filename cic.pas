unit cic;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  sndbase;

type
  TCIC = class
  private
    fDiff,
    fAcc: array[0..1] of single;
  public
    constructor Create;

    function Interpolate(var AOutSamples: TSamples; const AInSamples: TSamples; out AConsumed: longint): longint;
  end;

implementation

constructor TCIC.Create;
begin
  inherited Create;
  fDiff:=[0,0];
  fAcc:=[0,0];
end;

function TCIC.Interpolate(var AOutSamples: TSamples; const AInSamples: TSamples; out AConsumed: longint): longint;
var
  consumed, len, cap: SizeInt;
  diff: array[0..1] of single;
begin
  result:=0;
  consumed:=0;

  len:=length(AInSamples[0]);
  cap:=length(AOutSamples[0]);

  while (consumed<len) and (cap-result>=2) do
  begin
    diff[0]:=AInSamples[0][consumed]-fDiff[0];
    diff[1]:=AInSamples[1][consumed]-fDiff[1];
    fDiff[0]:=AInSamples[0][consumed];
    fDiff[1]:=AInSamples[1][consumed];

    AOutSamples[0][result+0]:=fAcc[0]+diff[0];
    AOutSamples[1][result+0]:=fAcc[1]+diff[1];

    AOutSamples[0][result+1]:=fAcc[0]+diff[0]*2;
    AOutSamples[1][result+1]:=fAcc[1]+diff[1]*2;

    fAcc[0]:=fAcc[0]+diff[0]*2;
    fAcc[1]:=fAcc[1]+diff[1]*2;

    inc(result,2);
    inc(consumed);
  end;

  AConsumed:=consumed;
end;

end.

