{ launcheripc.pas

  Inter-process part of the launcher: the kernel objects and the monitor
  thread.

  Responsibilities:
    * single instance handling through a named mutex;
    * a pagefile backed shared memory section holding the "expected string"
      that the game reads back from the launcher, created with an inheritable
      handle;
    * a named event used by the game to tell the launcher that it consumed the
      expected string, plus the WM_CUSTOM ($BEEF) message posted back to the
      game's main thread with the section handle as lParam;
    * launching the game executable with the forwarded command line.
}

unit LauncherIpc;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows;

const
  { The games look these up by name, so both strings are part of the launcher
    protocol and must not change. }
  LauncherMutexName = '48BC11BD-C4D7-466b-8A31-C6ABBAD47B3E';
  LauncherEventName = 'D6E7FC97-64F9-4d28-B52C-754EDF721C6F';
  { WM_CUSTOM, posted to the game's main thread. }
  LauncherCustomMessage = $BEEF;
  { The monitor thread waits at most 300000 ms for the event. }
  LauncherEventTimeout = 300000;

type
  { Facade over the kernel objects listed above. CreateLauncherIpc builds the
    implementation. }
  TLauncherIpc = class
  public
    { Virtual, so that a Free() through this base class releases the resources
      of the actual implementation. }
    destructor Destroy; override;
    { Creates the launcher mutex. Returns True when this process created it,
      i.e. when this is the first launcher instance and it therefore owns the
      shared memory section. }
    function RecordAnotherInstance: Boolean; virtual; abstract;

    { Creates the named event used by the game. Every launcher instance creates
      it. }
    function CreateEvent: Boolean; virtual; abstract;

    { Creates the shared memory section, maps it into this process and puts the
      expected string into it. Size is the length of that string in bytes, so
      the section always has room for it. Returns False when either the section
      itself or the view could not be created. }
    function SetupSharedMemory(Size: DWORD; const ExpectedData: AnsiString): Boolean; virtual; abstract;

    { Last error code of SetupSharedMemory, or 0. }
    function ErrLastError: Integer; virtual; abstract;

    { True while the section is created and mapped. }
    function SharedMemoryValid: Boolean; virtual; abstract;

    { Handle of the section, passed to the game as WM_CUSTOM's lParam. }
    function SharedMemoryHandle: THandle; virtual; abstract;

    { True when the named event already existed, which means another launcher
      instance is already waiting for the game. }
    function IsOtherInstanceRunning: Boolean; virtual; abstract;

    { Waits for the named event or for the game process, at most
      LauncherEventTimeout milliseconds. Returns True when the event was
      signalled, i.e. when the section handle must be sent to the game. }
    function WaitForEventOrProcess(ProcessHandle: THandle): Boolean; virtual; abstract;

    { PostThreadMessage(ThreadId, WM_CUSTOM, 0, SectionHandle). }
    function PostCustomMessage(ThreadId: DWORD): Boolean; virtual; abstract;

    procedure Cleanup; virtual; abstract;
  end;

{ Creates the IPC implementation. Never nil. }
function CreateLauncherIpc: TLauncherIpc;

implementation

type
  TWindowsLauncherIpc = class(TLauncherIpc)
  private
    FMutex: THandle;
    FMapping: THandle;
    FView: Pointer;
    FViewSize: DWORD;
    FEvent: THandle;
    FOtherInstanceRunning: Boolean;
    FLastError: DWORD;
  public
    constructor Create;
    destructor Destroy; override;
    function RecordAnotherInstance: Boolean; override;
    function CreateEvent: Boolean; override;
    function SetupSharedMemory(Size: DWORD;
      const ExpectedData: AnsiString): Boolean; override;
    function ErrLastError: Integer; override;
    function SharedMemoryValid: Boolean; override;
    function SharedMemoryHandle: THandle; override;
    function IsOtherInstanceRunning: Boolean; override;
    function WaitForEventOrProcess(ProcessHandle: THandle): Boolean; override;
    function PostCustomMessage(ThreadId: DWORD): Boolean; override;
    procedure Cleanup; override;
  end;

constructor TWindowsLauncherIpc.Create;
begin
  inherited Create;
  FMutex := 0;
  FMapping := 0;
  FView := nil;
  FViewSize := 0;
  FEvent := 0;
  FOtherInstanceRunning := False;
end;

destructor TWindowsLauncherIpc.Destroy;
begin
  Cleanup;
  inherited Destroy;
end;

function TWindowsLauncherIpc.RecordAnotherInstance: Boolean;
var
  LastError: DWORD;
begin
  { The "created new" flag of the mutex decides whether this instance owns the
    shared memory section. CreateMutexW returns a valid handle in both cases, so
    only GetLastError() tells them apart. }
  SetLastError(0);
  FMutex := Windows.CreateMutexW(nil, LongBool(False),
    PWideChar(UnicodeString(LauncherMutexName)));
  LastError := GetLastError();
  if FMutex = 0 then
    raise Exception.CreateFmt('Failed to create launcher mutex. Error: %d',
      [LastError]);

  { ERROR_ALREADY_EXISTS is the only error the mutex can report here: a zero
    handle is handled above, so the only other outcome is a valid handle. }
  Result := LastError <> ERROR_ALREADY_EXISTS;
  FOtherInstanceRunning := not Result;
end;

function TWindowsLauncherIpc.CreateEvent: Boolean;
var
  LastError: DWORD;
begin
  SetLastError(0);
  FEvent := Windows.CreateEventW(nil, LongBool(False), LongBool(False),
    PWideChar(UnicodeString(LauncherEventName)));
  LastError := GetLastError();
  if FEvent = 0 then
  begin
    FOtherInstanceRunning := False;
    Exit(False);
  end;

  { ERROR_ALREADY_EXISTS means another instance created the event first. }
  FOtherInstanceRunning := (LastError = ERROR_ALREADY_EXISTS);
  Result := True;
end;

function TWindowsLauncherIpc.SetupSharedMemory(Size: DWORD;
  const ExpectedData: AnsiString): Boolean;
var
  SecurityAttributes: TSecurityAttributes;
begin
  FLastError := 0;

  { An inheritable handle is required: the game receives the section by
    inheritance and by the WM_CUSTOM message. }
  SecurityAttributes.nLength := SizeOf(TSecurityAttributes);
  SecurityAttributes.lpSecurityDescriptor := nil;
  SecurityAttributes.bInheritHandle := LongBool(True);

  SetLastError(0);
  FMapping := Windows.CreateFileMappingW(INVALID_HANDLE_VALUE,
    @SecurityAttributes, PAGE_READWRITE, DWORD(0), Size, nil);
  if FMapping = 0 then
  begin
    FLastError := Windows.GetLastError();
    Exit(False);
  end;

  { FILE_MAP_ALL_ACCESS is not declared by every FPC release; the numeric value
    is the documented one ($F001F). The whole section is mapped. Note that
    MapViewOfFile does not set the last error, so a failure is reported without
    an error code and the mapping handle must be closed here. }
  SetLastError(0);
  FView := Windows.MapViewOfFile(FMapping, $F001F, DWORD(0), DWORD(0), Size);
  if FView = nil then
  begin
    FLastError := Windows.GetLastError();
    Windows.CloseHandle(FMapping);
    FMapping := 0;
    Exit(False);
  end;

  FViewSize := Size;

  { The expected string goes into the view as soon as the view exists. }
  if (ExpectedData <> '') and (DWORD(Length(ExpectedData)) <= Size) then
    Move(ExpectedData[1], FView^, Length(ExpectedData));

  Result := True;
end;

function TWindowsLauncherIpc.ErrLastError: Integer;
begin
  Result := FLastError;
end;

function TWindowsLauncherIpc.SharedMemoryValid: Boolean;
begin
  Result := (FMapping <> 0) and (FView <> nil);
end;

function TWindowsLauncherIpc.SharedMemoryHandle: THandle;
begin
  Result := FMapping;
end;

function TWindowsLauncherIpc.IsOtherInstanceRunning: Boolean;
begin
  Result := FOtherInstanceRunning;
end;

function TWindowsLauncherIpc.WaitForEventOrProcess(ProcessHandle: THandle): Boolean;
var
  Handles: array[0..1] of THandle;
  WaitResult: DWORD;
begin
  Handles[0] := FEvent;
  Handles[1] := ProcessHandle;
  WaitResult := Windows.WaitForMultipleObjects(2, @Handles[0], LongBool(False),
    LauncherEventTimeout);
  Result := WaitResult = WAIT_OBJECT_0;
end;

function TWindowsLauncherIpc.PostCustomMessage(ThreadId: DWORD): Boolean;
begin
  Result := Windows.PostThreadMessageW(ThreadId, LauncherCustomMessage, 0,
    LPARAM(FMapping));
end;

procedure TWindowsLauncherIpc.Cleanup;
begin
  if FView <> nil then
  begin
    Windows.UnmapViewOfFile(FView);
    FView := nil;
  end;

  if FMapping <> 0 then
  begin
    Windows.CloseHandle(FMapping);
    FMapping := 0;
  end;

  if FEvent <> 0 then
  begin
    Windows.CloseHandle(FEvent);
    FEvent := 0;
  end;

  if FMutex <> 0 then
  begin
    Windows.CloseHandle(FMutex);
    FMutex := 0;
  end;
end;

destructor TLauncherIpc.Destroy;
begin
  inherited Destroy;
end;

function CreateLauncherIpc: TLauncherIpc;
begin
  Result := TWindowsLauncherIpc.Create;
end;

end.
