{ emperor.pas

  Emperor: Battle for Dune launcher.

  Emperor uses the same launcher protocol as the RA2 launchers: the game reads
  the expected string from an anonymous, inheritable shared memory section and
  is told where that section is by a WM_CUSTOM ($BEEF) message carrying the
  section handle.

  The game is `Game.exe` and its expected string is "UIDATA,3DDATA,MAPS", so the
  shared memory section is 19 bytes. These values, like every other per-game
  value, live in LauncherTarget; the launcher flow is shared.

}

program emperor;

{$mode objfpc}{$H+}

{ Windows GUI subsystem: the launcher creates no console window. It writes
  nothing to the standard output and reports a launch failure in a message box. }
{$APPTYPE GUI}

uses
  SysUtils, LauncherCore, LauncherTarget;

{$R emperor.res}

var
  Profile: TTargetProfile;
begin
  Profile := TEmperorProfile.Create;
  try
    ExitCode := RunLauncher(Profile);
  finally
    Profile.Free;
  end;
end.
