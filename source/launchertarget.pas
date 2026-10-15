{ launchertarget.pas

  The three games this launcher supports. Everything that differs between
  Red Alert 2, Yuri's Revenge and Emperor: Battle for Dune lives here; the
  launcher flow itself is shared (see launchercore.pas).

    game                RA2                 RA2MD               Emperor
    game executable     game.exe            gamemd.exe          Game.exe
    expected string     "(c) 2000 ..." + #0 "UIDATA,3DDATA,MAPS" + #0
    section size        51                  19                  19
    command line        launcher's own      launcher's own      launcher's own

  RA2MD and Emperor are the same in everything but the game executable.
}

unit LauncherTarget;

{$mode objfpc}{$H+}

interface

uses
  LauncherCmdLine;

type
  { Everything the launcher needs to know about the game it starts. }
  TTargetProfile = class
  public
    { Name of the launcher, used in the caption of the failure dialog. }
    function LauncherTitle: WideString; virtual; abstract;
    { The game executable, as it is passed to CreateProcess. }
    function GameExecutable: WideString; virtual; abstract;
    { The string the game expects to find in the shared memory section. }
    function ExpectedData: AnsiString; virtual; abstract;
    { Byte count of the shared memory section that holds ExpectedData. }
    function SharedMemorySize: Integer; virtual; abstract;
    { Arguments appended to the game executable: the launcher's own command
      line (see LauncherCmdLine). Kept as WideString so that non-ASCII
      arguments survive into CreateProcessW. The default implementation below
      forwards them for every game. }
    function CommandLineArguments: WideString; virtual;
  end;

type
  TTargetProfileClass = class of TTargetProfile;

  { Red Alert 2: retail RA2.exe, starts game.exe. }
  TRa2Profile = class(TTargetProfile)
  public
    function LauncherTitle: WideString; override;
    function GameExecutable: WideString; override;
    function ExpectedData: AnsiString; override;
    function SharedMemorySize: Integer; override;
  end;

  { Command & Conquer: Yuri's Revenge: retail RA2MD.exe, starts gamemd.exe. }
  TRa2MdProfile = class(TTargetProfile)
  public
    function LauncherTitle: WideString; override;
    function GameExecutable: WideString; override;
    function ExpectedData: AnsiString; override;
    function SharedMemorySize: Integer; override;
  end;

  { Emperor: Battle for Dune: starts Game.exe. }
  TEmperorProfile = class(TTargetProfile)
  public
    function LauncherTitle: WideString; override;
    function GameExecutable: WideString; override;
    function ExpectedData: AnsiString; override;
    function SharedMemorySize: Integer; override;
  end;

const
  Ra2LauncherTitle = 'RA2 Launcher';
  Ra2MdLauncherTitle = 'RA2MD Launcher';
  EmperorLauncherTitle = 'Emperor: Battle for Dune Launcher';

  { Each string carries its own terminator, and each section is exactly as long
    as its string. The game compares the section against its copy with strcmp
    semantics, byte by byte until it reads a zero, so the terminator has to be
    part of what the launcher writes. The original RA2.exe launcher writes its
    50 characters and no terminator, which leaves that byte past the section it
    created -- this is a bad practice. The terminator is added here so that the
    comparison stays inside the section. }
  Ra2ExpectedData = '(c) 2000 Electronic Arts, Inc. All Rights Reserved' + #0;

  { The same 19 bytes for both. }
  Ra2MdEmperorExpectedData: AnsiString = 'UIDATA,3DDATA,MAPS' + #0;

  Ra2GameExecutable = 'game.exe';
  Ra2MdGameExecutable = 'gamemd.exe';
  EmperorGameExecutable = 'Game.exe';

implementation

{ The command line behaviour shared by all three targets }

function TTargetProfile.CommandLineArguments: WideString;
begin
  { Forward the launcher's own command line. }
  Result := ForwardedCommandLineArguments;
end;

{ TRa2Profile }

function TRa2Profile.LauncherTitle: WideString;
begin
  Result := Ra2LauncherTitle;
end;

function TRa2Profile.GameExecutable: WideString;
begin
  Result := Ra2GameExecutable;
end;

function TRa2Profile.ExpectedData: AnsiString;
begin
  Result := Ra2ExpectedData;
end;

function TRa2Profile.SharedMemorySize: Integer;
begin
  Result := Length(Ra2ExpectedData);
end;

{ TRa2MdProfile }

function TRa2MdProfile.LauncherTitle: WideString;
begin
  Result := Ra2MdLauncherTitle;
end;

function TRa2MdProfile.GameExecutable: WideString;
begin
  Result := Ra2MdGameExecutable;
end;

function TRa2MdProfile.ExpectedData: AnsiString;
begin
  Result := Ra2MdEmperorExpectedData;
end;

function TRa2MdProfile.SharedMemorySize: Integer;
begin
  Result := Length(Ra2MdEmperorExpectedData);
end;

{ TEmperorProfile }

function TEmperorProfile.LauncherTitle: WideString;
begin
  Result := EmperorLauncherTitle;
end;

function TEmperorProfile.GameExecutable: WideString;
begin
  Result := EmperorGameExecutable;
end;

function TEmperorProfile.ExpectedData: AnsiString;
begin
  Result := Ra2MdEmperorExpectedData;
end;

function TEmperorProfile.SharedMemorySize: Integer;
begin
  Result := Length(Ra2MdEmperorExpectedData);
end;

end.
