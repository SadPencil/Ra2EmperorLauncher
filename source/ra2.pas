{ ra2.pas

  RA2 Launcher.

  This program is a drop-in replacement for the retail `RA2.exe` launcher: it
  hands the expected string to `game.exe` through a pagefile backed shared
  memory section and forwards its own command line to the game.
  All values that differ between the games live in LauncherTarget.

}

program ra2;

{$mode objfpc}{$H+}

{ Windows GUI subsystem: the launcher creates no console window. It writes
  nothing to the standard output and reports a launch failure in a message box. }
{$APPTYPE GUI}

uses
  SysUtils, LauncherCore, LauncherTarget;

{$R ra2.res}

var
  Profile: TTargetProfile;
begin
  Profile := TRa2Profile.Create;
  try
    ExitCode := RunLauncher(Profile);
  finally
    Profile.Free;
  end;
end.
