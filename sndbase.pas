unit sndbase;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  Math;

type
  TSingles = array of single;
  TSamples = array[0..1] of TSingles;

function Samples(ACount: sizeint): TSamples;

function Noise(ACount: sizeint): TSamples;
function Tone(APhase: single; ACount: sizeint): TSamples;

procedure WriteSamples(const AFilename: string; const ASamples: TSamples; ACount: SizeInt);
function  ReadFloats(const AFilename: string): TSingles;

implementation

function Samples(ACount: sizeint): TSamples;
begin
  setlength(result[0], ACount);
  setlength(result[1], ACount);
end;

function Noise(ACount: sizeint): TSamples;
var
  s, c, mag: single;
  i: SizeInt;
begin
  setlength(result[0], ACount);
  setlength(result[1], ACount);

  for i:=0 to ACount-1 do
  begin
    SinCos(random*Pi*2, s,c);
    mag:=sqrt(-2*Ln(random));

    result[0][i]:=c*mag;
    result[1][i]:=s*mag;
  end;
end;

function Tone(APhase: single; ACount: sizeint): TSamples;
var
  i: Integer;
  acc: double;
begin
  setlength(result[0], ACount);
  setlength(result[1], ACount);

  acc:=0;
  for i:=0 to ACount-1 do
  begin
    result[0][i]:=cos(acc);
    result[1][i]:=Sin(acc);

    acc:=acc+aphase;
  end;
end;

procedure WriteSamples(const AFilename: string; const ASamples: TSamples; ACount: SizeInt);
var
  f: TextFile;
  i: sizeint;
begin
  assign(f, AFilename);
  Rewrite(f);

  for i:=0 to ACount-1 do
  begin
    writeln(f,ASamples[0][i],',',ASamples[1][i]);
  end;

  closefile(f);
end;

function ReadFloats(const AFilename: string): TSingles;
var
  st: TStringList;
  i: longint;
begin
  st:=TStringList.Create;
  st.LoadFromFile(AFilename);

  setlength(result, st.Count);
  for i:=0 to st.Count-1 do
    result[i]:=StrToFloat(st[i]);

  st.free;
end;

initialization
  DecimalSeparator:='.';

end.

