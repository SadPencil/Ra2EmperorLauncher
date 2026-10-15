{ launchercore.pas

  Shared launcher logic of the RA2 / RA2MD / Emperor launcher.

  One flow serves all three games; the differences (game executable, expected
  string, section size) come from a TTargetProfile, see launchertarget.pas.
}

unit LauncherCore;

{$mode objfpc}{$H+}

interface

uses
  LauncherIpc, LauncherTarget;

{ The command line the game is started with: "<game executable>" [arguments]. }
function BuildGameCommandLine(const Executable, Parameters: WideString): WideString;
function BuildGameCommandLine(Profile: TTargetProfile): WideString;

{ What the monitor thread does once the game process is running: wait for the
  named event or for the game to exit, and post WM_CUSTOM with the section
  handle when the event fired. }
procedure RunMonitor(Profile: TTargetProfile; Ipc: TLauncherIpc;
  ProcessHandle: THandle; ProcessThreadId: DWORD;
  OtherInstanceRunning: Boolean);

{ Runs the launcher for one game and returns the process exit code. }
function RunLauncher(Profile: TTargetProfile): Integer;

implementation

uses
  Classes, SysUtils, Windows;

type
  { The monitor thread. Owns its process handle. }
  TMonitorThread = class(TThread)
  private
    FProfile: TTargetProfile;
    FIpc: TLauncherIpc;
    FProcessHandle: THandle;
    FProcessThreadId: DWORD;
    FOtherInstanceRunning: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AProfile: TTargetProfile; AIpc: TLauncherIpc;
      AProcessHandle: THandle; AProcessThreadId: DWORD;
      AOtherInstanceRunning: Boolean);
  end;

constructor TMonitorThread.Create(AProfile: TTargetProfile; AIpc: TLauncherIpc;
  AProcessHandle: THandle; AProcessThreadId: DWORD;
  AOtherInstanceRunning: Boolean);
begin
  { Assign before the thread is resumed, so that Execute never sees half
    initialised state. }
  FProfile := AProfile;
  FIpc := AIpc;
  FProcessHandle := AProcessHandle;
  FProcessThreadId := AProcessThreadId;
  FOtherInstanceRunning := AOtherInstanceRunning;
  inherited Create(False);
end;

procedure TMonitorThread.Execute;
begin
  try
    RunMonitor(FProfile, FIpc, FProcessHandle, FProcessThreadId,
      FOtherInstanceRunning);
  finally
    { This thread owns the duplicated process handle, see RunGameAndWait. }
    if FProcessHandle <> 0 then
      CloseHandle(FProcessHandle);
  end;
end;

{ The directory this launcher sits in, taken from the OS in UTF-16. It is the
  working directory the game is started in, so the game executable next to the
  launcher is found. }
function OwnDirectory: WideString;
var
  Module: array[0..MAX_PATH - 1] of WideChar;
  Length_: DWORD;
  Index: SizeInt;
begin
  Length_ := GetModuleFileNameW(0, @Module[0], MAX_PATH);
  if (Length_ = 0) or (Length_ >= MAX_PATH) then
    Exit('');
  Result := WideString(PWideChar(@Module[0]));
  Index := Length(Result);
  while (Index > 1) and (Result[Index] <> '\') do
    Dec(Index);
  if Index = 1 then
    Index := 0;
  SetLength(Result, Index);
end;

function BuildGameCommandLine(const Executable, Parameters: WideString): WideString;
begin
  Result := '"' + Executable + '"';
  if Parameters <> '' then
    Result := Result + ' ' + Parameters;
end;

function BuildGameCommandLine(Profile: TTargetProfile): WideString;
begin
  Result := BuildGameCommandLine(Profile.GameExecutable,
    Profile.CommandLineArguments);
end;

procedure RunMonitor(Profile: TTargetProfile; Ipc: TLauncherIpc;
  ProcessHandle: THandle; ProcessThreadId: DWORD;
  OtherInstanceRunning: Boolean);
begin
  { When another instance created the event first, this launcher must not send
    the section handle to a game it did not start. }
  if not OtherInstanceRunning then
  begin
    if Ipc.WaitForEventOrProcess(ProcessHandle) and Ipc.SharedMemoryValid then
      Ipc.PostCustomMessage(ProcessThreadId);
  end;
end;

{ Shows the reason a launch failed. The code is translated by the system, so the
  text appears in the language of this Windows installation; codes such as 740
  (administrator rights required) explain themselves. }
procedure ShowLaunchError(const Caption: WideString; ErrorCode: Integer);
var
  Buffer: PWideChar;
  Text: WideString;
begin
  Buffer := nil;
  if (ErrorCode = 0) or
     (FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER or
        FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS, nil,
        DWORD(ErrorCode), MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        PWideChar(@Buffer), 0, nil) = 0) or
     (Buffer = nil) then
    Text := WideString(Format('The game could not be started (code %d).',
      [ErrorCode]))
  else
  begin
    Text := Trim(WideString(Buffer));
    LocalFree(HLOCAL(Buffer));
  end;

  MessageBoxW(0, PWideChar('Failed to launch the game.' + #13#10#13#10 +
    Text), PWideChar(Caption), MB_OK or MB_ICONERROR);
end;

{ Starts the game with CreateProcess. bInheritHandles is True so that the game
  inherits the shared memory section; the handle is anonymous and can only reach
  the game that way. Returns the process handle, or 0 with the reason in
  ErrorCode. }
function CreateProcessGameProcess(const Executable, Parameters: WideString;
  out ProcessId: DWORD; out ThreadId: DWORD; out ErrorCode: Integer): THandle;
var
  StartupInfo: TStartupInfoW;
  ProcessInfo: TProcessInformation;
  CommandLine: WideString;
begin
  Result := 0;
  ProcessId := 0;
  ThreadId := 0;
  ErrorCode := 0;

  CommandLine := BuildGameCommandLine(Executable, Parameters);

  FillChar(StartupInfo, SizeOf(StartupInfo), 0);
  StartupInfo.cb := SizeOf(StartupInfo);

  if not CreateProcessW(nil, PWideChar(CommandLine), nil, nil, LongBool(True),
    0, nil, PWideChar(OwnDirectory), @StartupInfo, @ProcessInfo) then
  begin
    ErrorCode := GetLastOSError;
    Exit;
  end;

  { The thread handle is not needed; the game is waited for through its process
    handle. }
  CloseHandle(ProcessInfo.hThread);

  Result := ProcessInfo.hProcess;
  ProcessId := ProcessInfo.dwProcessId;
  ThreadId := ProcessInfo.dwThreadId;
end;

{ Starts the game, starts the monitor thread and waits for the game to exit.
  Returns False when the process could not be created, after reporting why. }
function RunGameAndWait(Profile: TTargetProfile; Ipc: TLauncherIpc;
  OtherInstanceRunning: Boolean): Boolean;
var
  ProcessHandle: THandle;
  ProcessId, ThreadId: DWORD;
  ErrorCode: Integer;
  MonitorProcessHandle: THandle;
begin
  ProcessHandle := CreateProcessGameProcess(Profile.GameExecutable,
    Profile.CommandLineArguments, ProcessId, ThreadId, ErrorCode);
  if ProcessHandle = 0 then
  begin
    ShowLaunchError(Profile.LauncherTitle, ErrorCode);
    Exit(False);
  end;

  try
    { The monitor thread needs the process handle for up to
      LauncherEventTimeout milliseconds while this thread waits forever on its
      own copy, so it gets a duplicate. Closing this handle would otherwise pull
      the object away from the waiting monitor thread. }
    MonitorProcessHandle := 0;
    if not DuplicateHandle(GetCurrentProcess, ProcessHandle, GetCurrentProcess,
      @MonitorProcessHandle, 0, LongBool(False), DUPLICATE_SAME_ACCESS) then
      MonitorProcessHandle := 0;

    { The monitor thread frees itself on termination and closes its own handle. }
    TMonitorThread.Create(Profile, Ipc, MonitorProcessHandle, ThreadId,
      OtherInstanceRunning);

    { Wait for the game process to exit (infinite wait). }
    WaitForSingleObject(ProcessHandle, INFINITE);
    Result := True;
  finally
    { Closing the process handle is left to the process exit; the monitor thread
      may still be waiting on its duplicate. }
  end;
end;

function RunLauncher(Profile: TTargetProfile): Integer;
var
  ExpectedDataBytes: AnsiString;
  Ipc: TLauncherIpc;
  MutexCreatedNew: Boolean;
begin
  Result := 0;

  SetCurrentDirectoryW(PWideChar(OwnDirectory));

  { The expected string goes into the shared memory section as it is. The
    section is sized from the profile, not from this string. }
  ExpectedDataBytes := AnsiString(Profile.ExpectedData);

  Ipc := CreateLauncherIpc;
  try
    MutexCreatedNew := Ipc.RecordAnotherInstance;

    if not MutexCreatedNew then
    begin
      { Another launcher instance already created the shared memory section and
        is waiting for the game to consume the expected string. A second game
        process would never receive the section handle, so exit instead. }
      Exit;
    end;

    { Creates the section, maps it and writes the expected string into it. }
    if not Ipc.SetupSharedMemory(DWORD(Profile.SharedMemorySize),
      ExpectedDataBytes) then
    begin
      { The error is captured before Cleanup closes the handles, which would
        overwrite the last error. }
      Exit;
    end;

    { The event is created for every instance; a failure to create it does not
      stop the game from being started. }
    Ipc.CreateEvent;

    if not RunGameAndWait(Profile, Ipc, Ipc.IsOtherInstanceRunning) then
      Exit;
  finally
    { Unmap the view and close the section. }
    Ipc.Cleanup;
    Ipc.Free;
  end;
end;

end.
