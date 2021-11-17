unit netsndbase;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  blcksock, synsock;

const
  MaxTimeout = 3*1000000000;
  UpdateRate = 500000000;
  PingInterval = UpdateRate;

type
  TPhysicalTimestamp = int64; // In units of nano seconds, unix time
  TVirtualTime = int64; // In units of nano seconds, unix time

  TNetworkSoundLoopfilter = class
  private
    fDamping: double;
    fLoopBandwidth: double;
    fSamplePeriod: double;
    procedure SetDamping(AValue: double);
    procedure SetLoopBandwidth(AValue: double);
    procedure SetSamplePeriod(AValue: double);
  private
    fLFAlpha, fLFBeta,
    fLFIntegrator,
    fLFResult: double;
    procedure Recalc;
  public
    constructor Create;

    procedure AddError(AError: double);

    property Output: double read fLFResult;

    property SamplePeriod: double read fSamplePeriod write SetSamplePeriod;
    property LoopBandwidth: double read fLoopBandwidth write SetLoopBandwidth;
    property Damping: double read fDamping write SetDamping;
  end;

  TNetworkSoundFilter = class
  private
    fFirst: boolean;
    fFactor: double;
    fValue: double;
    procedure SetFactor(AValue: double);
  public
    procedure AddMeasurement(AMeasurement: double);
    procedure Reset;

    constructor Create;

    property Value: double read fValue;
    property Factor: double read fFactor write SetFactor;
  end;

  TNetworkSoundTimer = class
  public
    function GetPhysicalTime: TPhysicalTimestamp; virtual;
  end;

  TNetworkSoundTimerClass = class of TNetworkSoundTimer;

  TNetworkSoundVirtualClock = class
  private
    fOffsetLoopfilter: TNetworkSoundFilter;
    fRoundtripLoopfilter: TNetworkSoundFilter;
    fTimer: TNetworkSoundTimer;

    fController: TNetworkSoundLoopfilter;

    function ToVirtual(APhysical: TPhysicalTimestamp): TVirtualTime;
    function ToPhysical(AVirtual: TVirtualTime): TPhysicalTimestamp;
  public
    function GetTimestamp: TVirtualTime;

    procedure AddRoundtripMeasurement(const ASendMS, ARecvMS, ASendSM, ARecvSM: TVirtualTime);
    procedure AddOffset(ASendMS, ARecvMS: TVirtualTime);

    procedure Reset;

    constructor Create(ATimer: TNetworkSoundTimer);
    destructor Destroy; override;

    property RoundtripLoopfilter: TNetworkSoundFilter read fRoundtripLoopfilter;
    property OffsetLoopfilter: TNetworkSoundFilter read fOffsetLoopfilter;
  end;

  TNetworkSoundClientState = (
    csReset,
    csFirstOffset,
    csFirstRoundtrip,
    csRunning
  );

  TNSMessageType = (mtSync, mtPing, mtPong);

  TNetworkSoundClient = class(TThread)
  private
    fSock: TUDPBlockSocket;
    fState: TNetworkSoundClientState;
    fVirtualClock: TNetworkSoundVirtualClock;
    fTimer: TNetworkSoundTimer;
    fLastPing: TPhysicalTimestamp;
    procedure AddEvent(AEvent: TNSMessageType; AID: word; const ATime0, ATime1, ARecvTime: TVirtualTime);
    procedure SendPing;
  protected
    procedure Execute; override;
  public
    constructor Create(const AServer: string; APort: word; ATimer: TNetworkSoundTimerClass);
    destructor Destroy; override;

    property VirtualClock: TNetworkSoundVirtualClock read fVirtualClock;
  end;

  TNetworkSoundSubscriber = class
  private
    fLastContact: TPhysicalTimestamp;
    fSin: TVarSin;
  public
    constructor Create(const ASin: TVarSin; ATime: TPhysicalTimestamp);

    procedure Contact(ATime: TPhysicalTimestamp);
    function TimedOut(ATime: TPhysicalTimestamp): boolean;

    property Sin: TVarSin read fSin;
    property LastContact: TPhysicalTimestamp read fLastContact;
  end;

  TNetworkSoundServer = class(TThread)
  private       
    fSock: TUDPBlockSocket;
    fTimer: TNetworkSoundTimer;
    fSubscribers: TList;
    function SubscribeFrom(const ASin: TVarSin; ATime: TPhysicalTimestamp): TNetworkSoundSubscriber;
  protected
    procedure Execute; override;
  public
    constructor Create(APort: word; ATimer: TNetworkSoundTimerClass);
    destructor Destroy; override;
  end;

implementation

type
  TNSMessage = packed record
    MessageType: TNSMessageType;
    Timestamp,
    RecvTimestamp: TVirtualTime;
  end;

constructor TNetworkSoundSubscriber.Create(const ASin: TVarSin; ATime: TPhysicalTimestamp);
begin
  inherited Create;
  fSin:=ASin;
  fLastContact:=ATime;
end;

procedure TNetworkSoundSubscriber.Contact(ATime: TPhysicalTimestamp);
begin
  fLastContact:=ATime;
end;

function TNetworkSoundSubscriber.TimedOut(ATime: TPhysicalTimestamp): boolean;
begin
  result:=(ATime-fLastContact) >= MaxTimeout;
end;

function TNetworkSoundServer.SubscribeFrom(const ASin: TVarSin; ATime: TPhysicalTimestamp): TNetworkSoundSubscriber;
var
  t: TNetworkSoundSubscriber;
  i: longint;
  s: Integer;
begin
  s:=SizeOfVarSin(ASin);
  for i:=0 to fSubscribers.Count-1 do
  begin
    t:=TNetworkSoundSubscriber(fSubscribers[i]);
    if (SizeOfVarSin(t.Sin)=s) and CompareMem(@t.Sin, @ASin, s) then
    begin
      t.Contact(ATime);
      exit(t);
    end;
  end;

  writeln('Got new client: ', GetSinIP(ASin), ':', GetSinPort(Asin));

  result:=TNetworkSoundSubscriber.Create(ASin, ATime);
  fSubscribers.Add(result);
end;

procedure TNetworkSoundServer.Execute;
var
  buf: array[0..63] of byte;
  client: TVarSin;
  recvTime, fLastPPS, slaveTime, sendTime: TPhysicalTimestamp;
  res: Integer;
  sub: TNetworkSoundSubscriber;
  t: Pointer;
  toRemove: TList;
begin
  //fSock.NonBlockMode:=true;

  toRemove:=TList.Create;
  fLastPPS:=fTimer.GetPhysicalTime;

  while not Terminated do
  begin                                         
    if fSock.CanReadEx(100) then
    begin
      res:=fSock.RecvBufferFrom(@buf[0], sizeof(buf));
      recvTime:=fTimer.GetPhysicalTime;
      if res>0 then
      begin
        sub:=SubscribeFrom(fSock.RemoteSin, recvTime);

        buf[0]:=Byte(mtPong);
        slaveTime:=pint64(@buf[3])^;
        sendTime:=fTimer.GetPhysicalTime;
        pint64(@buf[3])^:=recvTime-slaveTime-Sendtime;

        fSock.SendBufferTo(@buf[0], 11);
        continue;
      end;
    end;
                                
    recvTime:=fTimer.GetPhysicalTime;
    if (recvTime-fLastPPS) >= UpdateRate then
    begin
      toRemove.Clear;

      for t in fSubscribers do
      begin
        sub:=TNetworkSoundSubscriber(t);
        fSock.RemoteSin:=sub.Sin;

        if sub.TimedOut(recvTime) then
        begin
          toRemove.Add(sub);
          continue;
        end;

        buf[0]:=Byte(mtSync);
        pword(@buf[1])^:=0;
        pint64(@buf[3])^:=fTimer.GetPhysicalTime;
        fSock.SendBufferTo(@buf, 11);
      end;

      for t in toRemove do
      begin
        sub:=TNetworkSoundSubscriber(t);
        writeln('Client timed out: ', GetSinIP(sub.Sin), ':', GetSinPort(sub.sin));

        fSubscribers.Remove(t);
        sub.Free;
      end;

      fLastPPS:=fTimer.GetPhysicalTime;
    end;

    sleep(1);
  end;

  toRemove.Free;
end;

constructor TNetworkSoundServer.Create(APort: word; ATimer: TNetworkSoundTimerClass);
begin
  inherited Create(true);
  fTimer:=ATimer.Create;
  fSubscribers:=TList.Create;
  fSock:=TUDPBlockSocket.Create;
  fSock.Bind('0.0.0.0', IntToStr(APort));
  Start;
end;

destructor TNetworkSoundServer.Destroy;
begin
  Terminate;
  fSock.CloseSocket;
  WaitFor;
  fSock.Free;
  fTimer.Free;
  inherited Destroy;
end;

procedure TNetworkSoundFilter.SetFactor(AValue: double);
begin
  if fFactor=AValue then Exit;
  fFactor:=AValue;
end;

constructor TNetworkSoundFilter.Create;
begin
  inherited Create;
  fFactor:=0;
  Reset;
end;

procedure TNetworkSoundFilter.AddMeasurement(AMeasurement: double);
begin
  if fFirst then
    fValue:=AMeasurement
  else
    fValue:=fValue*fFactor+AMeasurement*(1-fFactor);
  fFirst:=false;
end;

procedure TNetworkSoundFilter.Reset;
begin
  fFirst:=true;
  fValue:=0;
end;

function TNetworkSoundVirtualClock.ToVirtual(APhysical: TPhysicalTimestamp): TVirtualTime;
begin
  result:=APhysical;
end;

function TNetworkSoundVirtualClock.ToPhysical(AVirtual: TVirtualTime): TPhysicalTimestamp;
begin
  result:=AVirtual;
end;

function TNetworkSoundVirtualClock.GetTimestamp: TVirtualTime;
begin
  result:=ToVirtual(fTimer.GetPhysicalTime);
end;

procedure TNetworkSoundVirtualClock.AddRoundtripMeasurement(const ASendMS, ARecvMS, ASendSM, ARecvSM: TVirtualTime);
var
  diffMS, diffSM, rt: Int64;
begin
  diffMS:=Int64(ARecvMS-ASendMS);
  diffSM:=Int64(ARecvSM-ASendSM);

  rt:=diffMS+diffSM;

  fRoundtripLoopfilter.AddMeasurement(rt);
end;

procedure TNetworkSoundVirtualClock.AddOffset(ASendMS, ARecvMS: TVirtualTime);
var
  diff: TVirtualTime;
begin
  diff:=ARecvMS-ASendMS;
  fOffsetLoopfilter.AddMeasurement(diff);
end;

procedure TNetworkSoundVirtualClock.Reset;
begin
  fOffsetLoopfilter.Reset;
  fRoundtripLoopfilter.Reset;
end;

constructor TNetworkSoundVirtualClock.Create(ATimer: TNetworkSoundTimer);
begin
  inherited Create;
  fTimer:=ATimer;
  fController:=TNetworkSoundLoopfilter.Create;
  fOffsetLoopfilter:=fOffsetLoopfilter.Create;
  fRoundtripLoopfilter:=fOffsetLoopfilter.Create;
end;

destructor TNetworkSoundVirtualClock.Destroy;
begin
  fOffsetLoopfilter.Free;
  fRoundtripLoopfilter.Free;
  inherited Destroy;
end;

procedure TNetworkSoundLoopfilter.SetDamping(AValue: double);
begin
  if fDamping=AValue then Exit;
  fDamping:=AValue;
  Recalc;
end;

procedure TNetworkSoundLoopfilter.SetLoopBandwidth(AValue: double);
begin
  if fLoopBandwidth=AValue then Exit;
  fLoopBandwidth:=AValue;
  Recalc;
end;

procedure TNetworkSoundLoopfilter.SetSamplePeriod(AValue: double);
begin
  if fSamplePeriod=AValue then Exit;
  fSamplePeriod:=AValue;
  Recalc;
end;

procedure TNetworkSoundLoopfilter.Recalc;
var
  k0, kp, theta_n, denom: double;
begin
  k0:=1.0;
  kp:=1.0;
  theta_n:=fLoopBandwidth * fSamplePeriod / (fDamping + 1.0/(4*fDamping));
  denom:=1+2*damping*theta_n + theta_n*theta_n;
  fLFAlpha:=4*damping*theta_n / (denom*kp*k0);
  fLFBeta :=4*theta_n*theta_n / (denom*kp*k0);
end;

procedure TNetworkSoundLoopfilter.AddError(AError: double);
var
  a, b: Double;
begin
  a:=AError*fLFAlpha;
  b:=AError*fLFBeta;

  fLFIntegrator:=fLFIntegrator+b;
  fLFResult:=fLFIntegrator+a;
end;

constructor TNetworkSoundLoopfilter.Create;
begin
  inherited Create;
  fSamplePeriod:=1.0;
  fLoopBandwidth:=1.0;
  fDamping:=sqrt(2)/2;

  Recalc;

  fLFIntegrator:=1;
end;

function TNetworkSoundTimer.GetPhysicalTime: TPhysicalTimestamp;
var
  res: TTimeStamp;
begin
  res:=DateTimeToTimeStamp(Now);
  result:=int64(res);
end;

procedure TNetworkSoundClient.AddEvent(AEvent: TNSMessageType; AID: word; const ATime0, ATime1, ARecvTime: TVirtualTime);
begin
  case AEvent of
    mtSync: writeln('Forward:   ', (ARecvTime-ATime0) / 1e9:1:10);
    mtPong: writeln('Roundtrip: ', (ARecvTime+ATime0) / 1e9:1:10);
  end;
  //writeln(format('%d: [%d] - [%d] - %d',[byte(AEvent), ATime0, ATime1, ARecvTime]));
end;

procedure TNetworkSoundClient.SendPing;
var
  buf: array[0..1023] of byte;
  recvTime: TVirtualTime;
begin
  buf[0]:=Byte(mtPing);
  pword(@buf[1])^:=0;             
  recvTime:=fVirtualClock.GetTimestamp;
  pint64(@buf[3])^:=recvTime;
  fSock.SendBufferTo(@buf, 11);

  fLastPing:=recvTime;
end;

procedure TNetworkSoundClient.Execute;
var
  buf: array[0..1023] of byte;
  res: Integer;
  recvTime: TVirtualTime;
begin
  fLastPing:=fTimer.GetPhysicalTime;
  //fSock.NonBlockMode:=true;
  while not Terminated do
  begin
    //res:=fSock.RecvBufferEx(@buf, sizeof(buf), 100);
    if fSock.CanReadEx(100) then
    begin
      res:=fSock.RecvBufferFrom(@buf, sizeof(buf));
      recvTime:=fVirtualClock.GetTimestamp;
      if res>0 then
      begin
        AddEvent(TNSMessageType(buf[0]), pword(@buf[1])^, pint64(@buf[3])^, pint64(@buf[11])^, recvTime);
        continue;
      end;
    end;
                  
    recvTime:=fVirtualClock.GetTimestamp;
    if (recvTime-fLastPing)>=PingInterval then
      SendPing;

    sleep(1);
  end;
end;

constructor TNetworkSoundClient.Create(const AServer: string; APort: word; ATimer: TNetworkSoundTimerClass);
begin
  inherited Create(true);
  fTimer:=ATimer.Create;
  fVirtualClock:=TNetworkSoundVirtualClock.Create(fTimer);
  fSock:=TUDPBlockSocket.Create;
  fSock.Connect(AServer,inttostr(APort));

  fState:=csReset;

  Start;
end;

destructor TNetworkSoundClient.Destroy;
begin
  Terminate;
  fSock.CloseSocket;
  WaitFor;
  fSock.Free;
  fVirtualClock.Free;
  fTimer.Free;
  inherited Destroy;
end;

end.

