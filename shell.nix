# Based of the generated code in ./npm-deps-nix/default.nix but with some Perl dependencies

{pkgs ? import <nixpkgs> {
    inherit system;
  }, system ? builtins.currentSystem, nodejs ? pkgs."nodejs-16_x"
}:

let
  nodeEnv = import ./npm-deps-nix/node-env.nix {
    inherit (pkgs) stdenv lib python2 runCommand writeTextFile writeShellScript;
    inherit pkgs nodejs;
    libtool = if pkgs.stdenv.isDarwin then pkgs.darwin.cctools else null;
  };
in
(import ./npm-deps-nix/node-packages.nix {
  inherit (pkgs) fetchurl nix-gitignore stdenv lib fetchgit;
  inherit nodeEnv;
  globalBuildInputs = [
    (pkgs.perl.withPackages (p: with p; [
      Mojolicious
      FutureAsyncAwait
      TimeDate
      StringShellQuote
      JSONXS
      CryptJWT
      ProcProcessTable
      DateTime
      DBI
      TieIxHash
      UUIDTiny
      HTMLParser
      GD
      ClassAccessor
      LocaleMaketextLexicon
      CGI
      DataStructureUtil
      MathRandomSecure
      IOSocketSSL
    ]))
  ];
}).shell
