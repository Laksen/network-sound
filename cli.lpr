program cli;

uses
  cthreads,
  Linux, BaseUnix, unixtype,
  netsndbase, resampler, cic, sndbase ;

type
  TLinuxTimer = class(TNetworkSoundTimer)
  public
    function GetPhysicalTime: TPhysicalTimestamp; override;
  end;

function TLinuxTimer.GetPhysicalTime: TPhysicalTimestamp;
var
  ts: timespec;
begin
  clock_gettime(CLOCK_REALTIME, @ts);
  result:=ts.tv_nsec+int64(ts.tv_sec)*1000000000;
end;

var
  serv: TNetworkSoundServer;
  clnt: TNetworkSoundClient;
  s,t: array[0..31] of single;
  i, c, r: longint;
  n, samp, x: TSamples;
  cc: TCIC;
  taps: TSingles;
  rsamp: TResampler;

begin
  {serv:=TNetworkSoundServer.Create(16030,TLinuxTimer);
  clnt:=TNetworkSoundClient.Create('127.0.0.1', 16030, TLinuxTimer);
  ReadLn;
  clnt.Free;
  serv.free;}

  n:=Tone(0.2, 32*1024);
  //n:=Noise(32*1024);
  samp:=Samples(64*1024);

  taps:=ReadFloats('taps.txt');
  rsamp:=TResampler.Create(TapsToBanks(taps, 32));
                                             
  WriteSamples('samp0.txt', n, length(n[0]));

  //cc:=TCIC.Create;
  //r:=cc.Interpolate(samp, n, c);
  //WriteSamples('samp1.txt', samp, r);

  x:=Samples(64*1024);
  //r:=rsamp.Downsample(0.5, 0.49, x, samp, r, c);
  r:=rsamp.Downsample(2, 0.5, 0.5, x, n, length(n[0]), c);
  writeln(c,' -> ',r);

  WriteSamples('samp2.txt', x, r);
  cc.free;
end.

