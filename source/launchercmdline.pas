{ launchercmdline.pas

  The launcher's own arguments, as they are handed to the game.

  They come from GetCommandLineW rather than from ParamStr, because ParamStr
  gives back unquoted single arguments while CreateProcessW takes one line: the
  OS text has to reach the game unchanged, quotes and spacing included.
}

unit LauncherCmdLine;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Windows;

{ The arguments this launcher was started with, without the executable path.
  Empty when it was started without arguments. }
function ForwardedCommandLineArguments: WideString;

implementation

{ Drops the executable path from a raw command line and returns the rest as it
  stands, with the original spacing. }
function ArgumentsOf(const CommandLine: WideString): WideString;
var
  Index: SizeInt;
begin
  Result := '';
  if CommandLine = '' then
    Exit;

  if CommandLine[1] = '"' then
  begin
    { The path is quoted, so it ends at the last quote: a path may contain
      spaces, quotes it may not. }
    Index := Length(CommandLine);
    while (Index > 1) and (CommandLine[Index] <> '"') do
      Dec(Index);
    if Index = 1 then
      { No closing quote: the whole line is the path. }
      Exit;
  end
  else
  begin
    { The path is not quoted, so it ends at the first space. }
    Index := 0;
    while (Index < Length(CommandLine)) and (CommandLine[Index + 1] <> ' ') do
      Inc(Index);
  end;

  while (Index < Length(CommandLine)) and (CommandLine[Index + 1] = ' ') do
    Inc(Index);

  Result := Copy(CommandLine, Index + 1, MaxInt);
end;

function ForwardedCommandLineArguments: WideString;
var
  CommandLineW: PWideChar;
begin
  CommandLineW := GetCommandLineW;
  if CommandLineW = nil then
    Exit('');
  Result := ArgumentsOf(WideString(CommandLineW));
end;

end.
